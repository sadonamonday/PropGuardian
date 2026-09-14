//+------------------------------------------------------------------+
//| Risk Manager — Capital Protection Layer                           |
//|                                                                    |
//| Multi-layered risk architecture in MQL5 for PropGuardian EA.      |
//| Integrates pre-trade risk gates, drawdown monitoring,              |
//| drawdown scaling, and position sizing.                            |
//+------------------------------------------------------------------+

#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include "safety_filters.mqh"
#include "signal_engine.mqh"
#include "position_manager.mqh"

// Input parameter declarations for risk management
#ifndef RISK_PARAMS_DEFINED
#define RISK_PARAMS_DEFINED
input int    Max_Trades_Per_Day       = 1;      // Max allowed trades per day
input int    Max_Consecutive_Losses   = 3;      // Max consecutive losses before circuit breaker
input int    Max_Open_Positions       = 1;      // Max simultaneous open positions
input double Max_Portfolio_DD_Pct     = 7.0;    // Max portfolio drawdown percentage
input double Max_Daily_Loss_Soft_Pct  = 2.5;    // Daily drawdown soft stop threshold (%)
input double Max_Daily_Loss_Hard_Pct  = 5.0;    // Daily drawdown hard stop threshold (%)
input double Portfolio_Emergency_DD_Pct = 10.0; // Total drawdown emergency stop threshold (%)
input double DD_Threshold_ScaleDown   = 7.0;    // Total DD threshold to halve risk (%)
input double Daily_DD_ScaleDown       = 2.5;    // Daily DD threshold to halve risk (%)
#endif

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

// Forward Declarations
double CalculateTotalDD(const RiskState &state);
double CalculatePortfolioDD(const RiskState &state);
int    CountOpenPositions();
void   EmergencyCloseAll();

//+------------------------------------------------------------------+
//| Daily Reset — CRITICAL: Must run BEFORE risk checks               |
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
//| Pre-Trade Risk Gate — Multi-layer checks                          |
//| ALL risk gates AND safety filters AND signal engine must agree.   |
//+------------------------------------------------------------------+
bool CanOpenTrade(const RiskState &state, string symbol, SignalResult &outSignal)
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
   
   // Gate 3: Max trades per day
   if(state.tradesToday >= Max_Trades_Per_Day)
   {
      PrintFormat("[RISK] BLOCKED: Max %d trades/day reached", Max_Trades_Per_Day);
      return false;
   }
   
   // Gate 4: Max losses per day / circuit breaker
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
   double portfolioDD = CalculatePortfolioDD(state);
   if(portfolioDD >= Max_Portfolio_DD_Pct)
   {
      PrintFormat("[RISK] BLOCKED: Portfolio DD %.2f%% >= %.2f%%",
                  portfolioDD, Max_Portfolio_DD_Pct);
      return false;
   }
   
   // Gate 8: Safety Filters Gate
   if(!PassesAllFilters(symbol))
   {
      PrintFormat("[RISK] BLOCKED: Safety filters gate failed for %s", symbol);
      return false;
   }

   // Gate 9: Signal Engine Gate
   outSignal = CheckSignal(symbol);
   if(outSignal.type == SIGNAL_NONE)
   {
      return false; // No trade signal
   }

   PrintFormat("[RISK] APPROVED: All risk gates, safety filters, and signal engine confirm trade for %s (%s)",
               symbol, outSignal.type == SIGNAL_BUY ? "BUY" : "SELL");
   return true;
}

// Overload for general risk gate checking without returning signal struct
bool CanOpenTrade(const RiskState &state, string symbol)
{
   SignalResult signal;
   return CanOpenTrade(state, symbol, signal);
}

