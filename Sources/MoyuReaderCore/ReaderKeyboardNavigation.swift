public enum ReaderKeyboardNavigation {
    public enum Action: Equatable {
        case previousChapter
        case nextChapter
        case scrollUp
        case scrollDown
    }

    public static func action(forKeyCode keyCode: UInt16) -> Action? {
        switch keyCode {
        case 123:
            .previousChapter
        case 124:
            .nextChapter
        case 126:
            .scrollUp
        case 125:
            .scrollDown
        default:
            nil
        }
    }
}
