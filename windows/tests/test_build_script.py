from __future__ import annotations

from pathlib import Path


def test_build_script_installs_python_312_when_missing() -> None:
    root = Path(__file__).resolve().parents[1]
    script = (root / "build_windows.ps1").read_text(encoding="utf-8")

    assert "Get-Python312Path" in script
    assert "Install-Python312" in script
    assert "winget install" in script
    assert "Python.Python.3.12" in script
    assert "python.org/ftp/python/3.12.10" in script
    assert 'Join-Path $env:LOCALAPPDATA "MoyuReaderBuild"' in script
    assert "& $PythonExe -m venv $VenvDir" in script
    assert '$VenvVersion -ne "3.12"' in script
    assert "--workpath" in script
    assert "--specpath" in script
    assert 'Join-Path $Root "AppIcon.png"' in script
    assert "--add-data" in script


def test_build_scripts_are_compatible_with_windows_powershell_51() -> None:
    root = Path(__file__).resolve().parents[1]
    powershell_script = (root / "build_windows.ps1").read_text(encoding="utf-8")
    batch_script = (root / "build_windows.bat").read_text(encoding="ascii")

    assert powershell_script.isascii()
    assert '$IconScript = @"' not in powershell_script
    assert 'Join-Path $Root "make_icon.py"' in powershell_script
    assert 'Join-Path $Root "moyureader_launcher.py"' in powershell_script
    assert "--onefile" in powershell_script
    assert batch_script.isascii()
    assert "powershell.exe" in batch_script
    assert "-ExecutionPolicy Bypass" in batch_script
    assert '"%~dp0build_windows.ps1"' in batch_script
    assert "build_windows.log" in batch_script
    assert 'if not exist "%~dp0dist\\MoyuReader.exe"' in batch_script
    assert "pause >nul" in batch_script
    assert "explorer.exe" in batch_script
    assert "Start-Transcript" in powershell_script
    assert "Stop-Transcript" in powershell_script


def test_windows_ci_builds_and_uploads_the_executable() -> None:
    root = Path(__file__).resolve().parents[2]
    workflow_path = root / ".github" / "workflows" / "windows-build.yml"
    if not workflow_path.exists():
        return
    workflow = workflow_path.read_text(encoding="utf-8")

    assert "windows-latest" in workflow
    assert 'python-version: "3.12"' in workflow
    assert "build_windows.ps1 -Clean" in workflow
    assert "dist/MoyuReader.exe" in workflow
    assert "actions/upload-artifact@v4" in workflow
