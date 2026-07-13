import AppKit
import CoreVideo
import MoyuReaderCore
import QuartzCore

final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    private let settings: ReaderSettings
    private let progressStore: ReadingProgressStore
    private let readerView: ReaderContentView

    private var currentBookPath: String?
    private var currentDocument: ReadingDocument?
    private var scrollObserver: NSObjectProtocol?
    private var scrollSyncTimer: Timer?

    init(settings: ReaderSettings, progressStore: ReadingProgressStore) {
        self.settings = settings
        self.progressStore = progressStore
        self.readerView = ReaderContentView(settings: settings)

        let panel = ReaderPanel(
            contentRect: settings.windowFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "MoyuReader"
        panel.contentView = readerView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = settings.keepWindowOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = nil

        super.init(window: panel)
        panel.delegate = self
        panel.readerKeyDownHandler = { [weak self] event in
            self?.readerView.handleReaderArrowKey(event) ?? false
        }
        readerView.onOpenLibrary = { [weak self] in
            self?.onOpenLibrary?()
        }
        readerView.onOpenSettings = { [weak self] in
            self?.onOpenSettings?()
        }
        readerView.onReadingProgressChanged = { [weak self] in
            self?.scheduleScrollSync()
        }

        observeScrolling()
    }

    var onOpenLibrary: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(book: EpubBook, document: ReadingDocument) {
        currentBookPath = book.sourceURL.path
        currentDocument = document

        let progress = progressStore.progress(for: book.sourceURL.path)
        readerView.setDocument(document, chapterIndex: progress.chapterIndex)
        apply(settings: settings)

        DispatchQueue.main.async { [weak self] in
            self?.readerView.scroll(toVerticalOffset: progress.offset)
            self?.readerView.refreshCurrentChapterFromVisibleText()
        }
    }

    func apply(settings: ReaderSettings) {
        readerView.apply(settings: settings)
        window?.level = settings.keepWindowOnTop ? .floating : .normal
    }

    func revealTemporarily() {
        readerView.revealTemporarily()
    }

    func beginAppearancePreview() {
        readerView.beginAppearancePreview()
    }

    func endAppearancePreview() {
        readerView.endAppearancePreview()
    }

    func saveWindowFrame() {
        guard let window else {
            return
        }

        settings.windowFrame = window.frame
        settings.save()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }

    private func observeScrolling() {
        readerView.clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: readerView.clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleScrollSync()
            }
        }
    }

    private func scheduleScrollSync() {
        scrollSyncTimer?.invalidate()
        let timer = Timer(timeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushScrollSync()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollSyncTimer = timer
    }

    private func flushScrollSync() {
        scrollSyncTimer = nil
        guard let currentBookPath else {
            return
        }

        progressStore.save(progress: readerView.readingProgress, for: currentBookPath)
        readerView.refreshCurrentChapterFromVisibleText()
    }
}

final class ReaderContentView: NSView {
    private let scrollView = CapturingScrollView()
    private let textView = StealthTextView()
    private let chapterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let libraryButton = NSButton()
    private let settingsButton = NSButton()
    private let hudView = NSView()
    private let previousChapterButton = NSButton(title: "<", target: nil, action: nil)
    private let nextChapterButton = NSButton(title: ">", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "")
    private let resizeHitSlop: CGFloat = 12
    private let minimumWindowSize = NSSize(width: 260, height: 100)

