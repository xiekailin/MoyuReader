import Testing
@testable import MoyuReaderCore

@Suite("Reader adaptive text color")
struct ReaderAdaptiveTextColorTests {
    @Test("uses light text on dark backgrounds")
    func usesLightTextOnDarkBackgrounds() {
        let luminance = ReaderAdaptiveTextColor.luminance(red: 0.08, green: 0.09, blue: 0.1)

        #expect(ReaderAdaptiveTextColor.recommendedHexColor(averageLuminance: luminance) == "#F2F2F2")
    }

    @Test("uses dark text on light backgrounds")
    func usesDarkTextOnLightBackgrounds() {
        let luminance = ReaderAdaptiveTextColor.luminance(red: 0.92, green: 0.9, blue: 0.86)

        #expect(ReaderAdaptiveTextColor.recommendedHexColor(averageLuminance: luminance) == "#3F4147")
    }
}
