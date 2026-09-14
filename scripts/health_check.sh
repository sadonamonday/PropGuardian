#!/bin/bash
# PropGuardian Health Dashboard — VPS monitoring script
#
# Shows real-time status of the trading bot including:
# - MT5 process status and uptime
# - Account balance and P/L
# - Open positions
# - System resources
#
# Usage: ssh vps "bash health_check.sh"

set -euo pipefail

DISPLAY=:99
WINEPREFIX=/home/trader/.wine
MT5_LOG_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/MQL5/Logs"

echo "╔══════════════════════════════════════════════════╗"
echo "║          PropGuardian Health Dashboard           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Service Status ────────────────────────────────────
echo "── Service Status ──"
if systemctl is-active --quiet propguardian; then
    UPTIME=$(systemctl show propguardian --property=ActiveEnterTimestamp --value)
    echo "  PropGuardian:  ✅ RUNNING (since $UPTIME)"
else
    echo "  PropGuardian:  ❌ STOPPED"
fi

if systemctl is-active --quiet xvfb; then
    echo "  Xvfb Display:  ✅ RUNNING"
else
    echo "  Xvfb Display:  ❌ STOPPED"
fi
echo ""

# ── MT5 Process ───────────────────────────────────────
echo "── MT5 Process ──"
MT5_PID=$(pgrep -f "terminal64.exe" || echo "")
if [ -n "$MT5_PID" ]; then
    MEM=$(ps -p $MT5_PID -o rss= 2>/dev/null | awk '{printf "%.0f", $1/1024}')
    CPU=$(ps -p $MT5_PID -o %cpu= 2>/dev/null)
    echo "  PID: $MT5_PID | Memory: ${MEM}MB | CPU: ${CPU}%"
else
    echo "  ⚠️  MT5 process not found"
fi
echo ""

# ── Latest Log ────────────────────────────────────────
echo "── Latest EA Log (last 10 lines) ──"
TODAY=$(date +%Y%m%d)
LOG_FILE="$MT5_LOG_DIR/$TODAY.log"
if [ -f "$LOG_FILE" ]; then
    tail -10 "$LOG_FILE" | while read line; do
        echo "  $line"
    done
    
    # Count today's trades
    TRADES=$(grep -c "\[ORDER\].*Fill confirmed" "$LOG_FILE" 2>/dev/null || echo "0")
    WINS=$(grep -c "\[RISK\].*Trade result: WIN" "$LOG_FILE" 2>/dev/null || echo "0")
    LOSSES=$(grep -c "\[RISK\].*Trade result: LOSS" "$LOG_FILE" 2>/dev/null || echo "0")
    echo ""
    echo "  Today: $TRADES trades ($WINS W / $LOSSES L)"
else
    echo "  No log file for today"
fi
echo ""

# ── System Resources ──────────────────────────────────
echo "── System Resources ──"
echo "  CPU:    $(top -bn1 | grep 'Cpu(s)' | awk '{print 100 - $8}')% used"
echo "  Memory: $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
echo "  Disk:   $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
echo "  Uptime: $(uptime -p)"
echo ""
echo "════════════════════════════════════════════════════"
