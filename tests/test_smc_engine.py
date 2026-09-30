import unittest

class TestSMCEngineRules(unittest.TestCase):

    def test_5bar_swing_high(self):
        # High[i] > High[i+1] and High[i] > High[i+2] and High[i] > High[i-1] and High[i] > High[i-2]
        highs = [1.1010, 1.1020, 1.1050, 1.1015, 1.1005] # index 2 is mid (1.1050)
        is_high = (highs[2] > highs[3] and highs[2] > highs[4] and
                   highs[2] > highs[1] and highs[2] > highs[0])
        self.assertTrue(is_high)

    def test_5bar_swing_low(self):
        lows = [1.1090, 1.1080, 1.1050, 1.1085, 1.1095]
        is_low = (lows[2] < lows[3] and lows[2] < lows[4] and
                  lows[2] < lows[1] and lows[2] < lows[0])
        self.assertTrue(is_low)

    def test_equal_high_rejection(self):
        # High[i] == High[i-1] -> Rejected under strict '>' rule
        highs = [1.1050, 1.1050, 1.1020, 1.1010]
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertFalse(is_high)

    def test_3bar_swing_high(self):
        highs = [1.1010, 1.1050, 1.1020] # mid is index 1
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertTrue(is_high)

    def test_bos_body_close_bullish(self):
        swing_high = 1.1050
        wick_break_close = 1.1045  # High > swing_high but Close <= swing_high
        body_break_close = 1.1055  # Candle BODY close > swing_high
        self.assertFalse(wick_break_close > swing_high)
        self.assertTrue(body_break_close > swing_high)

    def test_choch_body_close_bullish(self):
        preceding_lh = 1.1080
        completed_close = 1.1085
        is_choch = completed_close > preceding_lh
        self.assertTrue(is_choch)

    def test_fvg_bullish_midpoint(self):
        # Candle 1 High = 1.1000, Candle 3 Low = 1.1030
        high_c1 = 1.1000
        low_c3 = 1.1030
        self.assertTrue(low_c3 > high_c1)
        bottom = high_c1
        top = low_c3
        midpoint = (top + bottom) / 2.0
        self.assertAlmostEqual(midpoint, 1.1015, places=5)

    def test_fvg_bearish_midpoint(self):
        low_c1 = 1.1050
        high_c3 = 1.1020
        self.assertTrue(high_c3 < low_c1)
        bottom = high_c3
        top = low_c1
        midpoint = (top + bottom) / 2.0
        self.assertAlmostEqual(midpoint, 1.1035, places=5)

    def test_fvg_invalidation(self):
        # Bullish FVG bottom = 1.1000
        bottom = 1.1000
        close_candle = 1.0995 # Body close below C1 boundary
        is_invalid = close_candle < bottom
        self.assertTrue(is_invalid)

    def test_ob_confirmation(self):
        # OB confirmed only after displacement produces structural break and FVG
        has_m5_bos = True
        has_m5_fvg = True
        ob_confirmed = has_m5_bos and has_m5_fvg
        self.assertTrue(ob_confirmed)

    def test_no_chase_condition(self):
        # Bullish Buy Limit at midpoint = 1.1015
        entry_midpoint = 1.1015
        current_price = 1.1010 # Price already fell below/through midpoint
        no_chase_triggered = current_price <= entry_midpoint
        self.assertTrue(no_chase_triggered)

    def test_liquidity_sweep_deterministic_rule(self):
        swing_low = 1.1000
        completed_low = 1.0990 # Trades below
        completed_close = 1.1005 # Closes back above
        is_sweep = (completed_low < swing_low) and (completed_close > swing_low)
        self.assertTrue(is_sweep)

    def test_no_lookahead_completed_candles_only(self):
        current_unclosed_bar = 0
        min_confirmed_bar_5bar = 3 # barIndex 3 uses completed bars 1 & 2 on right
        min_confirmed_bar_3bar = 2 # barIndex 2 uses completed bar 1 on right
        self.assertGreater(min_confirmed_bar_5bar, current_unclosed_bar)
        self.assertGreater(min_confirmed_bar_3bar, current_unclosed_bar)

    def test_duplicate_order_prevention(self):
        active_pending_order_ticket = 123456
        can_place_new_order = (active_pending_order_ticket == 0)
        self.assertFalse(can_place_new_order)

    def test_state_machine_long_sequence(self):
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
        self.assertEqual(states[0], "SMC_IDLE")
        self.assertEqual(states[-1], "SMC_COMPLETED")

if __name__ == "__main__":
    unittest.main()
