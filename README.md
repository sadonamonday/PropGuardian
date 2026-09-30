# PropGuardian

**Automated Forex trading bot engineered for Prop Firm funding challenges (Funding Pips, FTMO).**

[![MQL5](https://img.shields.io/badge/Language-MQL5-blue)](https://www.mql5.com/)
[![MetaTrader 5](https://img.shields.io/badge/Platform-MetaTrader%205-green)](https://www.metatrader5.com/)
[![VPS](https://img.shields.io/badge/Deployment-Linux%20VPS-orange)](https://www.ovhcloud.com/)
[![Status](https://img.shields.io/badge/Status-Under%20Testing-brightgreen)]()

---

## Overview

PropGuardian is a fully autonomous Expert Advisor (EA) built in **MQL5** for MetaTrader 5. It is specifically engineered for Prop Firm challenges by prioritizing capital preservation and strict risk management over aggressive returns.

The bot runs 24/5 on a Linux VPS via Wine, with automated health checks and risk monitoring.

---

## Current Development Status

> **Status: Implemented, Audited & Verified (v0.1)**
>
> The EA implements the **4H → M15 → M5 Smart Money Concepts (SMC) Strategy**.
> The implementation has completed strategy fixes and audit verification across CHoCH selection, M5 displacement proxy, POI interface isolation, FVG lifecycle tracking, and structural TP targeting without fixed-R fallbacks. Verified via automated unit tests in `tests/test_smc_engine.py`.

---

## Strategy Architecture (4H → M15 → M5 SMC)

PropGuardian executes trades based on a deterministic, multi-timeframe Smart Money Concepts strategy:

### 1. 4H Timeframe (Higher-Timeframe Context)
- Higher-timeframe market structure mapping
- Isolated 4H POI provider interface (`Register4HPOI` / `GetActive4HPOI`). Requires an explicitly registered 4H POI zone (missing POI results in `NO TRADE` rather than guessing a zone).

### 2. M15 Timeframe (Structural Confirmation)
- Confirmed 5-bar swing structure mapping
- M15 Liquidity Sweep detection (price trades past M15 swing low/high and completed M15 candle closes back inside)
- M15 CHoCH (Change of Character) confirmation: Backward traversal from sweep extreme identifies opposing swing (Lower High for Buy, Higher Low for Sell) directly preceding the sweep leg. Confirmed on completed candle BODY close beyond CHoCH level.

### 3. M5 Timeframe (Execution Structure & Entry)
- Confirmed 3-bar execution swing structure mapping
- M5 execution structure break (M5 BOS) + **Structural displacement proxy**: directionally matching breakout candle (`Close > Open` for Buy, `Close < Open` for Sell) producing a valid 3-candle Fair Value Gap (FVG)
- **50% FVG Midpoint Entry**: Pending Limit Order (`BUY_LIMIT` / `SELL_LIMIT`) placed at exact 50% FVG midpoint
- **FVG Lifecycle**: Retains original setup FVG. Invalidated if completed M5 candle closes through C1 boundary before fill (cancels pending limit order)
- **Structural Stop Loss**: SL placed beyond swept structural low/high extreme with spread buffer
- **Structural Take Profit**: Targeted at opposing confirmed M15 structural high (Long) or low (Short). Setups are invalidated if no structural target exists (no 3R / ATR fallbacks used)

---

## Complete Multi-Timeframe Sequence

### LONG Sequence:
4H bullish context / demand POI active
→ M15 trades below confirmed swing low
→ M15 closes back above swept low
→ Identify final sweep low
→ Identify most recent confirmed LH directly preceding final bearish leg into sweep
→ M15 bullish CHoCH body close
→ M5 bullish execution structure (BOS body close)
→ M5 bullish structural displacement proxy (directionally bullish candle + FVG)
→ M5 bullish FVG (Low(C3) > High(C1))
→ FVG confirmed on C3 close
→ BUY LIMIT placed at 50% FVG midpoint
→ Structural SL below swept low
→ Structural TP at opposing M15 swing high
→ Existing risk-management system controls position size and safety

### SHORT Sequence:
4H bearish context / supply POI active
→ M15 trades above confirmed swing high
→ M15 closes back below swept high
→ Identify final sweep high
→ Identify most recent confirmed HL directly preceding final bullish leg into sweep
→ M15 bearish CHoCH body close
→ M5 bearish execution structure (BOS body close)
→ M5 bearish structural displacement proxy (directionally bearish candle + FVG)
→ M5 bearish FVG (High(C3) < Low(C1))
→ FVG confirmed on C3 close
→ SELL LIMIT placed at 50% FVG midpoint
→ Structural SL above swept high
→ Structural TP at opposing M15 swing low
→ Existing risk-management system controls position size and safety

---

## Risk Management Architecture

The entire system is built around capital preservation:

- **Double-Layer Daily Drawdown**: Soft stop (blocks new trades) + Hard stop (emergency close all)
- **Portfolio Emergency Shutdown**: Total drawdown limit across all symbols
- **Position Sizer**: Dynamic lot calculation based on structural stop distance and risk percentage
- **Circuit Breaker**: Auto-pause after consecutive losses
- **Safety Filters**: Spread check, GMT session window (08:00–22:00 GMT), Asian range filter, rollover block, toxic volatility guard, and trade idea cooldown
- **Position Management**: Virtual stealth SL/TP option, break-even (+4.0R), partial TP (+4.0R / +10.0R), ATR trailing stop, and Friday close protection

---

## Codebase Structure

### [`showcase/`](showcase/) — Core MQL5 Source Files

| File | Description |
|------|-------------|
| [`PropGuardian.mq5`](showcase/PropGuardian.mq5) | Core EA entry point: timer loop, SMC engine tick, pending limit order placement/cancellation on setup invalidation, deal execution tracking |
| [`smc_engine.mqh`](showcase/smc_engine.mqh) | Multi-timeframe SMC engine: 4H POI interface, M15 sweep/CHoCH, M5 execution/displacement proxy/FVG, 13-state setup machine |
| [`risk_manager.mqh`](showcase/risk_manager.mqh) | Multi-layer pre-trade risk gates, drawdown monitoring, daily reset, circuit breaker, lot sizer |
| [`safety_filters.mqh`](showcase/safety_filters.mqh) | Pre-trade safety filters: spread, trading window, Asian range, rollover window, toxic volatility |
| [`position_manager.mqh`](showcase/position_manager.mqh) | Active trade management: stealth SL/TP, break-even, partial TPs, ATR trailing, Friday close |

### [`tests/`](tests/) — Unit Test Suite

| File | Description |
|------|-------------|
| [`test_smc_engine.py`](tests/test_smc_engine.py) | Python unittest suite covering 34 deterministic strategy rules and state machine transitions |

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| **Language** | MQL5 (MetaQuotes Language 5) |
| **Platform** | MetaTrader 5 |
| **Testing** | Python standard `unittest` framework |
| **VPS Deployment** | Ubuntu 24.04 LTS via Wine + Xvfb + systemd |

---

## Disclaimer

This repository is a showcase and development codebase for PropGuardian.

**No strategy guarantees profitability.** Trading involves significant risk of loss. Past performance or backtest results do not guarantee future live performance.

---

## Author

Built by **[@Jotanune](https://github.com/Jotanune)** — automated trading systems engineering.
