import AppKit
import MoyuReaderCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = ReaderSettings.load()
    private let progressStore = ReadingProgressStore()
    private let bookLibraryStore = BookLibraryStore()

    private var statusItem: NSStatusItem?
    private var readerWindowController: ReaderWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var bookLibraryWindowController: BookLibraryWindowController?
    private var colorPanelCloseObserver: NSObjectProtocol?
    private var currentBook: EpubBook?
    private var bookCache: [String: EpubBook] = [:]
    private var latestLoadRequestID = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()

        if let launchURL = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:)) {
            loadBook(at: launchURL, showErrors: true)
        } else {
            restoreLastBookIfAvailable()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let epubURL = urls.first(where: { $0.pathExtension.lowercased() == "epub" }) else {
            return
        }

        loadBook(at: epubURL, showErrors: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if readerWindowController?.window != nil {
            showReaderWindow()
        } else {
            showSettings()
        }
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "设置...",
            action: #selector(showSettings),
            keyEquivalent: ","
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "退出 MoyuReader",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        appMenu.items.forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(NSMenuItem(
            title: "打开 EPUB...",
            action: #selector(openBook),
            keyEquivalent: "o"
        ))
        fileMenu.addItem(NSMenuItem(
            title: "书库...",
            action: #selector(showLibrary),
            keyEquivalent: "l"
        ))
        fileMenu.items.forEach { $0.target = self }
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(NSMenuItem(
            title: "显示/隐藏阅读窗",
            action: #selector(toggleReaderWindow),
            keyEquivalent: "h"
        ))
        viewMenu.items.forEach { $0.target = self }
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Moyu"
        item.button?.toolTip = "MoyuReader"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "打开 EPUB...",
            action: #selector(openBook),
            keyEquivalent: "o"
        ))
        menu.addItem(NSMenuItem(
            title: "显示/隐藏",
            action: #selector(toggleReaderWindow),
            keyEquivalent: "h"
        ))
        menu.addItem(NSMenuItem(
            title: "设置...",
            action: #selector(showSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: "书库...",
            action: #selector(showLibrary),
            keyEquivalent: "l"
        ))
        menu.addItem(.separator())
        menu.addItem(makeOpacityMenu())
        menu.addItem(makeTextColorMenu())
        menu.addItem(NSMenuItem(
            title: "增大字体",
            action: #selector(increaseFontSize),
            keyEquivalent: "+"
        ))
        menu.addItem(NSMenuItem(
            title: "减小字体",
            action: #selector(decreaseFontSize),
            keyEquivalent: "-"
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func makeOpacityMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "显示透明度", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in ReaderOpacityOption.allCases {
            let menuItem = NSMenuItem(
                title: option.title,
                action: #selector(setVisibleOpacity(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = option.rawValue
            menuItem.state = option.rawValue == settings.visibleAlpha ? .on : .off
            submenu.addItem(menuItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeTextColorMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "字体颜色", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for option in ReaderTextColorOption.allCases {
            let menuItem = NSMenuItem(
                title: option.title,
                action: #selector(setTextColor(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = option.hex
            menuItem.state = option.hex.caseInsensitiveCompare(settings.textColorHex) == .orderedSame ? .on : .off
            submenu.addItem(menuItem)
        }

        submenu.addItem(.separator())
        let customItem = NSMenuItem(
            title: "自定义...",
            action: #selector(openTextColorPanel),
            keyEquivalent: ""
        )
        customItem.target = self
        submenu.addItem(customItem)

        item.submenu = submenu
        return item
    }

    private func restoreLastBookIfAvailable() {
        guard
            let lastPath = settings.lastBookPath,
            FileManager.default.fileExists(atPath: lastPath)
        else {
            return
        }

        loadBook(at: URL(fileURLWithPath: lastPath), showErrors: false)
    }

    @objc private func openBook() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "打开 EPUB"
        panel.message = "选择一本 EPUB 电子书，在悬浮阅读窗中阅读。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadBook(at: url, showErrors: true)
    }

    @objc private func toggleReaderWindow() {
        guard let window = readerWindowController?.window else {
            openBook()
            return
        }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            showReaderWindow()
        }
    }

    @objc private func increaseFontSize() {
        settings.fontSize = CGFloat(ReaderSettingLimits.clampedFontSize(Double(settings.fontSize + 1)))
        applySettings()
    }

    @objc private func decreaseFontSize() {
        settings.fontSize = CGFloat(ReaderSettingLimits.clampedFontSize(Double(settings.fontSize - 1)))
        applySettings()
    }

    @objc private func setVisibleOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else {
            return
        }

        settings.visibleAlpha = ReaderSettingLimits.clampedAlpha(value)
        applySettings()

        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = item === sender ? .on : .off
            }
        }
    }

    @objc private func setTextColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else {
            return
        }

        settings.textColorHex = hex
        applySettings()
        updateTextColorMenuSelection(sender: sender)
    }

    @objc private func openTextColorPanel() {
        beginAppearancePreviewForColorPanel()
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = settings.textColor
        panel.orderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let hex = sender.color.hexString else {
            return
        }

        settings.textColorHex = hex
        applySettings()
        readerWindowController?.beginAppearancePreview()
        clearTextColorMenuSelection()
    }

    @objc private func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(
            settings: settings,
            onChange: { [weak self] in
                self?.applySettings()
            },
            onColorEditingBegan: { [weak self] in
                self?.beginAppearancePreviewForColorPanel()
            }
        )
        settingsWindowController = controller
        controller.showWindow(nil)
    }

    @objc private func showLibrary() {
        let controller = bookLibraryWindowController ?? BookLibraryWindowController(
            store: bookLibraryStore,
            onOpen: { [weak self] url in
                self?.loadBook(at: url, showErrors: true)
            }
        )
        bookLibraryWindowController = controller
        controller.showWindow(nil)
    }

    @objc private func quit() {
        readerWindowController?.saveWindowFrame()
        NSApplication.shared.terminate(nil)
    }

    private func loadBook(at url: URL, showErrors: Bool) {
        let requestID = UUID()
        latestLoadRequestID = requestID
        let inMemoryBook = bookCache[url.path]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () throws -> PreparedBook in
                if let inMemoryBook {
                    return PreparedBook(book: inMemoryBook, document: ReadingDocument(book: inMemoryBook))
                }

                if let cachedBook = BookParseCache().book(for: url) {
                    return PreparedBook(book: cachedBook, document: ReadingDocument(book: cachedBook))
                }

                let book = try EpubParser().parse(url)
                BookParseCache().store(book, for: url)
                return PreparedBook(book: book, document: ReadingDocument(book: book))
            }
            DispatchQueue.main.async {
                guard let self, self.latestLoadRequestID == requestID else {
                    return
                }

                switch result {
                case .success(let preparedBook):
                    self.bookCache[url.path] = preparedBook.book
                    self.finishLoading(preparedBook, at: url)
                case .failure(let error):
                    if showErrors {
                        self.showOpenError(error)
                    }
                }
            }
        }
    }

    private func finishLoading(_ preparedBook: PreparedBook, at url: URL) {
        let book = preparedBook.book
        currentBook = book
        bookLibraryStore.recordOpened(book: book)
        bookLibraryWindowController?.reload()
        settings.lastBookPath = url.path
        settings.save()

        let controller = readerWindowController ?? ReaderWindowController(
            settings: settings,
            progressStore: progressStore
        )
        controller.onOpenLibrary = { [weak self] in
            self?.showLibrary()
        }
        controller.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        readerWindowController = controller
        controller.load(book: book, document: preparedBook.document)
        showReaderWindow()
        controller.revealTemporarily()
    }

    private func showReaderWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        readerWindowController?.showWindow(nil)
        readerWindowController?.window?.orderFrontRegardless()
    }

    private func applySettings() {
        settings.save()
        readerWindowController?.apply(settings: settings)
        refreshMenuSelections()
    }

    private func beginAppearancePreviewForColorPanel() {
        readerWindowController?.beginAppearancePreview()

        if colorPanelCloseObserver == nil {
            colorPanelCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: NSColorPanel.shared,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.readerWindowController?.endAppearancePreview()
                    if let observer = self?.colorPanelCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    self?.colorPanelCloseObserver = nil
                }
            }
        }
    }

    private func showOpenError(_ error: Error) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "EPUB 打开失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func updateTextColorMenuSelection(sender: NSMenuItem) {
        guard let submenu = sender.menu else {
            return
        }

        for item in submenu.items where item.action == #selector(setTextColor(_:)) {
            item.state = item === sender ? .on : .off
        }
    }

    private func clearTextColorMenuSelection() {
        guard
            let textColorMenu = statusItem?.menu?.items.first(where: { $0.title == "字体颜色" })?.submenu
        else {
            return
        }

        for item in textColorMenu.items where item.action == #selector(setTextColor(_:)) {
            item.state = .off
        }
    }

    private func refreshMenuSelections() {
        guard let menu = statusItem?.menu else {
            return
        }

        if let opacityMenu = menu.items.first(where: { $0.title == "显示透明度" })?.submenu {
            for item in opacityMenu.items {
                guard let value = item.representedObject as? Double else {
                    continue
                }
                item.state = abs(value - settings.visibleAlpha) < 0.001 ? .on : .off
            }
        }

        if let textColorMenu = menu.items.first(where: { $0.title == "字体颜色" })?.submenu {
            for item in textColorMenu.items where item.action == #selector(setTextColor(_:)) {
                guard let hex = item.representedObject as? String else {
                    continue
                }
                item.state = hex.caseInsensitiveCompare(settings.textColorHex) == .orderedSame ? .on : .off
            }
        }
    }
}

private struct PreparedBook: Sendable {
    let book: EpubBook
    let document: ReadingDocument
}

private enum ReaderOpacityOption: Double, CaseIterable {
    case faint = 0.35
    case medium = 0.55
    case clear = 0.75
    case strong = 0.9

    var title: String {
        switch self {
        case .faint:
            "35%"
        case .medium:
            "55%"
        case .clear:
            "75%"
        case .strong:
            "90%"
        }
    }
}

private enum ReaderTextColorOption: CaseIterable {
    case softGray
    case black
    case white
    case amber
    case green
    case cyan

    var title: String {
        switch self {
        case .softGray:
            "柔和灰"
        case .black:
            "黑色"
        case .white:
            "白色"
        case .amber:
            "琥珀色"
        case .green:
            "绿色"
        case .cyan:
            "青蓝色"
        }
    }

    var hex: String {
        switch self {
        case .softGray:
            "#5F6368"
        case .black:
            "#111111"
        case .white:
            "#F2F2F2"
        case .amber:
            "#C9892B"
        case .green:
            "#4E8F58"
        case .cyan:
            "#2B8A9B"
        }
    }
}
