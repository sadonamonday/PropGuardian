# PropGuardian SMC Strategy v0.1 — Known Limitations & Engineering Decisions

## 1. Overview
This document outlines the source ambiguities, engineering decisions, and environment/verification limitations associated with **PropGuardian SMC Strategy v0.1**.

---

## 2. Strategy Engineering Decisions & Source Compliance

1. **Displacement Proxy Implementation**:
   - *Requirement*: Qualitative displacement requirement without a numerical point threshold.
   - *Engineering Solution*: Implemented as `"Structural displacement proxy: directional M5 breakout candle + qualifying FVG."`
   - *Behavior*: Enforces that M5 structural breakout candle must close beyond the M5 swing level AND be directionally matching (`Close > Open` for Buy, `Close < Open` for Sell) while producing a valid 3-candle Fair Value Gap (`Low(C3) > High(C1)` for Buy, `High(C3) < Low(C1)` for Sell).

2. **4H POI Detection & Provider Interface**:
   - *Requirement*: Valid 4H POI is either confirmed OB or FVG (equal status). Must agree with 4H structural direction.
   - *Engineering Solution*: Implemented scanning across 4H candles for confirmed 4H OB and 4H FVG matching 4H trend direction, plus an explicit POI registry interface (`Register4HPOI` / `GetActive4HPOI`).
   - *Behavior*: If no valid 4H POI is detected or explicitly registered, `GetActive4HPOI()` returns `false`, resulting in `NO TRADE` rather than inventing a proprietary scoring or ranking system.

3. **Take Profit Target Calculation**:
   - *Requirement*: Structural / liquidity-based TP target required. No fixed-R fallback allowed.
   - *Engineering Solution*: Setups target the next opposing confirmed M15 structural high (for Longs) or M15 structural low (for Shorts).
   - *Behavior*: No 3R, 2R, ATR, or fixed-pip fallbacks are used. If no opposing structural target is found ahead of entry, the setup is invalidated with an explicit reason (`NO TRADE`).

4. **Equal High / Equal Low Handling**:
   - *Requirement*: Strict `<` and `>` comparisons without discretionary tie-breaking rules.
   - *Engineering Solution*: Equal highs/lows do not qualify as confirmed fractal swings.

5. **Structural Stop Loss Buffer**:
   - *Requirement*: Structural SL placed beyond the swept extreme.
   - *Engineering Solution*: Market spread + 2.0 points buffer added beyond the swept low/high extreme to prevent accidental spread stop-outs.

---

## 3. Environment & Runtime Verification Limitations

1. **Local Execution Environment Limitations**:
   - The sandbox execution environment does not have the MetaEditor / MQL5 binary compiler (`metaeditor.exe`) or MetaTrader 5 terminal runtime installed.
   - MQL5 syntax and MQL5 logic execution paths are verified via codebase inspection and deterministic Python unit test simulation (`tests/test_smc_engine.py`). MQL5 binary compilation and live MT5 strategy tester execution could not be run in this environment.

2. **In-Memory Setup Tracking**:
   - `SMCSetup` array state is maintained in RAM during runtime. Terminal or EA restarts re-initialize setup trackers to `SMC_IDLE`. Active pending orders and positions are tracked via `g_tracker` and MT5 order/history transactions.

3. **Multi-Symbol Execution**:
   - Pending limit orders are submitted sequentially per symbol as setups reach `SMC_WAITING_FOR_FVG_RETRACE` and pass pre-trade risk gates (`CanOpenTrade()`).
