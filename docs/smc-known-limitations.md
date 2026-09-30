# PropGuardian SMC Strategy v0.1 — Known Limitations & Unresolved Ambiguities

## 1. Overview
This document outlines the known source ambiguities, engineering trade-offs, and architectural limitations associated with **PropGuardian SMC Strategy v0.1**.

---

## 2. Unresolved Strategy Ambiguities & Implementation Choices

1. **Equal High / Equal Low Handling**:
   - *Specification*: Strict `<` and `>` comparisons without discretionary tie-breaking rules.
   - *Implementation*: Equal highs/lows do not qualify as confirmed fractal swings.

2. **Quantitative Displacement Threshold**:
   - *Specification*: Qualitative displacement requirement without a numeric threshold.
   - *Implementation*: M5 execution structure break (M5 BOS body close) coupled with a valid 3-candle FVG resulting from the structural impulse acts as the isolated deterministic proof of displacement.

3. **4H POI Definition & Touch Intersect**:
   - *Specification*: 4H timeframe activates setup via active Demand/Supply POI without inventing proprietary algorithms.
   - *Implementation*: Demand POI is anchored to the most recent confirmed 4H swing low, Supply POI to 4H swing high. Intersect occurs when M15 candle range `[Low, High]` overlaps POI range `[bottom, top]`.

4. **Structural Stop Loss Spread Buffer**:
   - *Specification*: Structural SL placed beyond the swept extreme.
   - *Implementation*: Market spread + 2.0 points buffer added beyond the swept low/high extreme.

---

## 3. System Limitations

1. **In-Memory Setup Tracking**:
   - `SMCSetup` array state is maintained in RAM. Terminal/EA restarts re-initialize setup trackers to `SMC_IDLE`. Active pending orders and positions are tracked via `g_tracker` and MT5 order history.
2. **Economic News Calendar Filter**:
   - `IsNearNewsEvent()` in `safety_filters.mqh` remains an external calendar stub returning `false`. Third-party economic calendar integration is required for news event filtering.
3. **Multi-Symbol Pending Orders**:
   - Pending limit orders are submitted sequentially per symbol as setups reach `SMC_WAITING_FOR_FVG_RETRACE` and pass `CanOpenTrade()`.
