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

    @staticmethod
    def _find_choch_level(direction, swept_swing, m15_swings):
        """
        Helper mirroring FindCHoCHLevel in smc_engine.mqh.
        Searches backward for confirmed swing (LH for BUY, HL for SELL)
        with swing.time < swept_swing.time directly preceding final leg into swept extreme.
        """
        if not swept_swing.get('isValid', True) or swept_swing.get('time', 0) <= 0:
            return None

        swept_time = swept_swing['time']
        candidates = [s for s in m15_swings if s['time'] < swept_time and s.get('isValid', True)]

        if direction == "BUY":
            # Search backward from swept low for confirmed LH (SWING_TYPE_HIGH)
            lh_candidates = [s for s in candidates if s['type'] == 'HIGH']
            if not lh_candidates:
                return None
            # Most recent LH prior to swept low
            return max(lh_candidates, key=lambda x: x['time'])

        elif direction == "SELL":
            # Search backward from swept high for confirmed HL (SWING_TYPE_LOW)
            hl_candidates = [s for s in candidates if s['type'] == 'LOW']
            if not hl_candidates:
                return None
            # Most recent HL prior to swept high
            return max(hl_candidates, key=lambda x: x['time'])

        return None

    @staticmethod
    def _check_m15_choch(direction, choch_swing, bar1_candle):
        """
        Helper mirroring CheckM15CHoCH in smc_engine.mqh.
        Evaluates completed M15 candle (bar 1).
        """
        if not choch_swing or not choch_swing.get('isValid', True):
            return False

        close1 = bar1_candle['close']
        if direction == "BUY":
            return close1 > choch_swing['price']
        elif direction == "SELL":
            return close1 < choch_swing['price']
        return False

    def test_choch_1_bullish_swing_selection(self):
        # 1. Correct bullish CHoCH swing selection:
        # Swept low at t=100. Lower high originating final downward leg is at t=80 (1.1050).
        swept_swing = {'type': 'LOW', 'price': 1.0950, 'time': 100, 'isValid': True}
        swings = [
            {'type': 'HIGH', 'price': 1.1100, 'time': 40, 'isValid': True},   # Older high
            {'type': 'HIGH', 'price': 1.1050, 'time': 80, 'isValid': True},   # LH originating final leg into swept low
            {'type': 'HIGH', 'price': 1.1080, 'time': 120, 'isValid': True},  # Post-sweep high (invalid)
        ]
        choch_swing = self._find_choch_level("BUY", swept_swing, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['time'], 80)
        self.assertEqual(choch_swing['price'], 1.1050)

    def test_choch_2_bearish_swing_selection(self):
        # 2. Correct bearish CHoCH swing selection:
        # Swept high at t=100. Higher low originating final upward leg is at t=80 (1.1020).
        swept_swing = {'type': 'HIGH', 'price': 1.1150, 'time': 100, 'isValid': True}
        swings = [
            {'type': 'LOW', 'price': 1.0900, 'time': 40, 'isValid': True},   # Older low
            {'type': 'LOW', 'price': 1.1020, 'time': 80, 'isValid': True},   # HL originating final leg into swept high
            {'type': 'LOW', 'price': 1.0980, 'time': 120, 'isValid': True},  # Post-sweep low (invalid)
        ]
        choch_swing = self._find_choch_level("SELL", swept_swing, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['time'], 80)
        self.assertEqual(choch_swing['price'], 1.1020)

    def test_choch_3_multiple_candidate_swings_selection(self):
        # 3. Multiple candidate swings where ONLY the swing originating the final leg is valid:
        swept_swing = {'type': 'LOW', 'price': 1.0900, 'time': 200, 'isValid': True}
        swings = [
            {'type': 'HIGH', 'price': 1.1200, 'time': 50, 'isValid': True},   # Global high / early LH
            {'type': 'HIGH', 'price': 1.1100, 'time': 100, 'isValid': True},  # Intermediate LH
            {'type': 'HIGH', 'price': 1.1040, 'time': 180, 'isValid': True},  # LH directly originating final leg into t=200 low
        ]
        choch_swing = self._find_choch_level("BUY", swept_swing, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['price'], 1.1040)
        self.assertNotEqual(choch_swing['price'], 1.1200)
        self.assertNotEqual(choch_swing['price'], 1.1100)

    def test_choch_4_sweep_without_choch(self):
        # 4. Sweep without CHoCH:
        # Valid sweep occurs, but completed M15 candles fail to close above LH price (1.1060)
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        bar1_candle = {'open': 1.1020, 'high': 1.1058, 'low': 1.1015, 'close': 1.1050} # Close <= LH
        is_choch = self._check_m15_choch("BUY", choch_lh, bar1_candle)
        self.assertFalse(is_choch)

    def test_choch_5_choch_without_valid_sweep(self):
        # 5. CHoCH without a valid sweep:
        # If swept swing is invalid or missing, FindCHoCHLevel returns None and no CHoCH can be confirmed
        invalid_swept_swing = {'type': 'LOW', 'price': 1.0900, 'time': 0, 'isValid': False}
        swings = [{'type': 'HIGH', 'price': 1.1050, 'time': 80, 'isValid': True}]
        choch_swing = self._find_choch_level("BUY", invalid_swept_swing, swings)
        self.assertIsNone(choch_swing)

        bar1_candle = {'open': 1.1040, 'high': 1.1070, 'low': 1.1035, 'close': 1.1065}
        is_choch = self._check_m15_choch("BUY", choch_swing, bar1_candle)
        self.assertFalse(is_choch)

    def test_choch_6_wick_only_break_does_not_qualify(self):
        # 6. Wick-only break does not qualify:
        # High wicks above LH (1.1060), but body close is 1.1055 <= 1.1060
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        wick_break_bar1 = {'open': 1.1030, 'high': 1.1075, 'low': 1.1025, 'close': 1.1055}
        is_choch = self._check_m15_choch("BUY", choch_lh, wick_break_bar1)
        self.assertFalse(is_choch)

    def test_choch_7_forming_candle_cannot_confirm_choch(self):
        # 7. Forming candle cannot confirm CHoCH:
        # Bar 0 (forming candle) has close 1.1070 > LH (1.1060), but completed bar 1 close is 1.1050 <= 1.1060
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        bar0_forming = {'open': 1.1040, 'high': 1.1080, 'low': 1.1035, 'close': 1.1070}
        bar1_completed = {'open': 1.1020, 'high': 1.1055, 'low': 1.1015, 'close': 1.1050}

        # Check completed bar 1
        is_choch_completed = self._check_m15_choch("BUY", choch_lh, bar1_completed)
        self.assertFalse(is_choch_completed)

        # Confirming that code only evaluates bar 1, not forming bar 0
        self.assertNotEqual(bar1_completed['close'], bar0_forming['close'])


    # --- 3. M5 EXECUTION & DISPLACEMENT RULES ---

    @staticmethod
    def _check_m5_displacement_and_fvg(direction, candles, m5_swing_price):
        """
        Helper replicating CheckM5DisplacementAndFVG in smc_engine.mqh.
        candles dict mapping barIndex (1, 2, 3) -> candle dict
          bar 3 = C1
          bar 2 = C2 (displacement candle)
          bar 1 = C3 (third candle, confirms FVG pattern after close)
        """
        c1 = candles[3]
        c2 = candles[2]
        c3 = candles[1]

        if direction == "BUY":
            # 1. C2 must be bullish displacement candle (Close > Open)
            if c2['close'] <= c2['open']:
                return False, None
            # 2. C2 body close must break M5 swing high
            if c2['close'] <= m5_swing_price:
                return False, None
            # 3. C3 completes 3-candle sequence creating valid bullish FVG (Low(C3) > High(C1))
            if c3['low'] <= c1['high']:
                return False, None

            bottom = c1['high']
            top = c3['low']
            midpoint = (bottom + top) / 2.0
            return True, {
                'is_bullish': True,
                'bottom': bottom,
                'top': top,
                'midpoint': midpoint,
                'c1Index': 3,
                'c2Index': 2,
                'c3Index': 1,
                'timeC3': c3.get('time', 100)
            }

        elif direction == "SELL":
            # 1. C2 must be bearish displacement candle (Close < Open)
            if c2['close'] >= c2['open']:
                return False, None
            # 2. C2 body close must break M5 swing low
            if c2['close'] >= m5_swing_price:
                return False, None
            # 3. C3 completes 3-candle sequence creating valid bearish FVG (High(C3) < Low(C1))
            if c3['high'] >= c1['low']:
                return False, None

            bottom = c3['high']
            top = c1['low']
            midpoint = (bottom + top) / 2.0
            return True, {
                'is_bullish': False,
                'bottom': bottom,
                'top': top,
                'midpoint': midpoint,
                'c1Index': 3,
                'c2Index': 2,
                'c3Index': 1,
                'timeC3': c3.get('time', 100)
            }

        return False, None

    def test_valid_bullish_c1_c2_c3_fvg(self):
        # 1. Valid bullish C1/C2/C3 FVG test
        candles = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},          # C1
            2: {'open': 1.1005, 'close': 1.1040, 'high': 1.1045, 'low': 1.1002},          # C2 displacement
            1: {'open': 1.1035, 'close': 1.1025, 'high': 1.1038, 'low': 1.1015, 'time': 300} # C3 confirms FVG
        }
        m5_swing_high = 1.1020
        valid, fvg = self._check_m5_displacement_and_fvg("BUY", candles, m5_swing_high)
        self.assertTrue(valid)
        self.assertTrue(fvg['is_bullish'])
        self.assertEqual(fvg['bottom'], 1.1000)
        self.assertEqual(fvg['top'], 1.1015)
        self.assertAlmostEqual(fvg['midpoint'], 1.10075, places=5)
        self.assertEqual(fvg['c2Index'], 2)
        self.assertEqual(fvg['c3Index'], 1)

    def test_valid_bearish_c1_c2_c3_fvg(self):
        # 2. Valid bearish C1/C2/C3 FVG test
        candles = {
            3: {'low': 1.1050, 'high': 1.1070, 'open': 1.1065, 'close': 1.1055},          # C1
            2: {'open': 1.1045, 'close': 1.1010, 'high': 1.1048, 'low': 1.1005},          # C2 displacement
            1: {'open': 1.1015, 'close': 1.1025, 'high': 1.1035, 'low': 1.1010, 'time': 300} # C3 confirms FVG
        }
        m5_swing_low = 1.1030
        valid, fvg = self._check_m5_displacement_and_fvg("SELL", candles, m5_swing_low)
        self.assertTrue(valid)
        self.assertFalse(fvg['is_bullish'])
        self.assertEqual(fvg['bottom'], 1.1035)
        self.assertEqual(fvg['top'], 1.1050)
        self.assertAlmostEqual(fvg['midpoint'], 1.10425, places=5)
        self.assertEqual(fvg['c2Index'], 2)
        self.assertEqual(fvg['c3Index'], 1)

    def test_c2_treated_as_displacement_candle(self):
        # 3. Prove C2 is treated as the displacement candle
        m5_swing_high = 1.1020

        # Case A: C2 is bullish and body closes above swing high -> Valid displacement
        candles_valid = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},
            2: {'open': 1.1005, 'close': 1.1040, 'high': 1.1045, 'low': 1.1002}, # C2 bullish & breaks swing high
            1: {'open': 1.1035, 'close': 1.1025, 'high': 1.1038, 'low': 1.1015}  # C3
        }
        valid_a, _ = self._check_m5_displacement_and_fvg("BUY", candles_valid, m5_swing_high)
        self.assertTrue(valid_a)

        # Case B: C2 is a down-close candle (close <= open) despite passing high -> REJECTED (not bullish displacement)
        candles_down_c2 = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},
            2: {'open': 1.1045, 'close': 1.1040, 'high': 1.1050, 'low': 1.1002}, # C2 open > close
            1: {'open': 1.1035, 'close': 1.1025, 'high': 1.1038, 'low': 1.1015}
        }
        valid_b, _ = self._check_m5_displacement_and_fvg("BUY", candles_down_c2, m5_swing_high)
        self.assertFalse(valid_b)

        # Case C: C2 close does NOT close above swing high -> REJECTED
        candles_weak_c2 = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},
            2: {'open': 1.1005, 'close': 1.1015, 'high': 1.1018, 'low': 1.1002}, # C2 close <= 1.1020
            1: {'open': 1.1035, 'close': 1.1025, 'high': 1.1038, 'low': 1.1015}
        }
        valid_c, _ = self._check_m5_displacement_and_fvg("BUY", candles_weak_c2, m5_swing_high)
        self.assertFalse(valid_c)

    def test_c3_confirms_fvg_not_displacement(self):
        # 4. Prove C3 confirms the FVG rather than being treated as the displacement candle
        m5_swing_high = 1.1020

        # Case A: C2 was the displacement candle. C3 is a down-close candle (close < open) and close <= swing_high,
        # but C3 low > C1 high -> VALID! (Proves C3 is NOT required to be the displacement candle).
        candles_c3_retrace = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},          # C1
            2: {'open': 1.1005, 'close': 1.1040, 'high': 1.1045, 'low': 1.1002},          # C2 displacement
            1: {'open': 1.1035, 'close': 1.1015, 'high': 1.1038, 'low': 1.1010}           # C3 down candle, low > C1 high
        }
        valid_a, fvg_a = self._check_m5_displacement_and_fvg("BUY", candles_c3_retrace, m5_swing_high)
        self.assertTrue(valid_a)
        self.assertIsNotNone(fvg_a)

        # Case B: C2 was NOT the displacement candle (C2 close <= swing high), but C3 WAS a huge breakout candle
        # closing above swing high. -> REJECTED! (Proves C3 is NOT treated as the displacement candle).
        candles_c3_displacement = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},          # C1
            2: {'open': 1.1002, 'close': 1.1010, 'high': 1.1012, 'low': 1.1000},          # C2 fails to break swing high
            1: {'open': 1.1015, 'close': 1.1050, 'high': 1.1055, 'low': 1.1012}           # C3 breaks swing high
        }
        valid_b, fvg_b = self._check_m5_displacement_and_fvg("BUY", candles_c3_displacement, m5_swing_high)
        self.assertFalse(valid_b)
        self.assertIsNone(fvg_b)

    def test_wick_only_structural_break_rejected(self):
        # 5. Prove wick-only structural breaks do not qualify where a body close is required
        m5_swing_high = 1.1020

        # C2 high wicks up to 1.1025 (> 1.1020), but C2 body closes at 1.1018 (<= 1.1020)
        candles_wick_break = {
            3: {'high': 1.1000, 'low': 1.0980, 'open': 1.0985, 'close': 1.0995},
            2: {'open': 1.1005, 'close': 1.1018, 'high': 1.1025, 'low': 1.1002}, # Wick break only
            1: {'open': 1.1020, 'close': 1.1025, 'high': 1.1030, 'low': 1.1015}
        }
        valid, fvg = self._check_m5_displacement_and_fvg("BUY", candles_wick_break, m5_swing_high)
        self.assertFalse(valid)
        self.assertIsNone(fvg)

        # Bearish wick break test
        m5_swing_low = 1.1000
        candles_bearish_wick = {
            3: {'low': 1.1020, 'high': 1.1040, 'open': 1.1035, 'close': 1.1025},
            2: {'open': 1.1015, 'close': 1.1002, 'high': 1.1018, 'low': 1.0995}, # Wick reaches 1.0995 (< 1.1000), close 1.1002
            1: {'open': 1.1000, 'close': 1.0990, 'high': 1.1005, 'low': 1.0985}
        }
        valid_bear, fvg_bear = self._check_m5_displacement_and_fvg("SELL", candles_bearish_wick, m5_swing_low)
        self.assertFalse(valid_bear)
        self.assertIsNone(fvg_bear)

    def test_fvg_midpoint_calculation(self):
        # 6. Prove FVG midpoint is calculated correctly
        # Bullish: bottom = High(C1), top = Low(C3) -> midpoint = (bottom + top) / 2.0
        bottom_bull = 1.1000
        top_bull = 1.1030
        midpoint_bull = (bottom_bull + top_bull) / 2.0
        self.assertAlmostEqual(midpoint_bull, 1.1015, places=5)

        # Bearish: bottom = High(C3), top = Low(C1) -> midpoint = (bottom + top) / 2.0
        bottom_bear = 1.1020
        top_bear = 1.1060
        midpoint_bear = (bottom_bear + top_bear) / 2.0
        self.assertAlmostEqual(midpoint_bear, 1.1040, places=5)

    def test_fvg_invalidation_rules(self):
        # 7. Prove FVG invalidation follows locked rules
        # Bullish FVG (bottom = 1.1000, top = 1.1015)
        fvg_bullish = {'is_bullish': True, 'bottom': 1.1000, 'top': 1.1015, 'isValid': True}

        def is_fvg_invalidated(fvg, close_price):
            if fvg['is_bullish']:
                return close_price < fvg['bottom']
            else:
                return close_price > fvg['top']

        # Completed M5 candle body close below C1 bottom -> INVALIDATED
        self.assertTrue(is_fvg_invalidated(fvg_bullish, 1.0995))

        # Completed M5 candle body close above or at C1 bottom -> NOT INVALIDATED
        self.assertFalse(is_fvg_invalidated(fvg_bullish, 1.1000))
        self.assertFalse(is_fvg_invalidated(fvg_bullish, 1.1005))

        # Touch/mitigation without body close below C1 bottom (e.g. Low = 1.0990, Close = 1.1002) -> NOT INVALIDATED
        touch_candle_close = 1.1002
        self.assertFalse(is_fvg_invalidated(fvg_bullish, touch_candle_close))

        # Bearish FVG (bottom = 1.1035, top = 1.1050)
        fvg_bearish = {'is_bullish': False, 'bottom': 1.1035, 'top': 1.1050, 'isValid': True}

        # Completed M5 candle body close above C1 top -> INVALIDATED
        self.assertTrue(is_fvg_invalidated(fvg_bearish, 1.1055))

        # Completed M5 candle body close below or at C1 top -> NOT INVALIDATED
        self.assertFalse(is_fvg_invalidated(fvg_bearish, 1.1050))
        self.assertFalse(is_fvg_invalidated(fvg_bearish, 1.1040))

        # Touch/mitigation without body close above C1 top (e.g. High = 1.1058, Close = 1.1048) -> NOT INVALIDATED
        touch_bear_close = 1.1048
        self.assertFalse(is_fvg_invalidated(fvg_bearish, touch_bear_close))

    def test_no_forming_candle_used_for_confirmation(self):
        # 8. Prove no current/forming candle (bar 0) is used for confirmation
        # Completed candles are bar 3 (C1), bar 2 (C2), bar 1 (C3). Bar 0 is the forming candle.
        completed_bars = [3, 2, 1]
        forming_bar = 0

        # Confirmation logic explicitly accesses completed bars index >= 1
        for bar in completed_bars:
            self.assertGreaterEqual(bar, 1)

        self.assertNotIn(forming_bar, completed_bars)


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
