import AppKit
import MoyuReaderCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: ReaderSettings
    private let onChange: () -> Void
    private let onColorEditingBegan: () -> Void

    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontSizeSlider = NSSlider()
    private let fontSizeValueLabel = NSTextField(labelWithString: "")
    private let lineSpacingSlider = NSSlider()
    private let lineSpacingValueLabel = NSTextField(labelWithString: "")
    private let visibleAlphaSlider = NSSlider()
    private let visibleAlphaValueLabel = NSTextField(labelWithString: "")
    private let hiddenAlphaSlider = NSSlider()
    private let hiddenAlphaValueLabel = NSTextField(labelWithString: "")
    private let backgroundAlphaSlider = NSSlider()
    private let backgroundAlphaValueLabel = NSTextField(labelWithString: "")
    private let scrollStepSlider = NSSlider()
    private let scrollStepValueLabel = NSTextField(labelWithString: "")
    private let colorWell = PreviewColorWell()
    private let adaptiveTextColorCheckbox = NSButton()
    private let keepOnTopCheckbox = NSButton()

    init(
        settings: ReaderSettings,
        onChange: @escaping () -> Void,
        onColorEditingBegan: @escaping () -> Void
    ) {
        self.settings = settings
        self.onChange = onChange
        self.onColorEditingBegan = onColorEditingBegan

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MoyuReader 设置"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = makeContentView()
        syncControlsFromSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        syncControlsFromSettings()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        root.addSubview(stack)

        stack.addArrangedSubview(makeTitleLabel("阅读"))
        stack.addArrangedSubview(makeFontRow())
        configureSlider(
            fontSizeSlider,
            min: ReaderSettingLimits.minimumFontSize,
            max: ReaderSettingLimits.maximumFontSize
        )
        stack.addArrangedSubview(makeSliderRow(
            title: "字体大小",
            slider: fontSizeSlider,
            valueLabel: fontSizeValueLabel
        ))

        configureSlider(
            lineSpacingSlider,
            min: ReaderSettingLimits.minimumLineSpacing,
            max: ReaderSettingLimits.maximumLineSpacing
        )
        stack.addArrangedSubview(makeSliderRow(
            title: "行距",
            slider: lineSpacingSlider,
            valueLabel: lineSpacingValueLabel
        ))

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeTitleLabel("隐蔽显示"))
        configureSlider(
            visibleAlphaSlider,
            min: ReaderSettingLimits.minimumAlpha,
            max: ReaderSettingLimits.maximumAlpha
        )
        stack.addArrangedSubview(makeSliderRow(
            title: "悬停透明度",
            slider: visibleAlphaSlider,
            valueLabel: visibleAlphaValueLabel
        ))

        configureSlider(
            hiddenAlphaSlider,
            min: ReaderSettingLimits.minimumAlpha,
            max: ReaderSettingLimits.maximumAlpha
        )
        stack.addArrangedSubview(makeSliderRow(
            title: "鼠标移出透明度",
            slider: hiddenAlphaSlider,
            valueLabel: hiddenAlphaValueLabel
        ))

        configureSlider(
            backgroundAlphaSlider,
            min: ReaderSettingLimits.minimumBackgroundAlpha,
            max: ReaderSettingLimits.maximumBackgroundAlpha
        )
        stack.addArrangedSubview(makeSliderRow(
            title: "背景透明度",
            slider: backgroundAlphaSlider,
            valueLabel: backgroundAlphaValueLabel
        ))

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeTitleLabel("外观"))
        stack.addArrangedSubview(makeColorRow())

        adaptiveTextColorCheckbox.title = "根据背景自动调整文字颜色"
        adaptiveTextColorCheckbox.setButtonType(.switch)
        adaptiveTextColorCheckbox.target = self
        adaptiveTextColorCheckbox.action = #selector(controlChanged)
        stack.addArrangedSubview(adaptiveTextColorCheckbox)

        configureSlider(
            scrollStepSlider,
            min: ReaderSettingLimits.minimumScrollStep,
            max: ReaderSettingLimits.maximumScrollStep
        )
        stack.addArrangedSubview(makeSliderRow(
            title: "滚动速度",
            slider: scrollStepSlider,
            valueLabel: scrollStepValueLabel
        ))

        keepOnTopCheckbox.title = "阅读窗保持在其他应用上方"
        keepOnTopCheckbox.setButtonType(.switch)
        keepOnTopCheckbox.target = self
        keepOnTopCheckbox.action = #selector(controlChanged)
        stack.addArrangedSubview(keepOnTopCheckbox)

        let resetButton = NSButton(
            title: "恢复默认外观",
            target: self,
            action: #selector(resetAppearance)
        )
        resetButton.bezelStyle = .rounded
        stack.addArrangedSubview(resetButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        return root
    }

    private func configureSlider(_ slider: NSSlider, min: Double, max: Double) {
        slider.minValue = min
        slider.maxValue = max
        slider.target = self
        slider.action = #selector(controlChanged)
        slider.isContinuous = true
    }

    private func makeTitleLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeSliderRow(
        title: String,
        slider: NSSlider,
        valueLabel: NSTextField
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true

        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func makeFontRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let titleLabel = NSTextField(labelWithString: "字体")
        titleLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true

        for option in ReaderFontOption.allCases {
            fontPopup.addItem(withTitle: option.title)
            fontPopup.lastItem?.representedObject = option.rawValue
        }
        fontPopup.target = self
        fontPopup.action = #selector(controlChanged)
        fontPopup.widthAnchor.constraint(equalToConstant: 260).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(fontPopup)
        return row
    }

    private func makeColorRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let titleLabel = NSTextField(labelWithString: "字体颜色")
        titleLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true

        colorWell.target = self
        colorWell.action = #selector(controlChanged)
        colorWell.onActivate = { [weak self] in
            self?.onColorEditingBegan()
        }
        colorWell.widthAnchor.constraint(equalToConstant: 52).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(colorWell)
        return row
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 460).isActive = true
        return separator
    }

    private func syncControlsFromSettings() {
        selectFont(settings.fontName)
        fontSizeSlider.doubleValue = Double(settings.fontSize)
        lineSpacingSlider.doubleValue = Double(settings.lineSpacing)
        visibleAlphaSlider.doubleValue = settings.visibleAlpha
        hiddenAlphaSlider.doubleValue = settings.hiddenAlpha
        backgroundAlphaSlider.doubleValue = settings.backgroundAlpha
        scrollStepSlider.doubleValue = settings.scrollStep
        colorWell.color = settings.textColor
        adaptiveTextColorCheckbox.state = settings.adaptiveTextColor ? .on : .off
        colorWell.isEnabled = !settings.adaptiveTextColor
        keepOnTopCheckbox.state = settings.keepWindowOnTop ? .on : .off
        refreshValueLabels()
    }

    private func refreshValueLabels() {
        fontSizeValueLabel.stringValue = "\(Int(round(fontSizeSlider.doubleValue))) pt"
        lineSpacingValueLabel.stringValue = "\(Int(round(lineSpacingSlider.doubleValue)))"
        visibleAlphaValueLabel.stringValue = "\(Int(round(visibleAlphaSlider.doubleValue * 100)))%"
        hiddenAlphaValueLabel.stringValue = "\(Int(round(hiddenAlphaSlider.doubleValue * 100)))%"
        backgroundAlphaValueLabel.stringValue = "\(Int(round(backgroundAlphaSlider.doubleValue * 100)))%"
        scrollStepValueLabel.stringValue = "\(Int(round(scrollStepSlider.doubleValue)))"
    }

    @objc private func controlChanged() {
        if let fontName = fontPopup.selectedItem?.representedObject as? String {
            settings.fontName = fontName
        }
        settings.fontSize = CGFloat(ReaderSettingLimits.clampedFontSize(fontSizeSlider.doubleValue))
        settings.lineSpacing = CGFloat(ReaderSettingLimits.clampedLineSpacing(lineSpacingSlider.doubleValue))
        settings.visibleAlpha = ReaderSettingLimits.clampedAlpha(visibleAlphaSlider.doubleValue)
        settings.hiddenAlpha = ReaderSettingLimits.clampedAlpha(hiddenAlphaSlider.doubleValue)
        settings.backgroundAlpha = ReaderSettingLimits.clampedBackgroundAlpha(backgroundAlphaSlider.doubleValue)
        settings.scrollStep = ReaderSettingLimits.clampedScrollStep(scrollStepSlider.doubleValue)
        settings.textColorHex = colorWell.color.hexString ?? settings.textColorHex
        settings.adaptiveTextColor = adaptiveTextColorCheckbox.state == .on
        settings.keepWindowOnTop = keepOnTopCheckbox.state == .on
        colorWell.isEnabled = !settings.adaptiveTextColor
        settings.save()
        refreshValueLabels()
        onChange()
    }

    private func selectFont(_ fontName: String) {
        for index in 0..<fontPopup.numberOfItems {
            if fontPopup.item(at: index)?.representedObject as? String == fontName {
                fontPopup.selectItem(at: index)
                return
            }
        }
        fontPopup.selectItem(at: 0)
    }

    @objc private func resetAppearance() {
        settings.resetAppearance()
        settings.save()
        syncControlsFromSettings()
        onChange()
    }
}

private final class PreviewColorWell: NSColorWell {
    var onActivate: (() -> Void)?

    override func activate(_ exclusive: Bool) {
        onActivate?()
        super.activate(exclusive)
    }
}
