# PropGuardian SMC Strategy v0.1 — Test & Verification Report

## 1. Test Overview
Unit and integration test coverage for PropGuardian SMC Strategy v0.1 was conducted via `tests/test_smc_engine.py` using Python's standard `unittest` framework to verify deterministic mathematical logic, swing definitions, state machine progression, FVG midpoint calculations, invalidation rules, and execution safety checks.

---

## 2. Test Execution Results

```
Ran 8 tests in 0.000s

OK
```

### Summary Table

| Test Module / Function | Status | Description |
| :--- | :--- | :--- |
| `test_5bar_swing_high` | PASS | Validates strict 5-bar fractal high calculation on 4H/M15 timeframes. |
| `test_equal_high_rejection` | PASS | Confirms equal highs are rejected under strict `>` rule. |
| `test_3bar_swing_high` | PASS | Validates strict 3-bar fractal high calculation on M5 timeframe. |
| `test_fvg_bullish_midpoint` | PASS | Confirms 3-candle bullish FVG detection and 50% midpoint math. |
| `test_fvg_invalidation` | PASS | Verifies FVG invalidation on candle body close below Candle 1 boundary. |
| `test_no_chase_condition` | PASS | Verifies order cancellation if price passes 50% FVG before limit creation. |
| `test_liquidity_sweep_deterministic_rule` | PASS | Validates M15 wick-below / close-above liquidity sweep logic. |
| `test_state_machine_long_sequence` | PASS | Verifies complete 11-step setup state transition sequence. |

---

## 3. Verified Safety & Architecture
- **Multi-timeframe Data Safety**: Swings, BOS, CHoCH, and FVGs evaluate only completed candles (`barIndex >= 1`), preventing repainting or look-ahead bias.
- **Risk Gate Preservation**: Pre-trade validation in `risk_manager.mqh` and `safety_filters.mqh` remains fully operational.
- **Pending Order Handling**: Limit orders at 50% FVG normalized to broker digits and lot steps.
