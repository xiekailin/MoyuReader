import Foundation

public struct ReaderResizeGeometry: Equatable {
    public struct Rect: Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct Point: Equatable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Edge: Equatable {
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    public static func edge(
        at point: Point,
        in size: (width: Double, height: Double),
        threshold: Double
    ) -> Edge? {
        let nearLeft = point.x <= threshold
        let nearRight = point.x >= size.width - threshold
        let nearBottom = point.y <= threshold
        let nearTop = point.y >= size.height - threshold

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _):
            return .topLeft
        case (_, true, true, _):
            return .topRight
        case (true, _, _, true):
            return .bottomLeft
        case (_, true, _, true):
            return .bottomRight
        case (true, _, _, _):
            return .left
        case (_, true, _, _):
            return .right
        case (_, _, true, _):
            return .top
        case (_, _, _, true):
            return .bottom
        default:
            return nil
        }
    }

    public static func resizedFrame(
        original: Rect,
        edge: Edge,
        delta: Point,
        minimumSize: (width: Double, height: Double)
    ) -> Rect {
        var x = original.x
        var y = original.y
        var width = original.width
        var height = original.height

        if edge.affectsLeft {
            let proposedWidth = width - delta.x
            let clampedWidth = max(minimumSize.width, proposedWidth)
            x += width - clampedWidth
            width = clampedWidth
        }

        if edge.affectsRight {
            width = max(minimumSize.width, width + delta.x)
        }

        if edge.affectsBottom {
            let proposedHeight = height - delta.y
            let clampedHeight = max(minimumSize.height, proposedHeight)
            y += height - clampedHeight
            height = clampedHeight
        }

        if edge.affectsTop {
            height = max(minimumSize.height, height + delta.y)
        }

        return Rect(x: x, y: y, width: width, height: height)
    }
}

private extension ReaderResizeGeometry.Edge {
    var affectsLeft: Bool {
        self == .left || self == .topLeft || self == .bottomLeft
    }

    var affectsRight: Bool {
        self == .right || self == .topRight || self == .bottomRight
    }

    var affectsTop: Bool {
        self == .top || self == .topLeft || self == .topRight
    }

    var affectsBottom: Bool {
        self == .bottom || self == .bottomLeft || self == .bottomRight
    }
}
