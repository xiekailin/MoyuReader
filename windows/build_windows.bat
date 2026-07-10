@echo off
setlocal
cd /d "%~dp0"

set "LOG_PATH=%~dp0build_windows.log"
del /q "%LOG_PATH%" >nul 2>&1
echo MoyuReader Windows build is starting.
echo This can take several minutes on the first run.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Build failed with exit code %EXIT_CODE%.
    echo Build log: "%LOG_PATH%"
    echo Press any key to close this window.
    pause >nul
    exit /b %EXIT_CODE%
)

if not exist "%~dp0dist\MoyuReader.exe" (
    echo.
    echo Build did not create dist\MoyuReader.exe.
    echo Build log: "%LOG_PATH%"
    echo Press any key to close this window.
    pause >nul
    exit /b 1
)

echo.
echo Build succeeded: "%~dp0dist\MoyuReader.exe"
explorer.exe "%~dp0dist"
echo Press any key to close this window.
pause >nul
exit /b 0
