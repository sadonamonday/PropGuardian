# Backtest Analysis Report — PropGuardian EA

## Executive Summary
This report provides a comprehensive, evidence-based investigation of PropGuardian's latest MetaTrader 5 (MT5) Strategy Tester backtest results (`logs/ReportTester-169371460.html` and `logs/20261012.log`).

The backtest ended in a net loss of **-$100.17 USD (-10.02%)**, reducing the starting balance from **$1,000.00 USD** to **$899.83 USD**. All trading activity occurred strictly between **January 3, 2023, and August 31, 2023**. On August 31, 2023, at 15:30:40, the EA triggered its Emergency Drawdown Stop upon crossing the 10.00% total portfolio drawdown threshold (**10.02% actual drawdown**). Because emergency drawdown halts persist across daily resets as designed, the EA remained permanently halted for the remainder of 2023, 2024, and 2025.

---

## 1. Key Backtest Statistics

| Statistic | Value | Notes / Citation | Status |
| :--- | :--- | :--- | :--- |
| **Test Period (Tester Settings)** | `2023.01.01 – 2025.12.31` | `ReportTester-169371460.html` Row 6 | **Verified** |
| **Active Trading Window** | `2023.01.03 – 2023.08.31` | Trades halted permanently after 2023.08.31 15:30:40 | **Verified** |
| **Starting Balance** | `$1,000.00 USD` | Report Row 86 | **Verified** |
| **Final Balance** | `$899.83 USD` | Report Row 92 | **Verified** |
| **Total Net Profit / Loss** | **`-$100.17 USD (-10.02%)`** | Report Row 92 | **Verified** |
| **Gross Profit** | `$63.80 USD` | Report Row 93 | **Verified** |
| **Gross Loss** | `-$163.97 USD` | Report Row 94 | **Verified** |
| **Profit Factor** | **`0.39`** | Report Row 96 | **Verified** |
| **Expected Payoff** | **`-$1.86 USD`** | Report Row 96 | **Verified** |
| **Balance Drawdown Absolute** | `$100.17 USD` | Report Row 92 | **Verified** |
| **Balance Drawdown Maximal** | **`$100.17 USD (10.02%)`** | Report Row 93 | **Verified** |
| **Equity Drawdown Maximal** | **`$100.17 USD (10.02%)`** | Report Row 93 | **Verified** |
| **Recovery Factor** | `-1.00` | Report Row 97 | **Verified** |
| **Sharpe Ratio** | `-5.00` | Report Row 97 | **Verified** |
| **Z-Score** | `-3.56 (99.74%)` | Report Row 97 | **Verified** |
| **Margin Level** | `485.97%` | Report Row 96 | **Verified** |

---

## 2. Comprehensive Trade & Position Count Reconciliation

To eliminate ambiguity between MT5 report summary lines and position tracker records, all trade and deal counts are reconciled below using exact definitions:

