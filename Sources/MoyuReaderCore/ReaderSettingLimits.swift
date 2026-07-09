import Foundation

public enum ReaderSettingLimits {
    public static let minimumFontSize = 9.0
    public static let maximumFontSize = 36.0
    public static let minimumAlpha = 0.0
    public static let maximumAlpha = 1.0
    public static let minimumLineSpacing = 0.0
    public static let maximumLineSpacing = 18.0
    public static let minimumBackgroundAlpha = 0.0
    public static let maximumBackgroundAlpha = 0.45
    public static let minimumScrollStep = 12.0
    public static let maximumScrollStep = 72.0

    public static func clampedFontSize(_ value: Double) -> Double {
        min(max(value, minimumFontSize), maximumFontSize)
    }

    public static func clampedAlpha(_ value: Double) -> Double {
        min(max(value, minimumAlpha), maximumAlpha)
    }

    public static func clampedLineSpacing(_ value: Double) -> Double {
        min(max(value, minimumLineSpacing), maximumLineSpacing)
    }

    public static func clampedBackgroundAlpha(_ value: Double) -> Double {
        min(max(value, minimumBackgroundAlpha), maximumBackgroundAlpha)
    }

    public static func clampedScrollStep(_ value: Double) -> Double {
        min(max(value, minimumScrollStep), maximumScrollStep)
    }
}
