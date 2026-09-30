# PropGuardian SMC Strategy v0.1 — Known Limitations & Unresolved Ambiguities

## 1. Overview
This document outlines the known source ambiguities, engineering trade-offs, and architectural limitations associated with **PropGuardian SMC Strategy v0.1**.

---

## 2. Strategy Implementation Limitations & Rules

1. **Displacement Implementation**:
   - *Specification*: Qualitative displacement requirement without a defensible quantitative threshold.
   - *Implementation*: Documented as `"Structural displacement proxy: directional M5 breakout candle + qualifying FVG."`
   - *Behavior*: Enforces that M5 structural breakout candle must close beyond the M5 swing level AND be directionally matching (`Close > Open` for Buy, `Close < Open` for Sell) while producing a valid 3-candle Fair Value Gap (`Low(C3) > High(C1)` for Buy, `High(C3) < Low(C1)` for Sell).

2. **4H POI Detection & Interface**:
   - *Specification*: 4H timeframe activates setup via active Demand/Supply POI without inventing proprietary algorithms.
   - *Implementation*: Invented ±point zone offsets have been removed. An explicit POI provider interface (`Register4HPOI` / `GetActive4HPOI`) is established.
   - *Limitation*: If no verified 4H POI is explicitly provided by an external engine/provider, POI detection returns `false`. A missing POI results in `NO TRADE` rather than guessing a zone.

3. **Take Profit Target Calculation**:
   - *Specification*: Structural / liquidity-based TP target required.
   - *Implementation*: Setups target the next opposing confirmed M15 structural high (for Longs) or M15 structural low (for Shorts).
   - *Limitation*: No 3R, 2R, ATR, or fixed-pip fallbacks are used. If no opposing structural target is found, the setup is invalidated with an explicit reason (`NO TRADE`).

4. **Equal High / Equal Low Handling**:
   - *Specification*: Strict `<` and `>` comparisons without discretionary tie-breaking rules.
   - *Implementation*: Equal highs/lows do not qualify as confirmed fractal swings.

5. **Structural Stop Loss Spread Buffer**:
   - *Specification*: Structural SL placed beyond the swept extreme.
   - *Implementation*: Market spread + 2.0 points buffer added beyond the swept low/high extreme.

---

## 3. System & Operating Limitations

1. **In-Memory Setup Tracking**:
   - `SMCSetup` array state is maintained in RAM. Terminal/EA restarts re-initialize setup trackers to `SMC_IDLE`. Active pending orders and positions are tracked via `g_tracker` and MT5 order history.
2. **Economic News Calendar Filter**:
   - `IsNearNewsEvent()` in `safety_filters.mqh` remains an external calendar stub returning `false`. Third-party economic calendar integration is required for news event filtering.
3. **Multi-Symbol Pending Orders**:
   - Pending limit orders are submitted sequentially per symbol as setups reach `SMC_WAITING_FOR_FVG_RETRACE` and pass `CanOpenTrade()`.
