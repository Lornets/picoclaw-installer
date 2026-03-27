@echo off
title PicoClaw Server
cd /d "%~dp0"

:: Start Ollama in background
start /b ollama serve >nul 2>&1
timeout /t 3 /nobreak >nul

:: Start FastAPI server
echo PicoClaw server starting on http://localhost:7700 ...
python -m uvicorn main:app --host 0.0.0.0 --port 7700 --log-level warning
