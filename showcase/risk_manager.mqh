//+------------------------------------------------------------------+
//| Risk Manager — Capital Protection Layer (Sanitized Excerpt)       |
//|                                                                    |
//| This is a sanitized excerpt from PropGuardian V2.8.1.             |
//| All exact thresholds use input parameters (values not shown).     |
//| Demonstrates the multi-layered risk architecture in MQL5.        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Risk State Structure                                              |
//+------------------------------------------------------------------+
struct RiskState
{
   double dailyPnL;              // Today's P&L in account currency
   double dailyReferenceBalance;  // Balance at start of day
   double equityPeak;             // All-time equity peak
   bool   isSoftStopped;          // New trades blocked
   bool   isHardStopped;          // All positions to be closed
   int    consecutiveLosses;      // Sequential losing trades
   int    tradesToday;            // Trade count today
};

//+------------------------------------------------------------------+
//| Daily Reset — CRITICAL: Must run BEFORE risk checks               |
//|                                                                    |
//| Bug #33 Lesson: If this runs AFTER soft/hard stop checks,        |
//| the bot stays dead forever after a bad day because the stops     |
//| never get reset. Now it's the FIRST thing in OnTick().           |
//+------------------------------------------------------------------+
bool CheckNewDay(RiskState &state)
{
   static int lastDay = -1;
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_year != lastDay)
   {
      double oldPnL = state.dailyPnL;
      
      state.dailyPnL = 0.0;
      state.isSoftStopped = false;
      state.isHardStopped = false;
      state.dailyReferenceBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      state.tradesToday = 0;
      state.equityPeak = MathMax(state.equityPeak, 
                                  AccountInfoDouble(ACCOUNT_EQUITY));
      lastDay = dt.day_of_year;
      
      PrintFormat("[RISK] New day — Balance: $%.2f | Peak: $%.2f | Yesterday PnL: $%.2f",
                  state.dailyReferenceBalance, state.equityPeak, oldPnL);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Pre-Trade Risk Gate — 7 independent checks                        |
//| ALL must pass before any order is sent to the broker.             |
//+------------------------------------------------------------------+
bool CanOpenTrade(const RiskState &state, string symbol)
{
   // Gate 1: Hard stop (emergency — all positions being closed)
   if(state.isHardStopped)
   {
      PrintFormat("[RISK] BLOCKED: Hard stop active");
      return false;
   }
   
   // Gate 2: Soft stop (daily loss limit reached)
   if(state.isSoftStopped)
   {
      PrintFormat("[RISK] BLOCKED: Soft stop — daily loss limit");
      return false;
   }
   
   // Gate 3: Max trades per day (V2.8.1: ultra-conservative = 1)
   if(state.tradesToday >= Max_Trades_Per_Day)
   {
      PrintFormat("[RISK] BLOCKED: Max %d trades/day reached", Max_Trades_Per_Day);
      return false;
   }
   
   // Gate 4: Max losses per day
   if(state.consecutiveLosses >= Max_Consecutive_Losses)
   {
      PrintFormat("[RISK] BLOCKED: Circuit breaker — %d consecutive losses",
                  state.consecutiveLosses);
      return false;
   }
   
   // Gate 5: Max open positions
   int openCount = CountOpenPositions();
   if(openCount >= Max_Open_Positions)
   {
      PrintFormat("[RISK] BLOCKED: Max %d positions open", Max_Open_Positions);
      return false;
   }
   
   // Gate 6: Currency exposure (max positions per base currency)
   string baseCurrency = GetBaseCurrency(symbol);
   if(CountCurrencyExposure(baseCurrency) >= Max_Currency_Exposure)
   {
      PrintFormat("[RISK] BLOCKED: Max exposure for %s", baseCurrency);
      return false;
   }
   
   // Gate 7: Portfolio drawdown check
   double portfolioDD = CalculatePortfolioDD();
   if(portfolioDD >= Max_Portfolio_DD_Pct)
   {
      PrintFormat("[RISK] BLOCKED: Portfolio DD %.2f%% >= %.2f%%",
                  portfolioDD, Max_Portfolio_DD_Pct);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Position Sizing — ATR-based with drawdown scaling                 |
//|                                                                    |
//| Formula: lots = (balance × risk%) / (SL_pips × pip_value)        |
//| When approaching DD limits, risk% is automatically halved.       |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double slPips)
{
   if(slPips <= 0) return 0.0;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPct = Risk_Per_Trade;  // From input parameter
   
   // Drawdown scaling: halve risk when approaching limits
   double currentDD = CalculateTotalDD();
   if(currentDD >= DD_Threshold_ScaleDown)
   {
      riskPct *= 0.5;
      PrintFormat("[RISK] DD scaling active: %.2f%% DD → risk halved to %.2f%%",
                  currentDD, riskPct);
   }
   
   double riskAmount = balance * (riskPct / 100.0);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipValue = tickValue / tickSize * SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   double lots = riskAmount / (slPips * pipValue);
   
   // Normalize to broker's lot step
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   return lots;
}

//+------------------------------------------------------------------+
//| Drawdown Monitoring — Double layer (daily + total)                |
//+------------------------------------------------------------------+
void UpdateDrawdownState(RiskState &state)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   state.equityPeak = MathMax(state.equityPeak, equity);
   state.dailyPnL = equity - state.dailyReferenceBalance;
   
   // Daily loss check
   if(state.dailyReferenceBalance > 0)
   {
      double dailyLossPct = (-state.dailyPnL / state.dailyReferenceBalance) * 100.0;
      
      // Soft stop: block new trades
      if(dailyLossPct >= Max_Daily_Loss_Soft_Pct && !state.isSoftStopped)
      {
         state.isSoftStopped = true;
         PrintFormat("[RISK] ⚠️ SOFT STOP: Daily loss %.2f%% >= %.2f%%",
                     dailyLossPct, Max_Daily_Loss_Soft_Pct);
      }
      
      // Hard stop: close everything
      if(dailyLossPct >= Max_Daily_Loss_Hard_Pct && !state.isHardStopped)
      {
         state.isHardStopped = true;
         PrintFormat("[RISK] 🚨 HARD STOP: Daily loss %.2f%% >= %.2f%%",
                     dailyLossPct, Max_Daily_Loss_Hard_Pct);
         EmergencyCloseAll();
      }
   }
   
   // Total drawdown kill switch
   double totalDD = CalculateTotalDD();
   if(totalDD >= Portfolio_Emergency_DD_Pct)
   {
      state.isHardStopped = true;
      PrintFormat("[RISK] 🚨 EMERGENCY: Total DD %.2f%% — closing ALL positions",
                  totalDD);
      EmergencyCloseAll();
   }
}
