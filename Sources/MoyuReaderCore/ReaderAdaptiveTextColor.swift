import Foundation

public enum ReaderAdaptiveTextColor {
    public static let lightTextHex = "#F2F2F2"
    public static let darkTextHex = "#3F4147"

    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * clamped(red) + 0.7152 * clamped(green) + 0.0722 * clamped(blue)
    }

    public static func recommendedHexColor(averageLuminance: Double) -> String {
        clamped(averageLuminance) < 0.56 ? lightTextHex : darkTextHex
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(0, value), 1)
    }
}
