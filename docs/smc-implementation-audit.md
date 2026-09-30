# PropGuardian SMC Strategy v0.1 — Implementation Audit & Architecture Report

## 1. Overview
This report documents the architectural audit of the PropGuardian MT5 Expert Advisor codebase and defines the precise integration strategy for the **PropGuardian SMC Strategy v0.1**.

The strategy implements a deterministic, multi-timeframe Smart Money Concepts (SMC) execution model:
**4H context/POI → M15 liquidity sweep & CHoCH → M5 execution structure, displacement & FVG → 50% FVG limit order entry**, while strictly preserving all non-conflicting capital protection and risk management layers.

---

## 2. Codebase Structure & File Classification

| File | Classification | Purpose & Implementation Status |
| :--- | :--- | :--- |
| `showcase/PropGuardian.mq5` | Production / EA Entry | Main EA entry point (`OnInit`, `OnDeinit`, `OnTimer`, `OnTradeTransaction`). Integrates SMC engine timer tick, pending limit order submission, and deal fill/close tracking. Legacy H1 scanner disabled. |
| `showcase/smc_engine.mqh` | Production / Signal Engine | Core SMC engine. Houses 4H/M15 5-bar swing & M5 3-bar swing detectors, 4H POI state, M15 liquidity sweep & CHoCH detector, M5 execution structure break detector, M5 FVG/OB detector, and 13-state deterministic setup state machine. |
| `showcase/signal_engine.mqh` | Obsolete / Legacy Engine | Contained previous H1 PWH/PWL/PDH/PDL sweep signal logic. Retained as standalone file for reference but bypassed and disabled from active trading loop. |
| `showcase/risk_manager.mqh` | Production / Risk Protection | Multi-layer pre-trade risk gates, daily DD soft/hard stop, total portfolio DD emergency stop, daily reset, circuit breaker, ATR/risk-based lot sizer. **RETAINED IN FULL**. |
| `showcase/safety_filters.mqh` | Production / Safety Filters | Pre-trade blocking conditions (spread, GMT trading session, Asian range, rollover window, toxic volatility, cooldown). **RETAINED IN FULL**. |
| `showcase/position_manager.mqh` | Production / Position Mgmt | Active trade management (stealth SL/TP, break-even, partial TPs, ATR trailing, Friday close). **RETAINED IN FULL**. |
| `showcase/PropGuardian.ex5` | Build Artifact | Compiled output binary. |
| `tests/test_smc_engine.py` | Unit Tests | Python unittest suite covering 15 deterministic strategy rules. |

---

## 3. Integration Points & Execution Flow

1. **SMC Engine State Machine (`showcase/smc_engine.mqh`)**:
   - Maintains `g_SMCSetups` array tracking symbol setups across 13 deterministic states:
     `SMC_IDLE` → `SMC_H4_POI_ACTIVE` → `SMC_WAITING_FOR_M15_SWEEP` → `SMC_M15_SWEEP_DETECTED` → `SMC_WAITING_FOR_M15_CHOCH` → `SMC_M15_CHOCH_CONFIRMED` → `SMC_WAITING_FOR_M5_CONFIRMATION` → `SMC_M5_CONFIRMATION` → `SMC_FVG_DETECTED` → `SMC_WAITING_FOR_FVG_RETRACE` → `SMC_ENTRY_SUBMITTED` → `SMC_TRADE_ACTIVE` → `SMC_COMPLETED` (or `SMC_INVALIDATED`).

2. **Main EA Loop (`showcase/PropGuardian.mq5`)**:
   - `OnTimer()` invokes `SMCEngine_OnTick()` to advance setups across tradeable symbols.
   - When a setup reaches `SMC_WAITING_FOR_FVG_RETRACE` or `SMC_FVG_CONFIRMED`, `PropGuardian.mq5` calls `CanOpenTrade(g_riskState, symbol)` in `risk_manager.mqh`.
   - Upon pre-trade approval, a pending limit order (`ORDER_TYPE_BUY_LIMIT` / `ORDER_TYPE_SELL_LIMIT`) is placed at **50% FVG midpoint** with structural SL and TP.
   - Transition to `SMC_ENTRY_SUBMITTED` occurs upon order placement, `SMC_TRADE_ACTIVE` on fill (via `OnTradeTransaction`), and `SMC_COMPLETED` upon position close.

3. **Risk Management Integration (`risk_manager.mqh` & `safety_filters.mqh`)**:
   - `CanOpenTrade()` evaluates pre-trade risk gates (daily loss soft/hard stop, total portfolio DD, max trades/day, circuit breaker, max open positions, currency exposure, safety filters).
   - `CalculateLotSize()` calculates volume dynamically using structural stop distance (`MathAbs(entryPrice - slPrice)`).

---

## 4. Components Replaced vs. Retained

### Replaced or Disabled
- **Legacy Signal Engine (`CheckSignal` in `signal_engine.mqh`)**: Legacy H1 sweep signal scanner and buy/sell stop reclaim orders removed from the pre-trade risk check and main timer loop.
- **Generic ATR Stop Loss**: Initial SL is determined structurally (placed beyond swept low/high extreme) rather than generic ATR multiplication.

### Retained Unchanged
- **Pre-trade Risk Gates**: Daily soft/hard drawdown stops, portfolio emergency kill switch, trades/day limit, circuit breaker.
- **Position Sizing & Safety Filters**: Spread check, GMT session window, Asian range filter, rollover block, toxic volatility guard.
- **Active Position Management**: Stealth mode, break-even (+4.0R), partial TP (+4.0R / +10.0R), ATR trailing stop, Friday close.

---

## 5. Discrepancy & Production vs Showcase Audit Findings

1. **Showcase / Demo Scope**:
   - The `showcase/` directory contains sanitized/demo MQL5 code. MetaEditor / MQL5 compilation tools are not installed in the local environment, so MQL5 compilation must be performed in MT5 / MetaEditor.
2. **News Filter Integration**:
   - `IsNearNewsEvent()` in `safety_filters.mqh` is an external calendar stub returning `false`. Third-party economic calendar integration is required for news event blocking.
3. **In-Memory Setup State**:
   - Setup state is maintained in RAM. Terminal or EA restarts re-initialize setup trackers to `SMC_IDLE`. Active limit orders and open positions are preserved by MT5 and managed via `g_tracker` and `OnTradeTransaction`.
