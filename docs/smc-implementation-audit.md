# PropGuardian SMC Strategy v0.1 — Implementation Audit & Architecture Report

## 1. Overview
This report documents the architectural audit of the PropGuardian MT5 Expert Advisor codebase and defines the precise integration strategy for the new **PropGuardian SMC Strategy v0.1**.

The goal is to transition PropGuardian to a deterministic, testable, multi-timeframe Smart Money Concepts (SMC) execution model based on **4H context → M15 liquidity sweep & CHoCH → M5 displacement & FVG → 50% FVG limit order entry**, while strictly preserving all non-conflicting capital protection and risk management layers.

---

## 2. Codebase Structure & File Classification

| File | Classification | Status & Purpose |
| :--- | :--- | :--- |
| `showcase/PropGuardian.mq5` | Production / EA Entry | Core EA lifecycle (`OnInit`, `OnDeinit`, `OnTimer`, `OnTradeTransaction`). Standard entry point. |
| `showcase/signal_engine.mqh` | Production / Signal Module | Previous H1 PWH/PWL/PDH/PDL sweep signal logic. Will be augmented / wrapped by the new SMC strategy engine (`smc_engine.mqh`). |
| `showcase/risk_manager.mqh` | Production / Risk Protection | Multi-layer pre-trade risk gates, drawdown monitors, daily reset, circuit breaker, lot sizer. **RETAINED IN FULL**. |
| `showcase/safety_filters.mqh` | Production / Safety Filters | Pre-trade blocking conditions (spread, trading session, news stub, rollover, toxic volatility, cooldown). **RETAINED IN FULL**. |
| `showcase/position_manager.mqh` | Production / Position Mgmt | Active trade management (stealth SL/TP, break-even, partial TPs, ATR trailing, Friday close). **INTEGRATED & RETAINED**. |
| `showcase/PropGuardian.ex5` | Build Artifact | Compiled output. Will be regenerated or updated upon MQL5 build. |
| `scripts/deploy_vps.sh` | Infrastructure Script | VPS deployment automation. RETAINED. |
| `scripts/health_check.sh` | Infrastructure Script | Monitoring dashboard script. RETAINED. |
| `logs/sample_production.log` | Documentation / Evidence | Production log example. RETAINED. |

---

## 3. Integration Points for SMC Engine (`smc_engine.mqh`)

1. **New Module (`showcase/smc_engine.mqh`)**:
   - Houses the multi-timeframe structure tracker (4H, M15, M5), 5-bar (4H/M15) and 3-bar (M5) swing detectors, 4H POI state, M15 sweep & CHoCH detector, M5 displacement & FVG detector, and setup state machine lifecycle.
   - Maintains an array of `SMCSetup` state trackers with unique setup IDs (`SETUP_YYYYMMDD_HHMMSS_N`).

2. **Main Loop (`showcase/PropGuardian.mq5`)**:
   - `OnTimer()` will drive candle-close evaluation on 4H, M15, and M5 timeframes across tradeable symbols.
   - When `SMC_UseStrategy` is enabled, `OnTimer()` triggers `SMCEngine_OnTick()` / candle-close handlers.
   - When an SMC setup reaches `SMC_FVG_CONFIRMED`, `PropGuardian.mq5` verifies pre-trade risk via `CanOpenTrade()` in `risk_manager.mqh`.
   - Upon approval, a pending limit order (`ORDER_TYPE_BUY_LIMIT` / `ORDER_TYPE_SELL_LIMIT`) is placed at **50% of the M5 FVG**.

3. **Risk Management Integration (`risk_manager.mqh` & `safety_filters.mqh`)**:
   - The SMC engine supplies entry price, structural SL, and opposing structural TP to `risk_manager.mqh`.
   - `CanOpenTrade()` evaluates all 8 pre-trade risk gates (daily DD, total DD, max trades/day, circuit breaker, max positions, currency exposure, safety filters). If rejected, the setup transitions to `SMC_INVALIDATED` with reason logged.

4. **Position Management (`position_manager.mqh`)**:
   - Once a limit order fills (detected in `OnTradeTransaction`), position tracking is initialized in `g_tracker`.
   - Break-even, partial TP, and Friday close logic from `position_manager.mqh` remain active for filled positions.

