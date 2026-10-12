# Backtest Analysis Report — PropGuardian EA

## Executive Summary
This report provides a comprehensive, evidence-based investigation of PropGuardian's latest MetaTrader 5 (MT5) Strategy Tester backtest results (`logs/ReportTester-169371460.html` and `logs/20261012.log`).

The backtest ended in a net loss of **-$100.17 USD (-10.02%)**, reducing the starting balance from **$1,000.00 USD** to **$899.83 USD**. All trading activity occurred strictly between **January 3, 2023, and August 31, 2023**. On August 31, 2023, at 15:30:40, the EA triggered its Emergency Drawdown Stop upon crossing the 10.00% total portfolio drawdown threshold (**10.02% actual drawdown**). Because emergency drawdown halts persist across daily resets as designed, the EA remained permanently halted for the remainder of 2023, 2024, and 2025.

---

## 1. Key Backtest Statistics

| Statistic | Value | Notes / Citation |
| :--- | :--- | :--- |
| **Test Period (Tester Settings)** | `2023.01.01 – 2025.12.31` | `ReportTester-169371460.html` Row 6 |
| **Active Trading Window** | `2023.01.03 – 2023.08.31` | Trades halted permanently after 2023.08.31 15:30:40 |
| **Starting Balance** | `$1,000.00 USD` | Report Row 86 |
| **Final Balance** | `$899.83 USD` | Report Row 92 |
| **Total Net Profit / Loss** | **`-$100.17 USD (-10.02%)`** | Report Row 92 |
| **Gross Profit** | `$63.80 USD` | Report Row 93 |
| **Gross Loss** | `-$163.97 USD` | Report Row 94 |
| **Profit Factor** | **`0.39`** | Report Row 96 |
| **Expected Payoff** | **`-$1.86 USD`** | Report Row 96 |
| **Balance Drawdown Absolute** | `$100.17 USD` | Report Row 92 |
| **Balance Drawdown Maximal** | **`$100.17 USD (10.02%)`** | Report Row 93 |
| **Equity Drawdown Maximal** | **`$100.17 USD (10.02%)`** | Report Row 93 |
| **Recovery Factor** | `-1.00` | Report Row 97 |
| **Sharpe Ratio** | `-5.00` | Report Row 97 |
| **Z-Score** | `-3.56 (99.74%)` | Report Row 97 |
| **Margin Level** | `485.97%` | Report Row 96 |

---

## 2. Trade & Deal Execution Performance

| Parameter | Value | Details |
| :--- | :--- | :--- |
| **Total Trades (MT5 Report)** | `54` | Combines 46 completed position outcomes & partials |
| **Total Deals (MT5 Report)** | `100` | 46 IN deals, 54 OUT deals (plus 1 initial deposit) |
| **Filled Positions (Reconstructed)** | `46` | Matches `g_SMCCounters.retraceReached` = 46 |
| **Winning Trades (Profit Trades)** | `18 (33.33%)` | Report Row 102 |
| **Losing Trades (Loss Trades)** | `36 (66.67%)` | Report Row 102 |
| **Average Winning Trade** | `$3.54 USD` | Report Row 104 |
| **Average Losing Trade** | `-$4.55 USD` | Report Row 104 |
| **Win / Loss Payoff Ratio** | **`0.78`** | `$3.54 / $4.55` (Cutting wins short via BE / Partial TP) |
| **Largest Winning Trade** | `$9.12 USD` | Deal #23, GBPUSD BUY TP (2023.02.02 11:26:19) |
| **Largest Losing Trade** | `-$9.97 USD` | Deal #14, USDJPY SELL SL (2023.01.18 04:40:27) |
| **Maximal Consecutive Wins** | `7 ($17.32 USD)` | Report Row 105 |
| **Maximal Consecutive Losses** | `13 (-$67.09 USD)` | Report Row 105 |
| **Average Consecutive Wins** | `3` | Report Row 107 |
| **Average Consecutive Losses** | `5` | Report Row 107 |

### Holding Times
- **Minimal Position Holding Time:** `00:01:11`
- **Maximal Position Holding Time:** `27:14:22`
- **Average Position Holding Time:** `04:39:19`

---

## 3. Directional Performance (Long vs. Short)

| Direction | Trades | Wins | Losses | Win Rate (%) | Net Profit ($) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Short Trades (SELL)** | 28 | 14 | 14 | **50.00%** | -$18.24 |
| **Long Trades (BUY)** | 26 | 4 | 22 | **15.38%** | -$81.93 |
| **Total** | **54** | **18** | **36** | **33.33%** | **-$100.17** |

