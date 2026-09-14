#!/bin/bash
# PropGuardian VPS Deployment — Ubuntu 24.04 + Wine + MetaTrader 5
#
# This script automates the setup of a headless Linux VPS to run
# MetaTrader 5 via Wine with virtual framebuffer (Xvfb).
#
# Architecture:
#   Ubuntu 24.04 LTS (OVH VPS)
#   ├── Xvfb          Virtual framebuffer (headless display)
#   ├── x11vnc         VNC access for debugging
#   ├── Wine           Windows compatibility layer
#   ├── MetaTrader 5   Trading platform
#   ├── systemd        Auto-restart on crash
#   └── Bash scripts   Health checks + deploy automation
#
# Usage:
#   scp deploy_vps.sh vps:~/
#   ssh vps "chmod +x deploy_vps.sh && sudo ./deploy_vps.sh"

set -euo pipefail

echo "=========================================="
echo "  PropGuardian VPS Setup — Ubuntu 24.04"
echo "=========================================="

# ── System updates ────────────────────────────────────
echo "[1/6] Updating system..."
apt-get update && apt-get upgrade -y
apt-get install -y \
    wget curl gnupg2 software-properties-common \
    xvfb x11vnc xdotool \
    unzip cabextract

# ── Wine installation ─────────────────────────────────
echo "[2/6] Installing Wine..."
dpkg --add-architecture i386
mkdir -pm755 /etc/apt/keyrings
wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
apt-get update
apt-get install -y --install-recommends winehq-stable

# ── Create trading user ──────────────────────────────
echo "[3/6] Creating trading user..."
useradd -m -s /bin/bash trader 2>/dev/null || true

# ── Xvfb virtual display ─────────────────────────────
echo "[4/6] Setting up virtual display..."
cat > /etc/systemd/system/xvfb.service << 'EOF'
[Unit]
Description=Xvfb Virtual Framebuffer
After=network.target

[Service]
Type=simple
User=trader
ExecStart=/usr/bin/Xvfb :99 -screen 0 1024x768x16
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xvfb
systemctl start xvfb

# ── MetaTrader 5 installation ────────────────────────
echo "[5/6] Installing MetaTrader 5..."
su - trader << 'TRADEREOF'
export DISPLAY=:99
export WINEPREFIX=/home/trader/.wine

# Initialize Wine prefix
wineboot --init
sleep 10

# Download MT5 installer
wget -q "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" \
    -O /tmp/mt5setup.exe

# Silent install
wine /tmp/mt5setup.exe /auto
sleep 30

echo "MetaTrader 5 installed"
TRADEREOF

# ── PropGuardian systemd service ─────────────────────
echo "[6/6] Creating systemd service..."
cat > /etc/systemd/system/propguardian.service << 'EOF'
[Unit]
Description=PropGuardian Trading Bot (MetaTrader 5)
After=xvfb.service network-online.target
Wants=network-online.target
Requires=xvfb.service

[Service]
Type=simple
User=trader
Environment=DISPLAY=:99
Environment=WINEPREFIX=/home/trader/.wine
WorkingDirectory=/home/trader

ExecStart=/usr/bin/wine "/home/trader/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe" /portable
Restart=always
RestartSec=30
TimeoutStopSec=60

# Resource limits
MemoryMax=2G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable propguardian

echo ""
echo "=========================================="
echo "  Setup complete!"
echo ""
echo "  Start bot:    systemctl start propguardian"
echo "  Check status: systemctl status propguardian"
echo "  View logs:    journalctl -u propguardian -f"
echo "  VNC access:   x11vnc -display :99 -rfbport 5900"
echo "=========================================="