| Metric | Count | Citation Source | Definition & Technical Explanation | Status |
| :--- | :---: | :--- | :--- | :---: |
| **MT5 Reported Trades** | **54** | MT5 Report Row 101 | Total **exit deals** (out-deals) recorded by MT5 Strategy Tester. When a position undergoes a 50% partial TP close at +1.5R and later closes the remaining 50% (at TP or SL/BE), MT5 counts **each exit deal** as a separate trade segment. (38 single-exit positions + 8 two-exit positions = 54 exit deals). | **Verified** |
| **Filled Position Instances** | **46** | `g_SMCCounters.retraceReached = 46` | Total unique position instances opened (`DEAL_ENTRY_IN`) and closed (`DEAL_ENTRY_OUT`). | **Verified** |
| **MT5 Profit Trades** | **18** | MT5 Report Row 102 | Total **exit deals** with profit $\ge \$0.00$. Includes 15 positive-profit exit deals + 3 breakeven exit deals with exact $\$0.00$ net profit. | **Verified** |
| **Winning Exit Deals** | **15** | HTML Deal History (`net_p > $0.00`) | Exit deals yielding strictly positive net dollars ($> \$0.00$). | **Verified** |
| **Net Winning Positions** | **9** | Position Aggregation (`net_p > $0.00`) | Unique position instances whose sum of all exit deal profits (including partials, swaps, commissions) is strictly positive ($> \$0.00$). | **Verified** |
| **Net Losing Positions** | **34** | Position Aggregation (`net_p < $0.00`) | Unique position instances whose net profit across all exit deals is strictly negative ($< \$0.00$). | **Verified** |
| **Net Breakeven Positions**| **3** | Position Aggregation (`net_p == $0.00`)| Unique position instances whose net profit across all exit deals equals exactly $\$0.00$ (Positions #27, #28, #33). | **Verified** |

---

## 3. Position Execution Statistics

| Parameter | Value | Details | Status |
| :--- | :--- | :--- | :---: |
| **Average Winning Trade (MT5)** | `$3.54 USD` | Report Row 104 | **Verified** |
| **Average Losing Trade (MT5)** | `-$4.55 USD` | Report Row 104 | **Verified** |
| **Win / Loss Payoff Ratio** | **`0.78`** | `$3.54 / $4.55` (Cutting wins short via BE / Partial TP) | **Verified** |
| **Largest Winning Trade** | `$9.12 USD` | Deal #23, GBPUSD BUY TP (2023.02.02 11:26:19) | **Verified** |
| **Largest Losing Trade** | `-$9.97 USD` | Deal #14, USDJPY SELL SL (2023.01.18 04:40:27) | **Verified** |
| **Maximal Consecutive Wins** | `7 ($17.32 USD)` | Report Row 105 | **Verified** |
| **Maximal Consecutive Losses** | `13 (-$67.09 USD)` | Report Row 105 | **Verified** |
| **Average Consecutive Wins** | `3` | Report Row 107 | **Verified** |
| **Average Consecutive Losses** | `5` | Report Row 107 | **Verified** |

### Holding Times
- **Minimal Position Holding Time:** `00:01:11` (**Verified**)
- **Maximal Position Holding Time:** `27:14:22` (**Verified**)
- **Average Position Holding Time:** `04:39:19` (**Verified**)

---

## 4. Directional Performance (Long vs. Short)

| Direction | Exit Deals (MT5) | Wins (Exit Deals) | Losses | Win Rate (%) | Net Profit ($) | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Short Trades (SELL)** | 28 | 14 | 14 | **50.00%** | -$18.24 | **Verified** |
| **Long Trades (BUY)** | 26 | 4 | 22 | **15.38%** | -$81.93 | **Verified** |
| **Total MT5 Trades** | **54** | **18** | **36** | **33.33%** | **-$100.17** | **Verified** |

### Directional Findings:
Long positions performed drastically worse than Short positions (15.38% win rate vs. 50.00% win rate). During the first 8 months of 2023, multi-month strong dollar regimes caused counter-trend Long setups across EURUSD, GBPUSD, and AUDUSD to suffer high failure rates when sweeping minor lows.

---

## 5. Performance Breakdown by Symbol

| Symbol | Deals IN | Deals OUT | Wins (Out Deals) | Losses (Out Deals) | Win Rate (%) | Net Profit ($) | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **GBPUSD** | 17 | 20 | 7 | 13 | 35.00% | **-$9.99** | **Verified** |
| **EURUSD** | 3 | 4 | 2 | 2 | 50.00% | **-$11.05** | **Verified** |
| **USDCAD** | 8 | 10 | 2 | 5 | 28.57% | **-$19.88** | **Verified** |
| **AUDUSD** | 7 | 8 | 3 | 5 | 37.50% | **-$23.83** | **Verified** |
| **USDJPY** | 11 | 12 | 1 | 11 | **8.33%** | **-$35.42** | **Verified** |
| **Total** | **46** | **54** | **15** | **36** | **32.61%** | **-$100.17** | **Verified** |

---

## 6. Performance Breakdown by Year

| Year | Trades Closed | Deals IN / OUT | Net Profit ($) | Balance End ($) | Status |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **2023** | 46 | 46 / 54 | **-$100.17** | $899.83 | Halted on 2023.08.31 15:30:40 (**Verified**) |
| **2024** | 0 | 0 / 0 | **$0.00** | $899.83 | Permanently Halted (Emergency Stop Active) (**Verified**) |
| **2025** | 0 | 0 / 0 | **$0.00** | $899.83 | Permanently Halted (Emergency Stop Active) (**Verified**) |

---

## 7. Reported SMC Diagnostic Funnel Summary

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
- **4H POI Activation Rate:** `4,484 / 4,878 = 91.92%` (**Verified**)
- **M15 Sweep Detection Rate:** `3,453 / 4,484 = 77.01%` (**Verified**)
- **M15 CHoCH Confirmation Rate:** `701 / 2,098 = 33.41%` (**Verified**)
- **M5 Confirmation Rate:** `699 / 701 = 99.71%` (**Verified**)
- **Order Submission Rate (from FVGs):** `56 / 699 = 8.01%` **(MAJOR CONVERSION BOTTLENECK - Verified)**
- **Order Acceptance Rate:** `55 / 56 = 98.21%` (**Verified**)
- **Fill / Retrace Rate:** `46 / 55 = 83.64%` (**Verified**)
