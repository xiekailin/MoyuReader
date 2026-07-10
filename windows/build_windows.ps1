param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Get-Python312Path {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        try {
            $path = (& py -3.12 -c "import sys; print(sys.executable)" 2>$null | Select-Object -Last 1).Trim()
            if ($path -and (Test-Path $path)) {
                return $path
            }
        } catch {
        }
    }

    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe"
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
            if ($version -eq "3.12") {
                return $command.Source
            }
        } catch {
        }
    }

    return $null
}

function Assert-ExitCode {
    param(
        [string]$Step,
        [int]$ExitCode
    )

    if ($ExitCode -ne 0) {
        throw "$Step failed with exit code $ExitCode."
    }
}

function Install-Python312 {
    Write-Host "Python 3.12 was not found. Installing it now..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install `
            --id Python.Python.3.12 `
            --exact `
            --source winget `
            --scope user `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements
        Assert-ExitCode "winget Python installation" $LASTEXITCODE
    } else {
        $installerUrl = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
        $installerPath = Join-Path $env:TEMP "python-3.12.10-amd64.exe"
        Write-Host "winget was not found. Downloading Python from $installerUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        & $installerPath /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1 Include_test=0
        Assert-ExitCode "python.org Python installation" $LASTEXITCODE
    }

    $pythonPath = Get-Python312Path
    if (!$pythonPath) {
        throw "Python 3.12 was installed, but python.exe could not be located. Reopen the terminal and run this script again."
    }

    return $pythonPath
}

$LogPath = Join-Path $Root "build_windows.log"
$TranscriptStarted = $false
try {
    Start-Transcript -Path $LogPath -Force | Out-Null
    $TranscriptStarted = $true
} catch {
    Write-Warning "Build logging could not be started: $_"
}

try {
if ($Clean) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue build, dist, .venv
}

$PythonExe = Get-Python312Path
if (!$PythonExe) {
    $PythonExe = Install-Python312
}
Write-Host "Using Python: $PythonExe"

$VenvPython = Join-Path $Root ".venv\Scripts\python.exe"
if ((Test-Path .venv) -and !(Test-Path $VenvPython)) {
    Remove-Item -Recurse -Force .venv
}
if (Test-Path $VenvPython) {
    $VenvVersion = (& $VenvPython -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null | Select-Object -Last 1).Trim()
    if ($VenvVersion -ne "3.12") {
        Write-Host "Recreating virtual environment for Python 3.12..."
        Remove-Item -Recurse -Force .venv
    }
}
if (!(Test-Path $VenvPython)) {
    & $PythonExe -m venv .venv
    Assert-ExitCode "virtual environment creation" $LASTEXITCODE
}

& $VenvPython -m pip install --upgrade pip
Assert-ExitCode "pip upgrade" $LASTEXITCODE
& $VenvPython -m pip install -r requirements.txt
Assert-ExitCode "dependency installation" $LASTEXITCODE
& $VenvPython -m pytest
Assert-ExitCode "test suite" $LASTEXITCODE

$IconArgs = @()
$DataArgs = @()
$PngIconPath = Join-Path $Root "AppIcon.png"
$IconPath = Join-Path $Root "AppIcon.ico"
$IconScriptPath = Join-Path $Root "make_icon.py"
$LauncherPath = Join-Path $Root "moyureader_launcher.py"
if (!(Test-Path $IconPath)) {
    & $VenvPython -m pip install Pillow
    Assert-ExitCode "Pillow installation" $LASTEXITCODE
    & $VenvPython $IconScriptPath
    Assert-ExitCode "Windows icon generation" $LASTEXITCODE
}
if (Test-Path $IconPath) {
    $IconArgs = @("--icon", $IconPath)
}
if (Test-Path $PngIconPath) {
    $DataArgs = @("--add-data", "$PngIconPath;Resources")
}

& $VenvPython -m PyInstaller `
    --noconfirm `
    --clean `
    --windowed `
    --onefile `
    --name MoyuReader `
    @IconArgs `
    @DataArgs `
    $LauncherPath
Assert-ExitCode "PyInstaller build" $LASTEXITCODE

Write-Host "Windows executable: $Root\dist\MoyuReader.exe"
} finally {
    if ($TranscriptStarted) {
        Stop-Transcript | Out-Null
    }
}
