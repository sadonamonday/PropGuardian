# PropGuardian SMC Strategy v0.1 — Technical Specification & Documentation

## 1. Current Locked Strategy Architecture
PropGuardian SMC Strategy v0.1 implements a deterministic multi-timeframe Smart Money Concepts (SMC) execution engine in MQL5 for MetaTrader 5:

**4H → M15 → M5**

### Timeframe Responsibilities:
- **4H (Context Timeframe)**: Higher-timeframe context, market structure mapping, 4H POIs (Order Blocks & FVGs of equal status), setup activation.
- **M15 (Structural Timeframe)**: Intermediate structure mapping, 4H POI touch interaction, M15 liquidity sweep detection, M15 CHoCH confirmation on completed candle body close.
- **M5 (Execution Timeframe)**: Execution structure confirmation (M5 BOS body close), displacement impulse, Fair Value Gap (FVG) detection tied directly to displacement sequence, and limit order entry at **50% FVG midpoint**.

---

## 2. 4H POI Architecture & Rules
- **POI Types & Status**:
  - Valid 4H POIs include confirmed bullish/bearish Order Blocks (OB) and Fair Value Gaps (FVG).
  - OB and FVG have **equal status** (no automatic prioritization of OB over FVG).
- **Directional Alignment**:
  - POI direction must strictly agree with current 4H structural direction.
  - Bullish 4H structure → Only bullish POIs (Demand OB / Bullish FVG) eligible.
  - Bearish 4H structure → Only bearish POIs (Supply OB / Bearish FVG) eligible.
  - Undefined 4H structure → No POI activation.
- **POI Selection**:
  - When multiple valid POIs exist, select the **most recent valid, uninvalidated POI**.
  - No arbitrary distance thresholds, freshness scoring, or strength rankings are used.
- **POI Activation**:
  - Activated when a completed M15 candle range `[Low, High]` intersects the 4H POI range `[bottom, top]`:
    `M15 High >= POI Low AND M15 Low <= POI High`.
  - Intersection activates the M15 sweep stage; it does not trigger an order by itself.
- **POI Invalidation**:
  - *Bullish OB*: Invalidated when a completed 4H candle closes below the OB low.
  - *Bearish OB*: Invalidated when a completed 4H candle closes above the OB high.
  - *FVG*: Invalidated when a completed candle closes through the C1 boundary (`close < fvg.bottom` for bullish, `close > fvg.top` for bearish).

---

## 3. Swing Definitions
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

## 4. Structure, BOS & CHoCH
- **BOS (Break of Structure)**: Trend continuation.
  - *Bullish BOS*: Completed candle BODY closes above relevant confirmed swing high.
  - *Bearish BOS*: Completed candle BODY closes below relevant confirmed swing low.
  - Wick-only breaks are treated as liquidity sweeps/interactions, NOT structural BOS.
- **CHoCH (Change of Character)**: Structural reversal.
  - *Bullish CHoCH*: Established bearish structure → M15 liquidity sweep occurs → Identify most recent confirmed Lower High directly originating the final downward leg into the sweep low → Completed M15 candle BODY closes above that lower high.
  - *Bearish CHoCH*: Established bullish structure → M15 liquidity sweep occurs → Identify most recent confirmed Higher Low directly preceding the final upward leg into the sweep high → Completed M15 candle BODY closes below that higher low.

---

## 5. M15 Liquidity Sweep
- **M15 Liquidity Sweep Rule**:
  - *LONG*: Active 4H demand context exists → Price trades below most recent confirmed M15 swing low → Completed M15 candle closes back ABOVE that swept swing-low level.
  - *SHORT*: Active 4H supply context exists → Price trades above most recent confirmed M15 swing high → Completed M15 candle closes back BELOW that swept swing-high level.

---

## 6. M5 Execution, Displacement & FVG
- **M5 Execution Structure**: Requires M5 structural break confirmed by candle BODY close above relevant confirmed M5 swing high (Long) or below M5 swing low (Short).
- **M5 Displacement Proxy & FVG**:
  - Displacement proxy: Completed M5 candle is directionally matching (`Close > Open` for Buy, `Close < Open` for Sell), body closes beyond latest confirmed M5 swing, and a qualifying FVG is produced by that displacement sequence.
  - *Bullish FVG*: `Low(C3) > High(C1)`. Midpoint = `(High(C1) + Low(C3)) / 2.0`.
  - *Bearish FVG*: `High(C3) < Low(C1)`. Midpoint = `(Low(C1) + High(C3)) / 2.0`.
  - FVG boundaries use candle WICKS (Candle 1 and Candle 3). Confirmed on Candle 3 close.
  - The exact FVG produced by the displacement sequence is stored and monitored through its lifecycle.
- **Order Placement, Retrace & Mitigation**:
  - BUY LIMIT / SELL LIMIT placed at 50% FVG midpoint.
  - *No-Chase Invalidation*: If price passes through 50% midpoint before order creation, cancel setup.
  - *FVG Invalidation*: Completed candle body close beyond Candle 1 boundary invalidates setup and cancels active pending limit order.

---

## 7. Stop Loss & Take Profit
- **Structural Stop Loss**:
  - Placed beyond the swept low/high extreme with a spread + 2.0 point buffer.
  - Risk-based lot size calculated from actual entry-to-SL distance.
- **Structural Take Profit**:
  - Target must use the next opposing confirmed M15 structural target (M15 swing high for Long, M15 swing low for Short).
  - Target must be ahead of entry price in trade direction.
  - **NO FIXED-R FALLBACKS**: If no valid opposing structural target exists, DO NOT TAKE THE TRADE (setup is invalidated).

---

## 8. Complete Setup Sequences
- **LONG Sequence**: 4H bullish context / demand POI active → M15 trades below confirmed swing low → M15 closes back above swept low → identify final sweep low → identify most recent confirmed LH originating final bearish leg → M15 bullish CHoCH body close → M5 bullish execution structure (BOS body close) → M5 bullish displacement & FVG → FVG confirmed on C3 close → BUY LIMIT at 50% FVG midpoint → structural SL below swept low → structural TP at opposing M15 swing high.
- **SHORT Sequence**: 4H bearish context / supply POI active → M15 trades above confirmed swing high → M15 closes back below swept high → identify final sweep high → identify most recent confirmed HL preceding final bullish leg → M15 bearish CHoCH body close → M5 bearish execution structure (BOS body close) → M5 bearish displacement & FVG → FVG confirmed on C3 close → SELL LIMIT at 50% FVG midpoint → structural SL above swept high → structural TP at opposing M15 swing low.

---

## 9. Deterministic Setup State Machine
`SMC_IDLE` → `SMC_H4_POI_ACTIVE` → `SMC_WAITING_FOR_M15_SWEEP` → `SMC_M15_SWEEP_DETECTED` → `SMC_WAITING_FOR_M15_CHOCH` → `SMC_M15_CHOCH_CONFIRMED` → `SMC_WAITING_FOR_M5_CONFIRMATION` → `SMC_M5_CONFIRMATION` → `SMC_FVG_DETECTED` → `SMC_WAITING_FOR_FVG_RETRACE` → `SMC_ENTRY_SUBMITTED` → `SMC_TRADE_ACTIVE` → `SMC_COMPLETED` (or `SMC_INVALIDATED`).
