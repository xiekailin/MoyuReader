import CoreGraphics
import Foundation

struct ReadingProgress {
    let chapterIndex: Int
    let offset: CGFloat

    static let beginning = ReadingProgress(chapterIndex: 0, offset: 0)
}

final class ReadingProgressStore {
    private let defaults: UserDefaults
    private let key = "reader.progressByBookPath"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func progress(for bookPath: String) -> ReadingProgress {
        let values = defaults.dictionary(forKey: key) ?? [:]
        guard let value = values[bookPath] else {
            return .beginning
        }

        if let offset = value as? Double {
            return ReadingProgress(chapterIndex: 0, offset: CGFloat(max(0, offset)))
        }

        guard let progress = value as? [String: Any] else {
            return .beginning
        }

        let chapterIndex = max(0, progress["chapterIndex"] as? Int ?? 0)
        let offset = max(0, progress["offset"] as? Double ?? 0)
        return ReadingProgress(chapterIndex: chapterIndex, offset: CGFloat(offset))
    }

    func offset(for bookPath: String) -> CGFloat {
        progress(for: bookPath).offset
    }

    func save(offset: CGFloat, for bookPath: String) {
        save(
            progress: ReadingProgress(chapterIndex: 0, offset: offset),
            for: bookPath
        )
    }

    func save(progress: ReadingProgress, for bookPath: String) {
        var values = defaults.dictionary(forKey: key) ?? [:]
        values[bookPath] = [
            "chapterIndex": max(0, progress.chapterIndex),
            "offset": Double(max(0, progress.offset))
        ]
        defaults.set(values, forKey: key)
    }
}
