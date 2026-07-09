import Testing
@testable import MoyuReaderCore

@Suite("Reader setting limits")
struct ReaderSettingLimitsTests {
    @Test("clamps font size")
    func clampsFontSize() {
        #expect(ReaderSettingLimits.clampedFontSize(4) == 9)
        #expect(ReaderSettingLimits.clampedFontSize(18) == 18)
        #expect(ReaderSettingLimits.clampedFontSize(72) == 36)
    }

    @Test("clamps alpha")
    func clampsAlpha() {
        #expect(ReaderSettingLimits.clampedAlpha(-0.5) == 0)
        #expect(ReaderSettingLimits.clampedAlpha(0.45) == 0.45)
        #expect(ReaderSettingLimits.clampedAlpha(1.5) == 1)
    }

    @Test("clamps line spacing")
    func clampsLineSpacing() {
        #expect(ReaderSettingLimits.clampedLineSpacing(-2) == 0)
        #expect(ReaderSettingLimits.clampedLineSpacing(8) == 8)
        #expect(ReaderSettingLimits.clampedLineSpacing(40) == 18)
    }

    @Test("clamps background alpha")
    func clampsBackgroundAlpha() {
        #expect(ReaderSettingLimits.clampedBackgroundAlpha(-0.2) == 0)
        #expect(ReaderSettingLimits.clampedBackgroundAlpha(0.18) == 0.18)
        #expect(ReaderSettingLimits.clampedBackgroundAlpha(1.0) == 0.45)
    }

    @Test("clamps scroll step")
    func clampsScrollStep() {
        #expect(ReaderSettingLimits.clampedScrollStep(8) == 12)
        #expect(ReaderSettingLimits.clampedScrollStep(32) == 32)
        #expect(ReaderSettingLimits.clampedScrollStep(96) == 72)
    }
}
