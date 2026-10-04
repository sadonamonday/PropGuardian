# PropGuardian SMC Strategy v0.1 — Known Limitations & Engineering Decisions

## 1. Overview
This document outlines the source ambiguities, engineering decisions, and environment/verification limitations associated with **PropGuardian SMC Strategy v0.1**.

---

## 2. Strategy Engineering Decisions & Source Compliance

1. **Displacement Proxy Implementation**:
   - *Requirement*: Qualitative displacement requirement without a numerical point threshold.
   - *Engineering Solution*: Implemented as `"Structural displacement proxy: directional M5 breakout candle + qualifying FVG."`
   - *Behavior*: Enforces that M5 structural breakout candle must close beyond the M5 swing level AND be directionally matching (`Close > Open` for Buy, `Close < Open` for Sell) while producing a valid 3-candle Fair Value Gap (`Low(C3) > High(C1)` for Buy, `High(C3) < Low(C1)` for Sell).

2. **4H POI Detection & Qualification**:
   - *Requirement*: Valid 4H POI is either confirmed OB or FVG (equal status). Must agree with 4H structural direction.
   - *Engineering Solution*: Implemented scanning across 4H candles for confirmed 4H OB and 4H FVG matching 4H trend direction, plus an explicit POI registry interface (`Register4HPOI` / `GetActive4HPOI`).
   - *4H OB Sequence Rule*: Candidate 4H OB is the final opposite-direction candle before a qualifying displacement move originating after the OB bar (`c1 <= obBarIndex`) that produces BOTH an associated 4H FVG and a candle body-close 4H BOS within the same 3-candle move sequence. Obeying source constraints, unsupported assumptions (such as requiring an immediately adjacent candle state or rejecting OBs due to intervening opposite-colored candles during the displacement move) are omitted.
   - *Source Ambiguity & Search Loop Limitations*: Where the source material does not define a maximum candle count between the OB and qualifying BOS/FVG or a numerical threshold for internal consolidation during a multi-candle move, no arbitrary candle limits or thresholds are invented. Fixed engineering search loop limits (e.g. 50 bars for 4H POI/swings, 40 bars for M15 sweeps, 30 bars for M5 swings, 200 bars for opposing TP targets) serve solely as implementation processing boundaries rather than strategy definition rules.
   - *Behavior*: If no valid 4H POI is detected or explicitly registered, `GetActive4HPOI()` returns `false`, resulting in `NO TRADE` rather than inventing a proprietary scoring or ranking system.

3. **M15 CHoCH Swing Selection & Final-Leg Origin Limitation**:
   - *Requirement*: CHoCH swing must be the confirmed M15 swing (LH for Bullish, HL for Bearish) directly originating the final leg into the swept extreme.
   - *Engineering Solution*: Implemented `FindCHoCHLevel` finding the most recent confirmed 5-bar M15 swing before `sweepTime` and verifying its structural relationship (Lower High relative to preceding swing for Bullish, Higher Low relative to preceding swing for Bearish).
   - *Exact Final-Leg Origin Limitation*: The strategy source specifies that the LH/HL should be the swing directly preceding/originating the final leg into the swept extreme. However, the available source rules do not algorithmically define "final-leg origin" beyond the confirmed 5-bar swing LH/HL relationship. The current deterministic LH/HL implementation is kept without pretending a source rule exists where it does not.
   - *Deterministic Fallback Limitation*: If the most recent confirmed swing is not a valid LH or HL, or if insufficient confirmed structure exists to establish the relationship, the engine does not fall back to older swings merely because they exist; `FindCHoCHLevel()` returns `false` and the setup is safely invalidated (`NO TRADE`).

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
