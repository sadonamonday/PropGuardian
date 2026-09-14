//+------------------------------------------------------------------+
//| Signal Engine — SMC Liquidity Sweep Reversal Strategy             |
//|                                                                    |
//| Core signal generator for PropGuardian EA.                        |
//| Implements level tracking (PDH/PDL, PWH/PWL), sweep detection,    |
//| rejection candle filter, and D1 SMA50 trend alignment.            |
//+------------------------------------------------------------------+

#ifndef SIGNAL_ENGINE_MQH
#define SIGNAL_ENGINE_MQH

#property strict

//+------------------------------------------------------------------+
//| EA Input Parameters                                               |
//+------------------------------------------------------------------+
input double Rejection_Wick_Ratio     = 2.0;    // Wick-to-body ratio for rejection candle
input int    Trend_SMA_Period         = 50;     // D1 Trend SMA period
input int    ATR_Period               = 14;     // H1 ATR period for SL and trailing
input double SL_ATR_Multiplier        = 3.0;    // SL distance = ATR * multiplier
input double Breakeven_Trigger_RR     = 1.0;    // R-multiple to trigger break-even
input double Partial_TP_RR            = 1.5;    // R-multiple to trigger partial TP
input double Partial_Volume_Pct       = 50.0;   // Partial TP volume percentage
input double ATR_Trailing_Multiplier  = 2.5;    // ATR multiplier for trailing stop
input int    GMT_Offset               = 2;      // Broker server offset from GMT (hours)
input double Max_Asian_Range_Pips     = 50.0;   // Max Asian range in pips (00:00-05:00 GMT)
input int    NewsBufferHighImpact     = 30;     // News buffer for high-impact events (minutes)
input int    NewsBufferOther          = 12;     // News buffer for other events (minutes)
input int    Max_Currency_Exposure    = 1;      // Max allowed positions per base currency
input double Risk_Per_Trade           = 1.0;    // Risk per trade (% of balance)

// Tradeable Symbols
const string TradeableSymbols[5] = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD"};

//+------------------------------------------------------------------+
//| Signal Types & Output Structure                                   |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

struct SignalResult
{
   ENUM_SIGNAL_TYPE type;          // SIGNAL_BUY, SIGNAL_SELL, or SIGNAL_NONE
   double           entryPrice;    // Calculated entry price
   double           slPrice;       // Initial stop loss price
   double           stopDistance;  // Stop distance in price units
   string           levelSwept;    // Name of level swept ("PWH", "PWL", "PDH", "PDL")
};

// Internal level storage structure per symbol
struct SymbolLevels
{
   string   symbol;
   double   pdh;
   double   pdl;
   double   pwh;
   double   pwl;
   datetime lastD1Time;
   datetime lastW1Time;
};

static SymbolLevels g_SymbolLevels[];

// Indicator Handles Cache
static int g_maHandles[];
static int g_atrHandles[];

