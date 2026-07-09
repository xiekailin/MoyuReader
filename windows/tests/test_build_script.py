from __future__ import annotations

from pathlib import Path


def test_build_script_installs_python_311_when_missing() -> None:
    script = (Path(__file__).resolve().parents[1] / "build_windows.ps1").read_text(
        encoding="utf-8"
    )

    assert "Get-Python311Path" in script
    assert "Install-Python311" in script
    assert "winget install" in script
    assert "Python.Python.3.11" in script
    assert "python.org/ftp/python/3.11.9" in script
    assert "& $PythonExe -m venv .venv" in script
    assert 'Join-Path $Root "AppIcon.png"' in script
    assert "--add-data" in script
