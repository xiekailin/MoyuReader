import Foundation

public struct EpubBook: Codable, Equatable, Sendable {
    public let title: String
    public let chapters: [EpubChapter]
    public let sourceURL: URL
}

public struct EpubChapter: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let text: String
}

public enum EpubParserError: Error, Equatable, LocalizedError, Sendable {
    case missingContainer
    case missingRootfile
    case missingPackage(String)
    case missingSpine
    case missingManifestItem(String)
    case unreadableChapter(String)
    case unzipFailed(String)
    case malformedXML(String)

    public var errorDescription: String? {
        switch self {
        case .missingContainer:
            "EPUB is missing META-INF/container.xml."
        case .missingRootfile:
            "EPUB container does not point to a package document."
        case .missingPackage(let path):
            "EPUB package document is missing: \(path)."
        case .missingSpine:
            "EPUB package does not contain a readable spine."
        case .missingManifestItem(let id):
            "EPUB spine references a missing manifest item: \(id)."
        case .unreadableChapter(let path):
            "EPUB chapter cannot be read: \(path)."
        case .unzipFailed(let message):
            "EPUB unzip failed: \(message)."
        case .malformedXML(let path):
            "EPUB XML is malformed: \(path)."
        }
    }
}

public struct EpubParser: Sendable {
    fileprivate static let xhtmlEntityReplacements = [
        "&nbsp;": " ",
        "&ensp;": " ",
        "&emsp;": " ",
        "&thinsp;": " ",
        "&mdash;": "-",
        "&ndash;": "-",
        "&lsquo;": "'",
        "&rsquo;": "'",
        "&ldquo;": "\"",
        "&rdquo;": "\"",
        "&hellip;": "...",
        "&copy;": "(c)",
        "&reg;": "(R)",
        "&trade;": "(TM)"
    ]

    public init() {}

    public func parse(_ epubURL: URL) throws -> EpubBook {
        let extractionDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }

        try unzip(epubURL, to: extractionDirectory)

