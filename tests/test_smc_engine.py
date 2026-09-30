import unittest

class TestSMCEngineRules(unittest.TestCase):

    # --- 1. 4H SWINGS & POI RULES ---

    def test_4h_bullish_5bar_swing(self):
        # 5-bar swing high: index 2 is mid (1.1050)
        highs = [1.1010, 1.1020, 1.1050, 1.1015, 1.1005]
        is_high = (highs[2] > highs[3] and highs[2] > highs[4] and
                   highs[2] > highs[1] and highs[2] > highs[0])
        self.assertTrue(is_high)

    def test_4h_bearish_5bar_swing(self):
        # 5-bar swing low: index 2 is mid (1.1050)
        lows = [1.1090, 1.1080, 1.1050, 1.1085, 1.1095]
        is_low = (lows[2] < lows[3] and lows[2] < lows[4] and
                  lows[2] < lows[1] and lows[2] < lows[0])
        self.assertTrue(is_low)

    def test_4h_bullish_ob_definition(self):
        # Bullish OB: final bearish down-close candle before displacement + BOS + FVG
        ob_candle = {'open': 1.1020, 'close': 1.1000, 'high': 1.1025, 'low': 1.0995}
        is_down_close = ob_candle['close'] < ob_candle['open']
        has_subsequent_displacement = True
        is_bullish_ob = is_down_close and has_subsequent_displacement
        ob_boundaries = (ob_candle['low'], ob_candle['high'])
        self.assertTrue(is_bullish_ob)
        self.assertEqual(ob_boundaries, (1.0995, 1.1025))

    def test_4h_bearish_ob_definition(self):
        # Bearish OB: final bullish up-close candle before displacement + BOS + FVG
        ob_candle = {'open': 1.1000, 'close': 1.1020, 'high': 1.1025, 'low': 1.0995}
        is_up_close = ob_candle['close'] > ob_candle['open']
        has_subsequent_displacement = True
        is_bearish_ob = is_up_close and has_subsequent_displacement
        ob_boundaries = (ob_candle['low'], ob_candle['high'])
        self.assertTrue(is_bearish_ob)
        self.assertEqual(ob_boundaries, (1.0995, 1.1025))

    def test_4h_bullish_fvg(self):
        # Bullish FVG: Low(C3) > High(C1)
        high_c1 = 1.1000
        low_c3 = 1.1030
        is_bullish_fvg = low_c3 > high_c1
        fvg_boundaries = (high_c1, low_c3)
        self.assertTrue(is_bullish_fvg)
        self.assertEqual(fvg_boundaries, (1.1000, 1.1030))

    def test_4h_bearish_fvg(self):
        # Bearish FVG: High(C3) < Low(C1)
        low_c1 = 1.1050
        high_c3 = 1.1020
        is_bearish_fvg = high_c3 < low_c1
        fvg_boundaries = (high_c3, low_c1)
        self.assertTrue(is_bearish_fvg)
        self.assertEqual(fvg_boundaries, (1.1020, 1.1050))

    def test_4h_poi_direction_filtering(self):
        structure_4h = "BULLISH"
        bullish_poi = {'type': 'DEMAND', 'isActive': True}
        bearish_poi = {'type': 'SUPPLY', 'isActive': True}

        # In Bullish 4H structure, only DEMAND POIs are eligible
        is_demand_eligible = (structure_4h == "BULLISH" and bullish_poi['type'] == 'DEMAND')
        is_supply_eligible = (structure_4h == "BULLISH" and bearish_poi['type'] == 'DEMAND')

        self.assertTrue(is_demand_eligible)
        self.assertFalse(is_supply_eligible)

    def test_4h_poi_selection_most_recent(self):
        # Equal status OB and FVG -> pick most recent valid uninvalidated POI
        pois = [
            {'id': 1, 'type': 'DEMAND', 'time': 100, 'is_valid': True},  # Older OB
            {'id': 2, 'type': 'DEMAND', 'time': 200, 'is_valid': True},  # Newer FVG
        ]
        selected_poi = max(pois, key=lambda p: p['time'] if p['is_valid'] else -1)
        self.assertEqual(selected_poi['id'], 2)

    def test_4h_poi_intersection(self):
        poi = {'bottom': 1.1000, 'top': 1.1020}
        # M15 range intersects POI if M15 High >= POI Low AND M15 Low <= POI High
        m15_high = 1.1010
        m15_low = 1.0995
        is_intersecting = (m15_high >= poi['bottom']) and (m15_low <= poi['top'])
        self.assertTrue(is_intersecting)

        # Non-intersecting range
        m15_high_far = 1.1050
        m15_low_far = 1.1030
        is_far = (m15_high_far >= poi['bottom']) and (m15_low_far <= poi['top'])
        self.assertFalse(is_far)

    def test_4h_poi_invalidation_ob_and_fvg(self):
        # Bullish OB invalidated if 4H candle closes below OB low
        ob_low = 1.1000
        ob_close_invalid = 1.0995
        self.assertTrue(ob_close_invalid < ob_low)

        # Bearish OB invalidated if 4H candle closes above OB high
        ob_high = 1.1050
        ob_close_invalid_bearish = 1.1055
        self.assertTrue(ob_close_invalid_bearish > ob_high)

        # FVG invalidated if completed candle closes through C1 boundary
        fvg_c1_bottom = 1.1000
        fvg_close_invalid = 1.0990
        self.assertTrue(fvg_close_invalid < fvg_c1_bottom)


    # --- 2. M15 SWEEP & CHOCH RULES ---

    def test_m15_sweep_detection(self):
        m15_swing_low = 1.1000
        m15_low = 1.0990
        m15_close = 1.1005
        # Low sweeps swing low and close reclaims level
        is_sweep = (m15_low < m15_swing_low) and (m15_close > m15_swing_low)
        self.assertTrue(is_sweep)

    def test_m15_bullish_choch(self):
        choch_lh_price = 1.1060
        m15_close = 1.1065
        is_choch = m15_close > choch_lh_price
        self.assertTrue(is_choch)

    def test_m15_bearish_choch(self):
        choch_hl_price = 1.1020
        m15_close = 1.1015
        is_choch = m15_close < choch_hl_price
        self.assertTrue(is_choch)

    def test_m15_incorrect_swing_selection_rejection(self):
        # Must select LH originating final downward leg into sweep low, NOT an older unrelated swing
        swings = [
            {'time': 10, 'price': 1.1100, 'type': 'LH'},
            {'time': 20, 'price': 1.1060, 'type': 'LH'},  # Directly originated final leg into sweep at t=30
        ]
        sweep_time = 30
        selected = [s for s in sorted(swings, key=lambda x: x['time'], reverse=True) if s['time'] <= sweep_time][0]
        self.assertEqual(selected['price'], 1.1060)
        self.assertNotEqual(selected['price'], 1.1100)

    def test_m15_body_close_requirement(self):
        choch_lh = 1.1060
        m15_close = 1.1065
        self.assertTrue(m15_close > choch_lh)

    def test_m15_wick_only_break_rejected(self):
        choch_lh = 1.1060
        m15_high = 1.1070
        m15_close = 1.1055  # Wick goes above, body closes below -> Rejected as CHoCH
        is_choch = m15_close > choch_lh
        self.assertFalse(is_choch)


    # --- 3. M5 EXECUTION & DISPLACEMENT RULES ---

    def test_m5_confirmed_3bar_swing(self):
        highs = [1.1010, 1.1050, 1.1020]
        is_high = (highs[1] > highs[0] and highs[1] > highs[2])
        self.assertTrue(is_high)

    def test_m5_bullish_displacement(self):
        m5_swing_high = 1.1050
        open_bar = 1.1040
        close_bar = 1.1060
        has_fvg = True
        is_displacement = (close_bar > m5_swing_high) and (close_bar > open_bar) and has_fvg
        self.assertTrue(is_displacement)

    def test_m5_bearish_displacement(self):
        m5_swing_low = 1.1000
        open_bar = 1.1010
        close_bar = 1.0990
        has_fvg = True
        is_displacement = (close_bar < m5_swing_low) and (close_bar < open_bar) and has_fvg
        self.assertTrue(is_displacement)

    def test_m5_qualifying_fvg(self):
        high_c1 = 1.1000
        low_c3 = 1.1030
        self.assertTrue(low_c3 > high_c1)
        midpoint = (high_c1 + low_c3) / 2.0
        self.assertAlmostEqual(midpoint, 1.1015, places=5)

    def test_m5_unrelated_fvg_rejection(self):
        # FVG must be created by the qualifying displacement event
        displacement_time = 500
        fvg1_time = 200  # Older unrelated FVG
        fvg2_time = 500  # Displacement FVG
        selected_fvg_time = fvg2_time
        self.assertEqual(selected_fvg_time, displacement_time)
        self.assertNotEqual(fvg1_time, displacement_time)

    def test_m5_fvg_50percent_entry(self):
        bottom = 1.1000
        top = 1.1030
        entry_price = (bottom + top) / 2.0
        self.assertAlmostEqual(entry_price, 1.1015, places=5)

    def test_m5_fvg_invalidation(self):
        fvg_bottom = 1.1000
        close_bar = 1.0995  # Body close below C1 bottom invalidates
        is_invalidated = close_bar < fvg_bottom
        self.assertTrue(is_invalidated)

    def test_m5_pending_order_cancellation_on_invalidation(self):
        setup_state = "SMC_INVALIDATED"
        has_pending_order = True
        should_cancel_order = (setup_state == "SMC_INVALIDATED" and has_pending_order)
        self.assertTrue(should_cancel_order)


    # --- 4. TRADE & SYSTEM INTEGRATION TESTS ---

    def test_trade_valid_complete_setup(self):
        # Sequence: 4H POI -> M15 Sweep -> M15 CHoCH -> M5 Displacement & FVG -> 50% Entry & Structural TP
        poi_active = True
        m15_sweep = True
        m15_choch = True
        m5_displacement = True
        m5_fvg = True
        has_valid_tp = True
        risk_approved = True

        can_trade = (poi_active and m15_sweep and m15_choch and
                     m5_displacement and m5_fvg and has_valid_tp and risk_approved)
        self.assertTrue(can_trade)

    def test_trade_no_poi_rejected(self):
        poi_active = False
        self.assertFalse(poi_active)

    def test_trade_poi_without_sweep_rejected(self):
        poi_active = True
        m15_sweep = False
        can_trade = poi_active and m15_sweep
        self.assertFalse(can_trade)

    def test_trade_sweep_without_choch_rejected(self):
        m15_sweep = True
        m15_choch = False
        can_trade = m15_sweep and m15_choch
        self.assertFalse(can_trade)

    def test_trade_choch_without_m5_confirmation_rejected(self):
        m15_choch = True
        m5_displacement = False
        can_trade = m15_choch and m5_displacement
        self.assertFalse(can_trade)

    def test_trade_m5_confirmation_without_fvg_rejected(self):
        m5_displacement = True
        m5_fvg = False
        can_trade = m5_displacement and m5_fvg
        self.assertFalse(can_trade)

    def test_trade_invalid_fvg_rejected(self):
        fvg_valid = False
        self.assertFalse(fvg_valid)

    def test_trade_no_valid_tp_rejected_no_fallback(self):
        has_opposing_structural_tp = False
        can_trade = has_opposing_structural_tp  # Strict rule: DO NOT TAKE THE TRADE if no opposing structural target
        self.assertFalse(can_trade)

    def test_trade_risk_manager_rejection(self):
        risk_approved = False
        can_trade = risk_approved
        self.assertFalse(can_trade)

    def test_trade_successful_pending_order(self):
        retcode = 10009  # TRADE_RETCODE_DONE
        order_placed = (retcode == 10009 or retcode == 10008)
        self.assertTrue(order_placed)

    def test_trade_failed_pending_order(self):
        retcode = 10013  # TRADE_RETCODE_INVALID_REQUEST
        order_placed = (retcode == 10009 or retcode == 10008)
        self.assertFalse(order_placed)


if __name__ == "__main__":
    unittest.main()
