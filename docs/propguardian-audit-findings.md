# PropGuardian SMC Strategy — Comprehensive Codebase Audit & Findings

## 1. Executive Summary

An audit of the PropGuardian GitHub codebase was conducted against the MT5 Strategy Tester execution behavior (2023–2025 MT5 backtest report producing 6 trades and +$2.38 profit on a $1,000 deposit).

This audit identifies the exact codebase mechanics, state machine conditions, filter bottlenecks, and calculation defects that caused low trade frequency and micro-target execution, without modifying strategy rules or loosening strategy filters.

---

## 2. Setup State Machine & Trade Prevention Conditions (Task 1)

The PropGuardian SMC Strategy implements a deterministic 13-state multi-timeframe state machine (`4H -> M15 -> M5`):

`SMC_IDLE` -> `SMC_H4_POI_ACTIVE` -> `SMC_WAITING_FOR_M15_SWEEP` -> `SMC_M15_SWEEP_DETECTED` -> `SMC_WAITING_FOR_M15_CHOCH` -> `SMC_M15_CHOCH_CONFIRMED` -> `SMC_WAITING_FOR_M5_CONFIRMATION` -> `SMC_M5_CONFIRMATION` -> `SMC_FVG_DETECTED` -> `SMC_WAITING_FOR_FVG_RETRACE` -> `SMC_ENTRY_SUBMITTED` -> `SMC_TRADE_ACTIVE` -> `SMC_COMPLETED` (or `SMC_INVALIDATED`).

### Detailed Funnel Analysis & Block Conditions:

1. **`SMC_IDLE` -> `SMC_H4_POI_ACTIVE`**:
   - **Block Condition 1**: Active setups count reaches `SMC_MaxActiveSetups` (default 5 across symbols).
   - **Block Condition 2**: `GetTimeframeStructure(symbol, SMC_4H_Timeframe, 50)` returns `SMC_STRUCTURE_UNDEFINED` (4H market structure lacks 2 confirmed swing highs and 2 confirmed swing lows in last 50 bars).
   - **Block Condition 3**: No uninvalidated 4H Order Block or Fair Value Gap exists matching 4H structural direction. OB qualification requires candidate OB candle to be followed by a 3-candle sequence (`c1 <= obBarIndex`) with C2 being directional displacement, producing BOTH an associated 4H FVG AND a 4H body-close BOS beyond prior 4H swing.

2. **`SMC_H4_POI_ACTIVE` -> `SMC_WAITING_FOR_M15_SWEEP`**:
   - **Block Condition**: M15 candle range `[Low, High]` must intersect 4H POI range `[bottom, top]`. Stays active until M15 range intersects POI.

3. **`SMC_WAITING_FOR_M15_SWEEP` -> `SMC_M15_SWEEP_DETECTED`**:
   - **Block Condition 1**: Re-sweep duplicate check (`CheckM15LiquiditySweep`): Prevents re-creating setup for an already-invalidated sweep with same POI timestamp and sweep candle timestamp.
   - **Block Condition 2**: Must find confirmed 5-bar M15 swing low (for Buy) or high (for Sell) in last 40 M15 bars. Completed M15 bar 1 must sweep past swing extreme and close back inside (`low < swingLow.price AND close > swingLow.price` for Buy).

4. **`SMC_M15_SWEEP_DETECTED` -> `SMC_WAITING_FOR_M15_CHOCH`**:
   - **Block Condition**: `FindCHoCHLevel` scans backward from `sweepTime` for confirmed 5-bar M15 swing (swing1) and preceding confirmed swing (swing2). For Buy, swing1 must be Lower High (`swing1.price < swing2.price`); for Sell, Higher Low (`swing1.price > swing2.price`). If structure is ambiguous or not LH/HL, setup is immediately INVALIDATED (`"No valid structural M15 swing candidate found for CHoCH prior to sweep"`).

5. **`SMC_WAITING_FOR_M15_CHOCH` -> `SMC_M15_CHOCH_CONFIRMED`**:
   - **Block Condition 1**: Sweep price breach invalidates setup (`close < sweepPrice` or `low < sweepPrice` for Buy).
   - **Block Condition 2**: 4H POI invalidated prior to CHoCH.
   - **Block Condition 3**: Completed M15 candle body close beyond CHoCH level required. Wick-only breaks remain sweeps and keep setup in waiting state.

