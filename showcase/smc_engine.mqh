//+------------------------------------------------------------------+
//| smc_engine.mqh                                                   |
//| PropGuardian SMC Strategy v0.1 — Signal Engine & State Machine   |
//|                                                                  |
//| Multi-Timeframe Architecture:                                    |
//|   4H  -> Context, Directional Structure, 4H POIs                 |
//|   M15 -> Structural Mapping, POI Touch, Liquidity Sweep, CHoCH    |
//|   M5  -> Execution Structure, Displacement, FVG, 50% Entry       |
//+------------------------------------------------------------------+

#ifndef SMC_ENGINE_MQH
#define SMC_ENGINE_MQH

#property strict
#include "signal_engine.mqh"
// --- Timeframe Inputs & Strategy Toggles ---
input bool              SMC_UseStrategy      = true;         // Enable PropGuardian SMC Strategy v0.1
input ENUM_TIMEFRAMES   SMC_4H_Timeframe     = PERIOD_H4;    // Context Timeframe (4H)
input ENUM_TIMEFRAMES   SMC_M15_Timeframe    = PERIOD_M15;   // Structural Timeframe (M15)
input ENUM_TIMEFRAMES   SMC_M5_Timeframe     = PERIOD_M5;    // Execution Timeframe (M5)
input double            SMC_FVG_EntryPercent = 50.0;         // FVG Entry Percentage (50.0 = midpoint)
input bool              SMC_DebugLogging     = true;         // Enable Structured Debug Logging
input bool              SMC_DrawChartObjects = true;         // Enable Visual Chart Objects on MT5 Tester/Chart
input int               SMC_MaxActiveSetups  = 5;            // Max Simultaneous Active Setups Across Symbols

// --- Enums ---

enum ENUM_SMC_STRUCTURE
{
   SMC_STRUCTURE_UNDEFINED = 0,
   SMC_STRUCTURE_BULLISH   = 1,
   SMC_STRUCTURE_BEARISH   = -1
};

enum ENUM_SWING_TYPE
{
   SWING_TYPE_NONE = 0,
   SWING_TYPE_HIGH = 1,
   SWING_TYPE_LOW  = 2
};

enum ENUM_POI_TYPE
{
   POI_TYPE_NONE   = 0,
   POI_TYPE_DEMAND = 1,  // Bullish POI
   POI_TYPE_SUPPLY = 2   // Bearish POI
};

enum ENUM_SMC_STATE
{
   SMC_IDLE = 0,
   SMC_H4_POI_ACTIVE,
   SMC_WAITING_FOR_M15_SWEEP,
   SMC_M15_SWEEP_DETECTED,
   SMC_WAITING_FOR_M15_CHOCH,
   SMC_M15_CHOCH_CONFIRMED,
   SMC_WAITING_FOR_M5_CONFIRMATION,
   SMC_M5_CONFIRMATION,
   SMC_FVG_DETECTED,
   SMC_WAITING_FOR_FVG_RETRACE,
   SMC_ENTRY_SUBMITTED,
   SMC_TRADE_ACTIVE,
   SMC_COMPLETED,
   SMC_INVALIDATED
};

// --- Structures ---

struct SMCSwing
{
   ENUM_SWING_TYPE type;
   double          price;
   datetime        time;
   int             barIndex;
   ENUM_TIMEFRAMES timeframe;
   bool            isValid;
};

struct SMCPOI
{
   ENUM_POI_TYPE   type;
   double          top;
   double          bottom;
   datetime        time;
   bool            isActive;
   ENUM_TIMEFRAMES timeframe;
};

struct SMCFVG
{
   bool            isBullish;
   double          top;
   double          bottom;
   double          midpoint;
   datetime        timeC3;
   int             c1Index;
   int             c2Index;
   int             c3Index;
   bool            isValid;
   bool            isMitigated;
};

struct SMCOrderBlock
{
   bool            isBullish;
   double          high;
   double          low;
   datetime        time;
   bool            isValid;
};

struct SMCSetup
{
   string             setupID;
   string             symbol;
   ENUM_SIGNAL_TYPE   direction;      // SIGNAL_BUY or SIGNAL_SELL
   ENUM_SMC_STATE     state;

   // Context & Trigger Data
   SMCPOI             poi4H;
   SMCSwing           m15SweptSwing;
   double             sweepPrice;
   datetime           sweepTime;

   SMCSwing           m15ChochSwing;  // LH for Buy CHoCH, HL for Sell CHoCH
   double             chochPrice;
   datetime           chochTime;
   datetime           lastEvaluatedM15ChochTime; // Timestamp of last evaluated completed M15 candle for CHoCH

   // M5 Execution Data
   SMCFVG             m5FVG;
   SMCOrderBlock      m5OB;

   double             entryPrice;     // 50% FVG Midpoint
   double             slPrice;        // Structural SL
   double             tpPrice;        // Opposing Structural TP
   double             stopDistance;   // In price units

   ulong              orderTicket;    // Pending limit order ticket
   ulong              positionTicket; // Active position ticket

   datetime           createdTime;
   datetime           lastUpdatedTime;
   string             invalidationReason;
};

// --- Helper Formatting Function ---

string SMCStateToString(ENUM_SMC_STATE state)
{
   switch(state)
   {
      case SMC_IDLE:                        return "SMC_IDLE";
      case SMC_H4_POI_ACTIVE:               return "SMC_H4_POI_ACTIVE";
      case SMC_WAITING_FOR_M15_SWEEP:       return "SMC_WAITING_FOR_M15_SWEEP";
      case SMC_M15_SWEEP_DETECTED:          return "SMC_M15_SWEEP_DETECTED";
      case SMC_WAITING_FOR_M15_CHOCH:       return "SMC_WAITING_FOR_M15_CHOCH";
      case SMC_M15_CHOCH_CONFIRMED:         return "SMC_M15_CHOCH_CONFIRMED";
      case SMC_WAITING_FOR_M5_CONFIRMATION: return "SMC_WAITING_FOR_M5_CONFIRMATION";
      case SMC_M5_CONFIRMATION:             return "SMC_M5_CONFIRMATION";
      case SMC_FVG_DETECTED:                return "SMC_FVG_DETECTED";
      case SMC_WAITING_FOR_FVG_RETRACE:     return "SMC_WAITING_FOR_FVG_RETRACE";
      case SMC_ENTRY_SUBMITTED:             return "SMC_ENTRY_SUBMITTED";
      case SMC_TRADE_ACTIVE:                return "SMC_TRADE_ACTIVE";
      case SMC_COMPLETED:                   return "SMC_COMPLETED";
      case SMC_INVALIDATED:                 return "SMC_INVALIDATED";
   }
   return "UNKNOWN";
}

// --- Global Strategy State ---

static SMCSetup g_SMCSetups[];
static int      g_SMCSetupCounter = 0;

//+------------------------------------------------------------------+
//| Generate Unique Setup ID                                         |
//+------------------------------------------------------------------+
string GenerateSetupID(string symbol)
{
   g_SMCSetupCounter++;
   MqlDateTime dt;
   TimeCurrent(dt);
   return StringFormat("SETUP_%s_%04d%02d%02d_%02d%02d%02d_%03d",
                       symbol, dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, g_SMCSetupCounter);
}

//+------------------------------------------------------------------+
//| Log SMC Event                                                    |
//+------------------------------------------------------------------+
void SMCLog(string setupID, string symbol, string eventName, string details)
{
   if(!SMC_DebugLogging) return;
   PrintFormat("[SMC_LOG] [%s] [%s] %s | %s",
               setupID != "" ? setupID : "SYSTEM", symbol, eventName, details);
}

