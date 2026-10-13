import sys
from html.parser import HTMLParser
from collections import defaultdict

class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows = []
        self.curr = []
        self.in_cell = False
    def handle_starttag(self, tag, attrs):
        if tag in ['td', 'th']: self.in_cell = True
        elif tag == 'tr': self.curr = []
    def handle_endtag(self, tag):
        if tag in ['td', 'th']: self.in_cell = False
        elif tag == 'tr':
            if self.curr: self.rows.append(self.curr)
    def handle_data(self, data):
        if self.in_cell and data.strip():
            self.curr.append(data.strip())

def analyze(path):
    p = ReportParser()
    with open(path, 'r', encoding='utf-16', errors='ignore') as f:
        p.feed(f.read())

    mode = None
    deals = []
    orders = []
    for r in p.rows:
        if 'Orders' in r and len(r) <= 2: mode = 'orders'; continue
        if 'Deals' in r and len(r) <= 2: mode = 'deals'; continue
        if mode == 'deals' and len(r) >= 10 and r[0] != 'Time':
            deals.append(r)
        elif mode == 'orders' and len(r) >= 8 and r[0] != 'Open Time':
            orders.append(r)

    print(f'=== {path} DETAILED SUMMARY ===')
    by_symbol = defaultdict(lambda: {'deals': 0, 'profit': 0.0, 'wins': 0, 'losses': 0, 'gross_win': 0.0, 'gross_loss': 0.0})
    by_month = defaultdict(lambda: {'deals': 0, 'profit': 0.0, 'wins': 0, 'losses': 0})
    by_cat = defaultdict(lambda: {'deals': 0, 'profit': 0.0, 'wins': 0, 'losses': 0})

    total_exit_deals = 0
    total_profit = 0.0

    for d in deals:
        if len(d) >= 11 and d[4] == 'out':
            symbol = d[2]
            profit = float(d[10].replace(' ', '').replace('\xa0', '').replace(',', ''))
            time_str = d[0]
            month_str = time_str[:7]
            comment = d[12] if len(d) > 12 else ''

            cat = 'Other'
            if comment.startswith('sl'): cat = 'SL'
            elif comment.startswith('tp'): cat = 'TP'
            elif comment.startswith('be'): cat = 'BE'
            elif 'trail' in comment.lower(): cat = 'Trailing Stop'

            total_exit_deals += 1
            total_profit += profit

            by_symbol[symbol]['deals'] += 1
            by_symbol[symbol]['profit'] += profit

            by_month[month_str]['deals'] += 1
            by_month[month_str]['profit'] += profit

            by_cat[cat]['deals'] += 1
            by_cat[cat]['profit'] += profit

            if profit >= 0:
                by_symbol[symbol]['wins'] += 1
                by_symbol[symbol]['gross_win'] += profit
                by_month[month_str]['wins'] += 1
                by_cat[cat]['wins'] += 1
            else:
                by_symbol[symbol]['losses'] += 1
                by_symbol[symbol]['gross_loss'] += profit
                by_month[month_str]['losses'] += 1
                by_cat[cat]['losses'] += 1

    print(f'Total Exit Deals: {total_exit_deals}')
    print(f'Total Profit across Exit Deals: ${total_profit:.2f}')

    print('\nBY SYMBOL:')
    for sym, data in sorted(by_symbol.items()):
        wr = (data['wins'] / data['deals'] * 100) if data['deals'] > 0 else 0
        avg_w = (data['gross_win'] / data['wins']) if data['wins'] > 0 else 0
        avg_l = (data['gross_loss'] / data['losses']) if data['losses'] > 0 else 0
        print(f"  {sym:6s}: Deals={data['deals']:3d} | Net Profit=${data['profit']:8.2f} | WinRate={wr:5.1f}% (W:{data['wins']} L:{data['losses']}) | Avg W:${avg_w:5.2f} | Avg L:${avg_l:5.2f}")

    print('\nBY MONTH:')
    for m, data in sorted(by_month.items()):
        wr = (data['wins'] / data['deals'] * 100) if data['deals'] > 0 else 0
        print(f"  {m}: Deals={data['deals']:3d} | Net Profit=${data['profit']:8.2f} | WinRate={wr:5.1f}% (W:{data['wins']} L:{data['losses']})")

    print('\nBY EXIT CATEGORY:')
    for c, data in sorted(by_cat.items()):
        wr = (data['wins'] / data['deals'] * 100) if data['deals'] > 0 else 0
        avg_p = data['profit'] / data['deals'] if data['deals'] > 0 else 0
        print(f"  Category '{c:15s}': Deals={data['deals']:3d} | Net Profit=${data['profit']:8.2f} | WinRate={wr:5.1f}% (W:{data['wins']} L:{data['losses']}) | Avg Profit:${avg_p:5.2f}")

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'logs/ReportTester-169371460f.html'
    analyze(target)
