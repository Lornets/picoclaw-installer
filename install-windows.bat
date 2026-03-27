@echo off
title PicoClaw Installer
color 0A
echo.
echo  ============================================
echo   PicoClaw Local AI — One-Click Installer
echo  ============================================
echo.
echo  This will install:
echo    - Python 3.11 (if not installed)
echo    - Ollama (local AI runtime)
echo    - PicoClaw server + dependencies
echo    - Recommended AI model for your hardware
echo.
echo  Press any key to begin or close this window to cancel.
pause >nul

:: ── Check for Admin ──
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Requesting admin privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set INSTALL_DIR=%LOCALAPPDATA%\PicoClaw
mkdir "%INSTALL_DIR%" 2>nul

:: ── Step 1: Python ──
echo.
echo [1/5] Checking Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo       Downloading Python 3.11...
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe' -OutFile '%TEMP%\python-installer.exe'"
    echo       Installing Python silently...
    "%TEMP%\python-installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1
    del "%TEMP%\python-installer.exe"
    :: Refresh PATH
    set "PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%PATH%"
    echo       Python installed!
) else (
    echo       Python already installed.
)

:: ── Step 2: Ollama ──
echo.
echo [2/5] Checking Ollama...
where ollama >nul 2>&1
if %errorlevel% neq 0 (
    echo       Downloading Ollama...
    powershell -Command "Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile '%TEMP%\OllamaSetup.exe'"
    echo       Installing Ollama silently...
    "%TEMP%\OllamaSetup.exe" /VERYSILENT /NORESTART
    del "%TEMP%\OllamaSetup.exe"
    echo       Ollama installed!
) else (
    echo       Ollama already installed.
)

:: ── Step 3: Copy server files ──
echo.
echo [3/5] Setting up PicoClaw server...
set SCRIPT_DIR=%~dp0
xcopy "%SCRIPT_DIR%server\*" "%INSTALL_DIR%\server\" /E /Y /Q >nul
echo       Server files copied.

:: ── Step 4: Install Python dependencies ──
echo.
echo [4/5] Installing Python packages...
python -m pip install --quiet --upgrade pip >nul 2>&1
python -m pip install --quiet -r "%INSTALL_DIR%\server\requirements.txt"
echo       Dependencies installed!

:: ── Step 5: Pull AI model (hardware-aware) ──
echo.
echo [5/5] Downloading AI model (this may take a few minutes)...
:: Start Ollama service first
start /b ollama serve >nul 2>&1
timeout /t 5 /nobreak >nul

:: Detect RAM and pick model
for /f "tokens=2 delims==" %%A in ('wmic computersystem get TotalPhysicalMemory /value 2^>nul') do set RAM_BYTES=%%A
set /a RAM_GB=%RAM_BYTES:~0,-9%

if %RAM_GB% GEQ 16 (
    set MODEL=llama3.2:3b
    echo       16GB+ RAM detected — pulling llama3.2:3b...
) else if %RAM_GB% GEQ 8 (
    set MODEL=llama3.2:3b
    echo       8GB+ RAM detected — pulling llama3.2:3b...
) else (
    set MODEL=llama3.2:1b
    echo       Less than 8GB RAM — pulling llama3.2:1b (lightweight)...
)

ollama pull %MODEL%
echo       Model ready!

:: ── Create Start Menu shortcut ──
echo.
echo Creating Start Menu shortcut...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%APPDATA%\Microsoft\Windows\Start Menu\Programs\PicoClaw Server.lnk'); $s.TargetPath = '%INSTALL_DIR%\server\start.bat'; $s.WorkingDirectory = '%INSTALL_DIR%\server'; $s.Description = 'PicoClaw Local AI Server'; $s.Save()"

:: ── Start the server ──
echo.
echo Starting PicoClaw server...
start "" "%INSTALL_DIR%\server\start.bat"

echo.
echo  ============================================
echo   Installation Complete!
echo  ============================================
echo.
echo  PicoClaw is now running at http://localhost:7700
echo  Return to the Wubba extension to continue setup.
echo.
echo  Press any key to close this window.
pause >nul