    private var trackingArea: NSTrackingArea?
    private var visibleAlpha: Double
    private var hiddenAlpha: Double
    private var targetAlpha: Double
    private var isMouseInside = false
    private var pendingHide: DispatchWorkItem?
    private var smoothScrollTargetOffset: CGFloat?
    private var smoothScrollTimer: Timer?
    private var smoothScrollDisplayLink: CVDisplayLink?
    private var adaptiveColorTimer: Timer?
    private var adaptiveTextColor: NSColor?
    private var resizeDrag: ResizeDrag?
    private var currentSettings: ReaderSettings
    private var currentChapterIndex = 0
    private var document: ReadingDocument?
    private var isAppearancePreviewing = false
    private var lastProgressLabelText = ""
    var onReadingProgressChanged: (() -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    var clipView: NSClipView {
        scrollView.contentView
    }

    var verticalOffset: CGFloat {
        scrollView.contentView.bounds.origin.y
    }

    var readingProgress: ReadingProgress {
        ReadingProgress(chapterIndex: currentChapterIndex, offset: verticalOffset)
    }

    init(settings: ReaderSettings) {
        self.visibleAlpha = settings.visibleAlpha
        self.hiddenAlpha = settings.hiddenAlpha
        self.targetAlpha = settings.hiddenAlpha
        self.currentSettings = settings

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(settings.backgroundAlpha)
            .cgColor
        layer?.cornerRadius = 8
        alphaValue = settings.hiddenAlpha

        configureScrollView()
        configureChapterNavigation()
        configureTextView(settings: settings)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func layout() {
        super.layout()
        updateTextViewSize()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopSmoothScroll(clearTarget: true)
            stopAdaptiveColorTimer()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, currentSettings.adaptiveTextColor {
            refreshAdaptiveTextColor()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area

    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        pendingHide?.cancel()
        makeWindowKeyIfNeeded()
        window?.makeFirstResponder(self)
        refreshAdaptiveTextColor()
        ensureAdaptiveColorTimer()
        setProgressVisible(true)
        fade(to: visibleAlpha, duration: 0.28)
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        guard !isAppearancePreviewing else {
            return
        }
        stopAdaptiveColorTimer()
        setProgressVisible(false)
        fade(to: hiddenAlpha, duration: 0.55)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        makeWindowKeyIfNeeded()
        window?.makeFirstResponder(textView)

        if let edge = resizeEdge(for: event), let window {
            stopSmoothScroll(clearTarget: true)
            resizeDrag = ResizeDrag(
                edge: edge,
                originalFrame: window.frame,
                startScreenPoint: NSEvent.mouseLocation,
                anchorCharacterIndex: textView.firstVisibleCharacterIndex()
            )
            return
        }

        if event.modifierFlags.contains(.option) {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let resizeDrag, let window else {
            super.mouseDragged(with: event)
            return
        }

        let currentPoint = NSEvent.mouseLocation
        let delta = ReaderResizeGeometry.Point(
            x: currentPoint.x - resizeDrag.startScreenPoint.x,
            y: currentPoint.y - resizeDrag.startScreenPoint.y
        )
        let resized = ReaderResizeGeometry.resizedFrame(
            original: resizeDrag.originalFrame.readerResizeRect,
            edge: resizeDrag.edge,
            delta: delta,
            minimumSize: (width: minimumWindowSize.width, height: minimumWindowSize.height)
        )

        window.setFrame(resized.nsRect, display: true)
        updateTextViewSize()
        scrollToCharacterIndex(resizeDrag.anchorCharacterIndex)
    }

    override func mouseUp(with event: NSEvent) {
        if resizeDrag != nil {
            resizeDrag = nil
            refreshCurrentChapterFromVisibleText()
            window?.invalidateCursorRects(for: self)
            return
        }

        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        handleCapturedScrollWheel(event)
    }

    override func keyDown(with event: NSEvent) {
        if handleReaderArrowKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    func handleReaderArrowKey(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard
            event.modifierFlags.intersection(disallowedModifiers).isEmpty,
            isMouseInside
        else {
            return false
        }

        guard let action = ReaderKeyboardNavigation.action(forKeyCode: event.keyCode) else {
            return false
        }

        switch action {
        case .scrollUp:
            scrollSmoothly(to: verticalOffset - currentSettings.scrollStep)
            return true
        case .scrollDown:
            scrollSmoothly(to: verticalOffset + currentSettings.scrollStep)
            return true
        case .previousChapter, .nextChapter:
            break
        }

        guard let document else {
            return false
        }

        let direction: ReaderChapterNavigation.Direction = action == .previousChapter ? .previous : .next

        guard let destination = ReaderChapterNavigation.destination(
            current: currentChapterIndex,
            total: document.chapters.count,
            direction: direction
        ) else {
            return true
        }

        showChapter(at: destination, offset: 0, notifyProgress: true)
        return true
    }

    func setDocument(_ document: ReadingDocument, chapterIndex: Int = 0) {
        self.document = document
        textView.setAccessibilityLabel(document.title)
        configureChapterPopup(for: document)
        showChapter(at: chapterIndex, offset: 0, notifyProgress: false)
        updateTextViewSize()
        refreshCurrentChapterFromVisibleText()
    }

    func apply(settings: ReaderSettings) {
        currentSettings = settings
        visibleAlpha = settings.visibleAlpha
        hiddenAlpha = settings.hiddenAlpha
        chapterPopup.font = .systemFont(ofSize: max(11, settings.fontSize - 3), weight: .medium)
        if settings.adaptiveTextColor {
            applyCurrentTypography()
            refreshAdaptiveTextColor()
            ensureAdaptiveColorTimer()
        } else {
            stopAdaptiveColorTimer()
            adaptiveTextColor = nil
            applyCurrentTypography()
        }
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(settings.backgroundAlpha)
            .cgColor
        updateTextViewSize()
        updateProgressLabel()

        if isAppearancePreviewing {
            alphaValue = settings.visibleAlpha
            targetAlpha = settings.visibleAlpha
        } else if alphaValue > settings.hiddenAlpha {
            alphaValue = settings.visibleAlpha
            targetAlpha = settings.visibleAlpha
        }
    }

    func scroll(toVerticalOffset offset: CGFloat) {
        stopSmoothScroll(clearTarget: true)
        updateTextViewSize()
        let maxOffset = maximumVerticalOffset
        let clampedOffset = min(max(0, offset), maxOffset)
        scrollImmediately(to: clampedOffset)
        refreshCurrentChapterFromVisibleText()
    }

    func handleCapturedScrollWheel(_ event: NSEvent) {
        isMouseInside = true
        pendingHide?.cancel()
        makeWindowKeyIfNeeded()
        if abs(alphaValue - visibleAlpha) > 0.01 {
            fade(to: visibleAlpha, duration: 0.08)
        }

        let currentOffset = event.hasPreciseScrollingDeltas
            ? verticalOffset
            : (smoothScrollTargetOffset ?? verticalOffset)
        let nextOffset = ReaderScrollMath.nextOffset(
            current: Double(currentOffset),
            wheelDeltaY: event.scrollingDeltaY,
            maxOffset: Double(maximumVerticalOffset),
            isPrecise: event.hasPreciseScrollingDeltas,
            wheelStep: currentSettings.scrollStep
        )

        let clampedOffset = CGFloat(nextOffset)
        smoothScrollTargetOffset = clampedOffset
        if event.hasPreciseScrollingDeltas {
            stopSmoothScroll(clearTarget: false)
            scrollImmediately(to: clampedOffset)
        } else {
            scrollSmoothly(to: clampedOffset)
        }
    }

    func revealTemporarily() {
        pendingHide?.cancel()
        setProgressVisible(true)
        fade(to: visibleAlpha, duration: 0.2)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !isMouseInside else {
                return
            }

            fade(to: hiddenAlpha, duration: 0.55)
        }
        pendingHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    func beginAppearancePreview() {
        isAppearancePreviewing = true
        pendingHide?.cancel()
        refreshAdaptiveTextColor()
        ensureAdaptiveColorTimer()
        setProgressVisible(true)
        fade(to: visibleAlpha, duration: 0.12)
    }

    func endAppearancePreview() {
        isAppearancePreviewing = false
        guard !isMouseInside else {
            return
        }

        setProgressVisible(false)
        stopAdaptiveColorTimer()
        fade(to: hiddenAlpha, duration: 0.35)
    }

    func refreshCurrentChapterFromVisibleText() {
        guard document != nil else {
            return
        }

        if chapterPopup.indexOfSelectedItem != currentChapterIndex,
           currentChapterIndex < chapterPopup.numberOfItems {
            chapterPopup.selectItem(at: currentChapterIndex)
        }
        updateProgressLabel()
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configureHUD()
    }

    private func configureTextView(settings: ReaderSettings) {
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 18, height: 52)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.insertionPointColor = .clear
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        applyCurrentTypography()
    }

    private func configureHUD() {
        hudView.translatesAutoresizingMaskIntoConstraints = false
        hudView.wantsLayer = true
        hudView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.14).cgColor
        addSubview(hudView)

        chapterPopup.translatesAutoresizingMaskIntoConstraints = false
        chapterPopup.bezelStyle = .texturedRounded
        chapterPopup.controlSize = .small
        chapterPopup.font = .systemFont(ofSize: 12, weight: .medium)
        chapterPopup.target = self
        chapterPopup.action = #selector(chapterPopupChanged(_:))
        chapterPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hudView.addSubview(chapterPopup)

        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.bezelStyle = .texturedRounded
        libraryButton.controlSize = .small
        libraryButton.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "打开书库")
        libraryButton.imagePosition = .imageOnly
        libraryButton.toolTip = "打开书库"
        libraryButton.target = self
        libraryButton.action = #selector(libraryButtonClicked(_:))
        hudView.addSubview(libraryButton)

        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.controlSize = .small
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "打开设置")
        settingsButton.imagePosition = .imageOnly
        settingsButton.toolTip = "打开设置"
        settingsButton.target = self
        settingsButton.action = #selector(settingsButtonClicked(_:))
        hudView.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            hudView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            hudView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            hudView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            hudView.heightAnchor.constraint(equalToConstant: 28),

            libraryButton.leadingAnchor.constraint(equalTo: hudView.leadingAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: hudView.centerYAnchor),
            libraryButton.widthAnchor.constraint(equalToConstant: 28),
            libraryButton.heightAnchor.constraint(equalToConstant: 24),

            chapterPopup.leadingAnchor.constraint(equalTo: libraryButton.trailingAnchor, constant: 6),
            settingsButton.trailingAnchor.constraint(equalTo: hudView.trailingAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: hudView.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 28),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            chapterPopup.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            chapterPopup.centerYAnchor.constraint(equalTo: hudView.centerYAnchor)
        ])
    }

    private func configureChapterNavigation() {
        for button in [previousChapterButton, nextChapterButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .texturedRounded
            button.controlSize = .small
            button.font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
            button.isBordered = true
            addSubview(button)
        }

        previousChapterButton.target = self
        previousChapterButton.action = #selector(previousChapterButtonClicked(_:))
        previousChapterButton.setAccessibilityLabel("上一章")

        nextChapterButton.target = self
        nextChapterButton.action = #selector(nextChapterButtonClicked(_:))
        nextChapterButton.setAccessibilityLabel("下一章")

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.alignment = .center
        progressLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        progressLabel.textColor = currentSettings.textColor.withAlphaComponent(min(1, currentSettings.visibleAlpha + 0.2))
        progressLabel.isHidden = true
        progressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(progressLabel)

        NSLayoutConstraint.activate([
            previousChapterButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            previousChapterButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            previousChapterButton.widthAnchor.constraint(equalToConstant: 32),
            previousChapterButton.heightAnchor.constraint(equalToConstant: 28),

            nextChapterButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            nextChapterButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            nextChapterButton.widthAnchor.constraint(equalToConstant: 32),
            nextChapterButton.heightAnchor.constraint(equalToConstant: 28),

            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressLabel.centerYAnchor.constraint(equalTo: previousChapterButton.centerYAnchor),
            progressLabel.leadingAnchor.constraint(greaterThanOrEqualTo: previousChapterButton.trailingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(lessThanOrEqualTo: nextChapterButton.leadingAnchor, constant: -16)
        ])

        updateChapterNavigation()
    }

    private func configureChapterPopup(for document: ReadingDocument) {
        chapterPopup.removeAllItems()

        if document.chapters.isEmpty {
            chapterPopup.addItem(withTitle: document.title)
            chapterPopup.isEnabled = false
            return
        }

        chapterPopup.isEnabled = true
        let total = document.chapters.count
        for chapter in document.chapters {
            chapterPopup.addItem(withTitle: "第 \(chapter.index + 1)/\(total) 章 · \(chapter.title)")
        }
    }

    @objc private func chapterPopupChanged(_ sender: NSPopUpButton) {
        scrollToChapter(at: sender.indexOfSelectedItem)
    }

    @objc private func libraryButtonClicked(_ sender: NSButton) {
        onOpenLibrary?()
    }

    @objc private func settingsButtonClicked(_ sender: NSButton) {
        onOpenSettings?()
    }

    @objc private func previousChapterButtonClicked(_ sender: NSButton) {
        showChapter(at: currentChapterIndex - 1, offset: 0, notifyProgress: true)
    }

    @objc private func nextChapterButtonClicked(_ sender: NSButton) {
        showChapter(at: currentChapterIndex + 1, offset: 0, notifyProgress: true)
    }

    private func scrollToChapter(at index: Int) {
        guard
            let document,
            document.chapters.indices.contains(index)
        else {
            return
        }

        stopSmoothScroll(clearTarget: true)
        showChapter(at: index, offset: 0, notifyProgress: true)
    }

    private func showChapter(at index: Int, offset: CGFloat, notifyProgress: Bool) {
        guard let document, !document.chapters.isEmpty else {
            currentChapterIndex = 0
            textView.string = ""
            updateTextViewSize()
            updateChapterNavigation()
            updateProgressLabel()
            return
        }

        let clampedIndex = min(max(0, index), document.chapters.count - 1)
        currentChapterIndex = clampedIndex
        textView.string = document.chapterText(at: clampedIndex)
        applyCurrentTypography()
        updateTextViewSize()

        let clampedOffset = min(max(0, offset), maximumVerticalOffset)
        scrollImmediately(to: clampedOffset)
        smoothScrollTargetOffset = nil
        refreshCurrentChapterFromVisibleText()
        updateChapterNavigation()
        updateProgressLabel()

        if notifyProgress {
            onReadingProgressChanged?()
        }
    }

    private func updateChapterNavigation() {
        let total = document?.chapters.count ?? 0
        let hasPrevious = currentChapterIndex > 0
        let hasNext = currentChapterIndex + 1 < total
        previousChapterButton.isHidden = !hasPrevious
        previousChapterButton.isEnabled = hasPrevious
        nextChapterButton.isHidden = !hasNext
        nextChapterButton.isEnabled = hasNext
        updateProgressLabel()
    }

    private func updateTextViewSize() {
        let width = max(1, scrollView.contentSize.width)
        textView.textContainer?.containerSize = NSSize(
            width: max(1, width - textView.textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame.size.width = width

        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = max(
                scrollView.contentSize.height + 1,
                ceil(usedRect.height + textView.textContainerInset.height * 2 + 40)
            )
            textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        updateProgressLabel()
    }

    private func resizeEdge(for event: NSEvent) -> ReaderResizeGeometry.Edge? {
        let point = convert(event.locationInWindow, from: nil)
        return ReaderResizeGeometry.edge(
            at: ReaderResizeGeometry.Point(x: point.x, y: point.y),
            in: (width: bounds.width, height: bounds.height),
            threshold: resizeHitSlop
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else {
            return
        }

        let slop = min(resizeHitSlop, min(width, height) / 2)
        addCursorRect(NSRect(x: 0, y: 0, width: slop, height: height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: width - slop, y: 0, width: slop, height: height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: width, height: slop), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: height - slop, width: width, height: slop), cursor: .resizeUpDown)

        for edge: ReaderResizeGeometry.Edge in [.topLeft, .topRight, .bottomLeft, .bottomRight] {
            addCursorRect(cursorRect(for: edge, slop: slop), cursor: resizeCursor(for: edge))
        }
    }

    private func cursorRect(for edge: ReaderResizeGeometry.Edge, slop: CGFloat) -> NSRect {
        switch edge {
        case .topLeft:
            NSRect(x: 0, y: bounds.height - slop, width: slop, height: slop)
        case .topRight:
            NSRect(x: bounds.width - slop, y: bounds.height - slop, width: slop, height: slop)
        case .bottomLeft:
            NSRect(x: 0, y: 0, width: slop, height: slop)
        case .bottomRight:
            NSRect(x: bounds.width - slop, y: 0, width: slop, height: slop)
        case .left, .right, .top, .bottom:
            .zero
        }
    }

    private func resizeCursor(for edge: ReaderResizeGeometry.Edge) -> NSCursor {
        switch edge {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return .crosshair
        case .topRight, .bottomLeft:
            return .crosshair
        }
    }

    private var maximumVerticalOffset: CGFloat {
        max(0, textView.frame.height - scrollView.contentSize.height)
    }

    private func scrollToCharacterIndex(_ characterIndex: Int) {
        updateTextViewSize()
        let offset = textView.verticalOffset(forCharacterIndex: characterIndex)
        let clampedOffset = min(max(0, offset), maximumVerticalOffset)
        scrollContent(to: clampedOffset)
    }

    private func scrollImmediately(to offset: CGFloat) {
        smoothScrollTargetOffset = offset
        scrollContent(to: offset)
    }

    private func scrollContent(to offset: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateProgressLabel()
    }

    private var effectiveTextColor: NSColor {
        adaptiveTextColor ?? currentSettings.textColor
    }

    private func applyCurrentTypography() {
        let color = effectiveTextColor
        textView.applyTypography(settings: currentSettings, textColor: color)
        chapterPopup.contentTintColor = color.withAlphaComponent(min(1, currentSettings.visibleAlpha + 0.1))
        previousChapterButton.contentTintColor = color.withAlphaComponent(min(1, currentSettings.visibleAlpha + 0.16))
        nextChapterButton.contentTintColor = color.withAlphaComponent(min(1, currentSettings.visibleAlpha + 0.16))
        progressLabel.textColor = color.withAlphaComponent(min(1, currentSettings.visibleAlpha + 0.2))
    }

    private func ensureAdaptiveColorTimer() {
        guard currentSettings.adaptiveTextColor, window != nil else {
            stopAdaptiveColorTimer()
            return
        }
        guard adaptiveColorTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAdaptiveTextColor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        adaptiveColorTimer = timer
    }

    private func stopAdaptiveColorTimer() {
        adaptiveColorTimer?.invalidate()
        adaptiveColorTimer = nil
    }

    private func refreshAdaptiveTextColor() {
        guard currentSettings.adaptiveTextColor else {
            if adaptiveTextColor != nil {
                adaptiveTextColor = nil
                applyCurrentTypography()
            }
            return
        }

        guard
            let image = captureBackgroundBelowWindow(),
            let color = Self.recommendedTextColor(from: image)
        else {
            return
        }

        guard adaptiveTextColor?.hexString != color.hexString else {
            return
        }

        adaptiveTextColor = color
        applyCurrentTypography()
    }

    private func captureBackgroundBelowWindow() -> CGImage? {
        guard let window else {
            return nil
        }

        let windowID = CGWindowID(window.windowNumber)
        guard let captureRect = Self.windowListBounds(for: windowID), !captureRect.isEmpty else {
            return nil
        }

        return CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            windowID,
            [.bestResolution]
        )
    }

    private static func windowListBounds(for windowID: CGWindowID) -> CGRect? {
        guard
            let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
            let bounds = windows.first?[kCGWindowBounds as String] as? [String: Any],
            let x = bounds["X"] as? CGFloat,
            let y = bounds["Y"] as? CGFloat,
            let width = bounds["Width"] as? CGFloat,
            let height = bounds["Height"] as? CGFloat
        else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func recommendedTextColor(from image: CGImage) -> NSColor? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            return nil
        }

        let xStep = max(1, width / 18)
        let yStep = max(1, height / 10)
        var luminanceTotal = 0.0
        var sampleCount = 0

        for y in stride(from: 0, to: height, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }

                luminanceTotal += ReaderAdaptiveTextColor.luminance(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                )
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        let hex = ReaderAdaptiveTextColor.recommendedHexColor(
            averageLuminance: luminanceTotal / Double(sampleCount)
        )
        return NSColor(hexString: hex)
    }

    private func setProgressVisible(_ visible: Bool) {
        progressLabel.isHidden = !visible
        if visible {
            updateProgressLabel()
        }
    }

    private func updateProgressLabel() {
        guard !progressLabel.isHidden else {
            return
        }

        let total = document?.chapters.count ?? 0
        guard total > 0 else {
            if !lastProgressLabelText.isEmpty {
                lastProgressLabelText = ""
                progressLabel.stringValue = ""
            }
            return
        }

        let percent = ReaderScrollMath.progressPercent(
            offset: Double(verticalOffset),
            maxOffset: Double(maximumVerticalOffset)
        )
        let text = "第 \(currentChapterIndex + 1)/\(total) 章 · 当前章 \(percent)%"
        guard text != lastProgressLabelText else {
            return
        }

        lastProgressLabelText = text
        progressLabel.stringValue = text
    }

    private func scrollSmoothly(to offset: CGFloat) {
        smoothScrollTargetOffset = offset

        guard smoothScrollTimer == nil, smoothScrollDisplayLink == nil else {
            return
        }

        if startDisplaySyncedScroll() {
            return
        }

        let timer = Timer(
            timeInterval: scrollAnimationFrameInterval,
            target: self,
            selector: #selector(smoothScrollTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        smoothScrollTimer = timer
    }

    private func startDisplaySyncedScroll() -> Bool {
        var link: CVDisplayLink?
        let createStatus = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard createStatus == kCVReturnSuccess, let link else {
            return false
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callbackStatus = CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context in
            guard let context else {
                return kCVReturnSuccess
            }

            let readerView = Unmanaged<ReaderContentView>
                .fromOpaque(context)
                .takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    readerView.advanceSmoothScroll()
                }
            }
            return kCVReturnSuccess
        }, context)
        guard callbackStatus == kCVReturnSuccess else {
            return false
        }

        let startStatus = CVDisplayLinkStart(link)
        guard startStatus == kCVReturnSuccess else {
            return false
        }

        smoothScrollDisplayLink = link
        return true
    }

    @objc private func smoothScrollTimerFired(_ timer: Timer) {
        advanceSmoothScroll()
    }

    private func advanceSmoothScroll() {
        guard let target = smoothScrollTargetOffset else {
            stopSmoothScroll(clearTarget: true)
            return
        }

        let nextOffset = ReaderScrollMath.smoothedOffset(
            current: Double(verticalOffset),
            target: Double(target),
            response: 0.32,
            minimumStep: 0.75
        )
        let clampedOffset = CGFloat(nextOffset)
        scrollContent(to: clampedOffset)

        if clampedOffset == target {
            stopSmoothScroll(clearTarget: true)
            refreshCurrentChapterFromVisibleText()
        }
    }

    private var scrollAnimationFrameInterval: TimeInterval {
        let framesPerSecond = window?.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond
            ?? ReaderScrollMath.minimumFramesPerSecond
        return ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: framesPerSecond)
    }

    private func stopSmoothScroll(clearTarget: Bool) {
        if let displayLink = smoothScrollDisplayLink {
            CVDisplayLinkStop(displayLink)
        }
        smoothScrollDisplayLink = nil
        smoothScrollTimer?.invalidate()
        smoothScrollTimer = nil
        if clearTarget {
            smoothScrollTargetOffset = nil
        }
    }

    private func fade(to alpha: Double, duration: TimeInterval) {
        guard abs(targetAlpha - alpha) > 0.001 else {
            return
        }

        targetAlpha = alpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = alpha
        }
    }

    private func makeWindowKeyIfNeeded() {
        guard let window else {
            return
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func activateForKeyboard() {
        isMouseInside = true
        makeWindowKeyIfNeeded()
    }
}

private struct ResizeDrag {
    let edge: ReaderResizeGeometry.Edge
    let originalFrame: NSRect
    let startScreenPoint: NSPoint
    let anchorCharacterIndex: Int
}

private extension NSRect {
    var readerResizeRect: ReaderResizeGeometry.Rect {
        ReaderResizeGeometry.Rect(
            x: origin.x,
            y: origin.y,
            width: width,
            height: height
        )
    }
}

private extension ReaderResizeGeometry.Rect {
    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

final class ReaderPanel: NSPanel {
    var readerKeyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, readerKeyDownHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

final class CapturingScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if let readerView = enclosingReaderContentView {
            readerView.handleCapturedScrollWheel(event)
        }
    }

    private var enclosingReaderContentView: ReaderContentView? {
        var view = superview
        while let currentView = view {
            if let readerView = currentView as? ReaderContentView {
                return readerView
            }
            view = currentView.superview
        }
        return nil
    }
}

final class StealthTextView: NSTextView {
    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if let readerView = enclosingReaderContentView {
            readerView.handleCapturedScrollWheel(event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        enclosingReaderContentView?.activateForKeyboard()
        if event.modifierFlags.contains(.option) {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if let readerView = enclosingReaderContentView, readerView.handleReaderArrowKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    func firstVisibleCharacterIndex() -> Int {
        guard
            let layoutManager,
            let textContainer,
            !string.isEmpty
        else {
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)

        var visibleRect = visibleRect
        visibleRect.origin.x -= textContainerOrigin.x
        visibleRect.origin.y -= textContainerOrigin.y

        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        guard glyphRange.location != NSNotFound else {
            return 0
        }

        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        return min(characterRange.location, max(0, (string as NSString).length - 1))
    }

    func verticalOffset(forCharacterIndex characterIndex: Int) -> CGFloat {
        guard
            let layoutManager,
            let textContainer,
            !string.isEmpty
        else {
            return 0
        }

        let stringLength = (string as NSString).length
        let clampedIndex = min(max(0, characterIndex), max(0, stringLength - 1))
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: clampedIndex, length: 1),
            actualCharacterRange: nil
        )
        guard glyphRange.location != NSNotFound else {
            return 0
        }

        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return max(0, floor(glyphRect.minY + textContainerOrigin.y))
    }

    func applyTypography(settings: ReaderSettings, textColor overrideTextColor: NSColor? = nil) {
        let font = settings.readerFont()
        let color = (overrideTextColor ?? settings.textColor).withAlphaComponent(settings.visibleAlpha)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = settings.lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        self.font = font
        textColor = color
        defaultParagraphStyle = paragraphStyle
        typingAttributes = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let range = NSRange(location: 0, length: (string as NSString).length)
        guard range.length > 0 else {
            return
        }

        textStorage?.setAttributes(typingAttributes, range: range)
    }

    private var enclosingReaderContentView: ReaderContentView? {
        var view = superview
        while let currentView = view {
            if let readerView = currentView as? ReaderContentView {
                return readerView
            }
            view = currentView.superview
        }
        return nil
    }
}
