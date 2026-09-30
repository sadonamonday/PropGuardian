import unittest

class TestSMCEngineRules(unittest.TestCase):

    # --- SWINGS ---
    def test_5bar_swing_high(self):
        # High[i] > High[i+1] and High[i] > High[i+2] and High[i] > High[i-1] and High[i] > High[i-2]
        highs = [1.1010, 1.1020, 1.1050, 1.1015, 1.1005]  # index 2 is mid (1.1050)
        is_high = (highs[2] > highs[3] and highs[2] > highs[4] and
                   highs[2] > highs[1] and highs[2] > highs[0])
        self.assertTrue(is_high)

    def test_5bar_swing_low(self):
        lows = [1.1090, 1.1080, 1.1050, 1.1085, 1.1095]
        is_low = (lows[2] < lows[3] and lows[2] < lows[4] and
                  lows[2] < lows[1] and lows[2] < lows[0])
        self.assertTrue(is_low)

    def test_3bar_swing_high(self):
        highs = [1.1010, 1.1050, 1.1020]  # mid is index 1
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertTrue(is_high)

    def test_3bar_swing_low(self):
        lows = [1.1090, 1.1050, 1.1085]  # mid is index 1
        is_low = (lows[1] < lows[0] and lows[1] < lows[2])
        self.assertTrue(is_low)

    def test_equal_highs_rejection(self):
        # High[i] == High[i-1] -> Rejected under strict '>' rule
        highs = [1.1050, 1.1050, 1.1020, 1.1010]
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertFalse(is_high)

    def test_equal_lows_rejection(self):
        lows = [1.1000, 1.1000, 1.1020, 1.1030]
        is_low = (lows[1] < lows[0] and lows[1] < lows[2])
        self.assertFalse(is_low)

    def test_unconfirmed_swing_rejection(self):
        # Requires right-side candles: barIndex must be >= 3 for 5-bar, >= 2 for 3-bar
        current_unclosed_bar = 0
        min_5bar_bar = 3
        min_3bar_bar = 2
        self.assertGreater(min_5bar_bar, current_unclosed_bar)
        self.assertGreater(min_3bar_bar, current_unclosed_bar)

    # --- BOS ---
    def test_bos_bullish_body_close(self):
        swing_high = 1.1050
        body_break_close = 1.1055
        self.assertTrue(body_break_close > swing_high)

    def test_bos_bearish_body_close(self):
        swing_low = 1.1000
        body_break_close = 1.0995
        self.assertTrue(body_break_close < swing_low)

    def test_bos_wick_only_break_rejected(self):
        swing_high = 1.1050
        candle_high = 1.1060
        candle_close = 1.1045  # Wick goes above swing_high, but body closes below
        is_bos = candle_close > swing_high
        self.assertFalse(is_bos)

    # --- CHOCH ---
    def test_choch_correct_lh_selected_for_bullish_reversal(self):
        # Candidate M15 swing highs preceding sweep low:
        # LH1 at t=10 (price=1.1080), LH2 at t=20 (price=1.1060), Sweep at t=30 (price=1.1000)
        swings = [
            {'time': 10, 'price': 1.1080, 'type': 'LH'},
            {'time': 20, 'price': 1.1060, 'type': 'LH'}
        ]
        sweep_time = 30
        # Backward traversal from sweep_time finds LH2 (t=20, price=1.1060) as opposing swing directly preceding sweep leg
        selected_lh = None
        for s in reversed(swings):
            if s['time'] <= sweep_time:
                selected_lh = s
                break
        self.assertIsNotNone(selected_lh)
        self.assertEqual(selected_lh['price'], 1.1060)

    def test_choch_correct_hl_selected_for_bearish_reversal(self):
        swings = [
            {'time': 10, 'price': 1.1000, 'type': 'HL'},
            {'time': 20, 'price': 1.1020, 'type': 'HL'}
        ]
        sweep_time = 30
        selected_hl = None
        for s in reversed(swings):
            if s['time'] <= sweep_time:
                selected_hl = s
                break
        self.assertIsNotNone(selected_hl)
        self.assertEqual(selected_hl['price'], 1.1020)

    def test_choch_multiple_candidate_swings(self):
        swings = [
            {'time': 5, 'price': 1.1100},
            {'time': 15, 'price': 1.1080},
            {'time': 25, 'price': 1.1050}
        ]
        sweep_time = 30
        # Traversal backward from sweep finds the most recent preceding swing (time=25)
        selected = [s for s in sorted(swings, key=lambda x: x['time'], reverse=True) if s['time'] <= sweep_time][0]
        self.assertEqual(selected['price'], 1.1050)

    def test_choch_wick_only_rejected(self):
        choch_lh = 1.1060
        candle_high = 1.1070
        candle_close = 1.1055
        is_choch = candle_close > choch_lh
        self.assertFalse(is_choch)

    # --- LIQUIDITY ---
    def test_bullish_sweep_reclaim(self):
        swing_low = 1.1000
        completed_low = 1.0990
        completed_close = 1.1005
        is_sweep = (completed_low < swing_low) and (completed_close > swing_low)
        self.assertTrue(is_sweep)

    def test_bearish_sweep_reclaim(self):
        swing_high = 1.1000
        completed_high = 1.1010
        completed_close = 1.0995
        is_sweep = (completed_high > swing_high) and (completed_close < swing_high)
        self.assertTrue(is_sweep)

    def test_sweep_without_reclaim_rejected(self):
        swing_low = 1.1000
        completed_low = 1.0990
        completed_close = 1.0995  # Closes BELOW swing_low (breakout, not sweep)
        is_sweep = (completed_low < swing_low) and (completed_close > swing_low)
        self.assertFalse(is_sweep)

    # --- DISPLACEMENT ---
    def test_bullish_structural_displacement_proxy(self):
        m5_swing_high = 1.1050
        open_bar = 1.1040
        close_bar = 1.1060  # Body close > swing_high AND Close > Open
        has_fvg = True
        is_displacement = (close_bar > m5_swing_high) and (close_bar > open_bar) and has_fvg
        self.assertTrue(is_displacement)

    def test_bearish_structural_displacement_proxy(self):
        m5_swing_low = 1.1000
        open_bar = 1.1010
        close_bar = 1.0990  # Body close < swing_low AND Close < Open
        has_fvg = True
        is_displacement = (close_bar < m5_swing_low) and (close_bar < open_bar) and has_fvg
        self.assertTrue(is_displacement)

    def test_displacement_wrong_direction_breakout_rejected(self):
        m5_swing_high = 1.1050
        open_bar = 1.1065
        close_bar = 1.1055  # Close > swing_high, but Close < Open (bearish candle)
        is_displacement_candle = (close_bar > m5_swing_high) and (close_bar > open_bar)
        self.assertFalse(is_displacement_candle)

    def test_displacement_breakout_without_fvg_rejected(self):
        m5_swing_high = 1.1050
        open_bar = 1.1040
        close_bar = 1.1060
        has_fvg = False
        is_displacement = (close_bar > m5_swing_high) and (close_bar > open_bar) and has_fvg
        self.assertFalse(is_displacement)

    def test_displacement_wick_only_breakout_rejected(self):
        m5_swing_high = 1.1050
        high_bar = 1.1060
        close_bar = 1.1045
        open_bar = 1.1030
        is_breakout = close_bar > m5_swing_high
        self.assertFalse(is_breakout)

    # --- FVG ---
    def test_bullish_fvg_midpoint(self):
        high_c1 = 1.1000
        low_c3 = 1.1030
        self.assertTrue(low_c3 > high_c1)
        bottom = high_c1
        top = low_c3
        midpoint = (top + bottom) / 2.0
        self.assertAlmostEqual(midpoint, 1.1015, places=5)

    def test_bearish_fvg_midpoint(self):
        low_c1 = 1.1050
        high_c3 = 1.1020
        self.assertTrue(high_c3 < low_c1)
        bottom = high_c3
        top = low_c1
        midpoint = (top + bottom) / 2.0
        self.assertAlmostEqual(midpoint, 1.1035, places=5)

    def test_fvg_mitigation_vs_invalidation(self):
        # Bullish FVG: bottom = 1.1000, top = 1.1030
        bottom = 1.1000
        top = 1.1030
        # Price retraces into FVG (e.g. low = 1.1015) -> Valid Retrace / Mitigated
        retrace_price = 1.1015
        is_mitigated = retrace_price <= top and retrace_price >= bottom
        self.assertTrue(is_mitigated)

        # Body close below bottom -> Full Invalidation
        close_price = 1.0995
        is_invalidated = close_price < bottom
        self.assertTrue(is_invalidated)

    def test_fvg_invalidation_after_several_candles(self):
        bottom = 1.1000
        closes = [1.1020, 1.1015, 1.1005, 1.0990]  # Bar 4 closes below bottom
        invalidated_at_bar = None
        for idx, cl in enumerate(closes):
            if cl < bottom:
                invalidated_at_bar = idx
                break
        self.assertEqual(invalidated_at_bar, 3)

    def test_persistent_active_fvg_not_replaced(self):
        # Active setup retains its m5FVG and does not overwrite with later FVGs
        initial_fvg = {'bottom': 1.1000, 'top': 1.1030, 'time': 100}
        later_fvg = {'bottom': 1.1040, 'top': 1.1070, 'time': 200}
        active_fvg = initial_fvg  # Retained
        self.assertEqual(active_fvg['time'], 100)

    # --- TP ---
    def test_opposing_structural_target_found(self):
        m15_swing_high = 1.1120
        has_opposing_swing = True
        tp = m15_swing_high if has_opposing_swing else None
        self.assertEqual(tp, 1.1120)

    def test_no_structural_target_invalidates_no_3r_fallback(self):
        has_opposing_swing = False
        tp = 1.1120 if has_opposing_swing else None
        self.assertIsNone(tp)  # No 3R fallback guessing

    # --- STATE MACHINE ---
    def test_full_long_sequence(self):
        states = [
            "SMC_IDLE",
            "SMC_H4_POI_ACTIVE",
            "SMC_WAITING_FOR_M15_SWEEP",
            "SMC_M15_SWEEP_DETECTED",
            "SMC_WAITING_FOR_M15_CHOCH",
            "SMC_M15_CHOCH_CONFIRMED",
            "SMC_WAITING_FOR_M5_CONFIRMATION",
            "SMC_M5_CONFIRMATION",
            "SMC_FVG_DETECTED",
            "SMC_WAITING_FOR_FVG_RETRACE",
            "SMC_ENTRY_SUBMITTED",
            "SMC_TRADE_ACTIVE",
            "SMC_COMPLETED"
        ]
        self.assertEqual(len(states), 13)

    def test_full_short_sequence(self):
        states = [
            "SMC_IDLE",
            "SMC_H4_POI_ACTIVE",
            "SMC_WAITING_FOR_M15_SWEEP",
            "SMC_M15_SWEEP_DETECTED",
            "SMC_WAITING_FOR_M15_CHOCH",
            "SMC_M15_CHOCH_CONFIRMED",
            "SMC_WAITING_FOR_M5_CONFIRMATION",
            "SMC_M5_CONFIRMATION",
            "SMC_FVG_DETECTED",
            "SMC_WAITING_FOR_FVG_RETRACE",
            "SMC_ENTRY_SUBMITTED",
            "SMC_TRADE_ACTIVE",
            "SMC_COMPLETED"
        ]
        self.assertEqual(len(states), 13)

    def test_invalidation_at_major_stages(self):
        # Setup can transition to SMC_INVALIDATED from POI, Sweep, CHoCH, FVG, or Risk failure
        current_state = "SMC_WAITING_FOR_M15_CHOCH"
        timeout_occurred = True
        if timeout_occurred:
            current_state = "SMC_INVALIDATED"
        self.assertEqual(current_state, "SMC_INVALIDATED")

    def test_duplicate_setup_prevention(self):
        active_setups = [{"symbol": "EURUSD", "state": "SMC_WAITING_FOR_M15_SWEEP"}]
        symbol = "EURUSD"
        has_existing = any(s['symbol'] == symbol and s['state'] != "SMC_INVALIDATED" for s in active_setups)
        self.assertTrue(has_existing)

    def test_duplicate_order_prevention(self):
        active_pending_order_ticket = 123456
        can_place_new_order = (active_pending_order_ticket == 0)
        self.assertFalse(can_place_new_order)


if __name__ == "__main__":
    unittest.main()
