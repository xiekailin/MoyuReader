import Foundation
import MoyuReaderCore

final class BookParseCache {
    private static let formatVersion = 1

    func book(for sourceURL: URL) -> EpubBook? {
        guard
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: Data(contentsOf: cacheURL(for: sourceURL))),
            entry.formatVersion == Self.formatVersion,
            entry.signature == fileSignature(for: sourceURL)
        else {
            return nil
        }
        return entry.book
    }

    func store(_ book: EpubBook, for sourceURL: URL) {
        guard let signature = fileSignature(for: sourceURL) else {
            return
        }

        let entry = CacheEntry(formatVersion: Self.formatVersion, signature: signature, book: book)
        guard let data = try? JSONEncoder().encode(entry) else {
            return
        }

        let url = cacheURL(for: sourceURL)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func cacheURL(for sourceURL: URL) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoyuReader", isDirectory: true)
            .appendingPathComponent("ParsedBooks", isDirectory: true)
        return directory.appendingPathComponent("\(stableHash(sourceURL.path)).json")
    }

    private func fileSignature(for url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        return FileSignature(
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            size: Int64(values.fileSize ?? 0)
        )
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct CacheEntry: Codable {
    let formatVersion: Int
    let signature: FileSignature
    let book: EpubBook
}

private struct FileSignature: Codable, Equatable {
    let modifiedAt: TimeInterval
    let size: Int64
}
