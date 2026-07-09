from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EpubChapter:
    id: str
    title: str
    text: str


@dataclass(frozen=True)
class EpubBook:
    title: str
    chapters: list[EpubChapter]
    source_path: Path


@dataclass(frozen=True)
class ReadingDocumentChapter:
    index: int
    title: str
    start: int
    end: int


class ReadingDocument:
    def __init__(self, book: EpubBook) -> None:
        self.title = book.title
        self.source_path = book.source_path
        parts: list[str] = []
        chapters: list[ReadingDocumentChapter] = []
        cursor = 0

        for index, chapter in enumerate(book.chapters):
            if parts:
                parts.append("\n\n")
                cursor += 2

            start = cursor
            parts.append(chapter.text)
            cursor += len(chapter.text)
            chapters.append(
                ReadingDocumentChapter(
                    index=index,
                    title=self._display_title(chapter),
                    start=start,
                    end=cursor,
                )
            )

        self.text = "".join(parts)
        self.chapters = chapters

    def chapter_index_containing(self, character_offset: int) -> int:
        if not self.chapters:
            return 0

        clamped = min(max(0, character_offset), max(0, len(self.text) - 1))
        for chapter in self.chapters:
            if chapter.start <= clamped < chapter.end:
                return chapter.index

        prior = [chapter for chapter in self.chapters if chapter.start <= clamped]
        return prior[-1].index if prior else 0

    def chapter_text(self, index: int) -> str:
        if index < 0 or index >= len(self.chapters):
            return ""

        chapter = self.chapters[index]
        return self.text[chapter.start:chapter.end]

    @staticmethod
    def _display_title(chapter: EpubChapter) -> str:
        title = chapter.title.strip()
        if title and title != chapter.id:
            return title

        for line in chapter.text.splitlines():
            clean = line.strip()
            if clean:
                return clean

        return f"章节 {chapter.id}"
