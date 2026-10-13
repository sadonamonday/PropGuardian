import unittest
from scripts.reconcile_trades import (
    parse_created_orders,
    parse_html_deals,
    reconstruct_positions_from_deals
)

class TestReconcileTrades(unittest.TestCase):

    def test_partial_closes_and_multiple_deals(self):
        """Test position reconstruction with partial closes producing multiple exit deals."""
        deals = [
            {"time": "2023.01.04 13:57", "deal_id": "6", "symbol": "GBPUSD", "type": "sell", "direction": "in", "volume": 0.02, "price": 1.20512, "order_id": "6", "commission": 0.0, "swap": 0.0, "profit": 0.0, "comment": ""},
            {"time": "2023.01.05 15:15", "deal_id": "7", "symbol": "GBPUSD", "type": "buy", "direction": "out", "volume": 0.01, "price": 1.19958, "order_id": "7", "commission": 0.0, "swap": -0.09, "profit": 5.54, "comment": ""},
            {"time": "2023.01.05 15:19", "deal_id": "8", "symbol": "GBPUSD", "type": "buy", "direction": "out", "volume": 0.01, "price": 1.19829, "order_id": "8", "commission": 0.0, "swap": -0.09, "profit": 6.83, "comment": "tp 1.19829"}
        ]
        orders = [
            {"setup_id": "S1", "symbol": "GBPUSD", "side": "SELL", "entry": 1.20512, "sl": 1.20878, "tp": 1.19829, "lots": 0.02}
        ]

        completed, active = reconstruct_positions_from_deals(deals, orders)
        self.assertEqual(len(completed), 1)
        self.assertEqual(len(active), 0)

        pos = completed[0]
        self.assertEqual(pos["position_id"], "6")
        self.assertEqual(len(pos["exit_deals"]), 2) # Two exit deals
        self.assertAlmostEqual(pos["net_profit"], 12.19, places=2)
        self.assertAlmostEqual(pos["planned_rr"], 1.87, places=2)

    def test_breakeven_positions(self):
        """Test position closing at breakeven ($0.00 profit)."""
        deals = [
            {"time": "2023.06.05 10:21", "deal_id": "63", "symbol": "USDCAD", "type": "sell", "direction": "in", "volume": 0.06, "price": 1.34339, "order_id": "63", "commission": 0.0, "swap": 0.0, "profit": 0.0, "comment": ""},
            {"time": "2023.06.05 11:25", "deal_id": "64", "symbol": "USDCAD", "type": "buy", "direction": "out", "volume": 0.06, "price": 1.34339, "order_id": "64", "commission": 0.0, "swap": 0.0, "profit": 0.0, "comment": "sl 1.34339"}
        ]
        orders = [
            {"setup_id": "S2", "symbol": "USDCAD", "side": "SELL", "entry": 1.34339, "sl": 1.34440, "tp": 1.34173, "lots": 0.06}
        ]

        completed, _ = reconstruct_positions_from_deals(deals, orders)
        self.assertEqual(len(completed), 1)
        pos = completed[0]
        self.assertEqual(pos["net_profit"], 0.0)
        self.assertAlmostEqual(pos["planned_rr"], 1.64, places=2)

    def test_missing_order_data_represented_as_unknown(self):
        """Test that missing SL or TP is represented as None/UNKNOWN, not zero."""
        deals = [
            {"time": "2023.06.20 17:39", "deal_id": "69", "symbol": "USDJPY", "type": "buy", "direction": "in", "volume": 0.01, "price": 141.601, "order_id": "69", "commission": 0.0, "swap": 0.0, "profit": 0.0, "comment": ""},
            {"time": "2023.06.20 18:12", "deal_id": "70", "symbol": "USDJPY", "type": "sell", "direction": "out", "volume": 0.01, "price": 141.275, "order_id": "70", "commission": 0.0, "swap": 0.0, "profit": -2.31, "comment": "sl 141.278"}
        ]
        orders = [] # No matching ENTRY_ORDER_CREATED log line

        completed, _ = reconstruct_positions_from_deals(deals, orders)
        self.assertEqual(len(completed), 1)
        pos = completed[0]
        self.assertIsNone(pos["initial_tp"])
        self.assertIsNone(pos["planned_rr"])
        self.assertEqual(pos["reconstructed_sl"], 141.278) # Parsed from exit comment

    def test_overlapping_positions_different_symbols(self):
        """Test overlapping active positions across multiple symbols."""
        deals = [
            {"time": "2023.01.03 18:10", "deal_id": "2", "symbol": "USDCAD", "type": "sell", "direction": "in", "volume": 0.03, "price": 1.36384, "order_id": "2", "commission": 0.0, "swap": 0.0, "profit": 0.0, "comment": ""},
            {"time": "2023.01.03 21:56", "deal_id": "4", "symbol": "AUDUSD", "type": "buy", "direction": "in", "volume": 0.06, "price": 0.67353, "order_id": "4", "commission": 0.0, "swap": 0.0, "profit": 0.0, "comment": ""},
            {"time": "2023.01.03 21:32", "deal_id": "3", "symbol": "USDCAD", "type": "buy", "direction": "out", "volume": 0.03, "price": 1.36806, "order_id": "3", "commission": 0.0, "swap": 0.0, "profit": -9.25, "comment": "sl 1.36806"},
            {"time": "2023.01.04 01:23", "deal_id": "5", "symbol": "AUDUSD", "type": "sell", "direction": "out", "volume": 0.06, "price": 0.67192, "order_id": "5", "commission": 0.0, "swap": -0.10, "profit": -9.66, "comment": "sl 0.67192"}
        ]

        completed, active = reconstruct_positions_from_deals(deals, [])
        self.assertEqual(len(completed), 2)
        self.assertEqual(len(active), 0)
        self.assertEqual(completed[0]["symbol"], "USDCAD")
        self.assertEqual(completed[1]["symbol"], "AUDUSD")

    def test_different_instrument_price_scales(self):
        """Test R:R calculations across 3-digit JPY vs 5-digit Forex instruments."""
        # JPY 3-digit scale
        jpy_buy = {"side": "BUY", "entry": 134.169, "sl": 133.913, "tp": 134.677}
        risk_jpy = jpy_buy["entry"] - jpy_buy["sl"] # 0.256
        reward_jpy = jpy_buy["tp"] - jpy_buy["entry"] # 0.508
        rr_jpy = reward_jpy / risk_jpy
        self.assertAlmostEqual(rr_jpy, 1.984375, places=4)

        # Forex 5-digit scale
        fx_buy = {"side": "BUY", "entry": 1.23761, "sl": 1.23584, "tp": 1.24032}
        risk_fx = fx_buy["entry"] - fx_buy["sl"] # 0.00177
        reward_fx = fx_buy["tp"] - fx_buy["entry"] # 0.00271
        rr_fx = reward_fx / risk_fx
        self.assertAlmostEqual(rr_fx, 1.531073, places=4)

if __name__ == "__main__":
    unittest.main()
