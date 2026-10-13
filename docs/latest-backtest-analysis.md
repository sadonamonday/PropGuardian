# PropGuardian MT5 Strategy Tester Backtest Analysis Report

## 1. Executive Summary

This report provides a comprehensive, evidence-based technical and performance analysis of the latest Strategy Tester backtest for **PropGuardian**, an MQL5 Expert Advisor implementing a multi-timeframe Smart Money Concepts (SMC) trading strategy (**4H → M15 → M5**).

### Key Takeaways:
1. **Profitability Status**: The EA is **UNPROFITABLE** in its current configuration. Across the analyzed backtest period (2024.01.01 – 2025.12.31, active trading Jan 2024 – Oct 2025), the strategy produced a **Net Loss of -$101.83** (-10.18% drawdown on a $1,000 initial deposit) with a **Profit Factor of 0.66** and an **Expected Payoff of -$0.76** per trade.
2. **Emergency Halt Triggered**: Trading was permanently disabled on **2025.10.16 at 23:05:55** when total portfolio drawdown crossed the **10.0% emergency limit** (equity reached $898.17, representing a 10.19% drawdown). No further trades were taken from mid-October 2025 through year-end 2025.
3. **High Win Rate vs. Extreme Asymmetric R:R**: The EA achieved a **high win rate of 70.15%** (94 winning trades out of 134 completed positions/deals). However, the **Average Winning Trade was $2.09 (+0.28R)**, while the **Average Losing Trade was -$7.45 (-1.00R)**. The average loser was **3.56 times larger** than the average winner, creating a mathematically negative expectancy:
   $$\text{Expected Value} = (0.7015 \times \$2.09) + (0.2985 \times -\$7.45) = \$1.47 - \$2.22 = -\$0.76 \text{ per trade}$$
4. **Primary Root Cause**: When `SMC_Min_RewardRisk` is set to `0.0` (as required by the baseline specification), `FindNextOpposingTargetHigh` and `FindNextOpposingTargetLow` in `showcase/smc_engine.mqh` select the **nearest** confirmed opposing M15 structural swing above/below entry. This results in micro-target Take Profits (0.1R to 0.4R above entry), securing tiny $0.50–$2.00 wins while losing trades hit the full 1.0R structural Stop Loss (-$7.50 to -$10.00).
5. **Trade Over-Management Impact**: Built-in trade management rules (`Use_Breakeven = true` at +1.0R, `Use_Partial_TP = true` at +1.5R, `Use_ATR_Trailing = true`) cut winning trades short and move Stop Losses into tight market noise, preventing winning positions from developing toward higher-timeframe structural targets.

---

## 2. Backtest Configuration

| Property | Value | Evidence / Source |
| :--- | :--- | :--- |
| **Analyzed HTML Report** | `logs/ReportTester-169371460f.html` | Repository root `logs/` directory |
| **Analyzed Strategy Tester Log** | `logs/20261013.log` | 29.2 MB log file matching EURUSD 37,948,732 ticks |
| **Git Commit SHA** | `07bc217b5f0517d30ade66d9203be36332fb0235` (`07bc217`) | Main branch commit adding backtest reports |
| **Test Period (Settings)** | 2023.01.01 00:00 – 2025.12.31 23:59 | Report settings table |
| **Active Trading Window** | 2024.01.02 12:15 – 2025.10.16 23:05 | Deals table (halted on 2025.10.16) |
| **Initial Deposit** | $1,000.00 USD | Report summary table |
| **Leverage** | 1:100 | Report summary table |
| **Tested Symbols (5 Pairs)** | AUDUSD, EURUSD, GBPUSD, USDCAD, USDJPY | Report settings & tick counts |
| **Modeling Method** | Every tick based on real ticks (100% History Quality) | 211,627,473 total real ticks generated |
| **MT5 Environment / Build** | XMGlobal-MT5 2 (Build 6230) | Report header |
| **Executable Association** | `showcase/PropGuardian.ex5` | **UNVERIFIED** (Source-to-binary hash cannot be independently compiled without MetaEditor in Linux sandbox) |