### Key Observation:
Long trades performed drastically worse than Short trades (15.38% win rate vs. 50.00% win rate). During the first 8 months of 2023, multi-month strong dollar regimes caused counter-trend Long setups across EURUSD, GBPUSD, and AUDUSD to suffer high failure rates when sweeping minor lows.

---

## 4. Performance Breakdown by Symbol

| Symbol | Deals IN | Deals OUT | Wins | Losses | Win Rate (%) | Net Profit ($) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **GBPUSD** | 17 | 20 | 7 | 13 | 35.00% | **-$9.99** |
| **EURUSD** | 3 | 4 | 2 | 2 | 50.00% | **-$11.05** |
| **USDCAD** | 8 | 10 | 2 | 5 | 28.57% | **-$19.88** |
| **AUDUSD** | 7 | 8 | 3 | 5 | 37.50% | **-$23.83** |
| **USDJPY** | 11 | 12 | 1 | 11 | **8.33%** | **-$35.42** |
| **Total** | **46** | **54** | **15** | **36** | **32.61%** | **-$100.17** |

### Key Findings by Symbol:
1. **USDJPY was the primary drag on account equity**, accounting for **$35.42 (35.36%)** of total net loss with 11 losses out of 12 closed deal exits. Tight structural SLs without spread buffers were repeatedly stopped out by JPY spread widening.
2. **AUDUSD and USDCAD combined for -$43.71 in losses**, driven by choppy structural target scanning and premature break-even triggering.
3. **GBPUSD was the most active symbol (17 trades)**, generating $14.30 gross win on Feb 2, 2023, but suffering multiple consecutive small losses during summer choppy range environments.

---

## 5. Performance Breakdown by Year

| Year | Trades Closed | Deals IN / OUT | Net Profit ($) | Balance End ($) | Status |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **2023** | 46 | 46 / 54 | **-$100.17** | $899.83 | Halted on 2023.08.31 15:30:40 |
| **2024** | 0 | 0 / 0 | **$0.00** | $899.83 | Permanently Halted (Emergency Stop Active) |
| **2025** | 0 | 0 / 0 | **$0.00** | $899.83 | Permanently Halted (Emergency Stop Active) |

---

## 6. Reported SMC Diagnostic Funnel Summary

The terminal diagnostic report printed upon emergency shutdown (`logs/20261012.log` at `2023.08.31 15:30:40`) summarizes the multi-timeframe SMC funnel:

```
[SMC_DIAGNOSTIC] --- Funnel Diagnostic Report ---
[SMC_DIAGNOSTIC] Symbol: EURUSD | Time: 2023.08.31 15:30 | Test Period Start: 2022.01.03
[SMC_DIAGNOSTIC] POIs Detected: 4878 | Activated: 4484
[SMC_DIAGNOSTIC] Sweeps Detected: 3453
[SMC_DIAGNOSTIC] CHoCH Candidates: 2098 | Confirmed: 701 | Rejected/Invalidated: 1355
[SMC_DIAGNOSTIC] M5 Confirmed: 699 | FVGs Detected: 699 | FVGs Invalidated: 93
[SMC_DIAGNOSTIC] Retrace Reached: 46 | No Chase Triggered: 0
[SMC_DIAGNOSTIC] Orders Submitted: 56 | Accepted: 55 | Rejected: 1 | Expired: 3
[SMC_DIAGNOSTIC] Trades Closed: 46
[SMC_DIAGNOSTIC] Invalidated After CHoCH: 0
[SMC_DIAGNOSTIC] Expired Waiting Sweep: 125 | Expired Waiting M5: 0 | POI Revalidation Failed: 207
```

### Funnel Conversion Rates:
- **4H POI Activation Rate:** `4,484 / 4,878 = 91.92%`
- **M15 Sweep Detection Rate:** `3,453 / 4,484 = 77.01%`
- **M15 CHoCH Confirmation Rate:** `701 / 2,098 = 33.41%`
- **M5 Confirmation Rate:** `699 / 701 = 99.71%`
- **Order Submission Rate (from FVGs):** `56 / 699 = 8.01%` **(MAJOR CONVERSION BOTTLENECK)**
- **Order Acceptance Rate:** `55 / 56 = 98.21%`
- **Fill / Retrace Rate:** `46 / 55 = 83.64%`
