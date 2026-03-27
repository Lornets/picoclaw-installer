# PicoClaw Installer for Windows
# Installs Python, Ollama, pulls a small model, sets up the server

$ErrorActionPreference = "Stop"
$picoDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$serverDir = Join-Path $picoDir "server"
$tempDir = Join-Path $env:TEMP "picoclaw-install"

if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

function Write-Step($num, $total, $msg) {
    Write-Host ""
    Write-Host "[$num/$total] $msg" -ForegroundColor Cyan
}

function Download-WithRetry($url, $outPath, $label) {
    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Host "      Downloading $label (attempt $i/$maxRetries)..."
        try {
            # Use curl.exe for reliable downloads with progress
            $curlArgs = @('-L', '-o', $outPath, '--progress-bar', '--retry', '3', '--retry-delay', '3', $url)
            & curl.exe @curlArgs
            if ($LASTEXITCODE -eq 0 -and (Test-Path $outPath)) {
                $size = (Get-Item $outPath).Length
                if ($size -gt 1MB) {
                    Write-Host "      Download complete ($([math]::Round($size / 1MB, 1)) MB)" -ForegroundColor Green
                    return $true
                }
            }
            Write-Host "      Download too small or failed, retrying..." -ForegroundColor Yellow
        } catch {
            Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        if ($i -lt $maxRetries) { Start-Sleep -Seconds 3 }
    }
    Write-Host "      Failed to download $label after $maxRetries attempts." -ForegroundColor Red
    return $false
}

$totalSteps = 5

# ── Step 1: Python ──
Write-Step 1 $totalSteps "Checking Python..."

$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python 3\.\d+") {
            $pythonCmd = $cmd
            break
        }
    } catch {}
}

if ($pythonCmd) {
    Write-Host "      Python already installed ($pythonCmd)." -ForegroundColor Green
} else {
    $pyInstaller = Join-Path $tempDir "python-installer.exe"
    $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    $ok = Download-WithRetry $pyUrl $pyInstaller "Python 3.11"
    if (-not $ok) { throw "Failed to download Python" }

    Write-Host "      Installing Python silently..."
    Start-Process -FilePath $pyInstaller -ArgumentList "/quiet", "InstallAllUsers=0", "PrependPath=1", "Include_pip=1" -Wait -NoNewWindow
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $pythonCmd = "python"
    Write-Host "      Python installed." -ForegroundColor Green
}

# ── Step 2: Ollama ──
Write-Step 2 $totalSteps "Checking Ollama..."

$ollamaInstalled = $false
try {
    $ollamaVer = & ollama --version 2>&1
    if ($ollamaVer -match "ollama") { $ollamaInstalled = $true }
} catch {}

if ($ollamaInstalled) {
    Write-Host "      Ollama already installed." -ForegroundColor Green
} else {
    $ollamaInstaller = Join-Path $tempDir "OllamaSetup.exe"
    $ollamaUrl = "https://ollama.com/download/OllamaSetup.exe"
    $ok = Download-WithRetry $ollamaUrl $ollamaInstaller "Ollama"
    if (-not $ok) { throw "Failed to download Ollama" }

    # Validate file size (Ollama installer should be > 50MB)
    $fileSize = (Get-Item $ollamaInstaller).Length
    if ($fileSize -lt 50MB) {
        throw "Ollama installer appears corrupt (only $([math]::Round($fileSize / 1MB, 1)) MB). Please check your internet connection."
    }

    Write-Host "      Installing Ollama silently..."
    Start-Process -FilePath $ollamaInstaller -ArgumentList "/VERYSILENT", "/NORESTART" -Wait -NoNewWindow
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "      Ollama installed." -ForegroundColor Green
}

# ── Step 3: Pull Model ──
Write-Step 3 $totalSteps "Pulling AI model..."

# Detect RAM to choose model
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Write-Host "      Detected ${ram}GB RAM"

if ($ram -ge 16) {
    $model = "llama3.2:3b"
    Write-Host "      Pulling llama3.2:3b (~2GB) - good for 16GB+ systems"
} else {
    $model = "llama3.2:1b"
    Write-Host "      Pulling llama3.2:1b (~1.3GB) - optimized for your hardware"
}

# Start Ollama serve in background if not running
try {
    $ollamaRunning = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
    if (-not $ollamaRunning) {
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
    }
} catch {}

Write-Host "      Downloading model (this may take a few minutes)..."
& ollama pull $model
if ($LASTEXITCODE -ne 0) {
    Write-Host "      Warning: Model pull may have failed. You can retry later." -ForegroundColor Yellow
} else {
    Write-Host "      Model ready!" -ForegroundColor Green
}

# ── Step 4: Install Python dependencies ──
Write-Step 4 $totalSteps "Installing PicoClaw server dependencies..."

if (Test-Path (Join-Path $serverDir "requirements.txt")) {
    & $pythonCmd -m pip install -r (Join-Path $serverDir "requirements.txt") --quiet --disable-pip-version-check 2>&1 | Out-Null
    Write-Host "      Dependencies installed." -ForegroundColor Green
} else {
    Write-Host "      Warning: requirements.txt not found in server/" -ForegroundColor Yellow
    & $pythonCmd -m pip install fastapi uvicorn chromadb ollama --quiet --disable-pip-version-check 2>&1 | Out-Null
    Write-Host "      Core dependencies installed." -ForegroundColor Green
}

# ── Step 5: Start server ──
Write-Step 5 $totalSteps "Starting PicoClaw server..."

$mainPy = Join-Path $serverDir "main.py"
if (Test-Path $mainPy) {
    Start-Process $pythonCmd -ArgumentList "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "7700" -WorkingDirectory $serverDir -WindowStyle Hidden
    Start-Sleep -Seconds 2
    
    # Verify it's running
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:7700/api/health" -TimeoutSec 5
        Write-Host "      Server running! Version: $($health.version)" -ForegroundColor Green
    } catch {
        Write-Host "      Server started but health check pending. It may need a moment." -ForegroundColor Yellow
    }
} else {
    Write-Host "      Warning: server/main.py not found. Server not started." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   PicoClaw installation complete!          " -ForegroundColor Green
Write-Host "   Server: http://localhost:7700            " -ForegroundColor Green
Write-Host "   Model:  $model                          " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Cleanup temp files
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
