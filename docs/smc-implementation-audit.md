# PropGuardian SMC Strategy v0.1 — Implementation Audit & Architecture Report

## 1. Overview
This report documents the architectural audit and implementation of core fixes in the PropGuardian MT5 Expert Advisor codebase for the **PropGuardian SMC Strategy v0.1**.

The strategy implements a deterministic, multi-timeframe Smart Money Concepts (SMC) execution model:
**4H context/POI → M15 liquidity sweep & CHoCH → M5 execution structure, displacement & FVG → 50% FVG limit order entry**, while strictly preserving all non-conflicting capital protection and risk management layers.

---

## 2. Core Implementation Fixes Executed

### 1. CHoCH Swing Selection Fix
- **Previous Problem**: `FindCHoCHLevel()` searched backward and selected the most recent confirmed M15 swing high/low before the sweep regardless of directional structure.
- **Fix Implemented**: Updated `FindCHoCHLevel()` in `showcase/smc_engine.mqh` to perform deterministic backward traversal starting from the sweep bar/time. For LONG setups, it identifies the most recent confirmed Lower High directly preceding the final bearish leg into the sweep low. For SHORT setups, it identifies the most recent confirmed Higher Low directly preceding the final bullish leg into the sweep high. Confirmation requires a completed M15 candle body close beyond the CHoCH swing.

### 2. M5 Displacement Implementation
- **Previous Problem**: The strategy treated `M5 BOS + FVG = displacement` without verifying directional candle characteristics.
- **Fix Implemented**: Updated `CheckM5ExecutionBreak()` in `showcase/smc_engine.mqh` to enforce that the breakout candle body close beyond the M5 swing must be directionally bullish (`Close > Open`) for BUY or directionally bearish (`Close < Open`) for SELL, coupled with the qualifying 3-candle FVG produced by the breakout. Documented explicitly as: `"Structural displacement proxy: directional M5 breakout candle + qualifying FVG."`

### 3. Removal of Invented 4H POI Algorithm
- **Previous Problem**: `GetActive4HPOI()` generated arbitrary POI zones around 4H swings using hardcoded ±3.0/15.0 point offsets.
- **Fix Implemented**: Removed invented point-offset zone logic. Introduced a clean POI interface and registry (`Register4HPOI` / `GetActive4HPOI`). If no verified 4H POI is explicitly provided, `GetActive4HPOI()` returns `false`, resulting in `NO TRADE` rather than guessing a POI zone.

### 4. FVG Lifecycle & Invalidation Fix
- **Previous Problem**: Active setups risked re-discovering or overwriting FVGs on every tick.
- **Fix Implemented**: Retained the specific FVG that generated the setup on `setup.m5FVG`. FVG tracks creation time, C1 boundary, C3 boundary, midpoint, mitigation, and invalidation state. If a completed M5 candle body closes through the C1 boundary before entry, the setup is invalidated and any active pending limit order is cancelled (`TRADE_ACTION_REMOVE`).

### 5. Removal of Fixed 3R TP Fallback
- **Previous Problem**: `setup.tpPrice` used a fallback of `entry ± 3R` if no opposing swing was found.
- **Fix Implemented**: Removed all fixed-R, pip, or ATR fallbacks. Setups strictly target the next opposing confirmed M15 structural high (Long) or low (Short). If no opposing structural target exists, the setup is invalidated with an explicit reason (`"No valid opposing M15 structural target found for TP"`).

---

## 3. Codebase File Classification

| File | Classification | Purpose & Implementation Status |
| :--- | :--- | :--- |
| `showcase/PropGuardian.mq5` | Production / EA Entry | Main EA entry point (`OnInit`, `OnDeinit`, `OnTimer`, `OnTradeTransaction`). Integrates SMC engine timer tick, pending limit order submission/cancellation on setup invalidation, and deal fill/close tracking. |
| `showcase/smc_engine.mqh` | Production / Signal Engine | Core SMC engine. Houses 4H/M15 5-bar swing & M5 3-bar swing detectors, 4H POI interface, M15 liquidity sweep & CHoCH detector, M5 displacement proxy & FVG detector, and 13-state deterministic setup state machine. |
| `showcase/signal_engine.mqh` | Obsolete / Legacy Engine | Contained previous H1 PWH/PWL/PDH/PDL sweep signal logic. Bypassed and disabled. |
| `showcase/risk_manager.mqh` | Production / Risk Protection | Multi-layer pre-trade risk gates, daily DD soft/hard stop, total portfolio DD emergency stop, daily reset, circuit breaker, ATR/risk-based lot sizer. **RETAINED IN FULL**. |
| `showcase/safety_filters.mqh` | Production / Safety Filters | Pre-trade blocking conditions (spread, GMT trading session, Asian range, rollover window, toxic volatility, cooldown). **RETAINED IN FULL**. |
| `showcase/position_manager.mqh` | Production / Position Mgmt | Active trade management (stealth SL/TP, break-even, partial TPs, ATR trailing, Friday close). **RETAINED IN FULL**. |
| `tests/test_smc_engine.py` | Unit Tests | Python unittest suite covering 34 deterministic strategy rules. |

---

## 4. Integration Points & Execution Flow

1. **SMC Engine State Machine (`showcase/smc_engine.mqh`)**:
   - Maintains `g_SMCSetups` array tracking symbol setups across 13 deterministic states:
     `SMC_IDLE` → `SMC_H4_POI_ACTIVE` → `SMC_WAITING_FOR_M15_SWEEP` → `SMC_M15_SWEEP_DETECTED` → `SMC_WAITING_FOR_M15_CHOCH` → `SMC_M15_CHOCH_CONFIRMED` → `SMC_WAITING_FOR_M5_CONFIRMATION` → `SMC_M5_CONFIRMATION` → `SMC_FVG_DETECTED` → `SMC_WAITING_FOR_FVG_RETRACE` → `SMC_ENTRY_SUBMITTED` → `SMC_TRADE_ACTIVE` → `SMC_COMPLETED` (or `SMC_INVALIDATED`).

2. **Main EA Loop (`showcase/PropGuardian.mq5`)**:
   - `OnTimer()` invokes `SMCEngine_OnTick()` to advance setups across tradeable symbols.
   - Pending order invalidation check cancels active pending limit orders if setup transitions to `SMC_INVALIDATED`.
   - When a setup reaches `SMC_WAITING_FOR_FVG_RETRACE` or `SMC_FVG_DETECTED`, `PropGuardian.mq5` calls `CanOpenTrade(g_riskState, symbol)`.
   - Upon pre-trade approval, a pending limit order (`ORDER_TYPE_BUY_LIMIT` / `ORDER_TYPE_SELL_LIMIT`) is placed at **50% FVG midpoint** with structural SL and opposing structural TP.
