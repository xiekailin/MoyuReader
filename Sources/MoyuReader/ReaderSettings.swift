import AppKit
import CoreGraphics
import Foundation
import MoyuReaderCore

final class ReaderSettings {
    private enum Key {
        static let fontSize = "reader.fontSize"
        static let visibleAlpha = "reader.visibleAlpha"
        static let hiddenAlpha = "reader.hiddenAlpha"
        static let textColorHex = "reader.textColorHex"
        static let lineSpacing = "reader.lineSpacing"
        static let keepWindowOnTop = "reader.keepWindowOnTop"
        static let backgroundAlpha = "reader.backgroundAlpha"
        static let scrollStep = "reader.scrollStep"
        static let fontName = "reader.fontName"
        static let windowFrame = "reader.windowFrame"
        static let lastBookPath = "reader.lastBookPath"
        static let adaptiveTextColor = "reader.adaptiveTextColor"
    }

    var fontSize: CGFloat
    var visibleAlpha: Double
    var hiddenAlpha: Double
    var textColorHex: String
    var lineSpacing: CGFloat
    var keepWindowOnTop: Bool
    var backgroundAlpha: Double
    var scrollStep: Double
    var fontName: String
    var windowFrame: CGRect
    var lastBookPath: String?
    var adaptiveTextColor: Bool

    var textColor: NSColor {
        NSColor(hexString: textColorHex) ?? .labelColor
    }

    private init(
        fontSize: CGFloat,
        visibleAlpha: Double,
        hiddenAlpha: Double,
        textColorHex: String,
        lineSpacing: CGFloat,
        keepWindowOnTop: Bool,
        backgroundAlpha: Double,
        scrollStep: Double,
        fontName: String,
        windowFrame: CGRect,
        lastBookPath: String?,
        adaptiveTextColor: Bool
    ) {
        self.fontSize = CGFloat(ReaderSettingLimits.clampedFontSize(Double(fontSize)))
        self.visibleAlpha = ReaderSettingLimits.clampedAlpha(visibleAlpha)
        self.hiddenAlpha = ReaderSettingLimits.clampedAlpha(hiddenAlpha)
        self.textColorHex = textColorHex
        self.lineSpacing = CGFloat(ReaderSettingLimits.clampedLineSpacing(Double(lineSpacing)))
        self.keepWindowOnTop = keepWindowOnTop
        self.backgroundAlpha = ReaderSettingLimits.clampedBackgroundAlpha(backgroundAlpha)
        self.scrollStep = ReaderSettingLimits.clampedScrollStep(scrollStep)
        self.fontName = Self.validatedFontName(fontName)
        self.windowFrame = windowFrame
        self.lastBookPath = lastBookPath
        self.adaptiveTextColor = adaptiveTextColor
    }

    static func load(defaults: UserDefaults = .standard) -> ReaderSettings {
        let savedFrame = defaults.string(forKey: Key.windowFrame)
            .flatMap(CGRect.initFromString)
        let mainFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 120, y: 120, width: 900, height: 640)
        let defaultFrame = CGRect(
            x: mainFrame.minX + 120,
            y: mainFrame.maxY - 320,
            width: min(720, mainFrame.width - 240),
            height: 220
        )

        let fontSize = ReaderSettingLimits.clampedFontSize(defaults.object(forKey: Key.fontSize) as? Double ?? 16)
        let visibleAlpha = ReaderSettingLimits.clampedAlpha(defaults.object(forKey: Key.visibleAlpha) as? Double ?? 0.75)
        let hiddenAlpha = ReaderSettingLimits.clampedAlpha(defaults.object(forKey: Key.hiddenAlpha) as? Double ?? 0.02)
        let textColorHex = defaults.string(forKey: Key.textColorHex) ?? "#5F6368"
        let lineSpacing = ReaderSettingLimits.clampedLineSpacing(defaults.object(forKey: Key.lineSpacing) as? Double ?? 2)
        let backgroundAlpha = ReaderSettingLimits.clampedBackgroundAlpha(defaults.object(forKey: Key.backgroundAlpha) as? Double ?? 0.06)
        let scrollStep = ReaderSettingLimits.clampedScrollStep(defaults.object(forKey: Key.scrollStep) as? Double ?? 32)
        let fontName = defaults.string(forKey: Key.fontName) ?? ReaderFontOption.monospaced.rawValue

