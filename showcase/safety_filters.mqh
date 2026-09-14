//+------------------------------------------------------------------+
//| Safety Filters — Trade Blocking Conditions (Sanitized Excerpt)    |
//|                                                                    |
//| These filters run BEFORE any trade signal is evaluated.           |
//| If ANY filter returns false, the signal is discarded.             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Master Filter — All-in-one pre-trade validation                   |
//+------------------------------------------------------------------+
bool PassesAllFilters(string symbol)
{
   // 1. Spread check
   if(!CheckSpread(symbol))
      return false;
   
   // 2. Session hours (avoid illiquid Asian hours for EUR pairs)
   if(!IsWithinTradingSession())
      return false;
   
   // 3. News filter (high-impact events: NFP, CPI, FOMC, etc.)
   if(IsNearNewsEvent())
      return false;
   
   // 4. Friday close protection
   if(IsFridayCloseWindow())
      return false;
   
   // 5. Rollover block (daily swap window)
   if(IsRolloverWindow())
      return false;
   
   // 6. Toxic volatility guard (ATR spike detection)
   if(IsToxicVolatility(symbol))
      return false;
   
   // 7. Latency check (broker connection quality)
   if(!IsLatencyAcceptable())
      return false;
   
   // 8. FP Zero: Floating P&L limit
   if(IsFloatingLossExceeded())
      return false;
   
   // 9. FP Zero: Same trade idea cooldown
   if(IsInCooldown(symbol))
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Spread Filter — Reject trades during wide spreads                 |
//+------------------------------------------------------------------+
bool CheckSpread(string symbol)
{
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   
   if(spread > Max_Spread_Points)
   {
      PrintFormat("[FILTER] Spread too wide: %d > %d points", 
                  (int)spread, Max_Spread_Points);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Toxic Volatility — Block when ATR exceeds historical average      |
//|                                                                    |
//| During extreme events (flash crashes, surprise announcements),    |
//| ATR spikes well above normal. Trading in these conditions has     |
//| negative expectancy due to slippage and erratic price action.     |
//+------------------------------------------------------------------+
bool IsToxicVolatility(string symbol)
{
   double atrCurrent = iATR(symbol, Timeframe, ATR_Period);
   
   // Compare to historical average (longer lookback)
   double atrHistorical = iATR(symbol, PERIOD_D1, ATR_Period * 5);
   
   if(atrHistorical > 0 && atrCurrent > atrHistorical * ATR_Max_Multiplier)
   {
      PrintFormat("[FILTER] Toxic volatility: ATR %.5f > %.1fx historical %.5f",
                  atrCurrent, ATR_Max_Multiplier, atrHistorical);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| News Filter — Block around high-impact economic events            |
//|                                                                    |
//| Reads news events from MQL5 calendar or external CSV file.       |
//| Different buffer times for normal vs critical events:            |
//| - Normal (rate decisions, retail sales): ±12 min                  |
//| - Critical (NFP, CPI, FOMC): ±12 min (uniform in V2.8.1)       |
//|                                                                    |
//| FP Zero rules require 10-min buffer. We add 2 min safety.       |
//+------------------------------------------------------------------+
bool IsNearNewsEvent()
{
   datetime now = TimeCurrent();
   
   // Check calendar events for the trading day
   // (Implementation reads from MQL5/Files/news_calendar.csv
   //  which is updated daily by an external script)
   
   // ... calendar reading logic omitted ...
   
   // If near a high-impact event, return true to block trading
   return false;  // Placeholder
}

//+------------------------------------------------------------------+
//| FP Zero: Same Trade Idea Cooldown                                 |
//|                                                                    |
//| Funding Pips Zero account rules prohibit opening the "same trade  |
//| idea" within 10 minutes. We enforce 12 minutes (10 + 2 buffer).  |
//| Tracked per symbol to allow different symbols simultaneously.     |
//+------------------------------------------------------------------+
bool IsInCooldown(string symbol)
{
   static datetime lastTradeTime[];
   static string   lastTradeSymbol[];
   
   datetime now = TimeCurrent();
   int cooldownSeconds = Same_Idea_Cooldown_Min * 60;
   
   for(int i = 0; i < ArraySize(lastTradeSymbol); i++)
   {
      if(lastTradeSymbol[i] == symbol)
      {
         if((now - lastTradeTime[i]) < cooldownSeconds)
         {
            int remaining = cooldownSeconds - (int)(now - lastTradeTime[i]);
            PrintFormat("[FILTER] Cooldown for %s: %d sec remaining",
                        symbol, remaining);
            return true;
         }
      }
   }
   return false;
}
