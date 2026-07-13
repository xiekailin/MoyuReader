import Testing
@testable import MoyuReaderCore

@Suite("Reader chapter navigation")
struct ReaderChapterNavigationTests {
    @Test("stops at the first and last chapter")
    func stopsAtBookBoundaries() {
        #expect(ReaderChapterNavigation.destination(current: 0, total: 3, direction: .previous) == nil)
        #expect(ReaderChapterNavigation.destination(current: 2, total: 3, direction: .next) == nil)
    }

    @Test("moves one chapter in each direction")
    func movesOneChapter() {
        #expect(ReaderChapterNavigation.destination(current: 1, total: 3, direction: .previous) == 0)
        #expect(ReaderChapterNavigation.destination(current: 1, total: 3, direction: .next) == 2)
    }

    @Test("maps macOS left and right arrow key codes")
    func mapsArrowKeyCodes() {
        #expect(ReaderChapterNavigation.direction(forKeyCode: 123) == .previous)
        #expect(ReaderChapterNavigation.direction(forKeyCode: 124) == .next)
        #expect(ReaderChapterNavigation.direction(forKeyCode: 125) == nil)
    }

    @Test("maps macOS up and down arrow key codes")
    func mapsVerticalArrowKeyCodes() {
        #expect(ReaderKeyboardNavigation.action(forKeyCode: 126) == .scrollUp)
        #expect(ReaderKeyboardNavigation.action(forKeyCode: 125) == .scrollDown)
        #expect(ReaderKeyboardNavigation.action(forKeyCode: 124) == .nextChapter)
    }
}
