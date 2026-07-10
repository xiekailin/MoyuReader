from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "AppIcon.png"
TARGET = ROOT / "AppIcon.ico"
ICON_SIZES = [
    (16, 16),
    (24, 24),
    (32, 32),
    (48, 48),
    (64, 64),
    (128, 128),
    (256, 256),
]


def main() -> int:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Icon source was not found: {SOURCE}")

    image = Image.open(SOURCE).convert("RGBA")
    image.save(TARGET, sizes=ICON_SIZES)
    print(TARGET)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
