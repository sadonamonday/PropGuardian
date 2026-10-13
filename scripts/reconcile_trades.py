import re
import json

def parse_created_orders(log_content):
    """
    Extracts initial order parameters from ENTRY_ORDER_CREATED log lines.
    Returns list of dicts with setup_id, symbol, side, entry, sl, tp, lots.
    """
    created_orders = []
    for line in log_content.splitlines():
        if "ENTRY_ORDER_CREATED" in line:
            m = re.search(r"\[(SETUP_[^\]]+)\]\s+\[([^\]]+)\]\s+ENTRY_ORDER_CREATED\s+\|\s+(BUY|SELL)\s+Limit at ([\d\.]+),\s+SL ([\d\.]+),\s+TP ([\d\.]+),\s+Lots ([\d\.]+)", line)
            if m:
                setup_id, symbol, side, entry, sl, tp, lots = m.groups()
                created_orders.append({
                    "setup_id": setup_id,
                    "symbol": symbol,
                    "side": side.upper(),
                    "entry": float(entry),
                    "sl": float(sl) if float(sl) > 0 else None,
                    "tp": float(tp) if float(tp) > 0 else None,
                    "lots": float(lots)
                })
    return created_orders

def parse_html_deals(html_content):
    """
    Parses MT5 Strategy Tester deal rows from HTML content.
    Returns list of deal dicts.
    """
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html_content, re.DOTALL | re.IGNORECASE)
    deals = []
    start = False
    for r in rows:
        cols = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", r, re.DOTALL | re.IGNORECASE)
        cols = [re.sub(r"<[^>]+>", "", c).strip() for c in cols]
        if len(cols) >= 10 and cols[0] == "Time":
            start = True
            continue
        if start and len(cols) >= 12:
            time, deal_id, symbol, dtype, direction, vol, price, order_id, comm, swap, profit, balance, comment = cols[:13]
            if dtype == "balance":
                continue
            deals.append({
                "time": time,
                "deal_id": deal_id,
                "symbol": symbol,
                "type": dtype.lower(),
                "direction": direction.lower(),
                "volume": float(vol) if vol else 0.0,
                "price": float(price) if price else 0.0,
                "order_id": order_id,
                "commission": float(comm) if comm else 0.0,
                "swap": float(swap) if swap else 0.0,
                "profit": float(profit) if profit else 0.0,
                "comment": comment
            })
    return deals

def reconstruct_positions_from_deals(deals, created_orders=None):
    """
    Reconstructs complete positions from deals using position ID tracking.
    Handles partial closes, multiple exit deals, overlapping positions, and missing order data.
    """
    active_positions = {}
    completed_positions = []
    order_match_index = 0
    created_orders = created_orders or []

    for d in deals:
        symbol = d["symbol"]
        net_deal_profit = d["profit"] + d["swap"] + d["commission"]

        if d["direction"] == "in":
            # In MT5 Strategy Tester, position_id equals the entry order_id
            pos_id = d["order_id"]
            side = d["type"].upper()

            # Match initial order parameters if available
            initial_sl = None
            initial_tp = None
            matched_setup_id = None

            for idx in range(order_match_index, len(created_orders)):
                o = created_orders[idx]
                if o["symbol"] == symbol and abs(o["entry"] - d["price"]) < 0.0005:
                    initial_sl = o["sl"]
                    initial_tp = o["tp"]
                    matched_setup_id = o["setup_id"]
                    order_match_index = idx + 1
                    break

            active_positions[pos_id] = {
                "position_id": pos_id,
                "symbol": symbol,
                "side": side,
                "entry_deal_id": d["deal_id"],
                "entry_time": d["time"],
                "entry_price": d["price"],
                "initial_volume": d["volume"],
                "remaining_volume": d["volume"],
                "initial_sl": initial_sl,
                "initial_tp": initial_tp,
                "setup_id": matched_setup_id,
                "exit_deals": [],
                "gross_profit": 0.0,
                "swaps": 0.0,
                "commissions": 0.0,
                "net_profit": 0.0,
                "comments": []
            }
        elif d["direction"] == "out":
            # Match exit deal to the oldest active position for this symbol
            matched_id = None
            for pid, pos in active_positions.items():
                if pos["symbol"] == symbol and pos["remaining_volume"] > 1e-6:
                    matched_id = pid
                    break

            if matched_id:
                pos = active_positions[matched_id]
                pos["exit_deals"].append(d)
                pos["gross_profit"] += d["profit"]
                pos["swaps"] += d["swap"]
                pos["commissions"] += d["commission"]
                pos["net_profit"] += net_deal_profit
                pos["remaining_volume"] -= d["volume"]
                if d["comment"]:
                    pos["comments"].append(d["comment"])

                if pos["remaining_volume"] <= 1e-6:
                    completed_positions.append(pos)
                    del active_positions[matched_id]

    # Calculate planned Risk, Reward, and R:R
    for p in completed_positions:
        entry = p["entry_price"]
        sl = p["initial_sl"]
        tp = p["initial_tp"]

        # Parse SL from exit comments if initial_sl missing
        if sl is None:
            for c in p["comments"]:
                m = re.search(r"sl ([\d\.]+)", c)
                if m:
                    sl = float(m.group(1))
                    break

        p["reconstructed_sl"] = sl
        p["reconstructed_tp"] = tp

        if sl is None or tp is None:
            p["planned_risk"] = None
            p["planned_reward"] = None
            p["planned_rr"] = None
        else:
            if p["side"] == "BUY":
                p["planned_risk"] = entry - sl
                p["planned_reward"] = tp - entry
            else: # SELL
                p["planned_risk"] = sl - entry
                p["planned_reward"] = entry - tp

            if p["planned_risk"] > 0 and p["planned_reward"] >= 0:
                p["planned_rr"] = p["planned_reward"] / p["planned_risk"]
            else:
                p["planned_rr"] = None

    return completed_positions, list(active_positions.values())

def main():
    try:
        with open("logs/ReportTester-169371460.html", "r", encoding="utf-16", errors="ignore") as f:
            html = f.read()
    except Exception:
        with open("logs/ReportTester-169371460.html", "r", encoding="utf-8", errors="ignore") as f:
            html = f.read()

    with open("logs/20261012.log", "r", encoding="utf-16", errors="ignore") as f:
        log_content = f.read()

    created_orders = parse_created_orders(log_content)
    deals = parse_html_deals(html)
    completed_positions, active_positions = reconstruct_positions_from_deals(deals, created_orders)

    print(f"Total reconstructed positions: {len(completed_positions)}")
    print(f"Remaining active positions: {len(active_positions)}")

    print("\n=== RECONCILED POSITIONS SUMMARY ===")
    for idx, p in enumerate(completed_positions, 1):
        sl_str = f"{p['reconstructed_sl']:.5f}" if p['reconstructed_sl'] is not None else "UNKNOWN"
        tp_str = f"{p['reconstructed_tp']:.5f}" if p['reconstructed_tp'] is not None else "UNKNOWN"
        rr_str = f"{p['planned_rr']:.2f}" if p['planned_rr'] is not None else "UNKNOWN"
        print(f"Pos #{idx:2d} | Ticket #{p['position_id']} | {p['symbol']} {p['side']:4s} | Entry={p['entry_price']:.5f} | SL={sl_str} | TP={tp_str} | Planned R:R={rr_str} | Net PnL=${p['net_profit']:.2f}")

if __name__ == "__main__":
    main()