        let containerURL = extractionDirectory
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EpubParserError.missingContainer
        }

        let rootfilePath = try parseContainer(at: containerURL)
        let packageURL = extractionDirectory.appendingPathComponent(rootfilePath)
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            throw EpubParserError.missingPackage(rootfilePath)
        }

        let package = try parsePackage(at: packageURL)
        guard !package.spineIDs.isEmpty else {
            throw EpubParserError.missingSpine
        }

        let packageDirectory = packageURL.deletingLastPathComponent()
        let chapters = try package.spineIDs.compactMap { idref -> EpubChapter? in
            guard let href = package.manifest[idref] else {
                throw EpubParserError.missingManifestItem(idref)
            }

            let decodedHref = href.filePathFromEPUBHref()
            let chapterURL = packageDirectory.appendingPathComponent(decodedHref)
            guard FileManager.default.fileExists(atPath: chapterURL.path) else {
                throw EpubParserError.unreadableChapter(decodedHref)
            }

            let extraction: ChapterExtraction
            do {
                extraction = try extractText(from: chapterURL)
            } catch EpubParserError.unreadableChapter {
                return nil
            } catch EpubParserError.malformedXML {
                return nil
            }

            let title = extraction.preferredTitle
            if extraction.isTableOfContents {
                return nil
            }

            let fallbackTitle = chapterURL.deletingPathExtension().lastPathComponent
            return EpubChapter(
                id: idref,
                title: title.isEmpty ? fallbackTitle : title,
                text: extraction.text
            )
        }

        guard !chapters.isEmpty else {
            throw EpubParserError.missingSpine
        }

        return EpubBook(
            title: package.title.isEmpty ? epubURL.deletingPathExtension().lastPathComponent : package.title,
            chapters: chapters,
            sourceURL: epubURL
        )
    }

    private func unzip(_ epubURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", epubURL.path, "-d", destinationURL.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw EpubParserError.unzipFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func parseContainer(at url: URL) throws -> String {
        let delegate = ContainerXMLDelegate()
        try parseXML(at: url, delegate: delegate)

        guard let rootfilePath = delegate.rootfilePath, !rootfilePath.isEmpty else {
            throw EpubParserError.missingRootfile
        }
        return rootfilePath
    }

    private func parsePackage(at url: URL) throws -> PackageDocument {
        let delegate = PackageXMLDelegate()
        try parseXML(at: url, delegate: delegate)
        return PackageDocument(
            title: delegate.title.normalizedBookText(),
            manifest: delegate.manifest,
            spineIDs: delegate.spineIDs
        )
    }

    private func extractText(from url: URL) throws -> ChapterExtraction {
        let delegate = XHTMLTextDelegate()

        let sourceText = try sanitizedXHTMLText(from: url)
        do {
            try parseXML(
                data: Data(sourceText.utf8),
                sourceDescription: url.lastPathComponent,
                delegate: delegate
            )

            let text = delegate.text.normalizedBookText()
            guard !text.isEmpty else {
                throw EpubParserError.unreadableChapter(url.lastPathComponent)
            }

            return ChapterExtraction(
                title: delegate.title.normalizedBookText(),
                bodyHeading: delegate.bodyHeading.normalizedBookText(),
                text: text
            )
        } catch EpubParserError.malformedXML {
            return try extractLooseHTML(from: sourceText, sourceDescription: url.lastPathComponent)
        }
    }

    private func parseXML(at url: URL, delegate: XMLParserDelegate) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EpubParserError.malformedXML(url.lastPathComponent)
        }

        try parseXML(parser: parser, sourceDescription: url.lastPathComponent, delegate: delegate)
    }

    private func parseXML(
        data: Data,
        sourceDescription: String,
        delegate: XMLParserDelegate
    ) throws {
        let parser = XMLParser(data: data)
        try parseXML(parser: parser, sourceDescription: sourceDescription, delegate: delegate)
    }

    private func parseXML(
        parser: XMLParser,
        sourceDescription: String,
        delegate: XMLParserDelegate
    ) throws {
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            throw EpubParserError.malformedXML(sourceDescription)
        }
    }

    private func sanitizedXHTMLText(from url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EpubParserError.unreadableChapter(url.lastPathComponent)
        }

        guard var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            throw EpubParserError.unreadableChapter(url.lastPathComponent)
        }

        for (entity, replacement) in Self.xhtmlEntityReplacements {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return text
    }

    private func extractLooseHTML(
        from source: String,
        sourceDescription: String
    ) throws -> ChapterExtraction {
        let title = firstCapture(in: source, pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#)?
            .looseHTMLText()
            .normalizedBookText() ?? ""

        var body = firstCapture(in: source, pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#) ?? source
        body = body.replacingOccurrences(
            of: #"(?is)<(script|style|svg)\b[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        body = body.replacingOccurrences(
            of: #"(?i)<br\b[^>]*>"#,
            with: "\n",
            options: .regularExpression
        )

        for element in htmlBlockElementNames {
            body = body.replacingOccurrences(
                of: #"(?i)</?\#(element)\b[^>]*>"#,
                with: "\n",
                options: .regularExpression
            )
        }

        let text = body.looseHTMLText().normalizedBookText()
        guard !text.isEmpty else {
            throw EpubParserError.unreadableChapter(sourceDescription)
        }

        return ChapterExtraction(title: title, bodyHeading: "", text: text)
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[captureRange])
    }
}

private let htmlBlockElementNames: Set<String> = [
    "address", "article", "aside", "blockquote", "body", "dd", "div", "dl", "dt",
    "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
    "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table",
    "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
]

private let htmlIgnoredElementNames: Set<String> = ["script", "style", "svg"]

private struct PackageDocument {
    let title: String
    let manifest: [String: String]
    let spineIDs: [String]
}

private struct ChapterExtraction {
    let title: String
    let bodyHeading: String
    let text: String

    var preferredTitle: String {
        let normalizedHeading = bodyHeading.normalizedBookText()
        let normalizedTitle = title.normalizedBookText()
        return normalizedTitle == "未知" || normalizedTitle.isEmpty ? normalizedHeading : normalizedTitle
    }

