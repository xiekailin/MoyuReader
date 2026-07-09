from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path

from .store import _load_json, _save_json, app_data_dir


def clamp(value: float, lower: float, upper: float) -> float:
    return min(max(lower, value), upper)


@dataclass
class ReaderSettings:
    font_size: int = 16
    line_spacing: int = 2
    visible_opacity: float = 0.75
    hidden_opacity: float = 0.02
    background_opacity: float = 0.06
    text_color: str = "#5F6368"
    font_family: str = "Microsoft YaHei UI"
    scroll_step: int = 32
    keep_on_top: bool = True
    width: int = 720
    height: int = 220

    @classmethod
    def load(cls, path: Path | None = None) -> "ReaderSettings":
        settings_path = path or app_data_dir() / "settings.json"
        raw = _load_json(settings_path, {})
        settings = cls(**{key: value for key, value in raw.items() if key in cls.__annotations__})
        settings.clamp_values()
        return settings

    def save(self, path: Path | None = None) -> None:
        self.clamp_values()
        settings_path = path or app_data_dir() / "settings.json"
        _save_json(settings_path, asdict(self))

    def clamp_values(self) -> None:
        self.font_size = int(clamp(self.font_size, 9, 36))
        self.line_spacing = int(clamp(self.line_spacing, 0, 18))
        self.visible_opacity = clamp(self.visible_opacity, 0, 1)
        self.hidden_opacity = clamp(self.hidden_opacity, 0, 1)
        self.background_opacity = clamp(self.background_opacity, 0, 0.45)
        self.scroll_step = int(clamp(self.scroll_step, 12, 72))
        self.width = int(clamp(self.width, 260, 2400))
        self.height = int(clamp(self.height, 100, 1600))
        if not self.text_color.startswith("#") or len(self.text_color) != 7:
            self.text_color = "#5F6368"
        if self.font_family not in {
            "Microsoft YaHei UI",
            "SimSun",
            "KaiTi",
            "Consolas",
        }:
            self.font_family = "Microsoft YaHei UI"