6. **`SMC_WAITING_FOR_M5_CONFIRMATION` -> `SMC_M5_CONFIRMATION`**:
   - **Block Condition**: `CheckM5DisplacementAndFVG` evaluates completed M5 bars (C1=bar 3, C2=bar 2, C3=bar 1). C2 must be directional displacement candle (`close > open` for Buy) closing past confirmed M5 swing high, and C3 completes FVG gap (`Low(C3) > High(C1)`).

7. **`SMC_M5_CONFIRMATION` -> `SMC_FVG_DETECTED`**:
   - **Block Condition**: Completed M5 candle body close through C1 boundary invalidates FVG (`close < fvg.bottom` for Buy).

8. **`SMC_FVG_DETECTED` -> `SMC_WAITING_FOR_FVG_RETRACE`**:
   - **Block Condition 1**: Structural SL calculation requires `slPrice < entryPrice` for Buy (`slPrice > entryPrice` for Sell).
   - **Block Condition 2**: Opposing M15 structural target search (`FindNextOpposingTargetHigh`/`Low`) must find valid confirmed M15 swing target ahead of entry price. If none found, setup is INVALIDATED (`NO FIXED-R FALLBACKS`).
   - **Block Condition 3**: No-Chase check: If completed M5 price already passed through 50% FVG midpoint prior to order creation (`completedPrice <= entryPrice` for Buy), setup is INVALIDATED.

9. **`SMC_WAITING_FOR_FVG_RETRACE` -> `SMC_ENTRY_SUBMITTED`**:
   - **Block Condition 1**: FVG body close invalidation while waiting for order placement.
   - **Block Condition 2**: Pre-Trade Risk Gate (`CanOpenTrade`):
     - `tradesToday >= Max_Trades_Per_Day` (1)
     - `openCount >= Max_Open_Positions` (1)
     - GMT Trading Session (`08:00–22:00 GMT`)
     - Asian Range Filter (08:00–10:00 GMT blocked if Asian range > 50 pips)
     - Spread Filter (`spread > 30 points` / 3 pips)
     - Rollover Window (Server hours 23 and 0)
     - Same Trade Idea Cooldown (12 mins per symbol)
   - **Block Condition 3**: Calculated lot size <= 0 or lot size < minimum volume step.

---

## 3. Diagnostic Counters Framework (Task 2 & 3)

To distinguish a rare market setup from a code path bottleneck, a diagnostic counter tracking system was integrated into `showcase/smc_engine.mqh` and `showcase/PropGuardian.mq5`.

### Diagnostic Counters Structure:
```mql5
struct SMCDiagnosticCounters
{
   int poiDetected;          // 4H POIs detected
   int poiActivated;         // M15 price range touched 4H POI
   int sweepDetected;        // Valid M15 liquidity sweeps detected
   int chochCandidateFound;  // Valid M15 CHoCH levels identified
   int chochConfirmed;      // M15 candle body closed beyond CHoCH
   int chochRejected;       // Sweeps rejected due to missing LH/HL candidate
   int m5Confirmed;         // M5 execution structure & displacement confirmed
   int fvgDetected;         // 3-candle FVG validated
   int fvgInvalidated;      // FVG closed through C1 boundary
   int retraceReached;      // Limit order filled at 50% FVG retrace
   int noChaseTriggered;    // Price passed 50% midpoint before order creation
   int orderSubmitted;     // Pending limit order sent to broker
   int orderAccepted;      // Order retcode 10009/10008
   int orderRejected;      // OrderSend failed
   int orderExpired;       // Pending limit order expired after 4 hours
   int tradeClosed;        // Active position closed
};
```

### Funnel Summary Output (generated via `PrintDiagnosticCountersReport()` in `OnDeinit`):
- `[SMC_DIAGNOSTIC] POIs Detected: N | Activated: N`
- `[SMC_DIAGNOSTIC] Sweeps Detected: N`
- `[SMC_DIAGNOSTIC] CHoCH Candidates: N | Confirmed: N | Rejected/Invalidated: N`
- `[SMC_DIAGNOSTIC] M5 Confirmed: N | FVGs Detected: N | FVGs Invalidated: N`
- `[SMC_DIAGNOSTIC] Retrace Reached: N | No Chase Triggered: N`
- `[SMC_DIAGNOSTIC] Orders Submitted: N | Accepted: N | Rejected: N | Expired: N`
- `[SMC_DIAGNOSTIC] Trades Closed: N`

