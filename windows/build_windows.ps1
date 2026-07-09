param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Get-Python311Path {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        try {
            $path = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null | Select-Object -Last 1).Trim()
            if ($path -and (Test-Path $path)) {
                return $path
            }
        } catch {
        }
    }

    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:ProgramFiles\Python311\python.exe",
        "${env:ProgramFiles(x86)}\Python311\python.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    foreach ($name in @("python", "python3")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (!$command) {
            continue
        }

        try {
            $version = (& $command.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null | Select-Object -Last 1).Trim()
            if ($version -eq "3.11") {
                return $command.Source
            }
        } catch {
        }
    }

    return $null
}

function Install-Python311 {
    Write-Host "未检测到 Python 3.11，开始自动安装..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install `
            --id Python.Python.3.11 `
            --exact `
            --source winget `
            --scope user `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget 安装 Python 3.11 失败。"
        }
    } else {
        $installerUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
        $installerPath = Join-Path $env:TEMP "python-3.11.9-amd64.exe"
        Write-Host "未检测到 winget，改用 python.org 安装器：$installerUrl"
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        & $installerPath /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1 Include_test=0
        if ($LASTEXITCODE -ne 0) {
            throw "python.org 安装器执行失败。"
        }
    }

    $pythonPath = Get-Python311Path
    if (!$pythonPath) {
        throw "Python 3.11 已安装，但当前 PowerShell 仍未定位到 python.exe。请重新打开 PowerShell 后再运行本脚本。"
    }

    return $pythonPath
}

if ($Clean) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue build, dist, .venv
}

$PythonExe = Get-Python311Path
if (!$PythonExe) {
    $PythonExe = Install-Python311
}
Write-Host "使用 Python：$PythonExe"

if (!(Test-Path .venv)) {
    & $PythonExe -m venv .venv
}

& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
& .\.venv\Scripts\python.exe -m pytest

$IconArgs = @()
$DataArgs = @()
$PngIconPath = Join-Path $Root "AppIcon.png"
$IconPath = Join-Path $Root "AppIcon.ico"
if (!(Test-Path $IconPath)) {
    & .\.venv\Scripts\python.exe -m pip install Pillow
    $IconScript = @"
from pathlib import Path
from PIL import Image

root = Path(r"$Root")
source = root / "AppIcon.png"
target = root / "AppIcon.ico"
if source.exists():
    image = Image.open(source).convert("RGBA")
    image.save(target, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
"@
    & .\.venv\Scripts\python.exe -c $IconScript
}
if (Test-Path $IconPath) {
    $IconArgs = @("--icon", $IconPath)
}
if (Test-Path $PngIconPath) {
    $DataArgs = @("--add-data", "$PngIconPath;Resources")
}

& .\.venv\Scripts\pyinstaller.exe `
    --noconfirm `
    --windowed `
    --name MoyuReader `
    @IconArgs `
    @DataArgs `
    -m moyureader_win

Write-Host "Windows 可执行文件：$Root\dist\MoyuReader\MoyuReader.exe"
