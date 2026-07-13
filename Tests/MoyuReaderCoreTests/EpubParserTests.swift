import Foundation
import Testing
@testable import MoyuReaderCore

@Suite("EPUB parser")
struct EpubParserTests {
    @Test("loads spine chapters in reading order")
    func loadsSpineChaptersInReadingOrder() throws {
        let epubURL = try TestEpubBuilder()
            .addChapter(
                id: "chapter-one",
                href: "Text/chapter1.xhtml",
                title: "Chapter One",
                body: "<h1>Chapter One</h1><p>Hello <em>hidden</em> reader.</p>"
            )
            .addChapter(
                id: "chapter-two",
                href: "Text/chapter2.xhtml",
                title: "Chapter Two",
                body: "<h1>Chapter Two</h1><p>Second page &amp; entities.</p>"
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.title == "Demo Book")
        #expect(book.chapters.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(book.chapters.map(\.text) == [
            "Chapter One\nHello hidden reader.",
            "Chapter Two\nSecond page & entities."
        ])
    }

    @Test("throws a clear error when container metadata is missing")
    func throwsWhenContainerMetadataIsMissing() throws {
        let tempDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let epubURL = tempDirectory.appendingPathComponent("broken.epub")
        try ZipFixtureWriter.write(
            entries: [
                "mimetype": "application/epub+zip"
            ],
            to: epubURL
        )

        #expect(throws: EpubParserError.self) {
            _ = try EpubParser().parse(epubURL)
        }
    }

    @Test("ignores manifest items that are not in the spine")
    func ignoresManifestItemsOutsideSpine() throws {
        let epubURL = try TestEpubBuilder()
            .addChapter(
                id: "chapter-one",
                href: "Text/chapter1.xhtml",
                title: "Chapter One",
                body: "<p>Readable text.</p>"
            )
            .addManifestOnlyItem(
                id: "notes",
                href: "Text/notes.xhtml",
                body: "<p>Not in the reading flow.</p>"
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.chapters.count == 1)
        #expect(book.chapters[0].text == "Readable text.")
    }

    @Test("normalizes common XHTML entities")
    func normalizesCommonXHTMLEntities() throws {
        let epubURL = try TestEpubBuilder()
            .addChapter(
                id: "chapter-one",
                href: "Text/chapter1.xhtml",
                title: "Chapter One",
                body: "<p>A&nbsp;quiet&mdash;line.</p>"
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.chapters[0].text == "A quiet-line.")
    }

    @Test("loads chapter hrefs that include fragments")
    func loadsChapterHrefsThatIncludeFragments() throws {
        let epubURL = try TestEpubBuilder()
            .addChapter(
                id: "chapter-one",
                manifestHref: "Text/chapter1.xhtml#page_1",
                filePath: "Text/chapter1.xhtml",
                title: "Chapter One",
                body: "<p>Fragment target should not affect file loading.</p>"
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.chapters[0].text == "Fragment target should not affect file loading.")
    }

    @Test("falls back for loose HTML chapters")
    func fallsBackForLooseHTMLChapters() throws {
        let epubURL = try TestEpubBuilder()
            .addRawChapter(
                id: "chapter-one",
                href: "Text/chapter1.xhtml",
                contents: """
                <html>
                  <head><title>Loose Chapter</title></head>
                  <body><h1>Loose Chapter</h1><p>First line<br>Second&nbsp;line</p></body>
                </html>
                """
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.chapters[0].title == "Loose Chapter")
        #expect(book.chapters[0].text == "Loose Chapter\nFirst line\nSecond line")
    }

    @Test("uses the body heading when the HTML title is generic")
    func usesBodyHeadingWhenHTMLTitleIsGeneric() throws {
        let epubURL = try TestEpubBuilder()
            .addRawChapter(
                id: "chapter-one",
                href: "Text/chapter1.xhtml",
                contents: """
                <html><head><title>未知</title></head>
                <body><h1>第1章 回魂压棺</h1><p>正文内容。</p></body></html>
                """
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.chapters[0].title == "第1章 回魂压棺")
    }

    @Test("skips unreadable spine items when other chapters are readable")
    func skipsUnreadableSpineItemsWhenOtherChaptersAreReadable() throws {
        let epubURL = try TestEpubBuilder()
            .addRawChapter(
                id: "cover",
                href: "Text/cover.xhtml",
                contents: "<html><body></body></html>"
            )
            .addChapter(
                id: "chapter-one",
                href: "Text/chapter1.xhtml",
                title: "Chapter One",
                body: "<p>Readable chapter.</p>"
            )
            .build()

        let book = try EpubParser().parse(epubURL)

        #expect(book.chapters.map(\.id) == ["chapter-one"])
        #expect(book.chapters[0].text == "Readable chapter.")
    }
}