---

## 4. M15 Candle Evaluation & Stale Data Verification (Task 4)

A strict audit of `ProcessSMCSetupStateMachine` under state `SMC_WAITING_FOR_M15_CHOCH` confirms that:

1. `setup.lastEvaluatedM15ChochTime` is initialized to `setup.sweepTime` upon sweep detection.
2. On every tick, completed M15 bar 1 timestamp (`m15Bar1Time = iTime(symbol, PERIOD_M15, 1)`) is checked against `setup.lastEvaluatedM15ChochTime`.
3. The evaluation executes ONLY IF `m15Bar1Time > setup.lastEvaluatedM15ChochTime`, after which `lastEvaluatedM15ChochTime` is updated to `m15Bar1Time`.
4. Multiple ticks during the same M15 candle window are ignored and do not re-evaluate CHoCH.
5. Incomplete / forming candles (`barIndex = 0`) are explicitly excluded (`CheckM15CHoCH` uses `barIndex = 1`).

**Conclusion**: Each completed M15 candle is evaluated **exactly once**. The EA does not repeatedly evaluate stale or incomplete candle data.

---

## 5. Audit of EURUSD Trade (Entry 1.06096, SL 1.06282, TP 1.06093) (Task 5)

### Reported Trade Parameters:
- **Symbol**: EURUSD (Sell Limit)
- **Entry Price**: 1.06096 (50% FVG Midpoint)
- **Stop Loss**: 1.06282 (Swept High Invalidation) -> Risk Distance = 18.6 pips
- **Take Profit**: 1.06093 (Opposing Swing Low) -> Target Distance = 0.3 pips (3 points!)
- **Reward-to-Risk (R:R)**: 0.3 pips / 18.6 pips = **0.016 R**

### Root Cause Analysis:
1. `FindNextOpposingTargetLow` in `showcase/smc_engine.mqh` scanned confirmed 5-bar M15 swing lows starting from `barIndex = 3` backward.
2. The function evaluated `if (swing.price < entryPrice)`.
3. An internal M15 swing low formed at 1.06093 (during the recent price action preceding/during the retracement leg) had `1.06093 < 1.06096` (a difference of 0.00003 or 0.3 pips).
4. `FindNextOpposingTargetLow` accepted 1.06093 as the TP price because no minimum distance or spread/StopLevel threshold was enforced.

### Evaluation Against Intended Rules:
- An internal micro-swing located 0.3 pips from entry (well within the EURUSD spread and broker StopLevel) is **not** a valid opposing structural liquidity target under SMC principles.
- Under intended strategy rules, a target that does not sit beyond the entry price by at least valid market spread / StopLevel distance is invalid.
- If no valid opposing target exists beyond the entry structure, the setup **must be invalidated** (`NO TRADE`).

---

## 6. System-Wide Bottlenecks & Multi-Symbol Processing (Task 6)

### 1. Global Multi-Symbol Tick Freeze (Primary Structural Defect):
In `showcase/PropGuardian.mq5`, `OnTick()` contained the following check:
```mql5
void OnTick()
{
   if(g_tracker.ticket == 0 && g_pendingOrderTicket == 0)
   {
      SMCEngine_OnTick();
   }
}
```
`g_tracker` and `g_pendingOrderTicket` are single global scalars. When a pending limit order or position was active on EURUSD, `SMCEngine_OnTick()` was **completely bypassed** for ALL 5 tradeable symbols (`GBPUSD`, `USDJPY`, `AUDUSD`, `USDCAD`). A pending limit order waiting 4 hours for retracement froze all market scanning across all symbols for 4 hours.

### 2. Global Account Trade Cap (`Max_Trades_Per_Day = 1`):
`Max_Trades_Per_Day = 1` applies globally across all 5 symbols. Once 1 trade occurs on any symbol, `tradesToday = 1`, causing `CanOpenTrade()` to fail and immediately INVALIDATE any valid SMC setup on all other symbols for the rest of the day.

