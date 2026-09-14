# PropGuardian

**Automated Forex trading bot engineered to pass Prop Firm challenges (Funding Pips).**

[![MQL5](https://img.shields.io/badge/Language-MQL5-blue)](https://www.mql5.com/)
[![MetaTrader 5](https://img.shields.io/badge/Platform-MetaTrader%205-green)](https://www.metatrader5.com/)
[![VPS](https://img.shields.io/badge/Deployment-Linux%20VPS-orange)](https://www.ovhcloud.com/)
[![Status](https://img.shields.io/badge/Status-Live%20Challenge-brightgreen)]()

---

## Overview

PropGuardian is a fully autonomous Expert Advisor (EA) built from scratch in **MQL5** to trade Forex on MetaTrader 5. It's specifically designed to pass Prop Firm funding challenges by prioritizing capital preservation over aggressive returns.

The bot runs 24/5 on a Linux VPS via Wine, with zero manual intervention required.

### Why This Exists

Most traders fail prop firm challenges due to:
- **Overtrading** — opening positions out of anxiety
- **Revenge trading** — chasing losses after a bad day
- **Miscalculated position sizing** — accidentally violating drawdown limits

PropGuardian eliminates all three by enforcing hard-coded risk rules that cannot be overridden.

---

## Strategy

The core engine uses **Smart Money Concepts (SMC) — Liquidity Sweeps**:

1. **Detect** institutional liquidity sweeps at key levels (Previous Day/Week High-Low)
2. **Confirm** rejection via candlestick analysis + trend alignment
3. **Enter** counter-direction with dynamic ATR-based stop loss
4. **Manage** positions with break-even, partial take profit, and trailing stop

> Strategy parameters, per-symbol configurations, and exact entry/exit logic are proprietary and not included in this repository.

---

## Architecture

```
PropGuardian EA (.mq5)
│
├── Signal Engine ─────── SMC Liquidity Sweep Detection
│   ├── PDH/PDL Scanner        Previous Day High/Low levels
│   ├── Rejection Analyzer     Wick ratio + body confirmation
│   └── Trend Filter           Multi-timeframe alignment
│
├── Risk Manager ─────── Capital Preservation Layer
│   ├── Daily DD Monitor       Soft stop + Hard stop (double layer)
│   ├── Total DD Monitor       Trailing equity-based limit
│   ├── Position Sizer         ATR-based dynamic lot calculation
│   ├── Circuit Breaker        Auto-pause after consecutive losses
│   └── Consistency Cap        Profit limit per day (Master accounts)
│
├── Position Manager ──── Active Trade Management
│   ├── Break-Even Engine      Move SL to entry at configurable R
│   ├── Partial TP             Lock profits on first target
│   └── ATR Trailing Stop      Dynamic trail based on volatility
│
├── Safety Filters ────── Trade Blocking Conditions
│   ├── News Filter            Block around HIGH/CRITICAL events
│   ├── Friday Close           Configurable weekend risk elimination
│   ├── Rollover Block         No trades during swap window
│   ├── Toxic Volatility       Block when ATR exceeds threshold
│   └── Stealth Mode           Virtual SL/TP in RAM + server hard SL
│
└── Infrastructure ────── Deployment & Monitoring
    ├── VPS Automation         systemd + Xvfb + VNC + Wine
    ├── Health Monitoring      Bash dashboards with real-time metrics
    └── PowerShell Framework   Compile, backtest, optimize pipeline
```

---

## Portfolio Performance

### Student Account — V2.5 (Backtest: 2024–2025, 5 Forex pairs)

| Metric | Value |
|--------|-------|
| **Total Return** | **+48.5%** |
| **Win Rate** | 67.7% |
| **Profit Factor** | 1.36 |
| **Max Equity DD** | 6.6% |
| **Total Trades** | 931 |

### Master Account — V2.8.1 (Backtest: 2024–2025, 5 Forex pairs, 1:50 leverage)

| Metric | Value |
|--------|-------|
| **Total Return** | **+29.4%** |
| **Win Rate** | 69.2% |
| **Profit Factor** | 1.40 |
| **Max Equity DD** | 3.5% |
| **Total Trades** | 880 |

> Results from MetaTrader 5 Strategy Tester with real tick data (99.9% quality). Past performance does not guarantee future results.

---

## Risk Management

The entire system is built around a "guardian of capital" philosophy:

- **Double-layer daily drawdown**: Soft stop (blocks new trades) + Hard stop (emergency close all)
- **Portfolio emergency shutdown**: Total DD limit across all symbols
- **Circuit breaker**: Auto-pause after N consecutive losses
- **Drawdown scaling**: Risk per trade automatically reduced when approaching DD limits
- **Stealth mode**: Virtual SL/TP kept in RAM to avoid broker stop hunting; server-side hard SL as backup
- **News filter**: Always-on protection around high-impact events (NFP, CPI, FOMC, etc.)
- **Friday close**: Configurable per-pair weekend risk elimination
- **Rollover block**: No trading during the daily swap window
- **Toxic volatility guard**: Blocks trading when ATR exceeds historical average

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| **Language** | MQL5 (MetaQuotes Language 5) |
| **Platform** | MetaTrader 5 |
| **VPS** | Ubuntu 24.04 LTS, OVH |
| **MT5 on Linux** | Wine + Xvfb + VNC |
| **Automation** | PowerShell 7 (backtest/optimize/deploy pipeline) |
| **Monitoring** | Bash dashboards (balance, P/L, win rate, DD tracking) |
| **Process Management** | systemd with auto-restart |
| **Version Control** | Versioned EAs (V2.5 Student, V2.8.1 Master) |

---

## Deployment

The bot runs on a headless Linux VPS with the following stack:

```
Ubuntu 24.04 (OVH VPS)
├── Xvfb          Virtual framebuffer (headless display)
├── x11vnc        VNC access for debugging
├── Wine           Windows compatibility layer
├── MetaTrader 5   Trading platform
├── systemd        Auto-restart on crash
└── Bash scripts   Health checks + deploy automation
```

Multiple MT5 instances run simultaneously (one per challenge account), each with its own VNC port and systemd service.

---

## Testing Pipeline

1. **Unit validation** — Manual per-module testing in Strategy Tester
2. **Backtesting** — Full tick simulation (2024–2025, all pairs)
3. **Walk-Forward optimization** — Rolling window parameter validation
4. **Stress testing** — Extreme spread, slippage, and gap scenarios
5. **Forward testing** — 2–4 weeks on demo before live challenge
6. **VPS validation** — Full deployment with monitoring dashboards

---

## Versions

| Version | Account Type | Key Features |
|---------|-------------|--------------|
| **V2.5** | Student ($5K) | Core SMC engine, 5 pairs, full risk management |
| **V2.8.1** | Master ($10K) | Consistency cap, tighter DD limits, 1:50 leverage adaptation |

---

## Code Samples

This repository includes **sanitized excerpts** from the production MQL5 codebase. No strategy parameters or exact entry/exit logic are exposed.

### [`showcase/`](showcase/) — Core EA Modules

| File | What it demonstrates |
|------|---------------------|
| [`risk_manager.mqh`](showcase/risk_manager.mqh) | 7 pre-trade risk gates, daily/total DD monitoring, ATR-based position sizing, circuit breaker |
| [`position_manager.mqh`](showcase/position_manager.mqh) | Stealth mode (virtual SL/TP in RAM), break-even, partial TP, ATR trailing, Friday close |
| [`safety_filters.mqh`](showcase/safety_filters.mqh) | 9 trade-blocking filters: spread, volatility, news, cooldown, rollover, Friday (FP Zero compliant) |

### [`logs/`](logs/) — Production Evidence

| File | What it shows |
|------|--------------|
| [`sample_production.log`](logs/sample_production.log) | Full trading day: SMC detection → ML ensemble → safety filters → order fill → break-even → partial TP → trailing stop → Friday close |

### [`scripts/`](scripts/) — VPS Automation

| File | Description |
|------|-------------|
| [`deploy_vps.sh`](scripts/deploy_vps.sh) | Full VPS setup: Xvfb + Wine + MT5 installation + systemd service creation |
| [`health_check.sh`](scripts/health_check.sh) | Live health dashboard: MT5 process status, today's P/L, trade count, system resources |

---

## Disclaimer

This repository is a **showcase of the architecture and engineering** behind PropGuardian. Source code, strategy parameters, and proprietary configurations are not included.

The bot is a real, actively-running trading system. Backtest results shown are from MetaTrader 5 Strategy Tester with real tick data. Live results may differ due to slippage, spread variations, and market conditions.

**This is not financial advice.** Trading involves significant risk of loss.

---

## Author

Built by **[@Jotanune](https://github.com/Jotanune)** — a solo developer building automated trading systems.

- 🔗 [CryptoGuardian](https://github.com/Jotanune/CryptoGuardian) — Crypto trading bot on Hyperliquid DEX (Python)
