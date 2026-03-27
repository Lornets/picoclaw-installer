@echo off
chcp 65001 >nul 2>&1
title PicoClaw Local AI - Installer
echo.
echo ============================================
echo   PicoClaw Local AI - One-Click Installer
echo ============================================
echo.
echo   This will install:
echo   - Python 3.11 (if not installed)
echo   - Ollama (local AI runtime)
echo   - PicoClaw server + dependencies
echo   - Recommended AI model for your hardware
echo.
echo   Press any key to begin or close this window to cancel.
pause >nul
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0installer\install-picoclaw.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   [ERROR] Installation failed. Check the output above.
    echo   Press any key to close.
    pause >nul
    exit /b 1
)

echo.
echo   Installation complete! PicoClaw is running.
echo   You can close this window.
echo   Press any key to exit.
pause >nul
