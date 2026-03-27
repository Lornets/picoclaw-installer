#!/bin/bash
cd "$(dirname "$0")"

# Start Ollama in background
ollama serve &>/dev/null &
sleep 2

# Start FastAPI server
echo "PicoClaw server starting on http://localhost:7700 ..."
python3 -m uvicorn main:app --host 0.0.0.0 --port 7700 --log-level warning
