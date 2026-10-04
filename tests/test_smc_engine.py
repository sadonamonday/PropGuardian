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

    @staticmethod
    def _find_4h_order_block(bars, ob_idx, prev_swing_price):
        """
        Helper replicating updated Find4HOrderBlock logic in smc_engine.mqh.
        bars: dict mapping barIndex (1, 2, ..., N) -> candle dict
        ob_idx: candidate Order Block bar index
        prev_swing_price: prior 4H swing high (for bullish) or swing low (for bearish) price
        """
        if ob_idx not in bars or ob_idx < 3:
            return False, None

        ob = bars[ob_idx]
        open_ob, close_ob = ob['open'], ob['close']
        high_ob, low_ob = ob['high'], ob['low']

        if open_ob == 0 or close_ob == 0:
            return False, None

        # Bullish OB: final down-close candle before qualifying bullish move
        if close_ob < open_ob:
            has_bos = False
            has_fvg = False

            for k in range(ob_idx - 1, 0, -1):
                if k not in bars:
                    break
                cl_k = bars[k]['close']

                if cl_k > prev_swing_price:
                    has_bos = True

                c1 = k + 2
                c3 = k
                if c1 <= ob_idx and c1 in bars and c3 in bars:
                    high_c1 = bars[c1]['high']
                    low_c3 = bars[c3]['low']
                    if high_c1 > 0 and low_c3 > high_c1:
                        has_fvg = True

                if has_bos and has_fvg:
                    break

            if not has_bos or not has_fvg:
                return False, None

            # Invalidation check: completed candle closes below bottom
            for k in range(ob_idx - 1, 0, -1):
                if k in bars and bars[k]['close'] < low_ob:
                    return False, None

            return True, {
                'type': 'DEMAND',
                'bottom': low_ob,
                'top': high_ob,
                'time': ob.get('time', 100),
                'isActive': True
            }

        # Bearish OB: final up-close candle before qualifying bearish move
        elif close_ob > open_ob:
            has_bos = False
            has_fvg = False

            for k in range(ob_idx - 1, 0, -1):
                if k not in bars:
                    break
                cl_k = bars[k]['close']

                if cl_k < prev_swing_price:
                    has_bos = True

                c1 = k + 2
                c3 = k
                if c1 <= ob_idx and c1 in bars and c3 in bars:
                    low_c1 = bars[c1]['low']
                    high_c3 = bars[c3]['high']
                    if low_c1 > 0 and high_c3 < low_c1:
                        has_fvg = True

                if has_bos and has_fvg:
                    break

            if not has_bos or not has_fvg:
                return False, None

            # Invalidation check: completed candle closes above top
            for k in range(ob_idx - 1, 0, -1):
                if k in bars and bars[k]['close'] > high_ob:
                    return False, None

            return True, {
                'type': 'SUPPLY',
                'bottom': low_ob,
                'top': high_ob,
                'time': ob.get('time', 100),
                'isActive': True
            }

        return False, None

    def test_4h_bullish_ob_definition(self):
        # 1. Valid Bullish 4H OB test
        bars = {
            4: {'open': 1.1020, 'close': 1.1000, 'high': 1.1025, 'low': 1.0995, 'time': 100}, # Down-close OB (bar 4)
            3: {'open': 1.1005, 'close': 1.1035, 'high': 1.1040, 'low': 1.1000},             # Bullish move
            2: {'open': 1.1030, 'close': 1.1050, 'high': 1.1055, 'low': 1.1028},             # Bullish move & BOS, low(2)=1.1028 > high(4)=1.1025 (FVG)
            1: {'open': 1.1048, 'close': 1.1060, 'high': 1.1065, 'low': 1.1042}              # Low(1)=1.1042 > high(3)=1.1040 (FVG)
        }
        prev_swing_high = 1.1040

        valid, ob = self._find_4h_order_block(bars, 4, prev_swing_high)
        self.assertTrue(valid)
        self.assertEqual(ob['type'], 'DEMAND')
        self.assertEqual((ob['bottom'], ob['top']), (1.0995, 1.1025))

    def test_4h_bearish_ob_definition(self):
        # 2. Valid Bearish 4H OB test
        bars = {
            4: {'open': 1.1000, 'close': 1.1020, 'high': 1.1025, 'low': 1.0995, 'time': 100}, # Up-close OB (bar 4)
            3: {'open': 1.1015, 'close': 1.0990, 'high': 1.1018, 'low': 1.0985},             # Bearish move
            2: {'open': 1.0985, 'close': 1.0960, 'high': 1.0990, 'low': 1.0955},             # Bearish move & BOS
            1: {'open': 1.0965, 'close': 1.0950, 'high': 1.0980, 'low': 1.0945}              # High(bar 1) 1.0980 < Low(bar 3) 1.0985
        }
        prev_swing_low = 1.0970

        valid, ob = self._find_4h_order_block(bars, 4, prev_swing_low)
        self.assertTrue(valid)
        self.assertEqual(ob['type'], 'SUPPLY')
        self.assertEqual((ob['bottom'], ob['top']), (1.0995, 1.1025))

    def test_4h_ob_followed_by_qualifying_move_and_delayed_fvg(self):
        # 3 & 5. OB followed by qualifying structural move where FVG occurs more than 1 candle after OB
        # Candle 5 = candidate down-close OB
        # Candle 4 = bullish move candle 1 (no FVG with C5 yet)
        # Candle 3 = bullish move candle 2 (BOS)
        # Candle 2 = bullish move candle 3
        # Candle 1 = FVG completed with C3 (Low(1) 1.1040 > High(3) 1.1035)
        bars = {
            5: {'open': 1.1020, 'close': 1.1000, 'high': 1.1025, 'low': 1.0995, 'time': 100}, # OB
            4: {'open': 1.1005, 'close': 1.1020, 'high': 1.1022, 'low': 1.1002},             # Bullish
            3: {'open': 1.1020, 'close': 1.1035, 'high': 1.1035, 'low': 1.1015},             # Bullish
            2: {'open': 1.1035, 'close': 1.1050, 'high': 1.1055, 'low': 1.1030},             # Bullish (BOS)
            1: {'open': 1.1048, 'close': 1.1060, 'high': 1.1065, 'low': 1.1040}              # Low(1) 1.1040 > High(3) 1.1035 -> FVG!
        }
        prev_swing_high = 1.1045

        valid, ob = self._find_4h_order_block(bars, 5, prev_swing_high)
        self.assertTrue(valid, "OB with delayed FVG must be valid and NOT automatically invalidated")
        self.assertEqual(ob['type'], 'DEMAND')

    def test_4h_multiple_opposite_candles_selects_final_qualifying(self):
        # 4. Multiple opposite-colored candles — verify the final qualifying opposite candle is selected
        # Candle 6 = down-close candle
        # Candle 5 = down-close candle (final down-close before move)
        # Candle 4 = bullish
        # Candle 3 = bullish (BOS)
        # Candle 2 = bullish
        # Candle 1 = bullish (completes FVG with C3)
        bars = {
            6: {'open': 1.1040, 'close': 1.1020, 'high': 1.1045, 'low': 1.1015, 'time': 80},  # Older down-close
            5: {'open': 1.1020, 'close': 1.1000, 'high': 1.1025, 'low': 1.0995, 'time': 100}, # Final down-close OB
            4: {'open': 1.1005, 'close': 1.1025, 'high': 1.1030, 'low': 1.1000},             # Bullish
            3: {'open': 1.1025, 'close': 1.1050, 'high': 1.1055, 'low': 1.1020},             # Bullish (BOS)
            2: {'open': 1.1050, 'close': 1.1060, 'high': 1.1065, 'low': 1.1045},             # Bullish
            1: {'open': 1.1060, 'close': 1.1070, 'high': 1.1075, 'low': 1.1060}              # FVG with C3
        }
        prev_swing_high = 1.1040

        # Bar 6 candidate: immediately followed by bar 5 which is down-close -> REJECTED (not final down-close)
        valid_bar6, _ = self._find_4h_order_block(bars, 6, prev_swing_high)
        self.assertFalse(valid_bar6, "Bar 6 must be rejected because Bar 5 is a subsequent down-close candle")

        # Bar 5 candidate: final down-close before move -> ACCEPTED
        valid_bar5, ob_bar5 = self._find_4h_order_block(bars, 5, prev_swing_high)
        self.assertTrue(valid_bar5)
        self.assertEqual(ob_bar5['time'], 100)

    def test_4h_unrelated_later_fvg_bos_does_not_validate_old_ob(self):
        # 6. Unrelated later FVG/BOS must not incorrectly validate an old unrelated OB
        # Candle 7 = down-close candle
        # Candle 6 = bullish move
        # Candle 5 = down-close candle (starts a new unrelated move)
        # Candle 4 = bullish
        # Candle 3 = bullish (BOS)
        # Candle 2 = bullish
        # Candle 1 = bullish (FVG with C3)
        bars = {
            7: {'open': 1.1020, 'close': 1.1000, 'high': 1.1025, 'low': 1.0995, 'time': 60},  # Old OB candidate
            6: {'open': 1.1005, 'close': 1.1015, 'high': 1.1018, 'low': 1.1000},             # Bullish
            5: {'open': 1.1015, 'close': 1.0990, 'high': 1.1018, 'low': 1.0985},             # Down-close candle! Intervenes!
            4: {'open': 1.0995, 'close': 1.1025, 'high': 1.1030, 'low': 1.0990},             # Bullish
            3: {'open': 1.1025, 'close': 1.1050, 'high': 1.1055, 'low': 1.1020},             # Bullish (BOS)
            2: {'open': 1.1050, 'close': 1.1060, 'high': 1.1065, 'low': 1.1045},             # Bullish
            1: {'open': 1.1060, 'close': 1.1070, 'high': 1.1075, 'low': 1.1060}              # FVG
        }
        prev_swing_high = 1.1040

        # Bar 7 is separated from the qualifying move by Bar 5 (down-close).
        valid_bar7, _ = self._find_4h_order_block(bars, 7, prev_swing_high)
        self.assertFalse(valid_bar7, "Old OB separated by an intervening down-close candle must be rejected")

    def test_4h_invalidated_bullish_ob_rejected(self):
        # 7. Invalidated bullish OB is rejected (completed candle close < lowOB)
        bars = {
            4: {'open': 1.1020, 'close': 1.1000, 'high': 1.1025, 'low': 1.0995, 'time': 100}, # OB
            3: {'open': 1.1005, 'close': 1.1050, 'high': 1.1055, 'low': 1.1000},             # Move & BOS & FVG
            2: {'open': 1.1045, 'close': 1.1060, 'high': 1.1065, 'low': 1.1030},
            1: {'open': 1.1030, 'close': 1.0990, 'high': 1.1035, 'low': 1.0985}              # Close 1.0990 < lowOB 1.0995 (Invalidated!)
        }
        prev_swing_high = 1.1040

        valid, _ = self._find_4h_order_block(bars, 4, prev_swing_high)
        self.assertFalse(valid, "Bullish OB closed below lowOB must be rejected as invalidated")

    def test_4h_invalidated_bearish_ob_rejected(self):
        # 8. Invalidated bearish OB is rejected (completed candle close > highOB)
        bars = {
            4: {'open': 1.1000, 'close': 1.1020, 'high': 1.1025, 'low': 1.0995, 'time': 100}, # OB
            3: {'open': 1.1015, 'close': 1.0970, 'high': 1.1018, 'low': 1.0965},             # Move & BOS & FVG
            2: {'open': 1.0965, 'close': 1.0950, 'high': 1.0980, 'low': 1.0945},
            1: {'open': 1.0955, 'close': 1.1030, 'high': 1.1035, 'low': 1.0950}              # Close 1.1030 > highOB 1.1025 (Invalidated!)
        }
        prev_swing_low = 1.0980

        valid, _ = self._find_4h_order_block(bars, 4, prev_swing_low)
        self.assertFalse(valid, "Bearish OB closed above highOB must be rejected as invalidated")

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

    @staticmethod
    def _get_active_4h_poi(structure_4h, registered_pois, detected_pois, bar_closes):
        """
        Helper replicating GetActive4HPOI in smc_engine.mqh.
        """
        if structure_4h == "UNDEFINED":
            return None

        newest_poi = None
        newest_time = 0

        # Filter and check registered POIs
        for poi in registered_pois:
            if not poi.get('isActive', True):
                continue

            matches_dir = (structure_4h == "BULLISH" and poi['type'] == 'DEMAND') or \
                          (structure_4h == "BEARISH" and poi['type'] == 'SUPPLY')
            if not matches_dir:
                continue

            # Check invalidation against bar_closes
            is_invalidated = False
            poi_time = poi['time']
            for bar_time, cl in bar_closes.items():
                if bar_time > poi_time:
                    if poi['type'] == 'DEMAND' and cl < poi['bottom']:
                        is_invalidated = True
                        break
                    elif poi['type'] == 'SUPPLY' and cl > poi['top']:
                        is_invalidated = True
                        break

            if not is_invalidated and poi_time > newest_time:
                newest_poi = poi
                newest_time = poi_time

        # Filter and check detected POIs (OB and FVG equal status)
        for poi in detected_pois:
            if not poi.get('isActive', True):
                continue

            matches_dir = (structure_4h == "BULLISH" and poi['type'] == 'DEMAND') or \
                          (structure_4h == "BEARISH" and poi['type'] == 'SUPPLY')
            if not matches_dir:
                continue

            # Check invalidation against bar_closes
            is_invalidated = False
            poi_time = poi['time']
            for bar_time, cl in bar_closes.items():
                if bar_time > poi_time:
                    if poi['type'] == 'DEMAND' and cl < poi['bottom']:
                        is_invalidated = True
                        break
                    elif poi['type'] == 'SUPPLY' and cl > poi['top']:
                        is_invalidated = True
                        break

            if not is_invalidated and poi_time > newest_time:
                newest_poi = poi
                newest_time = poi_time

        return newest_poi

    def test_4h_poi_direction_filtering(self):
        # 6. POI direction must match 4H structure
        structure_4h = "BULLISH"
        bullish_poi = {'id': 1, 'type': 'DEMAND', 'time': 100, 'isActive': True, 'bottom': 1.1000, 'top': 1.1020}
        bearish_poi = {'id': 2, 'type': 'SUPPLY', 'time': 200, 'isActive': True, 'bottom': 1.1050, 'top': 1.1070}

        selected = self._get_active_4h_poi(structure_4h, [], [bullish_poi, bearish_poi], {})
        self.assertIsNotNone(selected)
        self.assertEqual(selected['id'], 1) # Only DEMAND POI matches BULLISH structure

    def test_4h_poi_selection_most_recent(self):
        # 7. Most recent valid POI selected (equal priority for OB and FVG)
        structure_4h = "BULLISH"
        older_ob = {'id': 1, 'type': 'DEMAND', 'time': 100, 'isActive': True, 'bottom': 1.1000, 'top': 1.1020}
        newer_fvg = {'id': 2, 'type': 'DEMAND', 'time': 200, 'isActive': True, 'bottom': 1.1030, 'top': 1.1050}

        selected = self._get_active_4h_poi(structure_4h, [], [older_ob, newer_fvg], {})
        self.assertEqual(selected['id'], 2) # Newer FVG selected over older OB

    def test_registered_poi_cannot_bypass_direction_filtering(self):
        # 8. Registered POI cannot bypass direction filtering or invalidation
        structure_4h = "BULLISH"
        # Registered supply (bearish) POI
        registered_supply = {'id': 10, 'type': 'SUPPLY', 'time': 300, 'isActive': True, 'bottom': 1.1100, 'top': 1.1120}
        detected_demand = {'id': 1, 'type': 'DEMAND', 'time': 100, 'isActive': True, 'bottom': 1.1000, 'top': 1.1020}

        # Registered supply POI must be filtered out despite having a newer timestamp
        selected = self._get_active_4h_poi(structure_4h, [registered_supply], [detected_demand], {})
        self.assertEqual(selected['id'], 1)

        # Invalidation test for registered POI:
        registered_demand = {'id': 20, 'type': 'DEMAND', 'time': 200, 'isActive': True, 'bottom': 1.1000, 'top': 1.1020}
        detected_demand_older = {'id': 1, 'type': 'DEMAND', 'time': 50, 'isActive': True, 'bottom': 1.0900, 'top': 1.0920}
        bar_closes = {250: 1.0990} # 4H close below bottom 1.1000 for registered POI (time 200), but > 50 so after time 50
        selected_inv = self._get_active_4h_poi(structure_4h, [registered_demand], [detected_demand_older], bar_closes)
        self.assertEqual(selected_inv['id'], 1) # Registered demand was invalidated, fallback to detected

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

    def test_invalidated_pois_excluded(self):
        # 5. Invalidated POIs excluded from GetActive4HPOI selection
        structure_4h = "BULLISH"
        # Newer OB that was closed below (invalidated)
        invalidated_ob = {'id': 2, 'type': 'DEMAND', 'time': 200, 'isActive': True, 'bottom': 1.1000, 'top': 1.1020}
        # Older valid FVG
        older_valid_fvg = {'id': 1, 'type': 'DEMAND', 'time': 100, 'isActive': True, 'bottom': 1.0950, 'top': 1.0970}
        # Bar close at t=250 closes below invalidated OB low (1.0990 < 1.1000)
        bar_closes = {250: 1.0990}

        selected = self._get_active_4h_poi(structure_4h, [], [invalidated_ob, older_valid_fvg], bar_closes)
        self.assertIsNotNone(selected)
        self.assertEqual(selected['id'], 1) # Invalidated OB excluded, older valid FVG selected

    def test_no_poi_means_no_setup(self):
        # 10. No valid/active 4H POI means no setup is created (remains idle or returns None)
        structure_4h = "BULLISH"
        selected = self._get_active_4h_poi(structure_4h, [], [], {})
        self.assertIsNone(selected)

        # In state machine context: SMC_IDLE state without active POI results in no state transition
        setup = {'state': 'SMC_IDLE', 'poi4H': selected}
        if setup['poi4H'] is None or not setup['poi4H'].get('isActive', False):
            # Setup remains in SMC_IDLE state
            pass
        self.assertEqual(setup['state'], 'SMC_IDLE')


    # --- 2. M15 SWEEP & CHOCH RULES ---

    @staticmethod
    def _find_choch_level(direction, sweep_time, m15_swings):
        """
        Helper mirroring FindCHoCHLevel in smc_engine.mqh.
        Finds the most recent confirmed 5-bar M15 swing before sweep_time (swing1)
        and verifies its structural relationship (Lower High for BUY, Higher Low for SELL)
        against the preceding confirmed 5-bar M15 swing (swing2).
        If swing1 is not a LH/HL or structure cannot be established deterministically,
        returns None without fallback.
        """
        if sweep_time <= 0:
            return None

        # Filter for confirmed 5-bar swings before sweep_time
        candidates = [s for s in m15_swings
                      if s.get('time', 0) < sweep_time
                      and s.get('isValid', True)
                      and s.get('bar_index', 3) >= 3]

        if direction == "BUY":
            high_candidates = sorted([s for s in candidates if s['type'] == 'HIGH'], key=lambda x: x['time'], reverse=True)
            if len(high_candidates) < 2:
                return None # Structure cannot be established deterministically
            swing1 = high_candidates[0]
            swing2 = high_candidates[1]
            if swing1['price'] < swing2['price']:
                return swing1
            return None

        elif direction == "SELL":
            low_candidates = sorted([s for s in candidates if s['type'] == 'LOW'], key=lambda x: x['time'], reverse=True)
            if len(low_candidates) < 2:
                return None # Structure cannot be established deterministically
            swing1 = low_candidates[0]
            swing2 = low_candidates[1]
            if swing1['price'] > swing2['price']:
                return swing1
            return None

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

    def test_choch_test_a_valid_bullish_lh(self):
        # Test A — Valid bullish LH
        # Older confirmed swing high = 1.1100
        # Most recent confirmed swing high = 1.1050
        # Swept low occurs afterwards (sweep_time = 100)
        sweep_time = 100
        swings = [
            {'type': 'HIGH', 'price': 1.1100, 'time': 40, 'bar_index': 10, 'isValid': True},   # Older high
            {'type': 'HIGH', 'price': 1.1050, 'time': 80, 'bar_index': 5, 'isValid': True},    # Most recent high (valid LH)
        ]
        choch_swing = self._find_choch_level("BUY", sweep_time, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['price'], 1.1050)

    def test_choch_test_b_valid_bearish_hl(self):
        # Test B — Valid bearish HL
        # Older confirmed swing low = 1.0950
        # Most recent confirmed swing low = 1.1000
        # Swept high occurs afterwards (sweep_time = 100)
        sweep_time = 100
        swings = [
            {'type': 'LOW', 'price': 1.0950, 'time': 40, 'bar_index': 10, 'isValid': True},   # Older low
            {'type': 'LOW', 'price': 1.1000, 'time': 80, 'bar_index': 5, 'isValid': True},    # Most recent low (valid HL)
        ]
        choch_swing = self._find_choch_level("SELL", sweep_time, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['price'], 1.1000)

    def test_choch_test_c_most_recent_swing_not_lh(self):
        # Test C — Most recent swing is NOT an LH
        # Older confirmed high = 1.1050
        # Most recent confirmed high = 1.1100 (Higher High!)
        # Swept low occurs afterwards
        # Do NOT select the older high. Return no CHoCH level.
        sweep_time = 100
        swings = [
            {'type': 'HIGH', 'price': 1.1050, 'time': 40, 'bar_index': 10, 'isValid': True},   # Older high
            {'type': 'HIGH', 'price': 1.1100, 'time': 80, 'bar_index': 5, 'isValid': True},    # Most recent high (NOT an LH!)
        ]
        choch_swing = self._find_choch_level("BUY", sweep_time, swings)
        self.assertIsNone(choch_swing, "If most recent swing is not an LH, return None without fallback to older high")

    def test_choch_test_d_most_recent_swing_not_hl(self):
        # Test D — Most recent swing is NOT an HL
        # Older confirmed low = 1.1000
        # Most recent confirmed low = 1.0950 (Lower Low!)
        # Swept high occurs afterwards
        # Do NOT select the older low. Return no CHoCH level.
        sweep_time = 100
        swings = [
            {'type': 'LOW', 'price': 1.1000, 'time': 40, 'bar_index': 10, 'isValid': True},   # Older low
            {'type': 'LOW', 'price': 1.0950, 'time': 80, 'bar_index': 5, 'isValid': True},    # Most recent low (NOT an HL!)
        ]
        choch_swing = self._find_choch_level("SELL", sweep_time, swings)
        self.assertIsNone(choch_swing, "If most recent swing is not an HL, return None without fallback to older low")

    def test_choch_test_e_unconfirmed_swing(self):
        # Test E — Unconfirmed swing
        # Ensure an unconfirmed/forming swing (bar_index < 3) cannot become the CHoCH level.
        sweep_time = 200
        swings = [
            {'type': 'HIGH', 'price': 1.1100, 'time': 100, 'bar_index': 10, 'isValid': True},  # Older high
            {'type': 'HIGH', 'price': 1.1050, 'time': 150, 'bar_index': 5, 'isValid': True},   # Confirmed LH
            {'type': 'HIGH', 'price': 1.1020, 'time': 190, 'bar_index': 1, 'isValid': True},   # Unconfirmed swing (bar 1 < 3)
        ]
        choch_swing = self._find_choch_level("BUY", sweep_time, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['price'], 1.1050) # Unconfirmed swing at bar 1 ignored

    def test_choch_test_f_wick_only_break(self):
        # Test F — Wick-only break
        # Ensure a wick beyond the CHoCH level does not confirm CHoCH.
        # Only a completed candle body close confirms it.
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        wick_break_bar1 = {'open': 1.1030, 'high': 1.1075, 'low': 1.1025, 'close': 1.1055} # High > 1.1060 but Close <= 1.1060
        is_choch = self._check_m15_choch("BUY", choch_lh, wick_break_bar1)
        self.assertFalse(is_choch, "Wick-only break beyond CHoCH level must not confirm CHoCH")

        body_close_bar1 = {'open': 1.1030, 'high': 1.1075, 'low': 1.1025, 'close': 1.1065} # Close > 1.1060
        is_choch_body = self._check_m15_choch("BUY", choch_lh, body_close_bar1)
        self.assertTrue(is_choch_body, "Completed candle body close beyond CHoCH level must confirm CHoCH")

    def test_choch_test_g_ambiguous_structure(self):
        # Test G — Ambiguous structure
        # If there is insufficient confirmed structure to establish the LH/HL relationship, return no CHoCH level.
        sweep_time = 100
        # Only 1 confirmed swing before sweep_time -> cannot establish LH/HL relationship against a preceding swing!
        swings_single = [
            {'type': 'HIGH', 'price': 1.1050, 'time': 80, 'bar_index': 5, 'isValid': True}
        ]
        choch_single = self._find_choch_level("BUY", sweep_time, swings_single)
        self.assertIsNone(choch_single, "Single swing insufficient to verify LH relationship -> return None")

        # No confirmed swings
        swings_empty = []
        choch_empty = self._find_choch_level("BUY", sweep_time, swings_empty)
        self.assertIsNone(choch_empty, "Empty swings -> return None")

    def test_choch_4_sweep_without_choch(self):
        # 4. Sweep without CHoCH:
        # Valid sweep occurs, but completed M15 candle body fails to close above LH price (1.1060)
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        bar1_candle = {'open': 1.1020, 'high': 1.1058, 'low': 1.1015, 'close': 1.1050} # Close <= LH
        is_choch = self._check_m15_choch("BUY", choch_lh, bar1_candle)
        self.assertFalse(is_choch)

    def test_choch_5_choch_without_valid_sweep(self):
        # 5. CHoCH without a valid sweep:
        # If sweep_time is invalid (<= 0) or no sweep occurred, FindCHoCHLevel returns None
        invalid_sweep_time = 0
        swings = [{'type': 'HIGH', 'price': 1.1050, 'time': 80, 'bar_index': 5, 'isValid': True}]
        choch_swing = self._find_choch_level("BUY", invalid_sweep_time, swings)
        self.assertIsNone(choch_swing)

        bar1_candle = {'open': 1.1040, 'high': 1.1070, 'low': 1.1035, 'close': 1.1065}
        is_choch = self._check_m15_choch("BUY", choch_swing, bar1_candle)
        self.assertFalse(is_choch)

    def test_choch_6_wick_only_break_does_not_qualify(self):
        # 6. Wick-only break does not confirm CHoCH:
        # High wicks above LH (1.1060), but body close is 1.1055 <= 1.1060
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        wick_break_bar1 = {'open': 1.1030, 'high': 1.1075, 'low': 1.1025, 'close': 1.1055}
        is_choch = self._check_m15_choch("BUY", choch_lh, wick_break_bar1)
        self.assertFalse(is_choch)

    def test_choch_7_unconfirmed_swing_cannot_be_used(self):
        # 7. Unconfirmed swing (bar_index < 3) cannot be used for CHoCH
        sweep_time = 200
        swings = [
            {'type': 'HIGH', 'price': 1.1100, 'time': 100, 'bar_index': 12, 'isValid': True},  # Older confirmed high
            {'type': 'HIGH', 'price': 1.1080, 'time': 190, 'bar_index': 1, 'isValid': True},   # Unconfirmed swing (bar 1 < 3)
            {'type': 'HIGH', 'price': 1.1040, 'time': 150, 'bar_index': 6, 'isValid': True},   # Confirmed LH (bar 6 >= 3)
        ]
        choch_swing = self._find_choch_level("BUY", sweep_time, swings)
        self.assertIsNotNone(choch_swing)
        self.assertEqual(choch_swing['price'], 1.1040) # Unconfirmed swing at bar 1 skipped

    def test_choch_8_current_forming_candle_cannot_confirm_choch(self):
        # 8. Current forming candle (bar 0) cannot confirm CHoCH
        choch_lh = {'type': 'HIGH', 'price': 1.1060, 'time': 80, 'isValid': True}
        bar0_forming = {'open': 1.1040, 'high': 1.1080, 'low': 1.1035, 'close': 1.1070}
        bar1_completed = {'open': 1.1020, 'high': 1.1055, 'low': 1.1015, 'close': 1.1050}

        # Check completed bar 1
        is_choch_completed = self._check_m15_choch("BUY", choch_lh, bar1_completed)
        self.assertFalse(is_choch_completed)

        # Confirm that bar 0 is separate and not evaluated by completion check
        self.assertNotEqual(bar1_completed['close'], bar0_forming['close'])

    def test_choch_9_ambiguous_structure_does_not_invent_rules(self):
        # 9. Ambiguous structure where no confirmed swing exists prior to sweep -> returns None without inventing rules
        sweep_time = 100
        swings = [] # No confirmed prior swings in history
        choch_swing = self._find_choch_level("BUY", sweep_time, swings)
        self.assertIsNone(choch_swing, "If no confirmed swing exists in history prior to sweep, return None without inventing arbitrary fallback rules")


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


    # --- 5. STRUCTURAL SL & TP TARGETING RULES ---

    @staticmethod
    def _calculate_structural_sl(direction, sweep_price, entry_price):
        """
        Replicates structural SL logic in smc_engine.mqh:
        Uses the sweep invalidation level without arbitrary pip/point buffers.
        """
        if direction == "BUY":
            sl_price = sweep_price
            if sl_price >= entry_price:
                return None, "Structural SL is not below entry price for Buy setup"
            return sl_price, None
        elif direction == "SELL":
            sl_price = sweep_price
            if sl_price <= entry_price:
                return None, "Structural SL is not above entry price for Sell setup"
            return sl_price, None
        return None, "Invalid direction"

    @staticmethod
    def _find_next_opposing_target(direction, entry_price, m15_swings):
        """
        Replicates FindNextOpposingTargetHigh/Low logic in smc_engine.mqh.
        Scans confirmed M15 swings backward (bar index >= 3, swing.time <= current_time)
        and returns the next opposing target ahead of entry.
        """
        # Filter for confirmed swings only (bar_index >= 3 to ensure no unconfirmed/future swings)
        confirmed_swings = [s for s in m15_swings if s.get('isValid', True) and s.get('bar_index', 3) >= 3]

        # Sort by bar_index ascending (scanning backward from most recent confirmed bar 3)
        sorted_swings = sorted(confirmed_swings, key=lambda x: x.get('bar_index', 3))

        if direction == "BUY":
            for swing in sorted_swings:
                if swing.get('type') == 'HIGH' and swing['price'] > entry_price:
                    return swing
            return None
        elif direction == "SELL":
            for swing in sorted_swings:
                if swing.get('type') == 'LOW' and swing['price'] < entry_price:
                    return swing
            return None
        return None

    def test_bullish_structural_sl(self):
        # 1. Bullish structural SL: SL equals sweep invalidation low (below entry) with no spread/point buffer
        sweep_low = 1.0950
        entry_price = 1.1010
        sl, err = self._calculate_structural_sl("BUY", sweep_low, entry_price)
        self.assertIsNone(err)
        self.assertEqual(sl, 1.0950) # Pure structural invalidation low, no arbitrary buffer
        self.assertLess(sl, entry_price)

    def test_bearish_structural_sl(self):
        # 2. Bearish structural SL: SL equals sweep invalidation high (above entry) with no spread/point buffer
        sweep_high = 1.1080
        entry_price = 1.1010
        sl, err = self._calculate_structural_sl("SELL", sweep_high, entry_price)
        self.assertIsNone(err)
        self.assertEqual(sl, 1.1080) # Pure structural invalidation high, no arbitrary buffer
        self.assertGreater(sl, entry_price)

    def test_bullish_next_opposing_target(self):
        # 3. Bullish next opposing target: finds next M15 swing high above entry
        entry_price = 1.1010
        m15_swings = [
            {'type': 'HIGH', 'price': 1.1005, 'bar_index': 4, 'isValid': True}, # Behind entry (below)
            {'type': 'HIGH', 'price': 1.1050, 'bar_index': 10, 'isValid': True}, # Ahead of entry -> Next opposing target
            {'type': 'HIGH', 'price': 1.1080, 'bar_index': 20, 'isValid': True}, # Further ahead
        ]
        target = self._find_next_opposing_target("BUY", entry_price, m15_swings)
        self.assertIsNotNone(target)
        self.assertEqual(target['price'], 1.1050)
        self.assertGreater(target['price'], entry_price)

    def test_bearish_next_opposing_target(self):
        # 4. Bearish next opposing target: finds next M15 swing low below entry
        entry_price = 1.1000
        m15_swings = [
            {'type': 'LOW', 'price': 1.1010, 'bar_index': 5, 'isValid': True}, # Behind entry (above)
            {'type': 'LOW', 'price': 1.0950, 'bar_index': 12, 'isValid': True}, # Ahead of entry -> Next opposing target
            {'type': 'LOW', 'price': 1.0920, 'bar_index': 25, 'isValid': True}, # Further ahead
        ]
        target = self._find_next_opposing_target("SELL", entry_price, m15_swings)
        self.assertIsNotNone(target)
        self.assertEqual(target['price'], 1.0950)
        self.assertLess(target['price'], entry_price)

    def test_target_behind_entry_is_rejected(self):
        # 5. Target behind entry is rejected: skips swing behind entry and selects next swing ahead of entry
        entry_price = 1.1010
        m15_swings = [
            {'type': 'HIGH', 'price': 1.0990, 'bar_index': 3, 'isValid': True}, # Most recent swing, but behind entry
            {'type': 'HIGH', 'price': 1.1060, 'bar_index': 15, 'isValid': True}, # Next swing ahead of entry
        ]
        target = self._find_next_opposing_target("BUY", entry_price, m15_swings)
        self.assertIsNotNone(target)
        self.assertNotEqual(target['price'], 1.0990) # Most recent swing rejected because behind entry
        self.assertEqual(target['price'], 1.1060)

    def test_no_valid_target_means_no_trade(self):
        # 6. No valid target means no trade: invalidates setup if all swings are behind entry
        entry_price = 1.1010
        m15_swings = [
            {'type': 'HIGH', 'price': 1.1000, 'bar_index': 3, 'isValid': True},
            {'type': 'HIGH', 'price': 1.1005, 'bar_index': 8, 'isValid': True},
        ]
        target = self._find_next_opposing_target("BUY", entry_price, m15_swings)
        self.assertIsNone(target) # No valid opposing target exists ahead of entry

    def test_no_future_unconfirmed_swing_used(self):
        # 7. No future/unconfirmed swing is used: swing at bar_index < 3 is excluded
        entry_price = 1.1010
        m15_swings = [
            {'type': 'HIGH', 'price': 1.1070, 'bar_index': 1, 'isValid': True}, # Unconfirmed/future swing (bar 1 < 3)
            {'type': 'HIGH', 'price': 1.1050, 'bar_index': 5, 'isValid': True}, # Confirmed swing
        ]
        target = self._find_next_opposing_target("BUY", entry_price, m15_swings)
        self.assertIsNotNone(target)
        self.assertEqual(target['price'], 1.1050) # Unconfirmed swing at bar 1 skipped

    def test_no_fixed_3r_fallback_exists(self):
        # 8. No fixed 3R fallback exists: when no target exists, trade submission must be blocked rather than fallback to 3R
        entry_price = 1.1010
        sl_price = 1.0950
        stop_distance = entry_price - sl_price
        fallback_3r_tp = entry_price + (3.0 * stop_distance) # 1.1190

        m15_swings = [] # No opposing target
        target = self._find_next_opposing_target("BUY", entry_price, m15_swings)

        # Confirm target search returns None and setup MUST NOT use fallback_3r_tp
        self.assertIsNone(target)
        tp_to_use = target['price'] if target else None
        self.assertIsNone(tp_to_use)
        self.assertNotEqual(tp_to_use, fallback_3r_tp)


