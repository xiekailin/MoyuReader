import Foundation

public struct ReadingDocument: Equatable, Sendable {
    public let title: String
    public let text: String
    public let chapters: [ReadingDocumentChapter]
    public let sourceURL: URL

    public init(book: EpubBook) {
        var composedText = ""
        var composedChapters: [ReadingDocumentChapter] = []

        for (index, chapter) in book.chapters.enumerated() {
            if !composedText.isEmpty {
                composedText += "\n\n"
            }

            let start = composedText.count
            composedText += chapter.text
            let end = composedText.count

            composedChapters.append(ReadingDocumentChapter(
                index: index,
                title: Self.displayTitle(for: chapter),
                range: start..<end
            ))
        }

        title = book.title
        text = composedText
        chapters = composedChapters
        sourceURL = book.sourceURL
    }

    public func chapterIndex(containingCharacterOffset offset: Int) -> Int {
        guard !chapters.isEmpty else {
            return 0
        }

        let clampedOffset = min(max(0, offset), max(0, text.count - 1))

        if let chapter = chapters.first(where: { $0.range.contains(clampedOffset) }) {
            return chapter.index
        }

        let priorChapter = chapters.last { $0.range.lowerBound <= clampedOffset }
        return priorChapter?.index ?? 0
    }

    public func chapterText(at index: Int) -> String {
        guard chapters.indices.contains(index) else {
            return ""
        }

        let range = chapters[index].range
        let startIndex = text.index(text.startIndex, offsetBy: range.lowerBound)
        let endIndex = text.index(text.startIndex, offsetBy: range.upperBound)
        return String(text[startIndex..<endIndex])
    }

    private static func displayTitle(for chapter: EpubChapter) -> String {
        let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty, title != chapter.id {
            return title
        }

        let firstLine = chapter.text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return firstLine ?? "Chapter \(chapter.id)"
    }
}

public struct ReadingDocumentChapter: Equatable, Identifiable, Sendable {
    public var id: Int { index }

    public let index: Int
    public let title: String
    public let range: Range<Int>
}