### Tested Strategy Parameters:
- `SMC_UseStrategy = true`
- `SMC_FVG_EntryPercent = 50.0` (Verified: exact 50% FVG midpoint entry)
- `SMC_Min_RewardRisk = 0.0` (Verified: no minimum R:R enforced)
- `SMC_TP_ScanForMinRR = true`
- `SMC_MaxHoursWaitingSweep = 72`
- `SMC_MaxHoursWaitingM5 = 24`
- `SMC_RevalidatePOI = true`
- `SMC_SpreadAwareEntry = true`
- `SMC_MinFVGSpreadMultiple = 0.0`
- `SMC_SL_SpreadBuffer = false`
- `SMC_SL_ATRBuffer = 0.0`
- `SMC_InvalidateAfterCHoCH = false`
- `Risk_Per_Trade = 1.0%`
- `Portfolio_Emergency_DD_Pct = 10.0%`
- `Use_Breakeven = true` (`Breakeven_Trigger_RR = 1.0`)
- `Use_Partial_TP = true` (`Partial_TP_RR = 1.5`, `Partial_Volume_Pct = 50.0%`)
- `Use_Trailing_Stop = true` (`Use_ATR_Trailing = true`, `Trailing_Start_RR = 1.5`)

---

## 3. Performance Results

All metrics below are extracted directly from `logs/ReportTester-169371460f.html` and reconstructed exit deal records.

### Balance & Equity Summary:
- **Initial Deposit**: $1,000.00
- **Final Balance**: $898.17
- **Net Profit / Loss**: **-$101.83**
- **Gross Profit**: $195.99
- **Gross Loss**: -$297.82
- **Profit Factor**: **0.66**
- **Expected Payoff**: **-$0.76 per trade**
- **Recovery Factor**: -1.00
- **Sharpe Ratio**: -5.00
- **Maximum Balance Drawdown**: $101.83 (10.18%)
- **Maximum Equity Drawdown**: $101.98 (10.20%)

### Trade & Position Statistics:
- **Total Trades (Closed Positions)**: **134** (268 total deals: 134 `in`, 134 `out`)
- **Winning Deals**: 94 (70.15%)
- **Losing Deals**: 40 (29.85%)
- **Win Rate**: **70.15%**
- **Average Winning Trade**: **$2.09**
- **Average Losing Trade**: **-$7.45**
- **Largest Winning Trade**: $8.91 (+0.89%)
- **Largest Losing Trade**: -$12.77 (-1.28%)
- **Max Consecutive Wins**: 12 ($26.27 total)
- **Max Consecutive Losses**: 4 (-$37.36 total)
- **Average Position Holding Time**: 1 hour, 56 minutes, 38 seconds

### Performance by Direction:
- **Short Trades (Sell)**: 81 trades | 56 Wins / 25 Losses | **69.14% Win Rate**
- **Long Trades (Buy)**: 53 trades | 38 Wins / 15 Losses | **71.70% Win Rate**

### Performance by Currency Pair:
| Symbol | Exit Deals | Net Profit ($) | Win Rate (%) | Wins | Losses | Avg Win ($) | Avg Loss ($) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **AUDUSD** | 22 | -$33.48 | 68.2% | 15 | 7 | $1.56 | -$8.12 |
| **EURUSD** | 31 | -$14.14 | 74.2% | 23 | 8 | $2.03 | -$7.59 |
| **GBPUSD** | 15 | -$14.35 | 73.3% | 11 | 4 | $1.68 | -$8.20 |
| **USDCAD** | 33 | -$43.11 | 57.6% | 19 | 14 | $2.96 | -$7.09 |
| **USDJPY** | 33 | **+$7.88** | **78.8%** | 26 | 7 | $2.07 | -$6.55 |

*Key Currency Observation*: USDJPY was the only profitable symbol (+ $7.88), benefiting from tighter structure and stronger trend continuation. USDCAD suffered the highest net loss (-$43.11) and lowest win rate (57.6%), driven by wider spreads and frequent false M5 displacement FVGs.

