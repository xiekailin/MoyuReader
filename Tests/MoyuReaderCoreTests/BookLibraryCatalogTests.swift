import Foundation
import Testing
@testable import MoyuReaderCore

@Suite("Book library catalog")
struct BookLibraryCatalogTests {
    @Test("keeps recently opened books first")
    func keepsRecentlyOpenedBooksFirst() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)

        let catalog = BookLibraryCatalog(entries: [
            BookLibraryEntry(title: "Old", path: "/tmp/old.epub", lastOpened: oldDate),
            BookLibraryEntry(title: "New", path: "/tmp/new.epub", lastOpened: newDate)
        ])

        #expect(catalog.entries.map(\.title) == ["New", "Old"])
    }

    @Test("recording an existing book updates it instead of duplicating")
    func recordingExistingBookUpdatesItInsteadOfDuplicating() {
        var catalog = BookLibraryCatalog()

        catalog.recordOpened(
            title: "First Title",
            path: "/tmp/book.epub",
            at: Date(timeIntervalSince1970: 100)
        )
        catalog.recordOpened(
            title: "Updated Title",
            path: "/tmp/book.epub",
            at: Date(timeIntervalSince1970: 200)
        )

        #expect(catalog.entries.count == 1)
        #expect(catalog.entries[0].title == "Updated Title")
        #expect(catalog.entries[0].lastOpened == Date(timeIntervalSince1970: 200))
    }

    @Test("removes a book by path")
    func removesBookByPath() {
        var catalog = BookLibraryCatalog(entries: [
            BookLibraryEntry(title: "One", path: "/tmp/one.epub", lastOpened: .distantPast),
            BookLibraryEntry(title: "Two", path: "/tmp/two.epub", lastOpened: .distantPast)
        ])

        catalog.remove(path: "/tmp/one.epub")

        #expect(catalog.entries.map(\.title) == ["Two"])
    }
}
