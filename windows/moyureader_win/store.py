from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def app_data_dir() -> Path:
    import os

    root = os.environ.get("APPDATA")
    if root:
        path = Path(root) / "MoyuReader"
    else:
        path = Path.home() / ".moyureader"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def _save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


@dataclass(frozen=True)
class ReadingProgress:
    chapter_index: int = 0
    offset: int = 0


class ProgressStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or app_data_dir() / "progress.json"

    def progress_for(self, book_path: str | Path) -> ReadingProgress:
        values = _load_json(self.path, {})
        raw = values.get(str(book_path), {})
        if isinstance(raw, (int, float)):
            return ReadingProgress(chapter_index=0, offset=max(0, int(raw)))
        if not isinstance(raw, dict):
            return ReadingProgress()
        return ReadingProgress(
            chapter_index=max(0, int(raw.get("chapter_index", 0))),
            offset=max(0, int(raw.get("offset", 0))),
        )

    def save(self, book_path: str | Path, progress: ReadingProgress) -> None:
        values = _load_json(self.path, {})
        values[str(book_path)] = asdict(
            ReadingProgress(
                chapter_index=max(0, progress.chapter_index),
                offset=max(0, progress.offset),
            )
        )
        _save_json(self.path, values)


@dataclass(frozen=True)
class LibraryEntry:
    title: str
    path: str
    last_opened: str


class LibraryStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or app_data_dir() / "library.json"

    def entries(self) -> list[LibraryEntry]:
        raw_entries = _load_json(self.path, [])
        entries: list[LibraryEntry] = []
        for raw in raw_entries:
            if not isinstance(raw, dict):
                continue
            title = str(raw.get("title", "")).strip()
            path = str(raw.get("path", "")).strip()
            last_opened = str(raw.get("last_opened", "")).strip()
            if title and path:
                entries.append(LibraryEntry(title, path, last_opened))
        return sorted(entries, key=lambda entry: entry.last_opened, reverse=True)

    def record(self, title: str, path: str | Path) -> None:
        path_text = str(path)
        entries = [entry for entry in self.entries() if entry.path != path_text]
        entries.insert(
            0,
            LibraryEntry(
                title=title,
                path=path_text,
                last_opened=datetime.now(timezone.utc).isoformat(),
            ),
        )
        _save_json(self.path, [asdict(entry) for entry in entries[:80]])

    def remove(self, path: str | Path) -> None:
        path_text = str(path)
        entries = [entry for entry in self.entries() if entry.path != path_text]
        _save_json(self.path, [asdict(entry) for entry in entries])