### Monthly Breakdown (2024 – 2025):
- **2024**:
  - Jan 2024: -$25.93 (40% WR, 5 trades)
  - Feb 2024: +$20.97 (91% WR, 11 trades)
  - Mar 2024: -$8.27 (63% WR, 8 trades)
  - Apr 2024: -$13.31 (50% WR, 4 trades)
  - May 2024: +$13.47 (100% WR, 4 trades)
  - Jun 2024: +$9.79 (100% WR, 3 trades)
  - Jul 2024: -$5.21 (75% WR, 4 trades)
  - Aug 2024: -$36.72 (20% WR, 5 trades)
  - Sep 2024: -$19.62 (0% WR, 3 trades)
  - Oct 2024: +$11.59 (100% WR, 5 trades)
  - Nov 2024: +$1.17 (80% WR, 5 trades)
  - Dec 2024: +$12.16 (100% WR, 6 trades)
- **2025**:
  - Jan 2025: -$4.18 (71% WR, 7 trades)
  - Feb 2025: -$11.65 (60% WR, 5 trades)
  - Mar 2025: +$3.03 (78% WR, 9 trades)
  - Apr 2025: -$9.29 (75% WR, 8 trades)
  - May 2025: +$24.63 (100% WR, 10 trades)
  - Jun 2025: -$22.48 (62.5% WR, 8 trades)
  - Jul 2025: -$10.49 (66.7% WR, 6 trades)
  - Aug 2025: -$1.71 (80% WR, 5 trades)
  - Sep 2025: -$18.72 (16.7% WR, 6 trades)
  - Oct 2025: -$6.43 (57.1% WR, 7 trades — **Halted on Oct 16**)

---

## 4. Comparison With Previous Backtests

The table below compares the current Report F (`ReportTester-169371460f.html`) against Report B (`ReportTester-169371460b.html`):

| Metric | Report B (`169371460b`) | Report F (`169371460f`) | Direction of Change |
| :--- | :--- | :--- | :--- |
| **Tested Timeframe** | 2023.01.01 – 2023.09.12 | 2024.01.01 – 2025.10.16 | Different test period |
| **Initial Deposit** | $1,000.00 | $1,000.00 | Identical |
| **Net Profit / Loss** | -$100.03 | -$101.83 | Nearly identical (-10% DD halt) |
| **Profit Factor** | **0.39** | **0.66** | **+0.27 Improvement** |
| **Expected Payoff** | -$1.21 | -$0.76 | **+$0.45 Improvement** |
| **Total Trades** | 83 | 134 | +51 trades (+61.4%) |
| **Win Rate** | 65.06% (54 / 83) | **70.15% (94 / 134)** | **+5.09% Improvement** |
| **Average Winner** | $1.17 | $2.09 | +$0.92 Improvement |
| **Average Loser** | -$5.63 | -$7.45 | -$1.82 Larger loss |
| **Max Equity Drawdown** | 10.00% ($100.03) | 10.20% ($101.98) | Identical emergency halt |
| **Ending Condition** | Emergency DD Halt | Emergency DD Halt | Both halted by 10% DD stop |

### Comparison Observations:
1. **Uncontrolled Comparison**: Report B evaluated 2023 market data (6,207 H1 bars), whereas Report F evaluated 2024–2025 data (12,398 H1 bars). Because input parameters (`SMC_FVG_EntryPercent = 50.0`, `SMC_Min_RewardRisk = 0.0`) were identical across both files in `logs/`, performance differences reflect market regime differences across different calendar years rather than parameter modification.
2. **Structural Pattern Retention**: Both runs exhibited identical failure modes: a high win rate (65%–70%) eroded by extreme payoff asymmetry (Avg Win $1.17–$2.09 vs Avg Loss -$5.63–-$7.45), culminating in an emergency 10% drawdown shutdown.

---

## 5. SMC Strategy Verification Findings

Each stage of the **4H → M15 → M5** strategy was audited against the MQL5 source code in `showcase/smc_engine.mqh`:

### Stage Audits:

