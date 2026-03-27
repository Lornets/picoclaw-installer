#!/bin/bash
# ============================================
#  PicoClaw Local AI — One-Click Installer
#  For macOS (Intel & Apple Silicon)
# ============================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="$HOME/.picoclaw"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN} PicoClaw Local AI — One-Click Installer${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo " This will install:"
echo "   - Homebrew (if not installed)"
echo "   - Python 3.11 (if not installed)"
echo "   - Ollama (local AI runtime)"
echo "   - PicoClaw server + dependencies"
echo "   - Recommended AI model for your hardware"
echo ""
read -p " Press Enter to begin or Ctrl+C to cancel..."

# ── Step 1: Homebrew ──
echo ""
echo -e "${BLUE}[1/6] Checking Homebrew...${NC}"
if ! command -v brew &>/dev/null; then
    echo "       Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to PATH for Apple Silicon
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
    echo "       Homebrew installed!"
else
    echo "       Homebrew already installed."
fi

# ── Step 2: Python ──
echo ""
echo -e "${BLUE}[2/6] Checking Python...${NC}"
if ! command -v python3 &>/dev/null || [[ $(python3 -c "import sys; print(sys.version_info >= (3,10))") != "True" ]]; then
    echo "       Installing Python via Homebrew..."
    brew install python@3.11
    echo "       Python installed!"
else
    echo "       Python already installed ($(python3 --version))."
fi

# ── Step 3: Ollama ──
echo ""
echo -e "${BLUE}[3/6] Checking Ollama...${NC}"
if ! command -v ollama &>/dev/null; then
    echo "       Installing Ollama..."
    brew install ollama
    echo "       Ollama installed!"
else
    echo "       Ollama already installed."
fi

# ── Step 4: Copy server files ──
echo ""
echo -e "${BLUE}[4/6] Setting up PicoClaw server...${NC}"
mkdir -p "$INSTALL_DIR/server"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -r "$SCRIPT_DIR/server/"* "$INSTALL_DIR/server/"
chmod +x "$INSTALL_DIR/server/start.sh"
echo "       Server files copied."

# ── Step 5: Install Python dependencies ──
echo ""
echo -e "${BLUE}[5/6] Installing Python packages...${NC}"
python3 -m pip install --quiet --upgrade pip 2>/dev/null || true
python3 -m pip install --quiet -r "$INSTALL_DIR/server/requirements.txt"
echo "       Dependencies installed!"

# ── Step 6: Pull AI model ──
echo ""
echo -e "${BLUE}[6/6] Downloading AI model (this may take a few minutes)...${NC}"

# Start Ollama
ollama serve &>/dev/null &
sleep 3

# Detect RAM
RAM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1073741824}')

if [ "$RAM_GB" -ge 16 ]; then
    MODEL="llama3.2:3b"
    echo "       ${RAM_GB}GB RAM detected — pulling llama3.2:3b..."
elif [ "$RAM_GB" -ge 8 ]; then
    MODEL="llama3.2:3b"
    echo "       ${RAM_GB}GB RAM detected — pulling llama3.2:3b..."
else
    MODEL="llama3.2:1b"
    echo "       ${RAM_GB}GB RAM — pulling llama3.2:1b (lightweight)..."
fi

ollama pull "$MODEL"
echo "       Model ready!"

# ── Create LaunchAgent for auto-start ──
echo ""
echo -e "${BLUE}Setting up auto-start...${NC}"
PLIST_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$PLIST_DIR"
cat > "$PLIST_DIR/com.picoclaw.server.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.picoclaw.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/server/start.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLISTEOF
launchctl load "$PLIST_DIR/com.picoclaw.server.plist" 2>/dev/null || true

# ── Start the server now ──
echo ""
echo "Starting PicoClaw server..."
"$INSTALL_DIR/server/start.sh" &

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN} Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo " PicoClaw is now running at http://localhost:7700"
echo " Return to the Wubba extension to continue setup."
echo ""