    var isTableOfContents: Bool {
        let normalizedTitle = preferredTitle.lowercased()
        guard ["contents", "目录", "table of contents"].contains(normalizedTitle) else {
            return false
        }

        let chapterLines = text.components(separatedBy: .newlines)
            .filter { $0.contains("第") && $0.contains("章") }
        return chapterLines.count >= 5
    }
}

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var rootfilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.normalizedXMLName == "rootfile" else {
            return
        }

        rootfilePath = attributeDict["full-path"]
    }
}

private final class PackageXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var title = ""
    private(set) var manifest: [String: String] = [:]
    private(set) var spineIDs: [String] = []

    private var isReadingTitle = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.normalizedXMLName {
        case "title":
            isReadingTitle = true
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineIDs.append(idref)
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.normalizedXMLName == "title" {
            isReadingTitle = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingTitle {
            title += string
        }
    }
}

private final class XHTMLTextDelegate: NSObject, XMLParserDelegate {
    private(set) var title = ""
    private(set) var bodyHeading = ""
    private(set) var text = ""

    private var isInBody = false
    private var isReadingHeadTitle = false
    private var isReadingBodyHeading = false
    private var ignoredDepth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.normalizedXMLName

        if name == "body" {
            isInBody = true
        }

        if name == "title", !isInBody {
            isReadingHeadTitle = true
        }

        guard isInBody else {
            return
        }

        if htmlIgnoredElementNames.contains(name) {
            ignoredDepth += 1
            return
        }

        if ignoredDepth == 0 {
            if name == "h1", bodyHeading.isEmpty {
                isReadingBodyHeading = true
            }
            if name == "br" {
                appendLineBreak()
            } else if htmlBlockElementNames.contains(name) {
                appendLineBreak()
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.normalizedXMLName

        if name == "title" {
            isReadingHeadTitle = false
        }

        guard isInBody else {
            return
        }

        if htmlIgnoredElementNames.contains(name), ignoredDepth > 0 {
            ignoredDepth -= 1
            return
        }

        if ignoredDepth == 0, htmlBlockElementNames.contains(name) {
            appendLineBreak()
        }

        if name == "h1" {
            isReadingBodyHeading = false
        }

        if name == "body" {
            isInBody = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingHeadTitle {
            title += string
            return
        }

        guard isInBody, ignoredDepth == 0 else {
            return
        }

        if isReadingBodyHeading {
            bodyHeading += string
        }
        appendText(string)
    }

    private func appendText(_ rawText: String) {
        let normalized = rawText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        guard !normalized.isEmpty else {
            return
        }

        if text.last?.isWhitespace == true, normalized.first?.isWhitespace == true {
            text += String(normalized.drop { $0.isWhitespace })
        } else {
            text += normalized
        }
    }

    private func appendLineBreak() {
        let trimmedTrailingSpaces = text.trimmingCharacters(in: .whitespaces)
        text = trimmedTrailingSpaces

        if !text.isEmpty, !text.hasSuffix("\n") {
            text += "\n"
        }
    }
}

private extension String {
    func filePathFromEPUBHref() -> String {
        let withoutFragment = components(separatedBy: "#").first ?? self
        let withoutQuery = withoutFragment.components(separatedBy: "?").first ?? withoutFragment
        return withoutQuery.removingPercentEncoding ?? withoutQuery
    }

    var normalizedXMLName: String {
        let localName = split(separator: ":").last.map(String.init) ?? self
        return localName.lowercased()
    }

    func looseHTMLText() -> String {
        htmlEntityDecoded()
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    func htmlEntityDecoded() -> String {
        var decoded = self
        let replacements = EpubParser.xhtmlEntityReplacements.merging([
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'"
        ]) { current, _ in current }

        for (entity, replacement) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return decoded
        }

        for match in regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed() {
            guard
                let entityRange = Range(match.range(at: 0), in: decoded),
                let valueRange = Range(match.range(at: 1), in: decoded)
            else {
                continue
            }

            let rawValue = String(decoded[valueRange])
            let radix = rawValue.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(rawValue.dropFirst()) : rawValue
            guard
                let scalarValue = UInt32(digits, radix: radix),
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }

            decoded.replaceSubrange(entityRange, with: String(scalar))
        }

        return decoded
    }

    func normalizedBookText() -> String {
        let lines = components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"[ \t]+"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }
}