//+------------------------------------------------------------------+
//| Helper: Check if symbol is in TradeableSymbols                    |
//+------------------------------------------------------------------+
bool IsTradeableSymbol(string symbol)
{
   for(int i = 0; i < 5; i++)
   {
      if(TradeableSymbols[i] == symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update D1 and W1 levels once per new bar                          |
//+------------------------------------------------------------------+
void UpdateSymbolLevels(string symbol, SymbolLevels &levels)
{
   levels.symbol = symbol;

   // Check D1 new bar
   datetime currentD1Time = iTime(symbol, PERIOD_D1, 0);
   if(currentD1Time != levels.lastD1Time)
   {
      levels.pdh = iHigh(symbol, PERIOD_D1, 1);
      levels.pdl = iLow(symbol, PERIOD_D1, 1);
      levels.lastD1Time = currentD1Time;
   }

   // Check W1 new bar
   datetime currentW1Time = iTime(symbol, PERIOD_W1, 0);
   if(currentW1Time != levels.lastW1Time)
   {
      levels.pwh = iHigh(symbol, PERIOD_W1, 1);
      levels.pwl = iLow(symbol, PERIOD_W1, 1);
      levels.lastW1Time = currentW1Time;
   }
}

//+------------------------------------------------------------------+
//| Get or Initialize Symbol Levels                                   |
//+------------------------------------------------------------------+
void GetSymbolLevels(string symbol, SymbolLevels &levels)
{
   int count = ArraySize(g_SymbolLevels);
   for(int i = 0; i < count; i++)
   {
      if(g_SymbolLevels[i].symbol == symbol)
      {
         UpdateSymbolLevels(symbol, g_SymbolLevels[i]);
         levels = g_SymbolLevels[i];
         return;
      }
   }

   // Add new symbol level tracker
   ArrayResize(g_SymbolLevels, count + 1);
   ArrayResize(g_maHandles, count + 1);
   ArrayResize(g_atrHandles, count + 1);

   g_SymbolLevels[count].symbol = symbol;
   g_SymbolLevels[count].lastD1Time = 0;
   g_SymbolLevels[count].lastW1Time = 0;

   // Cache iMA and iATR handles for this symbol
   g_maHandles[count] = iMA(symbol, PERIOD_D1, Trend_SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   g_atrHandles[count] = iATR(symbol, PERIOD_H1, ATR_Period);

   UpdateSymbolLevels(symbol, g_SymbolLevels[count]);
   levels = g_SymbolLevels[count];
}

//+------------------------------------------------------------------+
//| Helper: Get Cached Indicator Index                               |
//+------------------------------------------------------------------+
int GetSymbolIndex(string symbol)
{
   int count = ArraySize(g_SymbolLevels);
   for(int i = 0; i < count; i++)
   {
      if(g_SymbolLevels[i].symbol == symbol)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Trend Bias Filter — D1 SMA(50)                                    |
//| Bullish bias (d1Close > sma50) -> Longs only                     |
//| Bearish bias (d1Close < sma50) -> Shorts only                    |
//+------------------------------------------------------------------+
int GetTrendBias(string symbol)
{
   int idx = GetSymbolIndex(symbol);
   if(idx < 0) return 0;

   int maHandle = g_maHandles[idx];
   if(maHandle == INVALID_HANDLE) return 0;

   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(maHandle, 0, 1, 1, ma) <= 0)
      return 0;

   double sma50 = ma[0];
   double d1Close = iClose(symbol, PERIOD_D1, 1);

   if(d1Close > sma50)
      return 1;   // Bullish bias
   else if(d1Close < sma50)
      return -1;  // Bearish bias

   return 0;
}

//+------------------------------------------------------------------+
//| Core Signal Evaluation Function                                   |
//| Evaluates completed H1 bar (index 1)                              |
//+------------------------------------------------------------------+
SignalResult CheckSignal(string symbol)
{
   SignalResult result;
   result.type = SIGNAL_NONE;
   result.entryPrice = 0.0;
   result.slPrice = 0.0;
   result.stopDistance = 0.0;
   result.levelSwept = "";

   if(!IsTradeableSymbol(symbol))
      return result;

   // 1. Get updated levels
   SymbolLevels levels;
   GetSymbolLevels(symbol, levels);

   // 2. Read H1 bar (index 1) OHLC
   double open1  = iOpen(symbol, PERIOD_H1, 1);
   double high1  = iHigh(symbol, PERIOD_H1, 1);
   double low1   = iLow(symbol, PERIOD_H1, 1);
   double close1 = iClose(symbol, PERIOD_H1, 1);

   // 3. Candle characteristics
   double body      = MathAbs(close1 - open1);
   double upperWick = high1 - MathMax(open1, close1);
   double lowerWick = MathMin(open1, close1) - low1;

   // 4. Trend Filter Check
   int trendBias = GetTrendBias(symbol);
   if(trendBias == 0) return result;

   // 5. Sweep & Rejection Detection
   bool isLowSweep = false;
   bool isHighSweep = false;
   string sweptLevelName = "";

   // --- Bullish Setup (Low Sweep) ---
   if(trendBias == 1) // Bullish bias -> LOW sweeps only
   {
      // Prioritize Weekly level (PWL) over Daily level (PDL)
      if(low1 < levels.pwl && close1 > levels.pwl)
      {
         isLowSweep = true;
         sweptLevelName = "PWL";
      }
      else if(low1 < levels.pdl && close1 > levels.pdl)
      {
         isLowSweep = true;
         sweptLevelName = "PDL";
      }

      if(isLowSweep)
      {
         // Rejection filter: Lower wick >= 2.0 * Body
         bool isRejection = (lowerWick >= Rejection_Wick_Ratio * body);
         if(!isRejection) isLowSweep = false;
      }
   }

   // --- Bearish Setup (High Sweep) ---
   if(trendBias == -1) // Bearish bias -> HIGH sweeps only
   {
      // Prioritize Weekly level (PWH) over Daily level (PDH)
      if(high1 > levels.pwh && close1 < levels.pwh)
      {
         isHighSweep = true;
         sweptLevelName = "PWH";
      }
      else if(high1 > levels.pdh && close1 < levels.pdh)
      {
         isHighSweep = true;
         sweptLevelName = "PDH";
      }

      if(isHighSweep)
      {
         // Rejection filter: Upper wick >= 2.0 * Body
         bool isRejection = (upperWick >= Rejection_Wick_Ratio * body);
         if(!isRejection) isHighSweep = false;
      }
   }

   // 6. Calculate ATR and Stop Distance if signal generated
   if(isLowSweep || isHighSweep)
   {
      int idx = GetSymbolIndex(symbol);
      if(idx < 0) return result;

      int atrHandle = g_atrHandles[idx];
      if(atrHandle == INVALID_HANDLE) return result;

      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0)
         return result;

      double atrValue = atr[0];

      if(atrValue <= 0) return result;

      double stopDist = atrValue * SL_ATR_Multiplier;

      if(isLowSweep)
      {
         result.type = SIGNAL_BUY;
         result.entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
         if(result.entryPrice <= 0) result.entryPrice = close1;
         result.slPrice = result.entryPrice - stopDist;
         result.stopDistance = stopDist;
         result.levelSwept = sweptLevelName;
      }
      else if(isHighSweep)
      {
         result.type = SIGNAL_SELL;
         result.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
         if(result.entryPrice <= 0) result.entryPrice = close1;
         result.slPrice = result.entryPrice + stopDist;
         result.stopDistance = stopDist;
         result.levelSwept = sweptLevelName;
      }
   }

   return result;
}

//+------------------------------------------------------------------+
//| EA Deinitialization — Release cached indicator handles            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int count = ArraySize(g_SymbolLevels);
   for(int i = 0; i < count; i++)
   {
      if(i < ArraySize(g_maHandles) && g_maHandles[i] != INVALID_HANDLE)
      {
         IndicatorRelease(g_maHandles[i]);
         g_maHandles[i] = INVALID_HANDLE;
      }
      if(i < ArraySize(g_atrHandles) && g_atrHandles[i] != INVALID_HANDLE)
      {
         IndicatorRelease(g_atrHandles[i]);
         g_atrHandles[i] = INVALID_HANDLE;
      }
   }
   ArrayResize(g_SymbolLevels, 0);
   ArrayResize(g_maHandles, 0);
   ArrayResize(g_atrHandles, 0);
}

#endif
