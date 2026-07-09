import Foundation
import MoyuReaderCore

final class BookLibraryStore {
    private let defaults: UserDefaults
    private let key = "reader.bookLibraryCatalog"

    private(set) var catalog: BookLibraryCatalog

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: key),
            let catalog = try? JSONDecoder().decode(BookLibraryCatalog.self, from: data)
        {
            self.catalog = catalog
        } else {
            self.catalog = BookLibraryCatalog()
        }
    }

    func recordOpened(book: EpubBook) {
        catalog.recordOpened(title: book.title, path: book.sourceURL.path)
        save()
    }

    func remove(path: String) {
        catalog.remove(path: path)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(catalog) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
