import Testing
@testable import MoyuReaderCore

@Suite("Reader scroll math")
struct ReaderScrollMathTests {
    @Test("scrolling down increases the document offset")
    func scrollingDownIncreasesOffset() {
        let offset = ReaderScrollMath.nextOffset(
            current: 100,
            wheelDeltaY: -1,
            maxOffset: 500,
            isPrecise: false
        )

        #expect(offset == 132)
    }

    @Test("scrolling up decreases the document offset")
    func scrollingUpDecreasesOffset() {
        let offset = ReaderScrollMath.nextOffset(
            current: 100,
            wheelDeltaY: 1,
            maxOffset: 500,
            isPrecise: false
        )

        #expect(offset == 68)
    }

    @Test("clamps at scroll boundaries")
    func clampsAtScrollBoundaries() {
        let top = ReaderScrollMath.nextOffset(
            current: 2,
            wheelDeltaY: 10,
            maxOffset: 500,
            isPrecise: false
        )
        let bottom = ReaderScrollMath.nextOffset(
            current: 498,
            wheelDeltaY: -10,
            maxOffset: 500,
            isPrecise: false
        )

        #expect(top == 0)
        #expect(bottom == 500)
    }

    @Test("precise scrolling keeps native pixel deltas")
    func preciseScrollingKeepsNativePixelDeltas() {
        let offset = ReaderScrollMath.nextOffset(
            current: 100,
            wheelDeltaY: -7.5,
            maxOffset: 500,
            isPrecise: true
        )

        #expect(offset == 107.5)
    }

    @Test("custom wheel step changes standard mouse scrolling")
    func customWheelStepChangesStandardMouseScrolling() {
        let offset = ReaderScrollMath.nextOffset(
            current: 100,
            wheelDeltaY: -1,
            maxOffset: 500,
            isPrecise: false,
            wheelStep: 48
        )

        #expect(offset == 148)
    }

    @Test("smooth scrolling moves toward target without overshooting")
    func smoothScrollingMovesTowardTarget() {
        let downward = ReaderScrollMath.smoothedOffset(
            current: 100,
            target: 200,
            response: 0.32,
            minimumStep: 0.75
        )
        let nearTarget = ReaderScrollMath.smoothedOffset(
            current: 199.7,
            target: 200,
            response: 0.28,
            minimumStep: 0.75
        )

        #expect(downward == 132)
        #expect(nearTarget == 200)
    }

    @Test("animation frame interval follows 60 to 240 fps displays")
    func animationFrameIntervalFollowsHighRefreshDisplays() {
        #expect(ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: 60) == 1.0 / 60.0)
        #expect(ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: 120) == 1.0 / 120.0)
        #expect(ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: 144) == 1.0 / 144.0)
        #expect(ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: 240) == 1.0 / 240.0)
        #expect(ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: 300) == 1.0 / 240.0)
        #expect(ReaderScrollMath.animationFrameInterval(maximumFramesPerSecond: 0) == 1.0 / 60.0)
    }

    @Test("chapter progress percent is clamped and rounded")
    func chapterProgressPercentIsClampedAndRounded() {
        #expect(ReaderScrollMath.progressPercent(offset: 350, maxOffset: 1_000) == 35)
        #expect(ReaderScrollMath.progressPercent(offset: -20, maxOffset: 1_000) == 0)
        #expect(ReaderScrollMath.progressPercent(offset: 1_200, maxOffset: 1_000) == 100)
        #expect(ReaderScrollMath.progressPercent(offset: 0, maxOffset: 0) == 100)
    }
}
