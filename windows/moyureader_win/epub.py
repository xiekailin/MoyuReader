from __future__ import annotations

import posixpath
import re
import tempfile
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote
from xml.etree import ElementTree

from .models import EpubBook, EpubChapter


class EpubParseError(Exception):
    pass


class _TextExtractor(HTMLParser):
    block_tags = {
        "address",
        "article",
        "aside",
        "blockquote",
        "br",
        "div",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "li",
        "p",
        "section",
        "tr",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self._in_title = False
        self._skip_depth = 0
        self._chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag in {"script", "style"}:
            self._skip_depth += 1
            return

        if tag == "title":
            self._in_title = True

        if tag in self.block_tags:
            self._push_newline()

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"script", "style"} and self._skip_depth > 0:
            self._skip_depth -= 1
            return

        if tag == "title":
            self._in_title = False

        if tag in self.block_tags:
            self._push_newline()

    def handle_data(self, data: str) -> None:
        if self._skip_depth > 0:
            return

        if self._in_title:
            self.title += data

        clean = re.sub(r"[ \t\r\f\v]+", " ", data)
        if clean.strip():
            self._chunks.append(clean)

    def text(self) -> str:
        value = "".join(self._chunks)
        lines = [line.strip() for line in value.splitlines()]
        clean_lines = [line for line in lines if line]
        return "\n".join(clean_lines)

    def _push_newline(self) -> None:
        if self._chunks and not self._chunks[-1].endswith("\n"):
            self._chunks.append("\n")


class EpubParser:
    container_path = "META-INF/container.xml"

    def parse(self, epub_path: str | Path) -> EpubBook:
        path = Path(epub_path)
        if not path.exists():
            raise EpubParseError(f"EPUB 文件不存在：{path}")

        with zipfile.ZipFile(path) as archive:
            package_path = self._package_path(archive)
            package_xml = self._read_text(archive, package_path)
            package = ElementTree.fromstring(package_xml)
            title = self._metadata_title(package) or path.stem
            manifest = self._manifest(package)
            spine = self._spine(package)
            base_dir = posixpath.dirname(package_path)
            chapters: list[EpubChapter] = []

            for idref in spine:
                href = manifest.get(idref)
                if not href:
                    continue

                chapter_path = self._resolve_href(base_dir, href)
                try:
                    chapter_html = self._read_text(archive, chapter_path)
                except KeyError:
                    continue

                extractor = _TextExtractor()
                extractor.feed(chapter_html)
                text = extractor.text()
                if not text:
                    continue

                chapters.append(
                    EpubChapter(
                        id=idref,
                        title=extractor.title.strip(),
                        text=text,
                    )
                )

        if not chapters:
            raise EpubParseError("EPUB 没有可阅读章节。")

        return EpubBook(title=title, chapters=chapters, source_path=path)

    def _package_path(self, archive: zipfile.ZipFile) -> str:
        try:
            container_xml = self._read_text(archive, self.container_path)
        except KeyError as error:
            raise EpubParseError("EPUB 缺少 META-INF/container.xml。") from error

        root = ElementTree.fromstring(container_xml)
        for element in root.iter():
            if self._local_name(element.tag) == "rootfile":
                full_path = element.attrib.get("full-path")
                if full_path:
                    return full_path

        raise EpubParseError("EPUB 容器没有指向 OPF 文件。")

    def _metadata_title(self, package: ElementTree.Element) -> str:
        for element in package.iter():
            if self._local_name(element.tag) == "title" and element.text:
                return element.text.strip()
        return ""

    def _manifest(self, package: ElementTree.Element) -> dict[str, str]:
        values: dict[str, str] = {}
        for element in package.iter():
            if self._local_name(element.tag) != "item":
                continue

            item_id = element.attrib.get("id")
            href = element.attrib.get("href")
            if item_id and href:
                values[item_id] = href
        return values

    def _spine(self, package: ElementTree.Element) -> list[str]:
        values: list[str] = []
        for element in package.iter():
            if self._local_name(element.tag) == "itemref":
                idref = element.attrib.get("idref")
                if idref:
                    values.append(idref)
        return values

    @staticmethod
    def _read_text(archive: zipfile.ZipFile, path: str) -> str:
        data = archive.read(path)
        for encoding in ("utf-8-sig", "utf-8", "gb18030"):
            try:
                return data.decode(encoding)
            except UnicodeDecodeError:
                continue
        return data.decode("utf-8", errors="replace")

    @staticmethod
    def _resolve_href(base_dir: str, href: str) -> str:
        clean_href = unquote(href.split("#", 1)[0])
        return posixpath.normpath(posixpath.join(base_dir, clean_href))

    @staticmethod
    def _local_name(tag: str) -> str:
        if "}" in tag:
            return tag.rsplit("}", 1)[1]
        return tag


def build_test_epub(epub_path: Path, chapters: list[tuple[str, str, str]]) -> Path:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        meta = root / "META-INF"
        oebps = root / "OEBPS"
        meta.mkdir()
        oebps.mkdir()
        (root / "mimetype").write_text("application/epub+zip", encoding="utf-8")
        (meta / "container.xml").write_text(
            """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
""",
            encoding="utf-8",
        )

        manifest_items: list[str] = []
        spine_items: list[str] = []
        for index, (item_id, title, body) in enumerate(chapters, start=1):
            file_name = f"chapter{index}.xhtml"
            manifest_items.append(
                f'<item id="{item_id}" href="{file_name}" media-type="application/xhtml+xml"/>'
            )
            spine_items.append(f'<itemref idref="{item_id}"/>')
            (oebps / file_name).write_text(
                f"""<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>{title}</title></head>
<body><h1>{title}</h1><p>{body}</p></body>
</html>
""",
                encoding="utf-8",
            )

        (oebps / "content.opf").write_text(
            f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">test-book</dc:identifier>
    <dc:title>测试书</dc:title>
  </metadata>
  <manifest>
    {"".join(manifest_items)}
  </manifest>
  <spine>
    {"".join(spine_items)}
  </spine>
</package>
""",
            encoding="utf-8",
        )

        with zipfile.ZipFile(epub_path, "w") as archive:
            archive.write(root / "mimetype", "mimetype", compress_type=zipfile.ZIP_STORED)
            for file_path in sorted(root.rglob("*")):
                if file_path.is_file() and file_path.name != "mimetype":
                    archive.write(file_path, file_path.relative_to(root).as_posix())

    return epub_path
