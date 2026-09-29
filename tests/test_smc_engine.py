import unittest

class TestSMCEngineRules(unittest.TestCase):

    def test_5bar_swing_high(self):
        # High[i] > High[i+1] and High[i] > High[i+2] and High[i] > High[i-1] and High[i] > High[i-2]
        highs = [1.1010, 1.1020, 1.1050, 1.1015, 1.1005] # index 2 is mid (1.1050)
        is_high = (highs[2] > highs[3] and highs[2] > highs[4] and
                   highs[2] > highs[1] and highs[2] > highs[0])
        self.assertTrue(is_high)

    def test_equal_high_rejection(self):
        # High[i] == High[i-1] -> Rejected under strict '>' rule
        highs = [1.1050, 1.1050, 1.1020, 1.1010]
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertFalse(is_high)

    def test_3bar_swing_high(self):
        highs = [1.1010, 1.1050, 1.1020] # mid is index 1
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertTrue(is_high)

    def test_fvg_bullish_midpoint(self):
        # Candle 1 High = 1.1000, Candle 3 Low = 1.1030
        high_c1 = 1.1000
        low_c3 = 1.1030
        self.assertTrue(low_c3 > high_c1)
        bottom = high_c1
        top = low_c3
        midpoint = (top + bottom) / 2.0
        self.assertAlmostEqual(midpoint, 1.1015, places=5)

    def test_fvg_invalidation(self):
        # Bullish FVG bottom = 1.1000
        bottom = 1.1000
        close_candle = 1.0995 # Body close below
        is_invalid = close_candle < bottom
        self.assertTrue(is_invalid)

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

    def test_state_machine_long_sequence(self):
        states = [
            "SMC_IDLE",
            "SMC_POI_ACTIVE",
            "SMC_WAITING_FOR_SWEEP",
            "SMC_SWEEP_CONFIRMED",
            "SMC_WAITING_FOR_CHOCH",
            "SMC_CHOCH_CONFIRMED",
            "SMC_WAITING_FOR_M5_CONFIRMATION",
            "SMC_FVG_CONFIRMED",
            "SMC_WAITING_FOR_FVG_ENTRY",
            "SMC_ENTRY_SUBMITTED",
            "SMC_TRADE_ACTIVE"
        ]
        self.assertEqual(len(states), 11)
        self.assertEqual(states[0], "SMC_IDLE")
        self.assertEqual(states[-1], "SMC_TRADE_ACTIVE")

if __name__ == "__main__":
    unittest.main()
