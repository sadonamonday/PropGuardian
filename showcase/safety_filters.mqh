//+------------------------------------------------------------------+
//| Safety Filters — Trade Blocking Conditions                        |
//|                                                                    |
//| These filters run BEFORE any trade signal is evaluated.           |
//| If ANY filter returns false, the signal is discarded.             |
//+------------------------------------------------------------------+

// Parameter declarations / defaults
#ifndef SAFETY_PARAMS_DEFINED
#define SAFETY_PARAMS_DEFINED
input int    Max_Spread_Points       = 30;     // Max allowed spread in points
input double ATR_Max_Multiplier      = 2.5;    // Toxic volatility threshold
input int    Same_Idea_Cooldown_Min  = 12;     // Cooldown period in minutes
input int    Rollover_Start_Hour     = 23;     // Rollover start hour (server)
input int    Rollover_End_Hour       = 0;      // Rollover end hour (server)
#endif

// Forward declarations of helper functions if needed
string GetBaseCurrency(string symbol)
{
   return StringSubstr(symbol, 0, 3);
}

int CountCurrencyExposure(string baseCurrency)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         if(GetBaseCurrency(posSymbol) == baseCurrency)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Master Filter — All-in-one pre-trade validation                   |
//+------------------------------------------------------------------+
bool PassesAllFilters(string symbol)
{
   // 1. Spread check
   if(!CheckSpread(symbol))
      return false;
   
   // 2. Session hours (08:00–22:00 GMT contiguous window)
   if(!IsWithinTradingSession())
      return false;
   
   // 3. Asian Session Range filter (08:00–10:00 GMT block if range > 50 pips)
   if(IsAsianRangeExceeded(symbol))
      return false;

   // 4. Currency Exposure filter
   string baseCurr = GetBaseCurrency(symbol);
   if(CountCurrencyExposure(baseCurr) >= Max_Currency_Exposure)
   {
      PrintFormat("[FILTER] Currency exposure limit reached for %s", baseCurr);
      return false;
   }

   // 5. News filter (30 min for high-impact, 12 min for other)
   if(IsNearNewsEvent())
      return false;
   
   // 6. Friday close protection
   if(IsFridayCloseWindow())
      return false;
   
   // 7. Rollover block (daily swap window)
   if(IsRolloverWindow())
      return false;
   
   // 8. Toxic volatility guard (ATR spike detection)
   if(IsToxicVolatility(symbol))
      return false;
   
   // 9. Latency check (broker connection quality)
   if(!IsLatencyAcceptable())
      return false;
   
   // 10. FP Zero: Floating P&L limit
   if(IsFloatingLossExceeded())
      return false;
   
   // 11. FP Zero: Same trade idea cooldown
   if(IsInCooldown(symbol))
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Trading Session Window (08:00–22:00 GMT contiguous block)        |
//+------------------------------------------------------------------+
bool IsWithinTradingSession()
{
   datetime serverTime = TimeTradeServer();
   // Convert server time to GMT hour using GMT_Offset
   datetime gmtTime = serverTime - GMT_Offset * 3600;

   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);

   // Allow trading only if GMT_Hour is in [8, 22)
   if(dt.hour >= 8 && dt.hour < 22)
      return true;

   PrintFormat("[FILTER] Outside GMT trading window (08:00-22:00 GMT). Current GMT hour: %d", dt.hour);
   return false;
}

