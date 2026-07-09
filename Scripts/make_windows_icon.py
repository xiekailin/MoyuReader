from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Resources" / "AppIcon.png"
TARGET = ROOT / "Resources" / "AppIcon.ico"


def main() -> int:
    image = Image.open(SOURCE).convert("RGBA")
    image.save(
        TARGET,
        sizes=[
            (16, 16),
            (24, 24),
            (32, 32),
            (48, 48),
            (64, 64),
            (128, 128),
            (256, 256),
        ],
    )
    print(TARGET)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
