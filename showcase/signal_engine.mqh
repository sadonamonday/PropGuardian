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
input int    Structure_Swing_Lookback_Bars = 8; // Completed W1 bars scanned for swing points
input double Counter_Trend_Wick_Multiplier = 1.5; // Extra rejection strictness when trading against weekly structure
input bool   Block_Counter_Trend_Entries   = false; // true = block counter-structure entries outright; false = require stricter rejection wick instead
input int    CHoCH_M15_Swing_Lookback_Bars = 40;    // M15 bars scanned backward to locate the reference swing point
input int    CHoCH_Max_Bars_Since_Break    = 8;     // Max M15 bars since the structural break for it to still count as a valid confirmation
input bool   Use_M15_CHoCH_Filter          = false; // toggle: false = skip CHoCH check entirely (current default while testing reclaim entries)
input double Stop_Entry_Buffer_Pips        = 2.0;   // Pips added beyond the sweep candle's extreme for the stop-order reclaim entry
input int    Pending_Order_Expiry_Bars     = 4;     // H1 bars before an unfilled pending stop order is cancelled
input int    Trend_SMA_Period         = 50;     // D1 Trend SMA period
input int    ADX_Regime_Period        = 14;     // D1 ADX period
input double ADX_Max_Threshold        = 30.0;   // block trades when ADX >= this
input int    ATR_Period               = 14;     // H1 ATR period for SL and trailing
input double SL_ATR_Multiplier        = 3.0;    // SL distance = ATR * multiplier
input double Breakeven_Trigger_RR              = 4.0;   // R-multiple to trigger break-even
input double Partial_TP_RR                     = 4.0;   // R-multiple to trigger partial TP
input double Partial_Volume_Pct                = 20.0;  // Partial TP volume percentage
input double Partial2_TP_RR                    = 10.0;  // Second partial TP trigger (R-multiple)
input double Partial2_Volume_Pct               = 50.0;  // Volume % of remaining position for second partial
input double ATR_Trailing_Multiplier           = 2.5;   // Wide ATR multiplier for trailing stop (before partial 2)
input double ATR_Trailing_Multiplier_Tight     = 1.6;   // Tight ATR multiplier for trailing stop (after partial 2)
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

enum ENUM_STRUCTURE_BIAS
{
   STRUCTURE_NEUTRAL   = 0,
   STRUCTURE_UPTREND   = 1,
   STRUCTURE_DOWNTREND = -1
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
static int g_adxHandles[];

//+------------------------------------------------------------------+
//| Helper: Pip size for a symbol (10x point on 3/5-digit symbols)    |
//+------------------------------------------------------------------+
double GetPipSizeForSymbol(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return point * ((digits == 3 || digits == 5) ? 10.0 : 1.0);
}

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
   ArrayResize(g_adxHandles, count + 1);

   g_SymbolLevels[count].symbol = symbol;
   g_SymbolLevels[count].lastD1Time = 0;
   g_SymbolLevels[count].lastW1Time = 0;

