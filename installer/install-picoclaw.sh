#!/bin/bash
# PicoClaw Installer for macOS
# Installs Python, Ollama, pulls a small model, sets up the server

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PICO_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$PICO_DIR/server"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${CYAN}[$1/$2] $3${NC}"; }

echo ""
echo "============================================"
echo "  PicoClaw Local AI - Installer (macOS)"
echo "============================================"
echo ""

TOTAL=5

# Step 1: Python
step 1 $TOTAL "Checking Python..."
if command -v python3 &>/dev/null; then
    echo "      Python3 already installed."
else
    echo "      Installing Python via Homebrew..."
    if ! command -v brew &>/dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install python@3.11
fi

# Step 2: Ollama
step 2 $TOTAL "Checking Ollama..."
if command -v ollama &>/dev/null; then
    echo "      Ollama already installed."
else
    echo "      Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    echo -e "      ${GREEN}Ollama installed.${NC}"
fi

# Step 3: Pull model
step 3 $TOTAL "Pulling AI model..."
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
echo "      Detected ${RAM_GB}GB RAM"

if [ "$RAM_GB" -ge 16 ]; then
    MODEL="llama3.2:3b"
    echo "      Pulling llama3.2:3b (~2GB)"
else
    MODEL="llama3.2:1b"
    echo "      Pulling llama3.2:1b (~1.3GB)"
fi

# Start ollama serve if needed
if ! pgrep -x "ollama" > /dev/null; then
    ollama serve &>/dev/null &
    sleep 3
fi

ollama pull "$MODEL"
echo -e "      ${GREEN}Model ready!${NC}"

# Step 4: Python dependencies
step 4 $TOTAL "Installing dependencies..."
if [ -f "$SERVER_DIR/requirements.txt" ]; then
    python3 -m pip install -r "$SERVER_DIR/requirements.txt" --quiet 2>/dev/null
else
    python3 -m pip install fastapi uvicorn chromadb ollama --quiet 2>/dev/null
fi
echo -e "      ${GREEN}Dependencies installed.${NC}"

# Step 5: Start server
step 5 $TOTAL "Starting PicoClaw server..."
if [ -f "$SERVER_DIR/main.py" ]; then
    cd "$SERVER_DIR"
    nohup python3 -m uvicorn main:app --host 127.0.0.1 --port 7700 &>/dev/null &
    sleep 2
    if curl -sf http://localhost:7700/api/health > /dev/null 2>&1; then
        echo -e "      ${GREEN}Server running on http://localhost:7700${NC}"
    else
        echo -e "      ${YELLOW}Server started but may need a moment...${NC}"
    fi
else
    echo -e "      ${YELLOW}server/main.py not found.${NC}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   PicoClaw installation complete!          ${NC}"
echo -e "${GREEN}   Server: http://localhost:7700            ${NC}"
echo -e "${GREEN}   Model:  $MODEL                          ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