private struct TestEpubBuilder {
    private var chapters: [ChapterFixture] = []
    private var manifestOnlyItems: [ChapterFixture] = []

    func addChapter(id: String, href: String, title: String, body: String) -> Self {
        var copy = self
        copy.chapters.append(ChapterFixture(
            id: id,
            manifestHref: href,
            filePath: href,
            title: title,
            body: body,
            rawContents: nil
        ))
        return copy
    }

    func addChapter(
        id: String,
        manifestHref: String,
        filePath: String,
        title: String,
        body: String
    ) -> Self {
        var copy = self
        copy.chapters.append(ChapterFixture(
            id: id,
            manifestHref: manifestHref,
            filePath: filePath,
            title: title,
            body: body,
            rawContents: nil
        ))
        return copy
    }

    func addRawChapter(id: String, href: String, contents: String) -> Self {
        var copy = self
        copy.chapters.append(ChapterFixture(
            id: id,
            manifestHref: href,
            filePath: href,
            title: id,
            body: "",
            rawContents: contents
        ))
        return copy
    }

    func addManifestOnlyItem(id: String, href: String, body: String) -> Self {
        var copy = self
        copy.manifestOnlyItems.append(ChapterFixture(
            id: id,
            manifestHref: href,
            filePath: href,
            title: id,
            body: body,
            rawContents: nil
        ))
        return copy
    }

    func build() throws -> URL {
        let tempDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )

        let manifestItems = (chapters + manifestOnlyItems)
            .map { item in
                """
                <item id="\(item.id)" href="\(item.manifestHref)" media-type="application/xhtml+xml"/>
                """
            }
            .joined(separator: "\n")
        let spineItems = chapters
            .map { "<itemref idref=\"\($0.id)\"/>" }
            .joined(separator: "\n")

        var entries: [String: String] = [
            "mimetype": "application/epub+zip",
            "META-INF/container.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """,
            "OPS/package.opf": """
            <?xml version="1.0" encoding="UTF-8"?>
            <package version="3.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Demo Book</dc:title>
              </metadata>
              <manifest>
                \(manifestItems)
              </manifest>
              <spine>
                \(spineItems)
              </spine>
            </package>
            """
        ]

        for chapter in chapters + manifestOnlyItems {
            entries["OPS/\(chapter.filePath)"] = chapter.rawContents ?? """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>\(chapter.title)</title></head>
              <body>\(chapter.body)</body>
            </html>
            """
        }

        let epubURL = tempDirectory.appendingPathComponent("demo.epub")
        try ZipFixtureWriter.write(entries: entries, to: epubURL)
        return epubURL
    }
}

private struct ChapterFixture {
    let id: String
    let manifestHref: String
    let filePath: String
    let title: String
    let body: String
    let rawContents: String?
}

private enum ZipFixtureWriter {
    static func write(entries: [String: String], to destinationURL: URL) throws {
        let tempDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        for (path, contents) in entries {
            let fileURL = tempDirectory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-X", "-q", "-r", destinationURL.path, "."]
        process.currentDirectoryURL = tempDirectory

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