---

## 4. Components Replaced vs. Retained

### Replaced or Overridden by SMC Strategy (when `SMC_UseStrategy = true`)
- **Previous Signal Engine (`CheckSignal` in `signal_engine.mqh`)**: The previous H1 PWH/PDL sweep logic and buy/sell stop reclaim orders are bypassed in favor of the SMC multi-timeframe state machine and pending limit orders at 50% FVG.
- **ATR-based Initial Stop Loss**: Initial SL is determined structurally (below/above swept extreme / M5 structural swing) rather than blindly multiplying ATR.

### Retained Unchanged
- **Pre-trade Risk Gates**: All gates in `risk_manager.mqh` (daily DD soft/hard stop, portfolio emergency stop, max trades per day, circuit breaker).
- **Position Manager Execution**: Order filling checks, lot normalization, lot sizing based on frozen account risk %, position tracking in `OnTradeTransaction`.
- **Safety Filters**: Spread check, trading session check, Asian range check, rollover block, toxic volatility check.

---

## 5. Audit Findings & Existing-Code Discrepancies (Section 23 Verification)

1. **`Trend_SMA_Period` (D1 SMA Filter)**:
   - *Finding*: `GetTrendBias()` in `signal_engine.mqh` calculates D1 SMA50 bias, but `CheckSignal()` in the showcase did not actually restrict entries by `GetTrendBias()`.
   - *SMC Rule*: Market structure is established strictly from 4H, M15, and M5 confirmed swing points (BULLISH/BEARISH/UNDEFINED), NOT from moving averages. The SMA filter is not used for SMC structure decisions.

2. **Cooldown State**:
   - *Finding*: `IsInCooldown()` in `safety_filters.mqh` uses `static` arrays in RAM (`lastTradeTime[]`, `lastTradeSymbol[]`).
   - *Impact*: On EA restart, RAM state is cleared, resetting cooldowns. SMC setup state tracking will also operate in RAM with clean initialization or recovery checks.

3. **News Filter**:
   - *Finding*: `IsNearNewsEvent()` in `safety_filters.mqh` is a placeholder returning `false`.
   - *Impact*: Documented as an external dependency stub. News filtering relies on MT5 calendar API or external feeds if available; currently non-blocking in code.

4. **Latency & Floating Loss Checks**:
   - *Finding*: `IsLatencyAcceptable()` and `IsFloatingLossExceeded()` return static default values (`true` / `false`). Documented as showcase stubs.

5. **Position Management State**:
   - *Finding*: `PositionTracker` in `position_manager.mqh` tracks single ticket in RAM.
   - *Impact*: On EA restart, `g_tracker` resets. Existing trade detection in `OnTradeTransaction` and `PositionSelectByTicket` handles active positions gracefully.

6. **SL/TP Mechanics Alignment**:
   - *Finding*: The previous engine used `SL_ATR_Multiplier` on H1.
   - *SMC Alignment*: SMC Strategy v0.1 uses **Structural SL** (placed beyond the swept structural extreme / M5 swing with spread buffer). The existing risk manager lot sizer calculates volume dynamically using `stopDistance = MathAbs(entryPrice - slPrice)`.

---

## 6. Critical Rules & Assumptions That MUST NOT Be Made

1. **No Discretionary EQH/EQL Rules**: Strictly use `<` and `>` comparisons for 5-bar and 3-bar swings. Do not introduce `>=` or `<=` or arbitrary tie-breakers.
2. **No Intrabar Triggering**: All swings, BOS, CHoCH, and FVG confirmations MUST occur on closed candles (index >= 1).
3. **No Repainting**: Swings are confirmed only after the required right-side candles close (2 bars for 5-bar swing, 1 bar for 3-bar swing).
4. **No Chasing**: Limit orders placed at 50% FVG. If price has already passed through the 50% midpoint before order placement, cancel the setup immediately.
5. **No Optimization/Curve-Fitting**: Fixed parameters (5-bar 4H/M15, 3-bar M5, 50% FVG) must remain fixed. Parameters are not tuned for historical profit fitting.
