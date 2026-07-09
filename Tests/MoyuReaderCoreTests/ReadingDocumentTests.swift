import Foundation
import Testing
@testable import MoyuReaderCore

@Suite("Reading document")
struct ReadingDocumentTests {
    @Test("builds chapter ranges over composed text")
    func buildsChapterRangesOverComposedText() {
        let book = EpubBook(
            title: "Demo",
            chapters: [
                EpubChapter(id: "c1", title: "One", text: "Alpha"),
                EpubChapter(id: "c2", title: "Two", text: "Beta\nGamma")
            ],
            sourceURL: URL(fileURLWithPath: "/tmp/demo.epub")
        )

        let document = ReadingDocument(book: book)

        #expect(document.text == "Alpha\n\nBeta\nGamma")
        #expect(document.chapters.map(\.title) == ["One", "Two"])
        #expect(document.chapters.map(\.range.lowerBound) == [0, 7])
        #expect(document.chapters.map(\.range.upperBound) == [5, 17])
    }

    @Test("resolves current chapter from character offset")
    func resolvesCurrentChapterFromCharacterOffset() {
        let book = EpubBook(
            title: "Demo",
            chapters: [
                EpubChapter(id: "c1", title: "One", text: "Alpha"),
                EpubChapter(id: "c2", title: "Two", text: "Beta")
            ],
            sourceURL: URL(fileURLWithPath: "/tmp/demo.epub")
        )

        let document = ReadingDocument(book: book)

        #expect(document.chapterIndex(containingCharacterOffset: -10) == 0)
        #expect(document.chapterIndex(containingCharacterOffset: 2) == 0)
        #expect(document.chapterIndex(containingCharacterOffset: 6) == 0)
        #expect(document.chapterIndex(containingCharacterOffset: 7) == 1)
        #expect(document.chapterIndex(containingCharacterOffset: 10_000) == 1)
    }

    @Test("uses first text line when chapter title is not useful")
    func usesFirstTextLineWhenChapterTitleIsNotUseful() {
        let book = EpubBook(
            title: "Demo",
            chapters: [
                EpubChapter(id: "intro", title: "intro", text: "\n真正的章节名\n正文")
            ],
            sourceURL: URL(fileURLWithPath: "/tmp/demo.epub")
        )

        let document = ReadingDocument(book: book)

        #expect(document.chapters[0].title == "真正的章节名")
    }

    @Test("returns isolated chapter text")
    func returnsIsolatedChapterText() {
        let book = EpubBook(
            title: "Demo",
            chapters: [
                EpubChapter(id: "c1", title: "One", text: "第一章\n正文"),
                EpubChapter(id: "c2", title: "Two", text: "第二章\n正文")
            ],
            sourceURL: URL(fileURLWithPath: "/tmp/demo.epub")
        )

        let document = ReadingDocument(book: book)

        #expect(document.chapterText(at: 0) == "第一章\n正文")
        #expect(document.chapterText(at: 1) == "第二章\n正文")
        #expect(document.chapterText(at: 99) == "")
    }
}
