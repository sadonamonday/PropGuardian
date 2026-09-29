# PropGuardian SMC Strategy v0.1 — Known Limitations & Unresolved Ambiguities

## 1. Overview
This document outlines the known source ambiguities, engineering trade-offs, and architectural limitations associated with the initial release of **PropGuardian SMC Strategy v0.1**.

---

## 2. Unresolved Source Ambiguities & Engineering Decisions

1. **Equal High / Equal Low Handling**:
   - *Ambiguity*: Source material does not define a tie-breaking rule for equal fractal highs or lows.
   - *PropGuardian Decision*: Enforce strict `<` and `>` comparisons. Equal highs/lows do not qualify as fractal swings. Debug log condition exposed.

2. **Quantitative Displacement Threshold**:
   - *Ambiguity*: Displacement is defined qualitatively in SMC literature without a numeric ATR/pip threshold.
   - *PropGuardian Decision*: Use the presence of a valid 3-candle FVG resulting from structural break as the deterministic proof of displacement.

3. **Internal vs. External Liquidity Filtering**:
   - *Ambiguity*: No deterministic mathematical rule provided for separating internal minor noise from external major structure.
   - *PropGuardian Decision*: Rely strictly on 5-bar swings for 4H/M15 and 3-bar swings for M5 without arbitrary pip/ATR noise filters.

4. **HTF POI Touch Tolerance**:
   - *Ambiguity*: Touch tolerance into 4H POI varies in discretionary trading.
   - *PropGuardian Decision*: Require M15 bar range `[Low, High]` to intersect the 4H POI range `[bottom, top]`.

5. **Structural Stop Loss Spread Buffer**:
   - *Ambiguity*: Exact buffer pips beyond swept structural low/high vary across brokers.
   - *PropGuardian Decision*: Use market spread + 2.0 points buffer beyond structural low/high.

---

## 3. Known System Limitations

1. **In-Memory Setup Tracking**:
   - `SMCSetup` array state is maintained in RAM. If MT5 terminal or EA restarts mid-setup before order placement, setup state resets to `SMC_IDLE`. Active broker limit orders and open positions are preserved and managed via `g_tracker` and MT5 order history.
2. **Calendar / News Filter Dependency**:
   - `IsNearNewsEvent()` in `safety_filters.mqh` remains a stub returning `false`. Third-party economic calendar integration is required for news event filtering.
3. **Multi-Symbol Limit Order Execution**:
   - Pending limit orders are placed one symbol at a time as setups fire and pass `CanOpenTrade()`.