### 3. Session & Filter Rejections Outside Trading Hours:
Setups reaching `SMC_FVG_DETECTED` outside 08:00–22:00 GMT or during rollover (hours 23 and 0) failed `CanOpenTrade()` and were immediately invalidated instead of waiting for session opening.

---

## 7. Test Results, Regression Test Suite & Execution Capabilities (Task 7)

### Python Unit Test Execution:
- Executed full test suite in `tests/test_smc_engine.py`.
- **Result**: `82/82 PASS` (0 errors, 0 failures, 0.004s).
- Added regression test cases:
  1. `test_micro_target_tp_rejected_by_min_distance`: Verifies micro-targets < minDistance (0.3 pips) are rejected in favor of valid opposing targets (e.g. 1.05500).
  2. `test_multi_symbol_tick_isolation`: Verifies active trades on Symbol A do not block state machine evaluation on Symbol B.

### Local Environment Capabilities:
- MetaEditor compiler (`metaeditor.exe`) and MetaTrader 5 terminal GUI/runtime are **not installed** in the local Linux execution environment.
- MQL5 syntax and strategy logic were verified via static codebase inspection, git diff verification, and Python test suite simulations. Local `.ex5` binary compilation could not be executed due to environmental limitations.

---

## 8. Root Causes Ranked by Evidence & Impact

1. **Rank 1 (Highest Impact)**: **Multi-Symbol Global Engine Freeze** in `showcase/PropGuardian.mq5` (`OnTick()` early exit when `g_pendingOrderTicket > 0` or `g_tracker.ticket > 0`), freezing all symbol state machine evaluations whenever 1 pending limit order or trade is active.
2. **Rank 2**: **Global `Max_Trades_Per_Day = 1` Account Limit & Immediate Risk Invalidation** in `showcase/risk_manager.mqh` and `showcase/PropGuardian.mq5`, causing all setups across 5 symbols to be permanently invalidated once 1 trade is taken per day or outside session hours.
3. **Rank 3**: **Unchecked Opposing TP Target Distance Defect** in `showcase/smc_engine.mqh` (`FindNextOpposingTargetLow`/`High`), causing internal micro-swings (0.3 pips from entry) to be selected as TP targets.

---

## 9. Exact Files & Functions Involved

- `showcase/PropGuardian.mq5`:
  - `OnTick()`: Multi-symbol tick freeze logic.
  - `OnTimer()`: Setup order placement, risk gate evaluation, and setup invalidation.
  - `OnTradeTransaction()`: Order fill detection and position closing.
  - `OnDeinit()`: Diagnostic report invocation.
- `showcase/smc_engine.mqh`:
  - `FindNextOpposingTargetHigh()` & `FindNextOpposingTargetLow()`: Opposing TP target selection & distance validation.
  - `ProcessSMCSetupStateMachine()`: Setup state machine transitions and invalidations.
  - `CheckM15CHoCH()` & `FindCHoCHLevel()`: CHoCH candidate selection and single completed M15 candle evaluation.
  - `g_SMCCounters` & `PrintDiagnosticCountersReport()`: Diagnostic counters framework.
- `showcase/risk_manager.mqh`:
  - `CanOpenTrade()`: Pre-trade risk gates (`Max_Trades_Per_Day`, soft stop, hard stop).
- `showcase/safety_filters.mqh`:
  - `PassesAllFilters()`: Session hours, Asian range, spread, rollover, and cooldown filters.
- `tests/test_smc_engine.py`:
  - Unit test suite and regression tests for confirmed defects.

---

## 10. Minimal Confirmed Fixes Applied

1. **Multi-Symbol Engine Freeze Fix**: Removed the global tick block `if(g_tracker.ticket == 0 && g_pendingOrderTicket == 0)` from `OnTick()` in `showcase/PropGuardian.mq5` so `SMCEngine_OnTick()` runs on every tick for all tracked symbols.
2. **Micro-Target TP Fix**: Updated `FindNextOpposingTargetHigh` and `FindNextOpposingTargetLow` in `showcase/smc_engine.mqh` to enforce `minDistance` (minimum 1.0x spread / StopLevel in points) ahead of entry price before accepting a swing as a valid opposing TP target.
3. **Diagnostic Counters Integration**: Added `SMCDiagnosticCounters g_SMCCounters` and `PrintDiagnosticCountersReport()` in `showcase/smc_engine.mqh` and `showcase/PropGuardian.mq5`.
