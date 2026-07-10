from __future__ import annotations

from pathlib import Path

from moyureader_win.epub import EpubParser, build_test_epub
from moyureader_win.models import EpubBook, EpubChapter, ReadingDocument
from moyureader_win.scrolling import animation_interval_ms, next_offset, progress_percent, smoothed_offset
from moyureader_win.settings import ReaderSettings
from moyureader_win.store import LibraryStore, ProgressStore, ReadingProgress
from moyureader_win.window_geometry import ResizeEdges, WindowGeometry, edge_at, resize_geometry


def test_reading_document_returns_isolated_chapter_text() -> None:
    book = EpubBook(
        title="Demo",
        chapters=[
            EpubChapter(id="c1", title="一", text="第一章\n正文"),
            EpubChapter(id="c2", title="二", text="第二章\n正文"),
        ],
        source_path=Path("demo.epub"),
    )

    document = ReadingDocument(book)

    assert document.chapter_text(0) == "第一章\n正文"
    assert document.chapter_text(1) == "第二章\n正文"
    assert document.chapter_text(9) == ""


def test_epub_parser_loads_chapters(tmp_path: Path) -> None:
    epub_path = build_test_epub(
        tmp_path / "demo.epub",
        [
            ("c1", "第一章", "风平浪静。"),
            ("c2", "第二章", "继续阅读。"),
        ],
    )

    book = EpubParser().parse(epub_path)

    assert book.title == "测试书"
    assert [chapter.title for chapter in book.chapters] == ["第一章", "第二章"]
    assert "风平浪静" in book.chapters[0].text


def test_progress_store_saves_chapter_and_offset(tmp_path: Path) -> None:
    store = ProgressStore(tmp_path / "progress.json")

    store.save("book.epub", ReadingProgress(chapter_index=3, offset=260))

    assert store.progress_for("book.epub") == ReadingProgress(chapter_index=3, offset=260)


def test_library_store_keeps_recent_books_first(tmp_path: Path) -> None:
    store = LibraryStore(tmp_path / "library.json")

    store.record("旧书", "old.epub")
    store.record("新书", "new.epub")

    assert [entry.title for entry in store.entries()] == ["新书", "旧书"]


def test_scrolling_math_targets_high_refresh_displays() -> None:
    assert next_offset(100, -1, 500, precise=False) == 132
    assert next_offset(100, -1, 500, precise=False, wheel_step=48) == 148
    assert next_offset(100, -7.5, 500, precise=True) == 107.5
    assert smoothed_offset(100, 200) == 132
    assert smoothed_offset(199.7, 200) == 200
    assert animation_interval_ms(60) == 17
    assert animation_interval_ms(144) == 7
    assert animation_interval_ms(240) == 4
    assert animation_interval_ms(300) == 4


def test_progress_percent_is_clamped() -> None:
    assert progress_percent(350, 1000) == 35
    assert progress_percent(-20, 1000) == 0
    assert progress_percent(1200, 1000) == 100
    assert progress_percent(0, 0) == 100


def test_settings_clamp_more_appearance_options() -> None:
    settings = ReaderSettings(
        background_opacity=9,
        scroll_step=99,
        font_family="BadFont",
        text_color="bad",
    )

    settings.clamp_values()

    assert settings.background_opacity == 0.45
    assert settings.scroll_step == 72
    assert settings.font_family == "Microsoft YaHei UI"
    assert settings.text_color == "#5F6368"


def test_window_geometry_detects_all_four_corners() -> None:
    assert edge_at(2, 2, 720, 220) == ResizeEdges.TOP | ResizeEdges.LEFT
    assert edge_at(718, 2, 720, 220) == ResizeEdges.TOP | ResizeEdges.RIGHT
    assert edge_at(2, 218, 720, 220) == ResizeEdges.BOTTOM | ResizeEdges.LEFT
    assert edge_at(718, 218, 720, 220) == ResizeEdges.BOTTOM | ResizeEdges.RIGHT


def test_window_geometry_resizes_from_top_left_and_keeps_minimum() -> None:
    start = WindowGeometry(100, 200, 720, 220)

    resized = resize_geometry(start, -80, -60, ResizeEdges.TOP | ResizeEdges.LEFT)
    assert resized == WindowGeometry(20, 140, 800, 280)

    clamped = resize_geometry(start, 900, 900, ResizeEdges.TOP | ResizeEdges.LEFT)
    assert clamped.width == 260
    assert clamped.height == 100
    assert clamped.right == start.right
    assert clamped.bottom == start.bottom