//+------------------------------------------------------------------+
//| VISUAL CHART DEBUGGING                                           |
//| Draws 4H POI, M15 Sweeps, CHoCH levels, FVG boxes & Entry/SL/TP  |
//+------------------------------------------------------------------+
void DrawSMCDebugObjects(const SMCSetup &setup)
{
   if(!SMC_DrawChartObjects) return;

   long chartID = ChartID();
   string prefix = "SMC_" + setup.setupID + "_";

   // 1. Draw 4H POI Box
   if(setup.poi4H.isActive)
   {
      string poiName = prefix + "4H_POI";
      ObjectCreate(chartID, poiName, OBJ_RECTANGLE, 0, setup.poi4H.time, setup.poi4H.top, TimeCurrent(), setup.poi4H.bottom);
      ObjectSetInteger(chartID, poiName, OBJPROP_COLOR, setup.poi4H.type == POI_TYPE_DEMAND ? clrBlue : clrRed);
      ObjectSetInteger(chartID, poiName, OBJPROP_FILL, true);
      ObjectSetInteger(chartID, poiName, OBJPROP_BACK, true);
   }

   // 2. Draw CHoCH Level
   if(setup.chochPrice > 0)
   {
      string chochName = prefix + "CHOCH";
      ObjectCreate(chartID, chochName, OBJ_HLINE, 0, 0, setup.chochPrice);
      ObjectSetInteger(chartID, chochName, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(chartID, chochName, OBJPROP_STYLE, STYLE_DASH);
   }

   // 3. Draw FVG Box & 50% Midpoint Line
   if(setup.m5FVG.isValid)
   {
      string fvgName = prefix + "FVG";
      ObjectCreate(chartID, fvgName, OBJ_RECTANGLE, 0, setup.m5FVG.timeC3, setup.m5FVG.top, TimeCurrent(), setup.m5FVG.bottom);
      ObjectSetInteger(chartID, fvgName, OBJPROP_COLOR, setup.m5FVG.isBullish ? clrLightCyan : clrMistyRose);
      ObjectSetInteger(chartID, fvgName, OBJPROP_FILL, true);

      string entryName = prefix + "ENTRY_50";
      ObjectCreate(chartID, entryName, OBJ_HLINE, 0, 0, setup.entryPrice);
      ObjectSetInteger(chartID, entryName, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(chartID, entryName, OBJPROP_WIDTH, 2);
   }
}

//+------------------------------------------------------------------+
//| SWING DEFINITIONS                                                |
//| 4H & M15: 5-bar swing fractals (barIndex >= 3 -> uses bar 1 & 2) |
//| M5: 3-bar swing fractals (barIndex >= 2 -> uses bar 1)           |
//| EQUAL HIGH / EQUAL LOW: Strict comparison only (< and >)         |
//| STRICT: Completed candles only (barIndex - 2 >= 1 -> barIndex >= 3)|
//+------------------------------------------------------------------+

bool Get5BarSwingHigh(string symbol, ENUM_TIMEFRAMES tf, int barIndex, SMCSwing &outSwing)
{
   ZeroMemory(outSwing);
   outSwing.isValid = false;

   // Requires 2 completed candles on right side -> barIndex - 2 >= 1 -> barIndex >= 3
   if(barIndex < 3) return false;

   double hMid   = iHigh(symbol, tf, barIndex);
   double hLeft1 = iHigh(symbol, tf, barIndex + 1);
   double hLeft2 = iHigh(symbol, tf, barIndex + 2);
   double hRight1= iHigh(symbol, tf, barIndex - 1);
   double hRight2= iHigh(symbol, tf, barIndex - 2);

   // Check for Equal Highs condition
   if(hMid == hLeft1 || hMid == hLeft2 || hMid == hRight1 || hMid == hRight2)
   {
      return false;
   }

   if(hMid > hLeft1 && hMid > hLeft2 && hMid > hRight1 && hMid > hRight2)
   {
      outSwing.type      = SWING_TYPE_HIGH;
      outSwing.price     = hMid;
      outSwing.time      = iTime(symbol, tf, barIndex);
      outSwing.barIndex  = barIndex;
      outSwing.timeframe = tf;
      outSwing.isValid   = true;
      return true;
   }
   return false;
}

// Search for the next valid opposing structural target ahead of entry price scanning backward
bool FindNextOpposingTargetHigh(string symbol, ENUM_TIMEFRAMES tf, int maxLookbackBars, double entryPrice, SMCSwing &outSwing)
{
   ZeroMemory(outSwing);
   outSwing.isValid = false;

   int startBar = (tf == PERIOD_M5) ? 2 : 3;

   for(int i = startBar; i <= maxLookbackBars; i++)
   {
      SMCSwing swing;
      bool found = (tf == PERIOD_M5)
                   ? Get3BarSwingHigh(symbol, tf, i, swing)
                   : Get5BarSwingHigh(symbol, tf, i, swing);
      if(found)
      {
         if(swing.price > entryPrice)
         {
            outSwing = swing;
            return true;
         }
      }
   }
   return false;
}

bool FindNextOpposingTargetLow(string symbol, ENUM_TIMEFRAMES tf, int maxLookbackBars, double entryPrice, SMCSwing &outSwing)
{
   ZeroMemory(outSwing);
   outSwing.isValid = false;

   int startBar = (tf == PERIOD_M5) ? 2 : 3;

   for(int i = startBar; i <= maxLookbackBars; i++)
   {
      SMCSwing swing;
      bool found = (tf == PERIOD_M5)
                   ? Get3BarSwingLow(symbol, tf, i, swing)
                   : Get5BarSwingLow(symbol, tf, i, swing);
      if(found)
      {
         if(swing.price < entryPrice)
         {
            outSwing = swing;
            return true;
         }
      }
   }
   return false;
}

bool Get5BarSwingLow(string symbol, ENUM_TIMEFRAMES tf, int barIndex, SMCSwing &outSwing)
{
   ZeroMemory(outSwing);
   outSwing.isValid = false;

   if(barIndex < 3) return false;

   double lMid   = iLow(symbol, tf, barIndex);
   double lLeft1 = iLow(symbol, tf, barIndex + 1);
   double lLeft2 = iLow(symbol, tf, barIndex + 2);
   double lRight1= iLow(symbol, tf, barIndex - 1);
   double lRight2= iLow(symbol, tf, barIndex - 2);

   if(lMid == lLeft1 || lMid == lLeft2 || lMid == lRight1 || lMid == lRight2)
   {
      return false;
   }

   if(lMid < lLeft1 && lMid < lLeft2 && lMid < lRight1 && lMid < lRight2)
   {
      outSwing.type      = SWING_TYPE_LOW;
      outSwing.price     = lMid;
      outSwing.time      = iTime(symbol, tf, barIndex);
      outSwing.barIndex  = barIndex;
      outSwing.timeframe = tf;
      outSwing.isValid   = true;
      return true;
   }
   return false;
}

bool Get3BarSwingHigh(string symbol, ENUM_TIMEFRAMES tf, int barIndex, SMCSwing &outSwing)
{
   ZeroMemory(outSwing);
   outSwing.isValid = false;

   // Requires 1 completed candle on right side -> barIndex - 1 >= 1 -> barIndex >= 2
   if(barIndex < 2) return false;

   double hMid   = iHigh(symbol, tf, barIndex);
   double hLeft  = iHigh(symbol, tf, barIndex + 1);
   double hRight = iHigh(symbol, tf, barIndex - 1);

   if(hMid == hLeft || hMid == hRight) return false;

   if(hMid > hLeft && hMid > hRight)
   {
      outSwing.type      = SWING_TYPE_HIGH;
      outSwing.price     = hMid;
      outSwing.time      = iTime(symbol, tf, barIndex);
      outSwing.barIndex  = barIndex;
      outSwing.timeframe = tf;
      outSwing.isValid   = true;
      return true;
   }
   return false;
}

bool Get3BarSwingLow(string symbol, ENUM_TIMEFRAMES tf, int barIndex, SMCSwing &outSwing)
{
   ZeroMemory(outSwing);
   outSwing.isValid = false;

   if(barIndex < 2) return false;

   double lMid   = iLow(symbol, tf, barIndex);
   double lLeft  = iLow(symbol, tf, barIndex + 1);
   double lRight = iLow(symbol, tf, barIndex - 1);

   if(lMid == lLeft || lMid == lRight) return false;

   if(lMid < lLeft && lMid < lRight)
   {
      outSwing.type      = SWING_TYPE_LOW;
      outSwing.price     = lMid;
      outSwing.time      = iTime(symbol, tf, barIndex);
      outSwing.barIndex  = barIndex;
      outSwing.timeframe = tf;
      outSwing.isValid   = true;
      return true;
   }
   return false;
}

// Get most recent confirmed swing on a given timeframe scanning backward
bool FindMostRecentSwingHigh(string symbol, ENUM_TIMEFRAMES tf, int maxLookbackBars, SMCSwing &outSwing, int startBar = -1)
{
   if(startBar < 0)
      startBar = (tf == PERIOD_M5) ? 2 : 3;

   for(int i = startBar; i <= maxLookbackBars; i++)
   {
      bool found = (tf == PERIOD_M5)
                   ? Get3BarSwingHigh(symbol, tf, i, outSwing)
                   : Get5BarSwingHigh(symbol, tf, i, outSwing);
      if(found) return true;
   }
   return false;
}

bool FindMostRecentSwingLow(string symbol, ENUM_TIMEFRAMES tf, int maxLookbackBars, SMCSwing &outSwing, int startBar = -1)
{
   if(startBar < 0)
      startBar = (tf == PERIOD_M5) ? 2 : 3;

   for(int i = startBar; i <= maxLookbackBars; i++)
   {
      bool found = (tf == PERIOD_M5)
                   ? Get3BarSwingLow(symbol, tf, i, outSwing)
                   : Get5BarSwingLow(symbol, tf, i, outSwing);
      if(found) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MARKET STRUCTURE TRACKER                                         |
//| Timeframe-independent structure mapping (BULLISH/BEARISH/UNDEF) |
//+------------------------------------------------------------------+

ENUM_SMC_STRUCTURE GetTimeframeStructure(string symbol, ENUM_TIMEFRAMES tf, int lookbackBars = 50)
{
   SMCSwing high1, high2, low1, low2;
   ZeroMemory(high1); ZeroMemory(high2); ZeroMemory(low1); ZeroMemory(low2);

   int hCount = 0, lCount = 0;
   int startBar = (tf == PERIOD_M5) ? 2 : 3;

   for(int i = startBar; i <= lookbackBars && (hCount < 2 || lCount < 2); i++)
   {
      SMCSwing tempSwing;
      bool isHigh = (tf == PERIOD_M5) ? Get3BarSwingHigh(symbol, tf, i, tempSwing) : Get5BarSwingHigh(symbol, tf, i, tempSwing);
      if(isHigh && hCount < 2)
      {
         if(hCount == 0) high1 = tempSwing;
         else high2 = tempSwing;
         hCount++;
      }

      bool isLow = (tf == PERIOD_M5) ? Get3BarSwingLow(symbol, tf, i, tempSwing) : Get5BarSwingLow(symbol, tf, i, tempSwing);
      if(isLow && lCount < 2)
      {
         if(lCount == 0) low1 = tempSwing;
         else low2 = tempSwing;
         lCount++;
      }
   }

   if(hCount < 2 || lCount < 2) return SMC_STRUCTURE_UNDEFINED;

   bool higherHigh = (high1.price > high2.price);
   bool higherLow  = (low1.price > low2.price);
   bool lowerHigh  = (high1.price < high2.price);
   bool lowerLow   = (low1.price < low2.price);

   if(higherHigh && higherLow) return SMC_STRUCTURE_BULLISH;
   if(lowerHigh && lowerLow)   return SMC_STRUCTURE_BEARISH;

   return SMC_STRUCTURE_UNDEFINED;
}

//+------------------------------------------------------------------+
//| 4H POI DETECTION & REGISTRATION                                  |
//| Bullish/Bearish Order Blocks & FVGs have EQUAL status.          |
//| Direction filtering: must agree with 4H structural direction.   |
//| Selection: Most recent valid, uninvalidated POI.                 |
//| Activation: M15 bar range [Low, High] intersects POI range.      |
//| Invalidation: OB: 4H close beyond extreme; FVG: close through C1 |
//+------------------------------------------------------------------+

static SMCPOI g_Registered4HPOIs[];

void Register4HPOI(const SMCPOI &poi)
{
   int total = ArraySize(g_Registered4HPOIs);
   for(int i = 0; i < total; i++)
   {
      if(g_Registered4HPOIs[i].timeframe == poi.timeframe &&
         g_Registered4HPOIs[i].type == poi.type &&
         g_Registered4HPOIs[i].time == poi.time)
      {
         g_Registered4HPOIs[i] = poi;
         return;
      }
   }
   ArrayResize(g_Registered4HPOIs, total + 1);
   g_Registered4HPOIs[total] = poi;
}

void ClearRegistered4HPOIs()
{
   ArrayFree(g_Registered4HPOIs);
}

// Detect 4H Fair Value Gap at bar index c3BarIndex
bool Find4HFVG(string symbol, int c3BarIndex, SMCPOI &outPOI)
{
   ZeroMemory(outPOI);

   if(c3BarIndex < 1) return false;
   int c1BarIndex = c3BarIndex + 2;

   double highC1 = iHigh(symbol, SMC_4H_Timeframe, c1BarIndex);
   double lowC1  = iLow(symbol, SMC_4H_Timeframe, c1BarIndex);

   double highC3 = iHigh(symbol, SMC_4H_Timeframe, c3BarIndex);
   double lowC3  = iLow(symbol, SMC_4H_Timeframe, c3BarIndex);

   if(highC1 == 0 || lowC3 == 0) return false;

   // Bullish FVG: Low(C3) > High(C1)
   if(lowC3 > highC1)
   {
      outPOI.type      = POI_TYPE_DEMAND;
      outPOI.bottom    = highC1;
      outPOI.top       = lowC3;
      outPOI.time      = iTime(symbol, SMC_4H_Timeframe, c3BarIndex);
      outPOI.timeframe = SMC_4H_Timeframe;
      outPOI.isActive  = true;

      // Invalidation check: completed 4H candle closed through C1 boundary (below bottom)
      for(int k = c3BarIndex - 1; k >= 1; k--)
      {
         double cl = iClose(symbol, SMC_4H_Timeframe, k);
         if(cl > 0 && cl < outPOI.bottom)
         {
            outPOI.isActive = false;
            return false;
         }
      }
      return true;
   }
   // Bearish FVG: High(C3) < Low(C1)
   else if(highC3 < lowC1)
   {
      outPOI.type      = POI_TYPE_SUPPLY;
      outPOI.bottom    = highC3;
      outPOI.top       = lowC1;
      outPOI.time      = iTime(symbol, SMC_4H_Timeframe, c3BarIndex);
      outPOI.timeframe = SMC_4H_Timeframe;
      outPOI.isActive  = true;

      // Invalidation check: completed 4H candle closed through C1 boundary (above top)
      for(int k = c3BarIndex - 1; k >= 1; k--)
      {
         double cl = iClose(symbol, SMC_4H_Timeframe, k);
         if(cl > 0 && cl > outPOI.top)
         {
            outPOI.isActive = false;
            return false;
         }
      }
      return true;
   }

   return false;
}

// Detect 4H Order Block at bar index obBarIndex
// Bullish OB: final bearish/down-close candle before qualifying bullish displacement/move.
// Bearish OB: final bullish/up-close candle before qualifying bearish displacement/move.
// Coherence Rules:
// - The candidate OB candle must be followed by a qualifying directional displacement move
//   originating after obBarIndex (c1 <= obBarIndex) that produces BOTH:
//   1) a directional displacement candle (c2 Close > Open for bullish, Close < Open for bearish),
//   2) an associated 3-candle FVG (Low(C3) > High(C1) for bullish, High(C3) < Low(C1) for bearish), AND
//   3) a candle body-close BOS beyond the relevant prior 4H swing level.
// - Note: The 50-bar lookback for prior swing detection is an engineering search limit for performance,
//   not a strategy restriction. Intervening candles are allowed. No arbitrary N-candle confirmation limit,
//   pip/point threshold, ATR limit, or minimum size threshold is introduced.
// - Full High-Low OB boundaries, completed candles only, body-close BOS, wick-to-wick FVG, and
//   OB invalidation on completed 4H candle close beyond the OB extreme are strictly preserved.
bool Find4HOrderBlock(string symbol, int obBarIndex, SMCPOI &outPOI)
{
   ZeroMemory(outPOI);

   if(obBarIndex < 3) return false;

   double openOB  = iOpen(symbol, SMC_4H_Timeframe, obBarIndex);
   double closeOB = iClose(symbol, SMC_4H_Timeframe, obBarIndex);
   double highOB  = iHigh(symbol, SMC_4H_Timeframe, obBarIndex);
   double lowOB   = iLow(symbol, SMC_4H_Timeframe, obBarIndex);

   if(openOB == 0 || closeOB == 0) return false;

   // Bullish OB: final down-close candle before qualifying bullish displacement/move
   if(closeOB < openOB)
   {
      // 1. Find prior 4H swing high formed at or before obBarIndex for BOS confirmation
      // (50 bars is an engineering search limit for performance, not a strategy rule)
      SMCSwing prevHigh;
      if(!FindMostRecentSwingHigh(symbol, SMC_4H_Timeframe, 50, prevHigh, obBarIndex + 1))
         return false;

      // 2. Search forward in chronological order after the OB (c1 <= obBarIndex)
      //    for a 3-candle displacement sequence (c1, c2, c3) that produces BOTH an associated FVG and body-close BOS.
      bool hasQualifyingMove = false;

      for(int c1 = obBarIndex; c1 >= 3; c1--)
      {
         int c2 = c1 - 1;
         int c3 = c1 - 2;

         double openC2 = iOpen(symbol, SMC_4H_Timeframe, c2);
         double clC2   = iClose(symbol, SMC_4H_Timeframe, c2);
         double clC3   = iClose(symbol, SMC_4H_Timeframe, c3);

         double highC1 = iHigh(symbol, SMC_4H_Timeframe, c1);
         double lowC3  = iLow(symbol, SMC_4H_Timeframe, c3);

         // Displacement check: C2 must be a bullish directional displacement candle (Close > Open)
         if(clC2 > openC2)
         {
            if(highC1 > 0 && lowC3 > highC1) // Associated 3-candle Bullish FVG
            {
               if(clC2 > prevHigh.price || clC3 > prevHigh.price) // Candle body-close BOS associated with this move
               {
                  hasQualifyingMove = true;
                  break;
               }
            }
         }
      }

      if(!hasQualifyingMove) return false;

      outPOI.type      = POI_TYPE_DEMAND;
      outPOI.bottom    = lowOB;
      outPOI.top       = highOB;
      outPOI.time      = iTime(symbol, SMC_4H_Timeframe, obBarIndex);
      outPOI.timeframe = SMC_4H_Timeframe;
      outPOI.isActive  = true;

      // Invalidation check: completed 4H candle closed below OB low (bottom)
      for(int k = obBarIndex - 1; k >= 1; k--)
      {
         double cl = iClose(symbol, SMC_4H_Timeframe, k);
         if(cl > 0 && cl < outPOI.bottom)
         {
            outPOI.isActive = false;
            return false;
         }
      }
      return true;
   }
   // Bearish OB: final up-close candle before qualifying bearish displacement/move
   else if(closeOB > openOB)
   {
      // 1. Find prior 4H swing low formed at or before obBarIndex for BOS confirmation
      // (50 bars is an engineering search limit for performance, not a strategy rule)
      SMCSwing prevLow;
      if(!FindMostRecentSwingLow(symbol, SMC_4H_Timeframe, 50, prevLow, obBarIndex + 1))
         return false;

      // 2. Search forward in chronological order after the OB (c1 <= obBarIndex)
      //    for a 3-candle displacement sequence (c1, c2, c3) that produces BOTH an associated FVG and body-close BOS.
      bool hasQualifyingMove = false;

      for(int c1 = obBarIndex; c1 >= 3; c1--)
      {
         int c2 = c1 - 1;
         int c3 = c1 - 2;

         double openC2 = iOpen(symbol, SMC_4H_Timeframe, c2);
         double clC2   = iClose(symbol, SMC_4H_Timeframe, c2);
         double clC3   = iClose(symbol, SMC_4H_Timeframe, c3);

         double lowC1  = iLow(symbol, SMC_4H_Timeframe, c1);
         double highC3 = iHigh(symbol, SMC_4H_Timeframe, c3);

         // Displacement check: C2 must be a bearish directional displacement candle (Close < Open)
         if(clC2 < openC2)
         {
            if(lowC1 > 0 && highC3 < lowC1) // Associated 3-candle Bearish FVG
            {
               if(clC2 < prevLow.price || clC3 < prevLow.price) // Candle body-close BOS associated with this move
               {
                  hasQualifyingMove = true;
                  break;
               }
            }
         }
      }

      if(!hasQualifyingMove) return false;

      outPOI.type      = POI_TYPE_SUPPLY;
      outPOI.bottom    = lowOB;
      outPOI.top       = highOB;
      outPOI.time      = iTime(symbol, SMC_4H_Timeframe, obBarIndex);
      outPOI.timeframe = SMC_4H_Timeframe;
      outPOI.isActive  = true;

      // Invalidation check: completed 4H candle closed above OB high (top)
      for(int k = obBarIndex - 1; k >= 1; k--)
      {
         double cl = iClose(symbol, SMC_4H_Timeframe, k);
         if(cl > 0 && cl > outPOI.top)
         {
            outPOI.isActive = false;
            return false;
         }
      }
      return true;
   }

   return false;
}

// Get the most recent valid, uninvalidated 4H POI agreeing with 4H structural direction
bool GetActive4HPOI(string symbol, SMCPOI &outPOI)
{
   ZeroMemory(outPOI);
   outPOI.isActive = false;

   // 1. Check 4H structural direction first
   ENUM_SMC_STRUCTURE structure4H = GetTimeframeStructure(symbol, SMC_4H_Timeframe, 50);
   if(structure4H == SMC_STRUCTURE_UNDEFINED) return false;

   SMCPOI newestPOI;
   ZeroMemory(newestPOI);
   datetime newestTime = 0;

   // 2. Check registered POIs (must satisfy same direction filter, validity, and invalidation rules)
   int total = ArraySize(g_Registered4HPOIs);
   for(int i = 0; i < total; i++)
   {
      if(g_Registered4HPOIs[i].isActive && g_Registered4HPOIs[i].timeframe == SMC_4H_Timeframe)
      {
         bool matchesDir = (structure4H == SMC_STRUCTURE_BULLISH && g_Registered4HPOIs[i].type == POI_TYPE_DEMAND) ||
                           (structure4H == SMC_STRUCTURE_BEARISH && g_Registered4HPOIs[i].type == POI_TYPE_SUPPLY);
         if(matchesDir)
         {
            // Verify registered POI is not invalidated by subsequent 4H candle closes
            bool isInvalidated = false;
            int regBarIndex = iBarShift(symbol, SMC_4H_Timeframe, g_Registered4HPOIs[i].time, false);
            if(regBarIndex > 1)
            {
               for(int k = regBarIndex - 1; k >= 1; k--)
               {
                  double cl = iClose(symbol, SMC_4H_Timeframe, k);
                  if(g_Registered4HPOIs[i].type == POI_TYPE_DEMAND && cl > 0 && cl < g_Registered4HPOIs[i].bottom)
                  {
                     isInvalidated = true;
                     break;
                  }
                  if(g_Registered4HPOIs[i].type == POI_TYPE_SUPPLY && cl > 0 && cl > g_Registered4HPOIs[i].top)
                  {
                     isInvalidated = true;
                     break;
                  }
               }
            }

            if(!isInvalidated && g_Registered4HPOIs[i].time > newestTime)
            {
               newestPOI = g_Registered4HPOIs[i];
               newestTime = g_Registered4HPOIs[i].time;
            }
         }
      }
   }

   // 3. Scan 4H bars for most recent valid, uninvalidated POI (OB and FVG have EQUAL status)
   for(int i = 1; i <= 50; i++)
   {
      // Check 4H FVG
      SMCPOI fvgPOI;
      if(Find4HFVG(symbol, i, fvgPOI))
      {
         bool matchesDir = (structure4H == SMC_STRUCTURE_BULLISH && fvgPOI.type == POI_TYPE_DEMAND) ||
                           (structure4H == SMC_STRUCTURE_BEARISH && fvgPOI.type == POI_TYPE_SUPPLY);
         if(matchesDir && fvgPOI.time > newestTime)
         {
            newestPOI = fvgPOI;
            newestTime = fvgPOI.time;
         }
      }

      // Check 4H OB
      SMCPOI obPOI;
      if(Find4HOrderBlock(symbol, i, obPOI))
      {
         bool matchesDir = (structure4H == SMC_STRUCTURE_BULLISH && obPOI.type == POI_TYPE_DEMAND) ||
                           (structure4H == SMC_STRUCTURE_BEARISH && obPOI.type == POI_TYPE_SUPPLY);
         if(matchesDir && obPOI.time > newestTime)
         {
            newestPOI = obPOI;
            newestTime = obPOI.time;
         }
      }
   }

   if(newestTime > 0)
   {
      outPOI = newestPOI;
      return true;
   }

   return false;
}

// Check if completed M15 candle intersects 4H POI
bool IsPriceIn4HPOI(string symbol, const SMCPOI &poi)
{
   if(!poi.isActive) return false;

   double m15High = iHigh(symbol, SMC_M15_Timeframe, 1);
   double m15Low  = iLow(symbol, SMC_M15_Timeframe, 1);

   // Intersection of bar range [m15Low, m15High] with POI range [poi.bottom, poi.top]
   if(m15High >= poi.bottom && m15Low <= poi.top)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| M15 LIQUIDITY SWEEP DETECTION                                    |
//| Deterministic rule:                                              |
//|   LONG: M15 Low[1] < SwingLow.price AND Close[1] > SwingLow.price|
//|   SHORT: M15 High[1] > SwingHigh.price AND Close[1] < SwingHigh.p|
//+------------------------------------------------------------------+

bool CheckM15LiquiditySweep(string symbol, const SMCPOI &poi, ENUM_SIGNAL_TYPE direction, SMCSwing &outSweptSwing)
{
   ZeroMemory(outSweptSwing);

   if(!IsPriceIn4HPOI(symbol, poi)) return false;

   // Check if this exact sweep on this POI was already processed and invalidated in history for this symbol
   datetime m15Bar1Time = iTime(symbol, SMC_M15_Timeframe, 1);

   for(int s = 0; s < ArraySize(g_SMCSetups); s++)
   {
      if(g_SMCSetups[s].symbol == symbol && g_SMCSetups[s].state == SMC_INVALIDATED)
      {
         if(g_SMCSetups[s].poi4H.time == poi.time && g_SMCSetups[s].sweepTime == m15Bar1Time)
         {
            // Already processed and invalidated sweep for this POI and candle
            return false;
         }
      }
   }

   if(direction == SIGNAL_BUY && poi.type == POI_TYPE_DEMAND)
   {
      SMCSwing m15Low;
      if(FindMostRecentSwingLow(symbol, SMC_M15_Timeframe, 40, m15Low))
      {
         double low1   = iLow(symbol, SMC_M15_Timeframe, 1);
         double close1 = iClose(symbol, SMC_M15_Timeframe, 1);

         if(low1 < m15Low.price && close1 > m15Low.price)
         {
            outSweptSwing = m15Low;
            SMCLog("", symbol, "SWEEP_DETECTED",
                   StringFormat("BUY Sweep Detected | CandleBar1Time=%s | Low1=%.5f | Close1=%.5f | SweptSwingTime=%s | SweptSwingPrice=%.5f",
                                TimeToString(m15Bar1Time, TIME_DATE|TIME_MINUTES), low1, close1,
                                TimeToString(m15Low.time, TIME_DATE|TIME_MINUTES), m15Low.price));
            return true;
         }
      }
   }
   else if(direction == SIGNAL_SELL && poi.type == POI_TYPE_SUPPLY)
   {
      SMCSwing m15High;
      if(FindMostRecentSwingHigh(symbol, SMC_M15_Timeframe, 40, m15High))
      {
         double high1  = iHigh(symbol, SMC_M15_Timeframe, 1);
         double close1 = iClose(symbol, SMC_M15_Timeframe, 1);

         if(high1 > m15High.price && close1 < m15High.price)
         {
            outSweptSwing = m15High;
            SMCLog("", symbol, "SWEEP_DETECTED",
                   StringFormat("SELL Sweep Detected | CandleBar1Time=%s | High1=%.5f | Close1=%.5f | SweptSwingTime=%s | SweptSwingPrice=%.5f",
                                TimeToString(m15Bar1Time, TIME_DATE|TIME_MINUTES), high1, close1,
                                TimeToString(m15High.time, TIME_DATE|TIME_MINUTES), m15High.price));
            return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| CHoCH SWING SELECTION & DETECTION                                |
//| Bullish CHoCH:                                                   |
//|   Start from final bearish extreme/sweep.                        |
//|   Search backward for confirmed M15 Lower High that directly     |
//|   originated the final downward leg into the sweep low.          |
//|   Completed M15 candle BODY CLOSES above that Lower High.        |
//| Bearish CHoCH:                                                   |
//|   Start from final bullish extreme/sweep.                        |
//|   Search backward for confirmed M15 Higher Low that directly     |
//|   preceded the final upward leg into the sweep high.             |
//|   Completed M15 candle BODY CLOSES below that Higher Low.        |
//+------------------------------------------------------------------+

// Deterministic CHoCH swing selection:
// Scans backward from swept extreme timestamp (sweepTime) across available M15 history to identify
// the confirmed 5-bar M15 swing (Lower High for Buy, Higher Low for Sell) that directly originated
// the final structural leg into the swept extreme.
// Source Limitation Note: If no confirmed 5-bar swing exists in available M15 history prior to sweepTime,
// or if structure is ambiguous without explicit source rules, FindCHoCHLevel returns false and the setup
// is safely invalidated rather than inventing unconfirmed swings or arbitrary lookback/threshold rules.
bool FindCHoCHLevel(string symbol, ENUM_SIGNAL_TYPE direction, datetime sweepTime, SMCSwing &outChochSwing)
{
   ZeroMemory(outChochSwing);

   if(sweepTime <= 0) return false;

   int sweepBar = iBarShift(symbol, SMC_M15_Timeframe, sweepTime, false);
   if(sweepBar < 0) return false;

   int startBar = MathMax(3, sweepBar);
   int totalBars = iBars(symbol, SMC_M15_Timeframe);
   int maxBarIndex = (totalBars > 0) ? (totalBars - 3) : (startBar + 300);

   double currentClose = iClose(symbol, SMC_M15_Timeframe, 1);

   SMCLog("", symbol, "CHOCH_EVAL_START",
          StringFormat("Direction=%s | SweepTime=%s | SweepBar=%d | CurrentM15Close=%.5f",
                       direction == SIGNAL_BUY ? "BUY" : "SELL",
                       TimeToString(sweepTime, TIME_DATE|TIME_MINUTES),
                       sweepBar, currentClose));

   if(direction == SIGNAL_BUY)
   {
      // 1. Find swing1: most recent confirmed 5-bar M15 swing high directly associated with leg before sweepTime
      SMCSwing swing1;
      ZeroMemory(swing1);
      int swing1Bar = -1;

      for(int i = startBar; i <= maxBarIndex; i++)
      {
         SMCSwing swing;
         if(Get5BarSwingHigh(symbol, SMC_M15_Timeframe, i, swing))
         {
            if(swing.time < sweepTime)
            {
               swing1 = swing;
               swing1Bar = i;
               break;
            }
         }
      }

      if(!swing1.isValid || swing1Bar < 0)
      {
         SMCLog("", symbol, "CHOCH_EVAL_FAILED", "No confirmed 5-bar M15 swing high found prior to sweepTime");
         return false;
      }

      // 2. Find swing2: preceding confirmed 5-bar M15 swing high before swing1
      SMCSwing swing2;
      ZeroMemory(swing2);

      for(int j = swing1Bar + 1; j <= maxBarIndex; j++)
      {
         SMCSwing candidatePrev;
         if(Get5BarSwingHigh(symbol, SMC_M15_Timeframe, j, candidatePrev))
         {
            if(candidatePrev.time < swing1.time)
            {
               swing2 = candidatePrev;
               break;
            }
         }
      }

      if(!swing2.isValid)
      {
         SMCLog("", symbol, "CHOCH_CANDIDATE_REJECTED",
                StringFormat("Candidate high at %s (bar %d, price %.5f) rejected: no preceding confirmed swing high found to verify LH structure",
                             TimeToString(swing1.time, TIME_DATE|TIME_MINUTES), swing1Bar, swing1.price));
         return false;
      }

      // 3. Verify structural relationship: swing1 must be a Lower High relative to swing2
      if(swing1.price < swing2.price)
      {
         outChochSwing = swing1;
         bool bodyCloseSatisfied = (currentClose > swing1.price);

         SMCLog("", symbol, "CHOCH_CANDIDATE_ACCEPTED",
                StringFormat("Selected CHoCH LH at %s (bar %d, price %.5f) | Preceding High at %s (price %.5f, LH=TRUE) | CHoCH Level=%.5f | CurrentClose=%.5f | BodyCloseSatisfied=%s",
                             TimeToString(swing1.time, TIME_DATE|TIME_MINUTES), swing1Bar, swing1.price,
                             TimeToString(swing2.time, TIME_DATE|TIME_MINUTES), swing2.price,
                             swing1.price, currentClose, bodyCloseSatisfied ? "YES" : "NO"));
         return true;
      }
      else
      {
         SMCLog("", symbol, "CHOCH_CANDIDATE_REJECTED",
                StringFormat("Candidate high at %s (bar %d, price %.5f) rejected: NOT an LH relative to preceding high at %s (price %.5f)",
                             TimeToString(swing1.time, TIME_DATE|TIME_MINUTES), swing1Bar, swing1.price,
                             TimeToString(swing2.time, TIME_DATE|TIME_MINUTES), swing2.price));
         return false;
      }
   }
   else if(direction == SIGNAL_SELL)
   {
      // 1. Find swing1: most recent confirmed 5-bar M15 swing low directly associated with leg before sweepTime
      SMCSwing swing1;
      ZeroMemory(swing1);
      int swing1Bar = -1;

      for(int i = startBar; i <= maxBarIndex; i++)
      {
         SMCSwing swing;
         if(Get5BarSwingLow(symbol, SMC_M15_Timeframe, i, swing))
         {
            if(swing.time < sweepTime)
            {
               swing1 = swing;
               swing1Bar = i;
               break;
            }
         }
      }

      if(!swing1.isValid || swing1Bar < 0)
      {
         SMCLog("", symbol, "CHOCH_EVAL_FAILED", "No confirmed 5-bar M15 swing low found prior to sweepTime");
         return false;
      }

      // 2. Find swing2: preceding confirmed 5-bar M15 swing low before swing1
      SMCSwing swing2;
      ZeroMemory(swing2);

      for(int j = swing1Bar + 1; j <= maxBarIndex; j++)
      {
         SMCSwing candidatePrev;
         if(Get5BarSwingLow(symbol, SMC_M15_Timeframe, j, candidatePrev))
         {
            if(candidatePrev.time < swing1.time)
            {
               swing2 = candidatePrev;
               break;
            }
         }
      }

      if(!swing2.isValid)
      {
         SMCLog("", symbol, "CHOCH_CANDIDATE_REJECTED",
                StringFormat("Candidate low at %s (bar %d, price %.5f) rejected: no preceding confirmed swing low found to verify HL structure",
                             TimeToString(swing1.time, TIME_DATE|TIME_MINUTES), swing1Bar, swing1.price));
         return false;
      }

      // 3. Verify structural relationship: swing1 must be a Higher Low relative to swing2
      if(swing1.price > swing2.price)
      {
         outChochSwing = swing1;
         bool bodyCloseSatisfied = (currentClose < swing1.price);

         SMCLog("", symbol, "CHOCH_CANDIDATE_ACCEPTED",
                StringFormat("Selected CHoCH HL at %s (bar %d, price %.5f) | Preceding Low at %s (price %.5f, HL=TRUE) | CHoCH Level=%.5f | CurrentClose=%.5f | BodyCloseSatisfied=%s",
                             TimeToString(swing1.time, TIME_DATE|TIME_MINUTES), swing1Bar, swing1.price,
                             TimeToString(swing2.time, TIME_DATE|TIME_MINUTES), swing2.price,
                             swing1.price, currentClose, bodyCloseSatisfied ? "YES" : "NO"));
         return true;
      }
      else
      {
         SMCLog("", symbol, "CHOCH_CANDIDATE_REJECTED",
                StringFormat("Candidate low at %s (bar %d, price %.5f) rejected: NOT an HL relative to preceding low at %s (price %.5f)",
                             TimeToString(swing1.time, TIME_DATE|TIME_MINUTES), swing1Bar, swing1.price,
                             TimeToString(swing2.time, TIME_DATE|TIME_MINUTES), swing2.price));
         return false;
      }
   }
   return false;
}

bool FindCHoCHLevel(string symbol, ENUM_SIGNAL_TYPE direction, const SMCSwing &sweptSwing, SMCSwing &outChochSwing)
{
   if(!sweptSwing.isValid || sweptSwing.time <= 0) return false;
   return FindCHoCHLevel(symbol, direction, sweptSwing.time, outChochSwing);
}

bool CheckM15CHoCH(string symbol, ENUM_SIGNAL_TYPE direction, const SMCSwing &chochSwing, bool newCompletedBar = true)
{
   if(chochSwing.price <= 0) return false;

   int barIndex = 1;
   datetime barTime = iTime(symbol, SMC_M15_Timeframe, barIndex);
   double open1  = iOpen(symbol, SMC_M15_Timeframe, barIndex);
   double high1  = iHigh(symbol, SMC_M15_Timeframe, barIndex);
   double low1   = iLow(symbol, SMC_M15_Timeframe, barIndex);
   double close1 = iClose(symbol, SMC_M15_Timeframe, barIndex);
   datetime currentTesterTime = TimeCurrent();

   bool result = false;
   string comparisonStr = "";

   if(direction == SIGNAL_BUY)
   {
      // Body close above Lower High
      result = (close1 > chochSwing.price);
      comparisonStr = StringFormat("Close %.5f > LH %.5f", close1, chochSwing.price);
   }
   else if(direction == SIGNAL_SELL)
   {
      // Body close below Higher Low
      result = (close1 < chochSwing.price);
      comparisonStr = StringFormat("Close %.5f < HL %.5f", close1, chochSwing.price);
   }

   SMCLog("", symbol, "CHOCH_CHECK",
          StringFormat("Direction=%s | CandidateLevel=%.5f | EvaluatedBarIndex=%d | EvaluatedBarTime=%s | IsCompleted=TRUE | Open=%.5f | High=%.5f | Low=%.5f | Close=%.5f | CurrentTesterTime=%s | NewCompletedBar=%s | Comparison=(%s) | Result=%s",
                       direction == SIGNAL_BUY ? "BUY" : "SELL",
                       chochSwing.price,
                       barIndex,
                       TimeToString(barTime, TIME_DATE|TIME_MINUTES),
                       open1, high1, low1, close1,
                       TimeToString(currentTesterTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                       newCompletedBar ? "YES" : "NO",
                       comparisonStr,
                       result ? "TRUE" : "FALSE"));

   return result;
}

//+------------------------------------------------------------------+
//| M5 DISPLACEMENT & FVG DETECTION (TIED TO DISPLACEMENT EVENT)     |
//| 3-candle structure on M5:                                        |
//|   C1 = bar 3 (first candle)                                      |
//|   C2 = bar 2 (middle / displacement candle)                      |
//|   C3 = bar 1 (third candle, confirms FVG pattern after close)    |
//|   Bullish: C2 Close > Open, C2 Close > SwingHigh, Low(C3) > High(C1)|
//|   Bearish: C2 Close < Open, C2 Close < SwingLow, High(C3) < Low(C1)|
//| Midpoint calculation = (Top + Bottom) / 2                        |
//| Invalidation: Body close beyond Candle 1 boundary                |
//+------------------------------------------------------------------+

bool CheckM5DisplacementAndFVG(string symbol, ENUM_SIGNAL_TYPE direction, SMCSwing &outM5Swing, SMCFVG &outFVG)
{
   ZeroMemory(outM5Swing);
   ZeroMemory(outFVG);
   outFVG.isValid = false;

   // C3 is bar 1 (most recent completed candle)
   // C2 is bar 2 (middle candle / displacement candle)
   // C1 is bar 3 (first candle)

   double openC2  = iOpen(symbol, SMC_M5_Timeframe, 2);
   double closeC2 = iClose(symbol, SMC_M5_Timeframe, 2);

   double highC1  = iHigh(symbol, SMC_M5_Timeframe, 3);
   double lowC1   = iLow(symbol, SMC_M5_Timeframe, 3);

   double highC3  = iHigh(symbol, SMC_M5_Timeframe, 1);
   double lowC3   = iLow(symbol, SMC_M5_Timeframe, 1);

   if(direction == SIGNAL_BUY)
   {
      // 1. C2 must be the bullish displacement candle (Close > Open)
      if(closeC2 <= openC2) return false;

      // 2. C2 body close must break relevant confirmed M5 swing high (prior to C2, i.e. bar >= 3)
      SMCSwing m5High;
      if(!FindMostRecentSwingHigh(symbol, SMC_M5_Timeframe, 30, m5High, 3)) return false;
      if(closeC2 <= m5High.price) return false;

      // 3. C3 completes 3-candle sequence creating valid bullish FVG (Low(C3) > High(C1))
      if(lowC3 <= highC1) return false;

      outM5Swing         = m5High;
      outFVG.isBullish   = true;
      outFVG.bottom      = highC1;
      outFVG.top         = lowC3;
      outFVG.midpoint    = (outFVG.top + outFVG.bottom) / 2.0;
      outFVG.timeC3      = iTime(symbol, SMC_M5_Timeframe, 1);
      outFVG.c1Index     = 3;
      outFVG.c2Index     = 2;
      outFVG.c3Index     = 1;
      outFVG.isValid     = true;
      outFVG.isMitigated = false;
      return true;
   }
   else if(direction == SIGNAL_SELL)
   {
      // 1. C2 must be the bearish displacement candle (Close < Open)
      if(closeC2 >= openC2) return false;

      // 2. C2 body close must break relevant confirmed M5 swing low (prior to C2, i.e. bar >= 3)
      SMCSwing m5Low;
      if(!FindMostRecentSwingLow(symbol, SMC_M5_Timeframe, 30, m5Low, 3)) return false;
      if(closeC2 >= m5Low.price) return false;

      // 3. C3 completes 3-candle sequence creating valid bearish FVG (High(C3) < Low(C1))
      if(highC3 >= lowC1) return false;

      outM5Swing         = m5Low;
      outFVG.isBullish   = false;
      outFVG.bottom      = highC3;
      outFVG.top         = lowC1;
      outFVG.midpoint    = (outFVG.top + outFVG.bottom) / 2.0;
      outFVG.timeC3      = iTime(symbol, SMC_M5_Timeframe, 1);
      outFVG.c1Index     = 3;
      outFVG.c2Index     = 2;
      outFVG.c3Index     = 1;
      outFVG.isValid     = true;
      outFVG.isMitigated = false;
      return true;
   }

   return false;
}

bool IsFVGInvalidated(string symbol, const SMCFVG &fvg)
{
   if(!fvg.isValid) return true;

   double close1 = iClose(symbol, SMC_M5_Timeframe, 1);

   if(fvg.isBullish)
   {
      // Invalidated if completed candle closes below Candle 1 boundary (bottom)
      if(close1 < fvg.bottom) return true;
   }
   else
   {
      // Invalidated if completed candle closes above Candle 1 boundary (top)
      if(close1 > fvg.top) return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| M5 ORDER BLOCK (Supporting Context)                              |
//| Low -> High range of final opposite-close candle before          |
//| displacement.                                                     |
//+------------------------------------------------------------------+

bool FindM5OrderBlock(string symbol, ENUM_SIGNAL_TYPE direction, SMCOrderBlock &outOB)
{
   ZeroMemory(outOB);

   for(int i = 2; i <= 10; i++)
   {
      double openI  = iOpen(symbol, SMC_M5_Timeframe, i);
      double closeI = iClose(symbol, SMC_M5_Timeframe, i);

      if(direction == SIGNAL_BUY && closeI < openI) // Down-close candle
      {
         outOB.isBullish = true;
         outOB.high      = iHigh(symbol, SMC_M5_Timeframe, i);
         outOB.low       = iLow(symbol, SMC_M5_Timeframe, i);
         outOB.time      = iTime(symbol, SMC_M5_Timeframe, i);
         outOB.isValid   = true;
         return true;
      }
      else if(direction == SIGNAL_SELL && closeI > openI) // Up-close candle
      {
         outOB.isBullish = false;
         outOB.high      = iHigh(symbol, SMC_M5_Timeframe, i);
         outOB.low       = iLow(symbol, SMC_M5_Timeframe, i);
         outOB.time      = iTime(symbol, SMC_M5_Timeframe, i);
         outOB.isValid   = true;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| STATE MACHINE & LIFECYCLE MANAGEMENT                             |
//+------------------------------------------------------------------+

void InvalidateSetup(SMCSetup &setup, string reason)
{
   setup.state = SMC_INVALIDATED;
   setup.invalidationReason = reason;
   setup.lastUpdatedTime = TimeCurrent();
   SMCLog(setup.setupID, setup.symbol, "SETUP_INVALIDATED", StringFormat("Reason: %s", reason));
}

// Helper: Count total active setups
int CountActiveSetups()
{
   int count = 0;
   int total = ArraySize(g_SMCSetups);
   for(int i = 0; i < total; i++)
   {
      if(g_SMCSetups[i].state != SMC_INVALIDATED && g_SMCSetups[i].state != SMC_COMPLETED && g_SMCSetups[i].state != SMC_IDLE)
         count++;
   }
   return count;
}

// Manage lifecycle for a specific setup on a symbol
void ProcessSMCSetupStateMachine(SMCSetup &setup)
{
   if(setup.state == SMC_INVALIDATED || setup.state == SMC_COMPLETED)
      return;

   string symbol = setup.symbol;
   datetime now  = TimeCurrent();
   setup.lastUpdatedTime = now;

   ENUM_SMC_STATE prevState = setup.state;

   switch(setup.state)
   {
      case SMC_IDLE:
      {
         if(CountActiveSetups() >= SMC_MaxActiveSetups)
         {
            break; // Max active setups limit reached
         }

         // Scan for 4H POI
         SMCPOI poi;
         if(GetActive4HPOI(symbol, poi))
         {
            setup.poi4H = poi;
            setup.direction = (poi.type == POI_TYPE_DEMAND) ? SIGNAL_BUY : SIGNAL_SELL;
            setup.state = SMC_H4_POI_ACTIVE;
         }
         break;
      }

      case SMC_H4_POI_ACTIVE:
      {
         if(!setup.poi4H.isActive)
         {
            InvalidateSetup(setup, "4H POI inactive");
            break;
         }

         if(IsPriceIn4HPOI(symbol, setup.poi4H))
         {
            setup.state = SMC_WAITING_FOR_M15_SWEEP;
         }
         break;
      }

      case SMC_WAITING_FOR_M15_SWEEP:
      {
         if(!setup.poi4H.isActive)
         {
            InvalidateSetup(setup, "4H POI inactive");
            break;
         }

         SMCSwing sweptSwing;
         if(CheckM15LiquiditySweep(symbol, setup.poi4H, setup.direction, sweptSwing))
         {
            setup.m15SweptSwing = sweptSwing;
            setup.sweepPrice     = (setup.direction == SIGNAL_BUY) ? iLow(symbol, SMC_M15_Timeframe, 1) : iHigh(symbol, SMC_M15_Timeframe, 1);
            setup.sweepTime      = iTime(symbol, SMC_M15_Timeframe, 1);
            setup.state          = SMC_M15_SWEEP_DETECTED;
         }
         break;
      }

      case SMC_M15_SWEEP_DETECTED:
      {
         // Search for CHoCH candidate swing in history prior to swept extreme time
         SMCSwing chochSwing;
         if(FindCHoCHLevel(symbol, setup.direction, setup.sweepTime, chochSwing))
         {
            setup.m15ChochSwing = chochSwing;
            setup.chochPrice    = chochSwing.price;
            setup.lastEvaluatedM15ChochTime = setup.sweepTime; // Initialize with sweep candle time so it is not re-evaluated as CHoCH confirmation
            setup.state         = SMC_WAITING_FOR_M15_CHOCH;
            SMCLog(setup.setupID, symbol, "CHOCH_CANDIDATE_FOUND",
                   StringFormat("Valid CHoCH candidate level identified at %.5f (time %s) -> Transitioning to SMC_WAITING_FOR_M15_CHOCH",
                                setup.chochPrice, TimeToString(chochSwing.time, TIME_DATE|TIME_MINUTES)));
         }
         else
         {
            // Invalidate strictly because no structural candidate exists prior to sweep
            InvalidateSetup(setup, "No valid structural M15 swing candidate found for CHoCH prior to sweep");
         }
         break;
      }

      case SMC_WAITING_FOR_M15_CHOCH:
      {
         datetime m15Bar1Time = iTime(symbol, SMC_M15_Timeframe, 1);
         double m15Close1     = iClose(symbol, SMC_M15_Timeframe, 1);
         double m15Low1       = iLow(symbol, SMC_M15_Timeframe, 1);
         double m15High1      = iHigh(symbol, SMC_M15_Timeframe, 1);

         if(m15Bar1Time <= 0 || m15Close1 <= 0)
            break;

         // Structural Invalidation Check: sweep level breached
         if(setup.direction == SIGNAL_BUY)
         {
            if(m15Close1 < setup.sweepPrice || m15Low1 < setup.sweepPrice)
            {
               InvalidateSetup(setup, "Sweep price invalidated by lower low before CHoCH confirmed");
               break;
            }
         }
         else if(setup.direction == SIGNAL_SELL)
         {
            if(m15Close1 > setup.sweepPrice || m15High1 > setup.sweepPrice)
            {
               InvalidateSetup(setup, "Sweep price invalidated by higher high before CHoCH confirmed");
               break;
            }
         }

         if(!setup.poi4H.isActive)
         {
            InvalidateSetup(setup, "4H POI inactive before CHoCH confirmed");
            break;
         }

         // Enforce strict chronological progression: evaluate newly completed M15 candles once
         if(m15Bar1Time > setup.lastEvaluatedM15ChochTime)
         {
            setup.lastEvaluatedM15ChochTime = m15Bar1Time;

            if(CheckM15CHoCH(symbol, setup.direction, setup.m15ChochSwing, true))
            {
               setup.chochTime = m15Bar1Time;
               setup.state     = SMC_M15_CHOCH_CONFIRMED;
               SMCLog(setup.setupID, symbol, "CHOCH_CONFIRMED",
                      StringFormat("M15 Candle Close %.5f broke CHoCH level %.5f -> Transitioning to SMC_M15_CHOCH_CONFIRMED",
                                   m15Close1, setup.chochPrice));
            }
            else
            {
               SMCLog(setup.setupID, symbol, "CHOCH_WAITING",
                      StringFormat("[M15] NEW_COMPLETED_BAR BarTime=%s | Direction=%s | CandidateLevel=%.5f | Close=%.5f | Result=NOT_CONFIRMED",
                                   TimeToString(m15Bar1Time, TIME_DATE|TIME_MINUTES),
                                   setup.direction == SIGNAL_BUY ? "BUY" : "SELL",
                                   setup.chochPrice, m15Close1));
            }
         }
         break;
      }

      case SMC_M15_CHOCH_CONFIRMED:
      {
         setup.state = SMC_WAITING_FOR_M5_CONFIRMATION;
         break;
      }

      case SMC_WAITING_FOR_M5_CONFIRMATION:
      {
         SMCSwing m5Swing;
         SMCFVG fvg;
         if(CheckM5DisplacementAndFVG(symbol, setup.direction, m5Swing, fvg))
         {
            setup.m5FVG = fvg;
            setup.state = SMC_M5_CONFIRMATION;
         }
         break;
      }

      case SMC_M5_CONFIRMATION:
      {
         if(setup.m5FVG.isValid && !IsFVGInvalidated(symbol, setup.m5FVG))
         {
            setup.state = SMC_FVG_DETECTED;
         }
         else
         {
            InvalidateSetup(setup, "M5 FVG invalid or invalidated");
         }
         break;
      }

      case SMC_FVG_DETECTED:
      {
         if(!setup.m5FVG.isValid || IsFVGInvalidated(symbol, setup.m5FVG))
         {
            InvalidateSetup(setup, "M5 FVG invalid or invalidated before entry calculation");
            break;
         }

         setup.entryPrice = setup.m5FVG.midpoint;

         // Calculate Structural SL (pure invalidation level of setup)
         if(setup.direction == SIGNAL_BUY)
         {
            setup.slPrice = setup.sweepPrice;
            if(setup.slPrice >= setup.entryPrice)
            {
               InvalidateSetup(setup, "Structural SL is not below entry price for Buy setup");
               break;
            }
         }
         else
         {
            setup.slPrice = setup.sweepPrice;
            if(setup.slPrice <= setup.entryPrice)
            {
               InvalidateSetup(setup, "Structural SL is not above entry price for Sell setup");
               break;
            }
         }
         setup.stopDistance = MathAbs(setup.entryPrice - setup.slPrice);

         // Calculate Opposing Structural TP (NO FIXED-R FALLBACK PERMITTED)
         SMCSwing oppSwing;
         if(setup.direction == SIGNAL_BUY)
         {
            if(FindNextOpposingTargetHigh(symbol, SMC_M15_Timeframe, 200, setup.entryPrice, oppSwing))
            {
               setup.tpPrice = oppSwing.price;
            }
            else
            {
               InvalidateSetup(setup, "No valid opposing M15 structural high target found ahead of entry price for TP");
               break;
            }
         }
         else
         {
            if(FindNextOpposingTargetLow(symbol, SMC_M15_Timeframe, 200, setup.entryPrice, oppSwing))
            {
               setup.tpPrice = oppSwing.price;
            }
            else
            {
               InvalidateSetup(setup, "No valid opposing M15 structural low target found ahead of entry price for TP");
               break;
            }
         }

         // Supporting OB
         FindM5OrderBlock(symbol, setup.direction, setup.m5OB);

         // Verify no-chase condition using confirmed completed candle (bar 1)
         double completedPrice = iClose(symbol, SMC_M5_Timeframe, 1);
         if(setup.direction == SIGNAL_BUY && completedPrice <= setup.entryPrice)
         {
            InvalidateSetup(setup, "NO CHASE: Price already passed through 50% FVG midpoint before order creation");
            break;
         }
         if(setup.direction == SIGNAL_SELL && completedPrice >= setup.entryPrice)
         {
            InvalidateSetup(setup, "NO CHASE: Price already passed through 50% FVG midpoint before order creation");
            break;
         }

         setup.state = SMC_WAITING_FOR_FVG_RETRACE;
         break;
      }

      case SMC_WAITING_FOR_FVG_RETRACE:
      case SMC_ENTRY_SUBMITTED:
      {
         // Check FVG invalidation while waiting for order execution or retrace
         if(IsFVGInvalidated(symbol, setup.m5FVG))
         {
            InvalidateSetup(setup, "M5 FVG invalidated by candle body close");
            break;
         }
         break;
      }

      case SMC_TRADE_ACTIVE:
      case SMC_COMPLETED:
      {
         // Active trade management handled via OnTradeTransaction & PositionTracker
         break;
      }

      case SMC_INVALIDATED:
      {
         // Idle terminal state for cleanup
         break;
      }
   }

   if(setup.state != prevState)
   {
      DrawSMCDebugObjects(setup);
      SMCLog(setup.setupID, symbol, "STATE_TRANSITION",
             StringFormat("%s -> %s", SMCStateToString(prevState), SMCStateToString(setup.state)));
   }
}

// Global update tick for all tracked symbol setups
void SMCEngine_OnTick()
{
   if(!SMC_UseStrategy) return;

   int totalSetups = ArraySize(g_SMCSetups);
   for(int i = 0; i < totalSetups; i++)
   {
      if(g_SMCSetups[i].state != SMC_INVALIDATED && g_SMCSetups[i].state != SMC_TRADE_ACTIVE)
      {
         ProcessSMCSetupStateMachine(g_SMCSetups[i]);
      }
   }
}

// Find existing non-invalidated setup or create setup slot for symbol
int GetOrCreateSetupForSymbol(string symbol)
{
   int total = ArraySize(g_SMCSetups);

   for(int i = 0; i < total; i++)
   {
      if(g_SMCSetups[i].symbol == symbol && g_SMCSetups[i].state != SMC_INVALIDATED && g_SMCSetups[i].state != SMC_COMPLETED)
      {
         return i;
      }
   }

   // Always append new setup slot to preserve historical/invalidated setup records
   int targetSlot = total;
   ArrayResize(g_SMCSetups, total + 1);

   ZeroMemory(g_SMCSetups[targetSlot]);
   g_SMCSetups[targetSlot].setupID       = GenerateSetupID(symbol);
   g_SMCSetups[targetSlot].symbol        = symbol;
   g_SMCSetups[targetSlot].state         = SMC_IDLE;
   g_SMCSetups[targetSlot].createdTime   = TimeCurrent();
   g_SMCSetups[targetSlot].lastUpdatedTime= TimeCurrent();

   SMCLog(g_SMCSetups[targetSlot].setupID, symbol, "SETUP_CREATED", "New setup initialized");
   return targetSlot;
}

#endif
