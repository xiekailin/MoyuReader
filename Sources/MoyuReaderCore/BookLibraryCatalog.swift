import Foundation

public struct BookLibraryEntry: Codable, Equatable, Identifiable {
    public var id: String { path }

    public let title: String
    public let path: String
    public let lastOpened: Date

    public init(title: String, path: String, lastOpened: Date) {
        self.title = title
        self.path = path
        self.lastOpened = lastOpened
    }
}

public struct BookLibraryCatalog: Codable, Equatable {
    public private(set) var entries: [BookLibraryEntry]

    public init(entries: [BookLibraryEntry] = []) {
        self.entries = entries.sorted { $0.lastOpened > $1.lastOpened }
    }

    public mutating func recordOpened(title: String, path: String, at date: Date = Date()) {
        entries.removeAll { $0.path == path }
        entries.insert(BookLibraryEntry(title: title, path: path, lastOpened: date), at: 0)
    }

    public mutating func remove(path: String) {
        entries.removeAll { $0.path == path }
    }
}
