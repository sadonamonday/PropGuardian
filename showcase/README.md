# PropGuardian — Showcase Code Snippets

This directory contains **sanitized excerpts** from the production PropGuardian V2.8.1 Expert Advisor (MQL5).

These files demonstrate the engineering quality and defensive programming behind the bot without exposing the actual signal generation logic.

## Files

| File | Description | What it demonstrates |
|------|-------------|---------------------|
| `risk_manager.mqh` | Multi-layered capital protection | 7 pre-trade gates, daily/total DD monitoring, Bug #33 fix, position sizing |
| `position_manager.mqh` | Active trade management | Stealth mode (virtual SL/TP), break-even, partial TP, ATR trailing, Friday close |
| `safety_filters.mqh` | Trade blocking conditions | Spread check, news filter, toxic volatility, FP Zero compliance, cooldown |

## What's NOT included

- Signal generation logic (SMC liquidity sweep detection)
- Rejection analysis and candlestick pattern recognition
- ML ensemble (Neural Network + Random Forest) filter
- Per-symbol optimized parameters (.set files)
- News calendar data and processing pipeline
- Exact threshold values for all risk parameters