        return ReaderSettings(
            fontSize: CGFloat(fontSize),
            visibleAlpha: visibleAlpha,
            hiddenAlpha: hiddenAlpha,
            textColorHex: textColorHex,
            lineSpacing: CGFloat(lineSpacing),
            keepWindowOnTop: defaults.object(forKey: Key.keepWindowOnTop) as? Bool ?? true,
            backgroundAlpha: backgroundAlpha,
            scrollStep: scrollStep,
            fontName: fontName,
            windowFrame: savedFrame ?? defaultFrame,
            lastBookPath: defaults.string(forKey: Key.lastBookPath),
            adaptiveTextColor: defaults.object(forKey: Key.adaptiveTextColor) as? Bool ?? false
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(ReaderSettingLimits.clampedFontSize(Double(fontSize)), forKey: Key.fontSize)
        defaults.set(ReaderSettingLimits.clampedAlpha(visibleAlpha), forKey: Key.visibleAlpha)
        defaults.set(ReaderSettingLimits.clampedAlpha(hiddenAlpha), forKey: Key.hiddenAlpha)
        defaults.set(textColorHex, forKey: Key.textColorHex)
        defaults.set(ReaderSettingLimits.clampedLineSpacing(Double(lineSpacing)), forKey: Key.lineSpacing)
        defaults.set(keepWindowOnTop, forKey: Key.keepWindowOnTop)
        defaults.set(ReaderSettingLimits.clampedBackgroundAlpha(backgroundAlpha), forKey: Key.backgroundAlpha)
        defaults.set(ReaderSettingLimits.clampedScrollStep(scrollStep), forKey: Key.scrollStep)
        defaults.set(Self.validatedFontName(fontName), forKey: Key.fontName)
        defaults.set(NSStringFromRect(windowFrame), forKey: Key.windowFrame)
        defaults.set(lastBookPath, forKey: Key.lastBookPath)
        defaults.set(adaptiveTextColor, forKey: Key.adaptiveTextColor)
    }

    func resetAppearance() {
        fontSize = 16
        visibleAlpha = 0.75
        hiddenAlpha = 0.02
        textColorHex = "#5F6368"
        lineSpacing = 2
        keepWindowOnTop = true
        backgroundAlpha = 0.06
        scrollStep = 32
        fontName = ReaderFontOption.monospaced.rawValue
        adaptiveTextColor = false
    }

    func readerFont() -> NSFont {
        let option = ReaderFontOption(rawValue: fontName) ?? .monospaced
        switch option {
        case .monospaced:
            return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        case .system:
            return .systemFont(ofSize: fontSize, weight: .regular)
        case .serif:
            return NSFont(name: "Songti SC", size: fontSize)
                ?? NSFont(name: "STSong", size: fontSize)
                ?? .systemFont(ofSize: fontSize, weight: .regular)
        case .rounded:
            return NSFont.systemFont(ofSize: fontSize, weight: .regular)
        }
    }

    private static func validatedFontName(_ value: String) -> String {
        ReaderFontOption(rawValue: value)?.rawValue ?? ReaderFontOption.monospaced.rawValue
    }
}

enum ReaderFontOption: String, CaseIterable {
    case monospaced
    case system
    case serif
    case rounded

    var title: String {
        switch self {
        case .monospaced:
            "系统等宽"
        case .system:
            "系统默认"
        case .serif:
            "宋体阅读"
        case .rounded:
            "圆体"
        }
    }
}

private extension CGRect {
    static func initFromString(_ value: String) -> CGRect? {
        let rect = NSRectFromString(value)
        return rect.isEmpty ? nil : rect
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        let sanitized = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard
            sanitized.count == 6,
            let value = Int(sanitized, radix: 16)
        else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String? {
        guard let color = usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
