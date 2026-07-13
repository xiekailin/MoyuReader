public enum ReaderChapterNavigation {
    public enum Direction {
        case previous
        case next
    }

    public static func destination(current: Int, total: Int, direction: Direction) -> Int? {
        guard total > 0 else {
            return nil
        }

        switch direction {
        case .previous where current > 0:
            return current - 1
        case .next where current + 1 < total:
            return current + 1
        default:
            return nil
        }
    }

    public static func direction(forKeyCode keyCode: UInt16) -> Direction? {
        switch keyCode {
        case 123:
            .previous
        case 124:
            .next
        default:
            nil
        }
    }
}
