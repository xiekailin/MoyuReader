from __future__ import annotations

from dataclasses import dataclass
from enum import IntFlag


class ResizeEdges(IntFlag):
    NONE = 0
    LEFT = 1
    TOP = 2
    RIGHT = 4
    BOTTOM = 8


@dataclass(frozen=True)
class WindowGeometry:
    x: int
    y: int
    width: int
    height: int

    @property
    def right(self) -> int:
        return self.x + self.width

    @property
    def bottom(self) -> int:
        return self.y + self.height


def edge_at(
    x: int,
    y: int,
    width: int,
    height: int,
    margin: int = 12,
) -> ResizeEdges:
    edges = ResizeEdges.NONE
    if x <= margin:
        edges |= ResizeEdges.LEFT
    elif x >= width - margin:
        edges |= ResizeEdges.RIGHT
    if y <= margin:
        edges |= ResizeEdges.TOP
    elif y >= height - margin:
        edges |= ResizeEdges.BOTTOM
    return edges


def resize_geometry(
    start: WindowGeometry,
    delta_x: int,
    delta_y: int,
    edges: ResizeEdges,
    minimum_width: int = 260,
    minimum_height: int = 100,
) -> WindowGeometry:
    left = start.x
    top = start.y
    right = start.right
    bottom = start.bottom

    if edges & ResizeEdges.LEFT:
        left = min(start.x + delta_x, right - minimum_width)
    elif edges & ResizeEdges.RIGHT:
        right = max(start.right + delta_x, left + minimum_width)

    if edges & ResizeEdges.TOP:
        top = min(start.y + delta_y, bottom - minimum_height)
    elif edges & ResizeEdges.BOTTOM:
        bottom = max(start.bottom + delta_y, top + minimum_height)

    return WindowGeometry(left, top, right - left, bottom - top)
