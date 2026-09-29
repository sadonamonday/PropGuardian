# PropGuardian SMC Strategy v0.1 — Technical Specification & Documentation

## 1. Overview & Core Architecture
PropGuardian SMC Strategy v0.1 implements a deterministic, multi-timeframe Smart Money Concepts trading engine in MQL5 for MetaTrader 5.

The engine relies on a strict multi-timeframe hierarchy:
- **4H (Context Timeframe)**: Directional structure mapping, 4H POI (Supply/Demand) identification.
- **M15 (Structural Timeframe)**: 5-bar swing mapping, POI interaction detection, M15 liquidity sweep, and M15 Change of Character (CHoCH) confirmation on candle body close.
- **M5 (Execution Timeframe)**: 3-bar swing mapping, execution structure alignment, displacement, Fair Value Gap (FVG) creation, and pending limit order execution at **50% FVG midpoint**.

---

## 2. Swing Definitions
- **4H and M15 Swings**: 5-Bar Fractals on completed candles.
  - *Swing High*: `High[i] > High[i+1]` AND `High[i] > High[i+2]` AND `High[i] > High[i-1]` AND `High[i] > High[i-2]`
  - *Swing Low*: `Low[i] < Low[i+1]` AND `Low[i] < Low[i+2]` AND `Low[i] < Low[i-1]` AND `Low[i] < Low[i-2]`
  - Confirmed only after two right-side candles close (`barIndex >= 2`).
- **M5 Swings**: 3-Bar Fractals on completed candles.
  - *Swing High*: `High[i] > High[i+1]` AND `High[i] > High[i-1]`
  - *Swing Low*: `Low[i] < Low[i+1]` AND `Low[i] < Low[i-1]`
  - Confirmed after one right-side candle closes (`barIndex >= 1`).
- **Equal High / Equal Low Rule**:
  - SOURCE-DERIVED RULE / SPEC: Equal highs/lows do NOT qualify as normal fractal swings under strict `<` and `>` comparisons.
  - No arbitrary tie-breaking logic is applied.

---

## 3. Structure, BOS & CHoCH
- **Market Structure**: Tracked independently for each timeframe (`SMC_STRUCTURE_BULLISH`, `SMC_STRUCTURE_BEARISH`, `SMC_STRUCTURE_UNDEFINED`).
- **Break of Structure (BOS)**: Trend continuation triggered when a completed candle **body closes** beyond the relevant confirmed swing level.
- **Change of Character (CHoCH)**: Reversal signal.
  - *Bullish CHoCH*: Existing structure BEARISH -> M15 price sweeps liquidity inside 4H Demand POI -> Completed M15 candle body closes above the most recent confirmed Lower High preceding the sweep extreme.
  - *Bearish CHoCH*: Existing structure BULLISH -> M15 price sweeps liquidity inside 4H Supply POI -> Completed M15 candle body closes below the most recent confirmed Higher Low preceding the sweep extreme.
  - Wick-only breaks are NOT BOS or CHoCH.

---

## 4. Liquidity Sweep Rule
- **PROPGUARDIAN ENGINEERING RECOMMENDATION**:
  - *Long Setup*: M15 price trades below the most recent confirmed M15 Swing Low while interacting with a 4H Demand POI, and the same completed M15 candle closes back above that swing-low price.
  - *Short Setup*: M15 price trades above the most recent confirmed M15 Swing High while interacting with a 4H Supply POI, and the same completed M15 candle closes back below that swing-high price.

---

## 5. Fair Value Gap (FVG) & Execution
- **3-Candle Structure (M5)**:
  - *Bullish FVG*: `Low(Candle 3) > High(Candle 1)`. Midpoint = `(Low(Candle 3) + High(Candle 1)) / 2.0`.
  - *Bearish FVG*: `High(Candle 3) < Low(Candle 1)`. Midpoint = `(High(Candle 3) + Low(Candle 1)) / 2.0`.
  - Confirmed on Candle 3 close.
- **Entry Mechanics**:
  - Pending Limit Order (`ORDER_TYPE_BUY_LIMIT` / `ORDER_TYPE_SELL_LIMIT`) placed at exact **50% FVG midpoint**.
  - **No-Chase Rule**: If price has already crossed through the 50% midpoint before order creation, the setup is invalidated immediately.
- **FVG Invalidation**:
  - Invalidated if a completed M5 candle body closes beyond the Candle 1 boundary.

---

## 6. Stop Loss & Take Profit
- **Stop Loss**: STRUCTURAL SL placed beyond the swept extreme with spread buffer.
- **Take Profit**: Targeted at opposing confirmed M15 structural swing high/low.

---

## 7. State Machine Lifecycle
`SMC_IDLE` -> `SMC_POI_ACTIVE` -> `SMC_WAITING_FOR_SWEEP` -> `SMC_SWEEP_CONFIRMED` -> `SMC_WAITING_FOR_CHOCH` -> `SMC_CHOCH_CONFIRMED` -> `SMC_WAITING_FOR_M5_CONFIRMATION` -> `SMC_FVG_CONFIRMED` -> `SMC_WAITING_FOR_FVG_ENTRY` -> `SMC_ENTRY_SUBMITTED` -> `SMC_TRADE_ACTIVE` (or `SMC_INVALIDATED`).

---

## 8. Risk Management Integration
All SMC signals pass through `CanOpenTrade()` in `risk_manager.mqh`. Gates include:
1. Daily loss soft stop (-2.5%) & hard stop (-5.0%)
2. Portfolio emergency drawdown (-10.0%)
3. Max trades per day limit
4. Circuit breaker consecutive loss cooldown
5. Safety filters (spread, session window, Asian range, rollover window, toxic volatility)
