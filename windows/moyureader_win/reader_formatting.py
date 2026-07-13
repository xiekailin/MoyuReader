from __future__ import annotations


def line_height_percent(line_spacing: int) -> int:
    """Map the settings slider to a visible QTextBlockFormat line height."""
    spacing = min(max(int(line_spacing), 0), 18)
    return 100 + spacing * 5
