from __future__ import annotations

from enum import Enum


class ChapterDirection(Enum):
    PREVIOUS = "previous"
    NEXT = "next"


def chapter_destination(current: int, total: int, direction: ChapterDirection) -> int | None:
    if total <= 0:
        return None
    if direction is ChapterDirection.PREVIOUS and current > 0:
        return current - 1
    if direction is ChapterDirection.NEXT and current + 1 < total:
        return current + 1
    return None