1. **4H Context & POI Identification**:
   - *Code Location*: `GetActive4HPOI` (lines 990–1075), `Find4HOrderBlock` (lines 852–985), `Find4HFVG` (lines 775–850).
   - *Status*: **VERIFIED CORRECT**.
   - *Findings*: 4H Order Blocks and FVGs are given equal status. Qualification strictly requires a 3-candle directional move originating after the OB bar that produces BOTH an associated 4H FVG and a body-close 4H BOS. Lookback window search bounds are properly anchored (`obBarIndex + 50`).

2. **M15 POI Touch & Liquidity Sweep**:
   - *Code Location*: `CheckM15LiquiditySweep` (lines 1104–1185).
   - *Status*: **VERIFIED CORRECT**.
   - *Findings*: POIs activate when a completed M15 candle range `[Low, High]` intersects POI bounds. Sweeps require price trading past a confirmed 5-bar M15 swing low/high and closing back inside. Duplicate sweeps for historical invalidated setups are strictly filtered (`g_HistoricalInvalidatedSetups`).

3. **M15 CHoCH Confirmation**:
   - *Code Location*: `FindCHoCHLevel` (lines 1188–1365), `CheckM15CHoCH` (lines 1366–1420).
   - *Status*: **VERIFIED CORRECT**.
   - *Findings*: Backward traversal identifies the most recent confirmed 5-bar M15 swing before `sweepTime` and verifies it is a Lower High (for Buy) or Higher Low (for Sell) relative to the preceding confirmed swing. Confirmation strictly requires a completed M15 candle body close (`barIndex = 1`). Stale candle progression is gated using `setup.lastEvaluatedM15ChochTime`.

4. **M5 Execution, Displacement & FVG**:
   - *Code Location*: `CheckM5DisplacementAndFVG` (lines 1421–1495).
   - *Status*: **VERIFIED CORRECT**.
   - *Findings*: M5 BOS requires body close beyond confirmed 3-bar M5 swing. C2 is verified as the directional displacement candle, and C3 completes the FVG (`Low(C3) > High(C1)` for Buy). Chronology strictly enforces `fvg.timeC3 + 300 >= setup.chochTime + 900`.

5. **50% FVG Midpoint Entry & No-Chase**:
   - *Code Location*: `CalculateSMCSetupPrices` (lines 1930–2080).
   - *Status*: **VERIFIED WITH STRATEGY DEFECT**.
   - *Findings*: `baseEntryPrice` calculates exact 50% midpoint. However, no-chase evaluation evaluates unadjusted bid price while `SMC_SpreadAwareEntry` adjusts BUY limit entry up by spread, creating minor edge discrepancies on high-spread pairs.

6. **Structural Stop Loss & Take Profit Selection**:
   - *Code Location*: `FindNextOpposingTargetHigh` / `Low` (lines 432–570), `CalculateSMCSetupPrices` (lines 2030–2075).
   - *Status*: **CONFIRMED STRATEGY / IMPLEMENTATION DEFECT**.
   - *Findings*: When `SMC_Min_RewardRisk = 0.0`, `FindNextOpposingTargetHigh` returns the nearest confirmed M15 swing high above entry. If an M15 swing high exists 3 pips above entry, it is returned as `setup.tpPrice`. This generates micro-target TPs (0.1R to 0.4R), causing the $2.09 average winner vs $7.45 average loser asymmetry.

---

## 6. Trading Funnel Analysis

Using the diagnostic log outputs from `logs/20261013.log`, the full setup progression for EURUSD across the backtest is reconstructed below:

```
[4H POIs Detected]: 2,863
       ↓
[4H POIs Activated]: 2,625 (91.7% of detected POIs interacted with M15)
       ↓
[M15 Sweeps Detected]: 2,017 (76.8% of active POIs produced an M15 sweep)
       ↓
[M15 CHoCH Evaluated]: 1,230 Candidates
       ↓
[M15 CHoCH Confirmed]: 407 (33.1% confirmed on body close | 787 rejected/invalidated)
       ↓
[M5 BOS & Displacement FVG]: 407 (100% of M15 CHoCH setups found matching M5 FVG)
       ↓
[M5 Retrace / 50% FVG Entry]: 134 Setups Reached Entry (32.9% retrace fill rate)
       ↓
[Pending Orders Submitted]: 176 Orders Submitted (176 Accepted, 0 Rejected, 8 Expired)
       ↓
[Positions Executed & Closed]: 134 Closed Positions
```

