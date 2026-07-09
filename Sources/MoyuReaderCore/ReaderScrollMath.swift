import Foundation

public enum ReaderScrollMath {
    public static let standardWheelStep = 32.0
    public static let minimumFramesPerSecond = 60
    public static let maximumFramesPerSecond = 240

    public static func nextOffset(
        current: Double,
        wheelDeltaY: Double,
        maxOffset: Double,
        isPrecise: Bool,
        wheelStep: Double = Self.standardWheelStep
    ) -> Double {
        let multiplier = isPrecise ? 1.0 : wheelStep
        let proposed = current - wheelDeltaY * multiplier
        return min(max(0, proposed), max(0, maxOffset))
    }

    public static func smoothedOffset(
        current: Double,
        target: Double,
        response: Double,
        minimumStep: Double
    ) -> Double {
        let distance = target - current
        guard abs(distance) > minimumStep else {
            return target
        }

        let clampedResponse = min(max(0, response), 1)
        let proposedStep = distance * clampedResponse
        let signedMinimumStep = distance > 0 ? minimumStep : -minimumStep
        let step = abs(proposedStep) < minimumStep ? signedMinimumStep : proposedStep
        let proposed = current + step

        return distance > 0 ? min(proposed, target) : max(proposed, target)
    }

    public static func animationFrameInterval(maximumFramesPerSecond: Int) -> Double {
        let framesPerSecond = min(
            max(Self.minimumFramesPerSecond, maximumFramesPerSecond),
            Self.maximumFramesPerSecond
        )
        return 1.0 / Double(framesPerSecond)
    }

    public static func progressPercent(offset: Double, maxOffset: Double) -> Int {
        guard maxOffset > 0 else {
            return 100
        }

        let clampedOffset = min(max(0, offset), maxOffset)
        return Int((clampedOffset / maxOffset * 100).rounded())
    }
}
