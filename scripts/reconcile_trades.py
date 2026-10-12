import re, json

with open("logs/ReportTester-169371460.html", "r", encoding="utf-16", errors="ignore") as f:
    html = f.read()
if "<html>" not in html and "<html" not in html:
    with open("logs/ReportTester-169371460.html", "r", encoding="utf-8", errors="ignore") as f:
        html = f.read()

with open("logs/20261012.log", "r", encoding="utf-16", errors="ignore") as f:
    log_content = f.read()

created_orders = []
for line in log_content.splitlines():
    if "ENTRY_ORDER_CREATED" in line:
        m = re.search(r"\[(SETUP_[^\]]+)\]\s+\[([^\]]+)\]\s+ENTRY_ORDER_CREATED\s+\|\s+(BUY|SELL)\s+Limit at ([\d\.]+),\s+SL ([\d\.]+),\s+TP ([\d\.]+),\s+Lots ([\d\.]+)", line)
        if m:
            setup_id, symbol, side, entry, sl, tp, lots = m.groups()
            created_orders.append({
                "setup_id": setup_id, "symbol": symbol, "side": side,
                "entry": float(entry), "sl": float(sl), "tp": float(tp), "lots": float(lots)
            })

rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.DOTALL | re.IGNORECASE)
deals = []
start = False
for r in rows:
    cols = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", r, re.DOTALL | re.IGNORECASE)
    cols = [re.sub(r"<[^>]+>", "", c).strip() for c in cols]
    if len(cols) >= 10 and cols[0] == "Time":
        start = True
        continue
    if start and len(cols) >= 12:
        deals.append(cols)

positions = []
curr_pos = None

for d in deals:
    time, deal_id, symbol, dtype, direction, vol, price, order_id, comm, swap, profit, balance, comment = d[:13]
    if dtype == "balance": continue
    vol = float(vol)
    price = float(price)
    profit = float(profit)
    swap = float(swap)
    comm = float(comm)
    net_p = profit + swap + comm

    if direction == "in":
        if curr_pos: positions.append(curr_pos)
        curr_pos = {
            "pos_num": len(positions) + 1,
            "symbol": symbol,
            "side": dtype,
            "entry_time": time,
            "entry_price": price,
            "volume": vol,
            "exits": [],
            "net_profit": 0.0,
            "comments": []
        }
    elif direction == "out" and curr_pos:
        curr_pos["exits"].append({
            "time": time, "price": price, "volume": vol, "profit": net_p, "comment": comment
        })
        curr_pos["net_profit"] += net_p
        if comment: curr_pos["comments"].append(comment)

if curr_pos: positions.append(curr_pos)

print(f"Total reconstructed positions: {len(positions)}")

order_idx = 0
for p in positions:
    matched_o = None
    for idx in range(order_idx, len(created_orders)):
        o = created_orders[idx]
        if o["symbol"] == p["symbol"] and abs(o["entry"] - p["entry_price"]) < 0.0005:
            matched_o = o
            order_idx = idx + 1
            break

    if matched_o:
        p["initial_entry"] = matched_o["entry"]
        p["initial_sl"] = matched_o["sl"]
        p["initial_tp"] = matched_o["tp"]
        p["side_upper"] = matched_o["side"]
    else:
        sl_val = None
        for ex in p["exits"]:
            m = re.search(r"sl ([\d\.]+)", ex["comment"])
            if m: sl_val = float(m.group(1))
        p["initial_entry"] = p["entry_price"]
        p["initial_sl"] = sl_val
        p["initial_tp"] = None
        p["side_upper"] = p["side"].upper()

    entry = p["initial_entry"]
    sl = p["initial_sl"]
    tp = p["initial_tp"]

    if p["side_upper"] == "BUY":
        risk = entry - sl if (entry and sl) else 0.0
        reward = tp - entry if (tp and entry) else 0.0
    else:
        risk = sl - entry if (sl and entry) else 0.0
        reward = entry - tp if (entry and tp) else 0.0

    p["planned_risk"] = risk
    p["planned_reward"] = reward
    p["planned_rr"] = reward / risk if risk > 0 else 0.0

print("\n=== RECONCILED POSITIONS WITH EXACT PLANNED R:R ===")
for p in positions:
    tp_str = f"{p['initial_tp']:.5f}" if p['initial_tp'] else "N/A"
    sl_str = f"{p['initial_sl']:.5f}" if p['initial_sl'] else "N/A"
    print(f"Pos #{p['pos_num']:2d} | {p['symbol']} {p['side_upper']:4s} | Entry={p['initial_entry']:.5f} | SL={sl_str} | TP={tp_str} | Risk={p['planned_risk']:.5f} | Reward={p['planned_reward']:.5f} | Planned R:R={p['planned_rr']:.2f} | Net PnL=${p['net_profit']:.2f}")

# Stats on wins/losses
pos_wins = [p for p in positions if p["net_profit"] > 0]
pos_losses = [p for p in positions if p["net_profit"] < 0]
pos_zeros = [p for p in positions if p["net_profit"] == 0]

print(f"\nPosition Statistics:")
print(f"Total Positions: {len(positions)}")
print(f"Winning Positions (> $0.00): {len(pos_wins)}")
print(f"Losing Positions (< $0.00): {len(pos_losses)}")
print(f"Breakeven Positions ($0.00): {len(pos_zeros)}")