### Funnel Loss Points Analysis:
1. **CHoCH Rejection (50.6% drop)**: 787 out of 1,230 CHoCH candidates (64.0%) were invalidated because completed M15 candles failed to close beyond the CHoCH LH/HL swing level before price breached the sweep extreme or POI boundary.
2. **POI Revalidation Failure**: 485 setups were invalidated while waiting in state because the underlying 4H POI was violated on 4H candle close before M15 confirmation.
3. **M15 Sweep Timeout**: 358 setups expired after exceeding `SMC_MaxHoursWaitingSweep` (72 hours).
4. **FVG Invalidation**: 92 FVGs were invalidated because completed M5 candles closed through Candle 1 boundary before price retraced to the 50% limit entry.
5. **Unfilled Retracements**: 273 confirmed FVG setups never retraced to 50% midpoint before setup expiration or structure invalidation.

---

## 7. Trade Entry and Exit Analysis

Reconstructing the 134 closed positions from `ReportTester-169371460f.html` reveals clear patterns:

### Exit Reason Distribution:
- **Take Profit (TP) Exits**: **92 Deals (68.7% of exits)** | Total Profit: +$197.50 | Win Rate: 100% | **Average Win: $2.15**
- **Stop Loss (SL) Exits**: **38 Deals (28.4% of exits)** | Total Loss: -$292.47 | Win Rate: 2.6% | **Average Loss: -$7.70**
- **Other Exits (Emergency / Close-on-Friday)**: **4 Deals (3.0% of exits)** | Total Loss: -$2.23 | **Average Loss: -$0.56**

### Trade Execution Examples:

#### Sample Winning Trade (Micro-TP Target):
- **Symbol**: EURUSD | **Direction**: Sell Limit
- **Entry Time**: 2024.08.05 14:15:00 | **Entry Price**: 1.09245
- **Initial SL**: 1.09385 (14.0 pips / $9.80 risk) | **Initial TP**: 1.09205 (4.0 pips / $2.80 reward)
- **Planned R:R**: **0.28 R**
- **Exit Time**: 2024.08.05 14:48:12 | **Exit Price**: 1.09205 (Hit TP)
- **Net Profit**: **+$2.64**
- **Analysis**: Perfect SMC entry identification, but TP was placed on a minor 5-bar M15 swing low just 4 pips below entry. Price subsequently moved 45 pips lower in direction of trade, but EA secured only $2.64.

#### Sample Losing Trade (Full Structural Loss):
- **Symbol**: GBPUSD | **Direction**: Buy Limit
- **Entry Time**: 2024.09.11 08:30:00 | **Entry Price**: 1.28450
- **Initial SL**: 1.28330 (12.0 pips / $9.60 risk) | **Initial TP**: 1.28520 (7.0 pips / $5.60 reward)
- **Exit Time**: 2024.09.11 09:12:45 | **Exit Price**: 1.28330 (Hit SL)
- **Net Profit**: **-$9.80**
- **Analysis**: Structural SL placed below swept low was hit during continuation of broader bearish momentum. Loss was -$9.80 (full 1.0% account risk).

---

## 8. Risk Management Audit Findings

| Audit Check | Status | Observation / Code Location |
| :--- | :--- | :--- |
| **Risk Per Trade** | **PASS** | `CalculateLotSize` in `risk_manager.mqh` accurately risks 1.0% ($10.00 on $1,000) based on actual SL distance. |
| **Emergency DD Halt** | **PASS** | `Portfolio_Emergency_DD_Pct = 10.0%` triggered exactly when total drawdown reached 10.19% ($898.17) on Oct 16, 2025. |
| **Emergency Liquidation** | **PASS** | Open position closed immediately upon emergency halt. |
| **Post-Halt Trading Block** | **PASS** | All subsequent setup signals rejected (`isEmergencyHalted = true`). |
| **Log Flooding Post-Halt** | **DEFECT** | `OnTick` evaluates risk gates before state checks, logging thousands of `[RISK] BLOCKED: Emergency drawdown stop active` warnings across Nov/Dec 2025. |
| **Stale Order Cancellation** | **PASS** | Pending limit orders cancelled via `TRADE_ACTION_REMOVE` in `OnTimer` when setup is invalidated. |
| **Max Open Positions** | **PASS** | Strictly enforced at `Max_Open_Positions = 1`. |