//+------------------------------------------------------------------+
//| Position Sizing — ATR-based with drawdown scaling                 |
//|                                                                    |
//| RiskAmount = Balance * RiskPercent                                |
//| LossPerLot = (StopDistance / TickSize) * TickValue               |
//| RawLotSize = RiskAmount / LossPerLot                             |
//| LotSize = MathFloor(RawLotSize / LotStep) * LotStep              |
//| Clamp to [SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX]                   |
//| If LotSize < SYMBOL_VOLUME_MIN: SKIP trade (do not round up)      |
//+------------------------------------------------------------------+
double CalculateLotSize(const RiskState &state, string symbol, double stopDistance)
{
   if(stopDistance <= 0) return 0.0;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPct = Risk_Per_Trade;  // Default 1.0%
   
   // Drawdown scaling: halve risk to 0.5% if daily PnL <= -2.5% or total DD >= 7.0%
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnLPct = 0.0;
   if(state.dailyReferenceBalance > 0)
      dailyPnLPct = (currentEquity - state.dailyReferenceBalance) / state.dailyReferenceBalance * 100.0;

   double currentDD = CalculateTotalDD(state);

   if(dailyPnLPct <= -Daily_DD_ScaleDown || currentDD >= DD_Threshold_ScaleDown)
   {
      riskPct *= 0.5; // Halved to 0.5%
      PrintFormat("[RISK] DD scaling active (Daily PnL: %.2f%%, Total DD: %.2f%%) → Risk halved to %.2f%%",
                  dailyPnLPct, currentDD, riskPct);
   }
   
   double riskAmount = balance * (riskPct / 100.0);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0 || tickValue <= 0) return 0.0;

   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0.0;

   double rawLotSize = riskAmount / lossPerLot;

   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   double lotSize = MathFloor(rawLotSize / lotStep) * lotStep;

   // CRITICAL: If LotSize < SYMBOL_VOLUME_MIN, SKIP the trade — do NOT round up!
   if(lotSize < minLot)
   {
      PrintFormat("[RISK] Calculated lot size %.2f < min lot %.2f. SKIPPING trade to preserve risk cap.",
                  lotSize, minLot);
      return 0.0;
   }

   lotSize = MathMin(maxLot, lotSize);
   return lotSize;
}

//+------------------------------------------------------------------+
//| Drawdown Monitoring — Double layer (daily + total)                |
//+------------------------------------------------------------------+
void UpdateDrawdownState(RiskState &state)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   state.equityPeak = MathMax(state.equityPeak, equity);
   state.dailyPnL   = equity - state.dailyReferenceBalance;
   
   // Daily loss check
   if(state.dailyReferenceBalance > 0)
   {
      double dailyLossPct = (-state.dailyPnL / state.dailyReferenceBalance) * 100.0;
      
      // Soft stop (-2.5%): block new trades
      if(dailyLossPct >= Max_Daily_Loss_Soft_Pct && !state.isSoftStopped)
      {
         state.isSoftStopped = true;
         PrintFormat("[RISK] ⚠️ SOFT STOP: Daily loss %.2f%% >= %.2f%%",
                     dailyLossPct, Max_Daily_Loss_Soft_Pct);
      }
      
      // Hard stop (-5.0%): close everything & halt EA for the trading day
      if(dailyLossPct >= Max_Daily_Loss_Hard_Pct && !state.isHardStopped)
      {
         state.isHardStopped = true;
         PrintFormat("[RISK] 🚨 HARD STOP: Daily loss %.2f%% >= %.2f%% — closing all positions & halting EA for the day",
                     dailyLossPct, Max_Daily_Loss_Hard_Pct);
         EmergencyCloseAll();
      }
   }
   
   // Total drawdown check (7.0% scale down, 10.0% emergency kill switch)
   double totalDD = CalculateTotalDD(state);
   if(totalDD >= Portfolio_Emergency_DD_Pct)
   {
      state.isHardStopped = true;
      PrintFormat("[RISK] 🚨 EMERGENCY: Total DD %.2f%% >= %.2f%% — closing ALL positions & halting EA entirely",
                  totalDD, Portfolio_Emergency_DD_Pct);
      EmergencyCloseAll();
   }
}

// Helper stub functions if not defined elsewhere
double CalculateTotalDD(const RiskState &state)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(state.equityPeak <= 0) return 0.0;
   return MathMax(0.0, (state.equityPeak - equity) / state.equityPeak * 100.0);
}

double CalculatePortfolioDD(const RiskState &state)
{
   return CalculateTotalDD(state);
}

int CountOpenPositions()
{
   return PositionsTotal();
}

void EmergencyCloseAll()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         ClosePosition(ticket);
      }
   }
}

#endif