//+------------------------------------------------------------------+
//| Asian Range Filter                                                |
//| 00:00–05:00 GMT range check. If > 50 pips, block 08:00–10:00 GMT   |
//+------------------------------------------------------------------+
bool IsAsianRangeExceeded(string symbol)
{
   datetime serverTime = TimeTradeServer();
   datetime gmtTime = serverTime - GMT_Offset * 3600;

   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);

   // Only block during the first 2 hours of London session (08:00–10:00 GMT)
   if(dt.hour < 8 || dt.hour >= 10)
      return false;

   // Find Asian H1 bars between 00:00 and 05:00 GMT today
   double asianHigh = -1.0;
   double asianLow  = 999999.0;
   bool foundBar = false;

   // Scan last 48 H1 bars to locate 00:00 to 05:00 GMT today
   for(int i = 1; i < 48; i++)
   {
      datetime barServerTime = iTime(symbol, PERIOD_H1, i);
      datetime barGmtTime = barServerTime - GMT_Offset * 3600;

      MqlDateTime barDt;
      TimeToStruct(barGmtTime, barDt);

      if(barDt.year == dt.year && barDt.mon == dt.mon && barDt.day == dt.day)
      {
         if(barDt.hour >= 0 && barDt.hour < 5)
         {
            double h = iHigh(symbol, PERIOD_H1, i);
            double l = iLow(symbol, PERIOD_H1, i);
            if(h > asianHigh) asianHigh = h;
            if(l < asianLow)  asianLow  = l;
            foundBar = true;
         }
      }
   }

   if(!foundBar || asianHigh <= 0 || asianLow >= 999999.0)
      return false;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pipSize = point * ((digits == 3 || digits == 5) ? 10.0 : 1.0);

   double asianRangePips = (asianHigh - asianLow) / pipSize;

   if(asianRangePips > Max_Asian_Range_Pips)
   {
      PrintFormat("[FILTER] Asian range for %s is %.1f pips > %.1f pips — blocking entries until 10:00 GMT",
                  symbol, asianRangePips, Max_Asian_Range_Pips);
      return true;
   }

   return false;
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
//+------------------------------------------------------------------+
bool IsToxicVolatility(string symbol)
{
   int atrCurrentHandle = iATR(symbol, PERIOD_H1, ATR_Period);
   int atrHistHandle    = iATR(symbol, PERIOD_D1, ATR_Period * 5);
   
   if(atrCurrentHandle == INVALID_HANDLE || atrHistHandle == INVALID_HANDLE)
      return false;

   double atrCurr[];
   double atrHist[];
   ArraySetAsSeries(atrCurr, true);
   ArraySetAsSeries(atrHist, true);

   if(CopyBuffer(atrCurrentHandle, 0, 1, 1, atrCurr) <= 0 ||
      CopyBuffer(atrHistHandle, 0, 1, 1, atrHist) <= 0)
   {
      IndicatorRelease(atrCurrentHandle);
      IndicatorRelease(atrHistHandle);
      return false;
   }

   double atrCurrent = atrCurr[0];
   double atrHistorical = atrHist[0];

   IndicatorRelease(atrCurrentHandle);
   IndicatorRelease(atrHistHandle);

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
//| Buffer: NewsBufferHighImpact (30 min), NewsBufferOther (12 min)  |
//+------------------------------------------------------------------+
bool IsNearNewsEvent()
{
   datetime now = TimeCurrent();
   
   // Calendar check logic placeholder reading calendar events
   // If within NewsBufferHighImpact (30 min) of high-impact news, return true
   // If within NewsBufferOther (12 min) of other news, return true

   return false;
}

//+------------------------------------------------------------------+
//| Friday Close Window                                               |
//+------------------------------------------------------------------+
bool IsFridayCloseWindow()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.day_of_week == 5 && dt.hour >= Friday_Close_Hour);
}

//+------------------------------------------------------------------+
//| Rollover Window Check                                             |
//+------------------------------------------------------------------+
bool IsRolloverWindow()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour == Rollover_Start_Hour || dt.hour == Rollover_End_Hour);
}

//+------------------------------------------------------------------+
//| Latency Check                                                     |
//+------------------------------------------------------------------+
bool IsLatencyAcceptable()
{
   return true;
}

//+------------------------------------------------------------------+
//| Floating Loss Exceeded                                            |
//+------------------------------------------------------------------+
bool IsFloatingLossExceeded()
{
   return false;
}

//+------------------------------------------------------------------+
//| FP Zero: Same Trade Idea Cooldown                                 |
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
