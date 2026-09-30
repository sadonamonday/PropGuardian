# PropGuardian SMC Strategy v0.1 — Test & Verification Report

## 1. Test Overview
Unit and integration test coverage for PropGuardian SMC Strategy v0.1 was conducted via `tests/test_smc_engine.py` using Python's standard `unittest` framework.

The test suite verifies deterministic mathematical logic, swing definitions, BOS/CHoCH body closes, CHoCH lower-high / higher-low selection, M15 liquidity sweeps, M5 displacement proxy, FVG 50% midpoint calculations, FVG lifecycle and invalidation, structural TP targeting without fallbacks, state machine transitions, and duplicate order prevention.

---

## 2. Test Execution Results

```
Ran 34 tests in 0.001s

OK
```

### Verified Test Cases Table

| Category | Test Function | Result | Description |
| :--- | :--- | :--- | :--- |
| **Swings** | `test_5bar_swing_high` | PASS | Validates strict 5-bar fractal high calculation on 4H/M15 timeframes. |
| **Swings** | `test_5bar_swing_low` | PASS | Validates strict 5-bar fractal low calculation on 4H/M15 timeframes. |
| **Swings** | `test_3bar_swing_high` | PASS | Validates strict 3-bar fractal high calculation on M5 timeframe. |
| **Swings** | `test_3bar_swing_low` | PASS | Validates strict 3-bar fractal low calculation on M5 timeframe. |
| **Swings** | `test_equal_highs_rejection` | PASS | Confirms equal highs are rejected under strict `>` rule. |
| **Swings** | `test_equal_lows_rejection` | PASS | Confirms equal lows are rejected under strict `<` rule. |
| **Swings** | `test_unconfirmed_swing_rejection` | PASS | Verifies unclosed bar cannot confirm swing fractal. |
| **BOS** | `test_bos_bullish_body_close` | PASS | Confirms bullish BOS requires completed candle BODY close above swing high. |
| **BOS** | `test_bos_bearish_body_close` | PASS | Confirms bearish BOS requires completed candle BODY close below swing low. |
| **BOS** | `test_bos_wick_only_break_rejected` | PASS | Rejects wick-only breaks for BOS. |
| **CHoCH** | `test_choch_correct_lh_selected_for_bullish_reversal` | PASS | Confirms correct Lower High directly preceding sweep low is selected for Bullish CHoCH. |
| **CHoCH** | `test_choch_correct_hl_selected_for_bearish_reversal` | PASS | Confirms correct Higher Low directly preceding sweep high is selected for Bearish CHoCH. |
| **CHoCH** | `test_choch_multiple_candidate_swings` | PASS | Verifies backward traversal selects opposing swing preceding sweep leg among multiple candidates. |
| **CHoCH** | `test_choch_wick_only_rejected` | PASS | Rejects wick-only breaks for CHoCH. |
| **Liquidity** | `test_bullish_sweep_reclaim` | PASS | Validates bullish liquidity sweep & close reclaim logic. |
| **Liquidity** | `test_bearish_sweep_reclaim` | PASS | Validates bearish liquidity sweep & close reclaim logic. |
| **Liquidity** | `test_sweep_without_reclaim_rejected` | PASS | Rejects sweep without close reclaim. |
| **Displacement**| `test_bullish_structural_displacement_proxy` | PASS | Validates bullish displacement proxy (directional M5 breakout candle + FVG). |
| **Displacement**| `test_bearish_structural_displacement_proxy` | PASS | Validates bearish displacement proxy (directional M5 breakout candle + FVG). |
| **Displacement**| `test_displacement_wrong_direction_breakout_rejected` | PASS | Rejects opposite-direction candle on breakout. |
| **Displacement**| `test_displacement_breakout_without_fvg_rejected` | PASS | Rejects breakout without qualifying FVG. |
| **Displacement**| `test_displacement_wick_only_breakout_rejected` | PASS | Rejects wick-only breakout. |
| **FVG** | `test_bullish_fvg_midpoint` | PASS | Confirms 3-candle bullish FVG detection and 50% midpoint calculation. |
| **FVG** | `test_bearish_fvg_midpoint` | PASS | Confirms 3-candle bearish FVG detection and 50% midpoint calculation. |
| **FVG** | `test_fvg_mitigation_vs_invalidation` | PASS | Verifies retracement mitigation vs body close through C1 boundary invalidation. |
| **FVG** | `test_fvg_invalidation_after_several_candles` | PASS | Verifies invalidation triggering after several candles. |
| **FVG** | `test_persistent_active_fvg_not_replaced` | PASS | Confirms active setup retains original FVG without replacement. |
| **TP** | `test_opposing_structural_target_found` | PASS | Validates opposing structural TP target finding. |
| **TP** | `test_no_structural_target_invalidates_no_3r_fallback` | PASS | Confirms setup invalidation when no structural TP exists (no 3R fallback guessing). |
| **State Machine**| `test_full_long_sequence` | PASS | Verifies complete 13-state long deterministic setup sequence. |
| **State Machine**| `test_full_short_sequence` | PASS | Verifies complete 13-state short deterministic setup sequence. |
| **State Machine**| `test_invalidation_at_major_stages` | PASS | Verifies state machine invalidation handling across major stages. |
| **State Machine**| `test_duplicate_setup_prevention` | PASS | Prevents duplicate setup creation on same symbol. |
| **State Machine**| `test_duplicate_order_prevention` | PASS | Blocks duplicate order placement when an order ticket is active. |

---

## 3. Verified Architecture & Risk Preservation
- **No Lookahead Bias**: Swings, BOS, CHoCH, and FVGs evaluate completed candles (`barIndex >= 1`), preventing repainting or unclosed bar triggers.
- **Risk Gate Preservation**: Pre-trade validation in `risk_manager.mqh` and `safety_filters.mqh` remains fully operational.
- **Order Mechanics**: BUY LIMIT / SELL LIMIT orders placed at 50% FVG midpoint with structural SL and opposing structural TP.
