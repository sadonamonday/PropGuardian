# PropGuardian SMC Strategy v0.1 — Technical Specification & Documentation

## 1. Current Locked Strategy Architecture
PropGuardian SMC Strategy v0.1 implements a deterministic multi-timeframe Smart Money Concepts (SMC) execution engine in MQL5 for MetaTrader 5:

**4H → M15 → M5**

### Timeframe Responsibilities:
- **4H (Context Timeframe)**: Higher-timeframe context, market structure mapping, major POI (Supply/Demand) identification, setup activation.
- **M15 (Structural Timeframe)**: Intermediate structure mapping, 4H POI touch interaction, M15 liquidity sweep detection, M15 CHoCH confirmation on completed candle body close.
- **M5 (Execution Timeframe)**: Execution structure confirmation (M5 BOS body close), displacement impulse, Fair Value Gap (FVG) detection, and limit order entry at **50% FVG midpoint**.

---

## 2. Swing Definitions
- **4H and M15 Swings**: Confirmed 5-Bar Fractals on completed candles.
  - *Swing High*: `High[i] > High[i+1]` AND `High[i] > High[i+2]` AND `High[i] > High[i-1]` AND `High[i] > High[i-2]`
  - *Swing Low*: `Low[i] < Low[i+1]` AND `Low[i] < Low[i+2]` AND `Low[i] < Low[i-1]` AND `Low[i] < Low[i-2]`
  - Becomes confirmed only after 2 right-side candles close (`barIndex >= 3`).
- **M5 Swings**: Confirmed 3-Bar Fractals on completed candles.
  - *Swing High*: `High[i] > High[i+1]` AND `High[i] > High[i-1]`
  - *Swing Low*: `Low[i] < Low[i+1]` AND `Low[i] < Low[i-1]`
  - Becomes confirmed after 1 right-side candle closes (`barIndex >= 2`).
- **Equal High / Equal Low Rule**:
  - Strict `<` and `>` comparisons only. No equal-high/equal-low tie-breaking algorithm is invented. Unclosed/future candles are never used.

---

## 3. Structure, BOS & CHoCH
- **BOS (Break of Structure)**: Trend continuation.
  - *Bullish BOS*: Completed candle BODY closes above relevant confirmed swing high.
  - *Bearish BOS*: Completed candle BODY closes below relevant confirmed swing low.
  - Wick-only breaks are treated as liquidity sweeps/interactions, NOT structural BOS.
- **CHoCH (Change of Character)**: Structural reversal.
  - *Bullish CHoCH*: Market in established bearish structure → M15 liquidity sweep occurs → Identify most recent confirmed lower high preceding final bearish leg into that low → Completed M15 candle BODY closes above that lower high.
  - *Bearish CHoCH*: Market in established bullish structure → M15 liquidity sweep occurs → Identify most recent confirmed higher low preceding final bullish leg into that high → Completed M15 candle BODY closes below that higher low.

---

## 4. 4H POI & M15 Liquidity Sweep
- **4H POI Context**: Activates the setup. M15 bar range `[Low, High]` must intersect 4H POI range `[bottom, top]`.
- **M15 Liquidity Sweep Rule**:
  - *LONG*: Active 4H demand context exists → Price trades below most recent confirmed M15 swing low → Completed M15 candle closes back ABOVE that swept swing-low level.
  - *SHORT*: Active 4H supply context exists → Price trades above most recent confirmed M15 swing high → Completed M15 candle closes back BELOW that swept swing-high level.

---

## 5. M5 Execution, FVG & Order Entry
- **M5 Execution Structure**: Requires M5 structural break confirmed by candle BODY close above relevant confirmed M5 swing high (Long) or below M5 swing low (Short).
- **M5 Displacement & FVG**:
  - *Bullish FVG*: `Low(C3) > High(C1)`. Midpoint = `(High(C1) + Low(C3)) / 2.0`.
  - *Bearish FVG*: `High(C3) < Low(C1)`. Midpoint = `(Low(C1) + High(C3)) / 2.0`.
  - FVG boundaries use candle WICKS (Candle 1 and Candle 3). Confirmed on Candle 3 close.
- **Order Placement & Mitigation**:
  - BUY LIMIT / SELL LIMIT placed at 50% FVG midpoint.
  - *No-Chase Invalidation*: If price passes through 50% midpoint before order creation, cancel setup.
  - *FVG Invalidation*: Completed candle body close beyond Candle 1 boundary invalidates setup.

---

## 6. Complete Setup Sequences
- **LONG Sequence**: 4H bullish context / demand POI active → M15 trades below confirmed swing low → M15 closes back above swept low → identify final sweep low → identify most recent confirmed LH preceding final bearish leg → M15 bullish CHoCH body close → M5 bullish execution structure (BOS body close) → M5 bullish displacement & FVG → FVG confirmed on C3 close → BUY LIMIT at 50% FVG midpoint → structural SL below swept low → structural TP at opposing M15 swing high.
- **SHORT Sequence**: 4H bearish context / supply POI active → M15 trades above confirmed swing high → M15 closes back below swept high → identify final sweep high → identify most recent confirmed HL preceding final bullish leg → M15 bearish CHoCH body close → M5 bearish execution structure (BOS body close) → M5 bearish displacement & FVG → FVG confirmed on C3 close → SELL LIMIT at 50% FVG midpoint → structural SL above swept high → structural TP at opposing M15 swing low.

---

## 7. Deterministic Setup State Machine
`SMC_IDLE` → `SMC_H4_POI_ACTIVE` → `SMC_WAITING_FOR_M15_SWEEP` → `SMC_M15_SWEEP_DETECTED` → `SMC_WAITING_FOR_M15_CHOCH` → `SMC_M15_CHOCH_CONFIRMED` → `SMC_WAITING_FOR_M5_CONFIRMATION` → `SMC_M5_CONFIRMATION` → `SMC_FVG_DETECTED` → `SMC_WAITING_FOR_FVG_RETRACE` → `SMC_ENTRY_SUBMITTED` → `SMC_TRADE_ACTIVE` → `SMC_COMPLETED` (or `SMC_INVALIDATED`).