   // Cache iMA, iATR, and iADX handles for this symbol
   g_maHandles[count] = iMA(symbol, PERIOD_D1, Trend_SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   g_atrHandles[count] = iATR(symbol, PERIOD_H1, ATR_Period);
   g_adxHandles[count] = iADX(symbol, PERIOD_D1, ADX_Regime_Period);

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
//| Get Cached ATR Handle                                            |
//+------------------------------------------------------------------+
int GetCachedATRHandle(string symbol)
{
   int idx = GetSymbolIndex(symbol);
   if(idx >= 0 && idx < ArraySize(g_atrHandles))
      return g_atrHandles[idx];
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Get Cached ADX Value                                             |
//+------------------------------------------------------------------+
double GetADXValue(string symbol)
{
   int idx = GetSymbolIndex(symbol);
   if(idx < 0) return -1.0;
   int adxHandle = g_adxHandles[idx];
   if(adxHandle == INVALID_HANDLE) return -1.0;
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(adxHandle, MAIN_LINE, 1, 1, adx) <= 0)
      return -1.0;
   return adx[0];
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
//| Weekly Structure Bias — compares the two most recent W1 swing     |
//| highs and two most recent W1 swing lows to determine whether      |
//| price structure is making Higher-Highs/Higher-Lows (uptrend),     |
//| Lower-Highs/Lower-Lows (downtrend), or neither (neutral).         |
//| Swing points found via 3-bar fractal on completed W1 bars only    |
//| (index 0, the current incomplete bar, is never used).             |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_BIAS GetWeeklyStructureBias(string symbol)
{
   double swingHighs[2];
   double swingLows[2];
   int    highCount = 0;
   int    lowCount  = 0;

   int maxIndex = Structure_Swing_Lookback_Bars + 1;

   for(int i = 2; i <= maxIndex && (highCount < 2 || lowCount < 2); i++)
   {
      double highMid  = iHigh(symbol, PERIOD_W1, i);
      double highPrev = iHigh(symbol, PERIOD_W1, i - 1); // more recent neighbor
      double highNext = iHigh(symbol, PERIOD_W1, i + 1); // older neighbor

      if(highCount < 2 && highMid > highPrev && highMid > highNext)
      {
         swingHighs[highCount] = highMid;
         highCount++;
      }

      double lowMid  = iLow(symbol, PERIOD_W1, i);
      double lowPrev = iLow(symbol, PERIOD_W1, i - 1);
      double lowNext = iLow(symbol, PERIOD_W1, i + 1);

      if(lowCount < 2 && lowMid < lowPrev && lowMid < lowNext)
      {
         swingLows[lowCount] = lowMid;
         lowCount++;
      }
   }

   // Not enough swing points found in the lookback window
   if(highCount < 2 || lowCount < 2)
      return STRUCTURE_NEUTRAL;

   // swingHighs[0]/swingLows[0] = most recent swing; [1] = the one before it
   bool higherHigh = swingHighs[0] > swingHighs[1];
   bool higherLow  = swingLows[0]  > swingLows[1];
   bool lowerHigh  = swingHighs[0] < swingHighs[1];
   bool lowerLow   = swingLows[0]  < swingLows[1];

   if(higherHigh && higherLow) return STRUCTURE_UPTREND;
   if(lowerHigh && lowerLow)   return STRUCTURE_DOWNTREND;

   return STRUCTURE_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Find the most recent confirmed M15 swing high using a 2-bar       |
//| fractal (2 bars on each side, strictly greater). Scans from the   |
//| most recent completed bar (index 3, the earliest a 2-bar fractal  |
//| can be confirmed) outward to CHoCH_M15_Swing_Lookback_Bars.       |
//+------------------------------------------------------------------+
bool FindM15SwingHigh(string symbol, int lookbackBars, double &outPrice, int &outIndex)
{
   for(int i = 3; i <= lookbackBars + 2; i++)
   {
      double hMid = iHigh(symbol, PERIOD_M15, i);
      if(hMid > iHigh(symbol, PERIOD_M15, i - 1) &&
         hMid > iHigh(symbol, PERIOD_M15, i - 2) &&
         hMid > iHigh(symbol, PERIOD_M15, i + 1) &&
         hMid > iHigh(symbol, PERIOD_M15, i + 2))
      {
         outPrice = hMid;
         outIndex = i;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find the most recent confirmed M15 swing low — mirror of          |
//| FindM15SwingHigh using strictly-lower comparisons.                 |
//+------------------------------------------------------------------+
bool FindM15SwingLow(string symbol, int lookbackBars, double &outPrice, int &outIndex)
{
   for(int i = 3; i <= lookbackBars + 2; i++)
   {
      double lMid = iLow(symbol, PERIOD_M15, i);
      if(lMid < iLow(symbol, PERIOD_M15, i - 1) &&
         lMid < iLow(symbol, PERIOD_M15, i - 2) &&
         lMid < iLow(symbol, PERIOD_M15, i + 1) &&
         lMid < iLow(symbol, PERIOD_M15, i + 2))
      {
         outPrice = lMid;
         outIndex = i;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| M15 Change of Character Confirmation                              |
//| direction == SIGNAL_BUY:  requires a body-close M15 break ABOVE   |
//|                           the most recent M15 swing high.         |
//| direction == SIGNAL_SELL: requires a body-close M15 break BELOW   |
//|                           the most recent M15 swing low.          |
//| Returns true only if that break happened within the most recent   |
//| CHoCH_Max_Bars_Since_Break completed M15 bars.                    |
//+------------------------------------------------------------------+
bool CheckM15CHoCHConfirms(string symbol, ENUM_SIGNAL_TYPE direction)
{
   if(direction == SIGNAL_BUY)
   {
      double swingHighPrice;
      int    swingHighIndex;
      if(!FindM15SwingHigh(symbol, CHoCH_M15_Swing_Lookback_Bars, swingHighPrice, swingHighIndex))
         return false;

      for(int j = swingHighIndex - 1; j >= 1; j--)
      {
         double closeJ = iClose(symbol, PERIOD_M15, j);
         if(closeJ > swingHighPrice)
         {
            int barsSinceBreak = j;
            return (barsSinceBreak <= CHoCH_Max_Bars_Since_Break);
         }
      }
      return false;
   }
   else if(direction == SIGNAL_SELL)
   {
      double swingLowPrice;
      int    swingLowIndex;
      if(!FindM15SwingLow(symbol, CHoCH_M15_Swing_Lookback_Bars, swingLowPrice, swingLowIndex))
         return false;

      for(int j = swingLowIndex - 1; j >= 1; j--)
      {
         double closeJ = iClose(symbol, PERIOD_M15, j);
         if(closeJ < swingLowPrice)
         {
            int barsSinceBreak = j;
            return (barsSinceBreak <= CHoCH_Max_Bars_Since_Break);
         }
      }
      return false;
   }

   return false;
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

   // 4. Regime Filter Check (ADX) — block trades in strong trending conditions
   double adxValue = GetADXValue(symbol);
   if(adxValue < 0) return result;          // indicator not ready
   if(adxValue >= ADX_Max_Threshold) return result;

   // 5. Sweep & Rejection Detection
   bool isLowSweep = false;
   bool isHighSweep = false;
   string sweptLevelName = "";

   // --- Bullish Setup (Low Sweep) ---
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
      bool isRejection = (lowerWick >= Rejection_Wick_Ratio * body);
      if(!isRejection) isLowSweep = false;
   }

   // --- Bearish Setup (High Sweep) ---
   // Prioritize Weekly level (PWH) over Daily level (PDH)
   if(!isLowSweep)   // a bar shouldn't trigger both; low sweep takes priority if it fires
   {
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
         bool isRejection = (upperWick >= Rejection_Wick_Ratio * body);
         if(!isRejection) isHighSweep = false;
      }
   }

   // 5b. Weekly Structure Filter — asymmetric counter-trend handling.
   // A long that sweeps a low during confirmed weekly DOWNTREND structure,
   // or a short that sweeps a high during confirmed weekly UPTREND structure,
   // is a counter-structure entry. Depending on Block_Counter_Trend_Entries,
   // it is either blocked outright or held to a stricter rejection-wick bar.
   if(isLowSweep || isHighSweep)
   {
      ENUM_STRUCTURE_BIAS structureBias = GetWeeklyStructureBias(symbol);

      if(isLowSweep && structureBias == STRUCTURE_DOWNTREND)
      {
         if(Block_Counter_Trend_Entries)
         {
            isLowSweep = false;
         }
         else
         {
            bool passesStrictRejection = (lowerWick >= Rejection_Wick_Ratio * Counter_Trend_Wick_Multiplier * body);
            if(!passesStrictRejection) isLowSweep = false;
         }
      }

      if(isHighSweep && structureBias == STRUCTURE_UPTREND)
      {
         if(Block_Counter_Trend_Entries)
         {
            isHighSweep = false;
         }
         else
         {
            bool passesStrictRejection = (upperWick >= Rejection_Wick_Ratio * Counter_Trend_Wick_Multiplier * body);
            if(!passesStrictRejection) isHighSweep = false;
         }
      }
   }

   // 5c. M15 CHoCH Confirmation Filter — disabled by default (Use_M15_CHoCH_Filter)
   // while the stop-order reclaim entry is tested on its own.
   if(Use_M15_CHoCH_Filter)
   {
      if(isLowSweep)
      {
         if(!CheckM15CHoCHConfirms(symbol, SIGNAL_BUY))
            isLowSweep = false;
      }
      if(isHighSweep)
      {
         if(!CheckM15CHoCHConfirms(symbol, SIGNAL_SELL))
            isHighSweep = false;
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

      double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
      double stopDist = (atrValue * SL_ATR_Multiplier) + spread;

      double pipSize     = GetPipSizeForSymbol(symbol);
      double entryBuffer = Stop_Entry_Buffer_Pips * pipSize;

      if(isLowSweep)
      {
         // Reclaim entry: price must trade back up through the sweep bar's
         // high (plus buffer) before the buy triggers — confirms momentum
         // has actually resumed, rather than entering on the sweep bar itself.
         result.type = SIGNAL_BUY;
         result.entryPrice = high1 + entryBuffer;
         result.slPrice = result.entryPrice - stopDist;
         result.stopDistance = stopDist;
         result.levelSwept = sweptLevelName;
      }
      else if(isHighSweep)
      {
         result.type = SIGNAL_SELL;
         result.entryPrice = low1 - entryBuffer;
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
void ReleaseSignalEngineHandles()
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
      if(i < ArraySize(g_adxHandles) && g_adxHandles[i] != INVALID_HANDLE)
      {
         IndicatorRelease(g_adxHandles[i]);
         g_adxHandles[i] = INVALID_HANDLE;
      }
   }
   ArrayResize(g_SymbolLevels, 0);
   ArrayResize(g_maHandles, 0);
   ArrayResize(g_atrHandles, 0);
   ArrayResize(g_adxHandles, 0);
}

#endif