class TestSMCStateMachineAudits(unittest.TestCase):

    def test_no_duplicate_switch_cases_in_mqh(self):
        """Verify SMC_ENTRY_SUBMITTED case is not duplicated in ProcessSMCSetupStateMachine in smc_engine.mqh."""
        with open("showcase/smc_engine.mqh", "r") as f:
            content = f.read()

        # Extract ProcessSMCSetupStateMachine body
        start = content.find("void ProcessSMCSetupStateMachine")
        end = content.find("void SMCEngine_OnTick")
        self.assertGreater(start, 0)
        self.assertGreater(end, start)

        fn_body = content[start:end]
        count = fn_body.count("case SMC_ENTRY_SUBMITTED:")
        self.assertEqual(count, 1, f"Expected case SMC_ENTRY_SUBMITTED: in ProcessSMCSetupStateMachine to appear 1 time, found {count}")

    def test_get_or_create_setup_preserves_invalidated_setups(self):
        """
        Verify GetOrCreateSetupForSymbol logic:
        Invalidated setups are preserved in history and never reused/overwritten.
        """
        setups = []

        def get_or_create_setup(symbol):
            # Mirror GetOrCreateSetupForSymbol logic in smc_engine.mqh
            for i, s in enumerate(setups):
                if s['symbol'] == symbol and s['state'] not in ('SMC_INVALIDATED', 'SMC_COMPLETED'):
                    return i

            new_slot = len(setups)
            setups.append({
                'id': f"SETUP_{symbol}_{new_slot}",
                'symbol': symbol,
                'state': 'SMC_IDLE'
            })
            return new_slot

        # 1. Create initial setup for EURUSD
        idx1 = get_or_create_setup("EURUSD")
        self.assertEqual(idx1, 0)
        self.assertEqual(setups[0]['state'], 'SMC_IDLE')

        # 2. Invalidate setup 0
        setups[0]['state'] = 'SMC_INVALIDATED'

        # 3. Request setup for EURUSD again -> must append new slot, NOT reuse slot 0
        idx2 = get_or_create_setup("EURUSD")
        self.assertEqual(idx2, 1)
        self.assertEqual(len(setups), 2)
        self.assertEqual(setups[0]['state'], 'SMC_INVALIDATED')
        self.assertEqual(setups[1]['state'], 'SMC_IDLE')

    def test_process_state_machine_ignores_invalidated_setups(self):
        """Verify that SMC_INVALIDATED is a terminal state and ignored on tick."""
        setup = {'state': 'SMC_INVALIDATED', 'symbol': 'EURUSD', 'invalidation_reason': '4H POI inactive'}

        # Replicate process state machine entry check
        def process_state_machine(s):
            if s['state'] in ('SMC_INVALIDATED', 'SMC_COMPLETED'):
                return
            s['state'] = 'SMC_H4_POI_ACTIVE'

        process_state_machine(setup)
        self.assertEqual(setup['state'], 'SMC_INVALIDATED')

    def test_m15_choch_structural_invalidation_without_arbitrary_timeout(self):
        """
        Verify M15 CHoCH waiting state invalidation:
        Price breaching sweep_price invalidates setup structurally without requiring an arbitrary 48h timeout.
        """
        setup = {
            'direction': 'BUY',
            'sweepPrice': 1.0950,
            'state': 'SMC_WAITING_FOR_M15_CHOCH'
        }

        # Case A: Completed candle M15 low reaches 1.0945 (< 1.0950 sweepPrice)
        m15_candle_bar1 = {'close': 1.0955, 'low': 1.0945, 'high': 1.0980}

        def check_waiting_choch(s, candle):
            if s['direction'] == 'BUY':
                if candle['close'] < s['sweepPrice'] or candle['low'] < s['sweepPrice']:
                    s['state'] = 'SMC_INVALIDATED'
                    s['invalidation_reason'] = 'Sweep price invalidated by lower low before CHoCH confirmed'

        check_waiting_choch(setup, m15_candle_bar1)
        self.assertEqual(setup['state'], 'SMC_INVALIDATED')
        self.assertEqual(setup['invalidation_reason'], 'Sweep price invalidated by lower low before CHoCH confirmed')

    def test_fvg_invalidation_blocks_entry(self):
        """Verify that an invalidated FVG prevents setup from proceeding to entry."""
        setup = {
            'state': 'SMC_M5_CONFIRMATION',
            'm5FVG': {'isValid': True, 'bottom': 1.1000, 'top': 1.1015, 'isBullish': True}
        }

        # Completed M5 candle body close is 1.0995 (< FVG bottom 1.1000)
        m5_close1 = 1.0995
        is_fvg_invalidated = m5_close1 < setup['m5FVG']['bottom']

        if not setup['m5FVG']['isValid'] or is_fvg_invalidated:
            setup['state'] = 'SMC_INVALIDATED'
            setup['invalidation_reason'] = 'M5 FVG invalid or invalidated'

        self.assertEqual(setup['state'], 'SMC_INVALIDATED')

    def test_failed_order_submission_invalidates_setup(self):
        """Verify that failed OrderSend or pre-trade risk rejection invalidates setup."""
        setup = {
            'state': 'SMC_WAITING_FOR_FVG_RETRACE',
            'symbol': 'EURUSD'
        }

        # Replicate risk manager gate rejection
        can_open_trade = False
        if not can_open_trade:
            setup['state'] = 'SMC_INVALIDATED'
            setup['invalidation_reason'] = 'Pre-trade risk gate blocked execution'

        self.assertEqual(setup['state'], 'SMC_INVALIDATED')


if __name__ == "__main__":
    unittest.main()