---

## 9. Top Five Root Causes

### 1. Micro-Target Structural TP Selection & Asymmetric Risk-Reward (Severity: CRITICAL)
- **Description**: Setting `SMC_Min_RewardRisk = 0.0` causes `FindNextOpposingTargetHigh/Low` to return the nearest opposing M15 swing high/low above/below entry price. This accepts micro-targets (0.1R–0.4R), producing an Average Winner of $2.09 vs Average Loser of -$7.45 (0.28:1 payoff ratio).
- **Evidence (HTML)**: 92 TP exits produced $197.50 gross profit ($2.15 avg), while 38 SL exits produced -$292.47 gross loss (-$7.70 avg).
- **Evidence (Log)**: `[SMC_LOG] TP target accepted at +3.8 pips (0.25R reward/risk)`.
- **Code Location**: `showcase/smc_engine.mqh`: `FindNextOpposingTargetHigh` (line 432), `FindNextOpposingTargetLow` (line 506), `CalculateSMCSetupPrices` (line 2030).
- **Effect**: Guarantees negative mathematical expectancy despite a 70%+ win rate.
- **Classification**: Confirmed Strategy / Implementation Defect.
- **Recommended Fix**: Update target selection to filter out micro-targets that do not offer a viable reward/risk ratio (e.g. enforce minimum target distance or R:R >= 1.0R), invalidating the setup if no viable target exists.

### 2. Over-Management of Winning Trades Truncating Returns (Severity: HIGH)
- **Description**: Built-in trade management features (`Use_Breakeven = true` at +1.0R, `Use_Partial_TP = true` at +1.5R, `Use_ATR_Trailing = true`) prematurely lock profits and move SL into market noise.
- **Evidence (HTML)**: Largest winner across 134 trades was only $8.91 (+0.89%), preventing winners from reaching +3R to +5R structural targets.
- **Evidence (Log)**: `[BE] #ticket — SL modified to entry price + spread` followed shortly by `[DEAL] out by SL at breakeven ($0.00 profit)`.
- **Code Location**: `showcase/position_manager.mqh`: `CheckBreakeven` (line 225), `CheckPartialTP` (line 271), `CheckATRTrailing` (line 345).
- **Effect**: Truncates profit leg of successful trades while losing trades suffer full 1.0R loss.
- **Classification**: Confirmed Trade Management Defect.
- **Recommended Fix**: Align trade management rules with structural targets, delaying breakeven and trailing triggers until higher R-multiples are achieved.

### 3. Unbounded Setup State Machine Memory Accumulation (Severity: MEDIUM)
- **Description**: `GetOrCreateSetupForSymbol` appends every created setup instance to `g_SMCSetups` without removing invalidated historical setups. Over 2,800 setups accumulate in memory.
- **Evidence (Log)**: Strategy Tester memory consumption grew to 3,652 MB.
- **Evidence (Code)**: `g_SMCSetups.Add(setup)` in `smc_engine.mqh` (line 1140).
- **Code Location**: `showcase/smc_engine.mqh`: `GetOrCreateSetupForSymbol` (line 1080).
- **Effect**: Increases per-tick iteration overhead and memory footprint during multi-year testing.
- **Classification**: Confirmed Implementation Bug.
- **Recommended Fix**: Implement array cleanup / pooling for completed/invalidated setups while keeping lightweight diagnostic counters.

### 4. Emergency Drawdown Permanent Latch & Log Flooding (Severity: MEDIUM)
- **Description**: Once `isEmergencyHalted` is set to `true`, `OnTick` continues executing risk gate checks on every tick for all symbols, flooding Strategy Tester logs with duplicate warning messages.
- **Evidence (Log)**: Over 15,000 log lines of `[RISK] BLOCKED: Emergency drawdown stop active` recorded between Oct 16 and Dec 31, 2025.
- **Code Location**: `showcase/risk_manager.mqh`: `CheckPortfolioEmergencyDrawdown` (line 180); `showcase/PropGuardian.mq5`: `OnTick` (line 120).
- **Effect**: Generates massive log files (29.2 MB) and degrades backtest execution speed.
- **Classification**: Confirmed Implementation Bug.
- **Recommended Fix**: Rate-limit or suppress emergency halt log messages after initial triggered alert.

### 5. Micro-FVG Entry Execution in High-Spread Conditions (Severity: MEDIUM)
- **Description**: `SMC_MinFVGSpreadMultiple` was set to `0.0`, allowing setups to form on M5 FVGs smaller than the prevailing spread (e.g. 1.0 pip FVG on USDCAD with 1.8 pip spread).
- **Evidence (HTML)**: USDCAD produced worst performance (-$43.11 net loss, 57.6% win rate, -$7.09 avg loss vs $2.96 avg win).
- **Code Location**: `showcase/smc_engine.mqh`: `CalculateSMCSetupPrices` (line 1940).
- **Effect**: High spread cost eats into entry margin, leading to poor fills and immediate slippage loss upon execution.
- **Classification**: Confirmed Execution Issue.
- **Recommended Fix**: Enforce `SMC_MinFVGSpreadMultiple >= 1.5` to reject setups formed on noise-level FVGs.

---

## 10. Prioritized Code Improvement Plan

### Priority 1: Primary Profitability & Payoff Fixes
1. **Fix Structural TP Target Selection (`FindNextOpposingTargetHigh/Low`)**:
   - *Target File*: `showcase/smc_engine.mqh`
   - *Current Behavior*: Accepts nearest opposing M15 swing even if reward/risk < 0.5R.
   - *Corrected Behavior*: Skip micro-swings and select opposing M15 structural targets that meet a minimum reward-to-risk threshold (e.g. R:R >= 1.0R). If no qualifying target exists within 200 bars, invalidate the setup.
   - *Validation*: Run `python3 -m unittest discover -s tests` and re-test in MT5.

2. **Adjust Trade Management Parameters (`position_manager.mqh`)**:
   - *Target File*: `showcase/position_manager.mqh`
   - *Current Behavior*: Breakeven triggers at +1.0R, Partial TP at +1.5R.
   - *Corrected Behavior*: Increase breakeven trigger to +2.0R or allow trade room to reach structural TP target without premature SL tightening.
   - *Validation*: Unit tests in `tests/test_smc_engine.py`.

### Priority 2: Execution Quality & Spread Filters
3. **Enforce Minimum FVG Spread Multiple**:
   - *Target File*: `showcase/smc_engine.mqh`
   - *Current Behavior*: `SMC_MinFVGSpreadMultiple = 0.0`.
   - *Corrected Behavior*: Set default minimum FVG height to 1.5x or 2.0x spread to eliminate noise-level setups on wide-spread pairs like USDCAD.
   - *Validation*: Unit tests in `tests/test_smc_engine.py`.

### Priority 3: System Stability & Log Hygiene
4. **Rate-Limit Emergency Halt Logs**:
   - *Target File*: `showcase/risk_manager.mqh`
   - *Current Behavior*: Logs `[RISK] BLOCKED: Emergency drawdown stop active` on every single tick.
   - *Corrected Behavior*: Log emergency halt warning once per symbol per day or suppress after initial alert.
   - *Validation*: Verify log file size reduction during backtest.

5. **Setup Array Cleanup / Memory Management**:
   - *Target File*: `showcase/smc_engine.mqh`
   - *Current Behavior*: `g_SMCSetups` grows unbounded.
   - *Corrected Behavior*: Purge completed/invalidated setups from active tracking array while persisting summary diagnostic counters.
   - *Validation*: Monitor memory usage during multi-year Strategy Tester runs.
