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
bool FindMostRecentSwingHigh(string symbol, ENUM_TIMEFRAMES tf, int maxLookbackBars, SMCSwing &outSwing)
{
   int startBar = (tf == PERIOD_M5) ? 2 : 3;
   for(int i = startBar; i <= maxLookbackBars; i++)
   {
      bool found = (tf == PERIOD_M5)
                   ? Get3BarSwingHigh(symbol, tf, i, outSwing)
                   : Get5BarSwingHigh(symbol, tf, i, outSwing);
      if(found) return true;
   }
   return false;
}

bool FindMostRecentSwingLow(string symbol, ENUM_TIMEFRAMES tf, int maxLookbackBars, SMCSwing &outSwing)
{
   int startBar = (tf == PERIOD_M5) ? 2 : 3;
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
//| 4H POI DETECTION                                                 |
//| Demand POI around 4H Swing Low / Supply POI around 4H Swing High |
//+------------------------------------------------------------------+

bool GetActive4HPOI(string symbol, SMCPOI &outPOI)
{
   ZeroMemory(outPOI);
   outPOI.isActive = false;

   SMCSwing swingHigh, swingLow;
   bool hasHigh = FindMostRecentSwingHigh(symbol, SMC_4H_Timeframe, 60, swingHigh);
   bool hasLow  = FindMostRecentSwingLow(symbol, SMC_4H_Timeframe, 60, swingLow);

   if(!hasHigh && !hasLow) return false;

   double currentPrice = iClose(symbol, SMC_M15_Timeframe, 1);

   // Select POI closest to current price or based on structural relationship
   if(hasLow && (!hasHigh || MathAbs(currentPrice - swingLow.price) < MathAbs(currentPrice - swingHigh.price)))
   {
      outPOI.type      = POI_TYPE_DEMAND;
      outPOI.bottom    = swingLow.price - (3.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
      outPOI.top       = swingLow.price + (15.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
      outPOI.time      = swingLow.time;
      outPOI.isActive  = true;
      outPOI.timeframe = SMC_4H_Timeframe;
      return true;
   }
   else if(hasHigh)
   {
      outPOI.type      = POI_TYPE_SUPPLY;
      outPOI.top       = swingHigh.price + (3.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
      outPOI.bottom    = swingHigh.price - (15.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
      outPOI.time      = swingHigh.time;
      outPOI.isActive  = true;
      outPOI.timeframe = SMC_4H_Timeframe;
      return true;
   }

   return false;
}

// Check if M15 price is interacting with (entering/touching) 4H POI
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
//|   Search backward for MOST RECENT confirmed M15 swing high.      |
//|   Completed M15 candle BODY CLOSES above that Lower High.        |
//| Bearish CHoCH:                                                   |
//|   Start from final bullish extreme/sweep.                        |
//|   Search backward for MOST RECENT confirmed M15 swing low.       |
//|   Completed M15 candle BODY CLOSES below that Higher Low.        |
//+------------------------------------------------------------------+

bool FindCHoCHLevel(string symbol, ENUM_SIGNAL_TYPE direction, datetime sweepTime, SMCSwing &outChochSwing)
{
   ZeroMemory(outChochSwing);

   if(direction == SIGNAL_BUY)
   {
      // Search for M15 Swing High preceding the sweep
      for(int i = 3; i <= 50; i++)
      {
         SMCSwing swing;
         if(Get5BarSwingHigh(symbol, SMC_M15_Timeframe, i, swing))
         {
            if(swing.time <= sweepTime)
            {
               outChochSwing = swing;
               return true;
            }
         }
      }
   }
   else if(direction == SIGNAL_SELL)
   {
      // Search for M15 Swing Low preceding the sweep
      for(int i = 3; i <= 50; i++)
      {
         SMCSwing swing;
         if(Get5BarSwingLow(symbol, SMC_M15_Timeframe, i, swing))
         {
            if(swing.time <= sweepTime)
            {
               outChochSwing = swing;
               return true;
            }
         }
      }
   }
   return false;
}

bool CheckM15CHoCH(string symbol, ENUM_SIGNAL_TYPE direction, const SMCSwing &chochSwing)
{
   if(!chochSwing.isValid) return false;

   double close1 = iClose(symbol, SMC_M15_Timeframe, 1);

   if(direction == SIGNAL_BUY)
   {
      // Body close above Lower High
      if(close1 > chochSwing.price) return true;
   }
   else if(direction == SIGNAL_SELL)
   {
      // Body close below Higher Low
      if(close1 < chochSwing.price) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| M5 FVG & DISPLACEMENT DETECTION                                  |
//| 3-candle structure on M5:                                        |
//|   Bullish FVG: Low(Candle 3) > High(Candle 1)                    |
//|   Bearish FVG: High(Candle 3) < Low(Candle 1)                    |
//| Midpoint calculation = (Top + Bottom) / 2                        |
//| Invalidation: Body close beyond Candle 1 boundary                |
//+------------------------------------------------------------------+

bool FindM5FVG(string symbol, ENUM_SIGNAL_TYPE direction, SMCFVG &outFVG)
{
   ZeroMemory(outFVG);
   outFVG.isValid = false;

   // Candle 3 is index 1 (most recent completed candle), Candle 2 is index 2, Candle 1 is index 3
   double highC1 = iHigh(symbol, SMC_M5_Timeframe, 3);
   double lowC1  = iLow(symbol, SMC_M5_Timeframe, 3);

   double highC3 = iHigh(symbol, SMC_M5_Timeframe, 1);
   double lowC3  = iLow(symbol, SMC_M5_Timeframe, 1);

   if(direction == SIGNAL_BUY)
   {
      if(lowC3 > highC1)
      {
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
   }
   else if(direction == SIGNAL_SELL)
   {
      if(highC3 < lowC1)
      {
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
      if(g_SMCSetups[i].state != SMC_INVALIDATED && g_SMCSetups[i].state != SMC_IDLE)
         count++;
   }
   return count;
}

// Helper to check M5 execution structure break (BODY close above M5 swing high for BUY / below M5 swing low for SELL)
bool CheckM5ExecutionBreak(string symbol, ENUM_SIGNAL_TYPE direction, SMCSwing &outM5Swing)
{
   ZeroMemory(outM5Swing);
   if(direction == SIGNAL_BUY)
   {
      SMCSwing m5High;
      if(FindMostRecentSwingHigh(symbol, SMC_M5_Timeframe, 30, m5High))
      {
         double close1 = iClose(symbol, SMC_M5_Timeframe, 1);
         if(close1 > m5High.price)
         {
            outM5Swing = m5High;
            return true;
         }
      }
   }
   else if(direction == SIGNAL_SELL)
   {
      SMCSwing m5Low;
      if(FindMostRecentSwingLow(symbol, SMC_M5_Timeframe, 30, m5Low))
      {
         double close1 = iClose(symbol, SMC_M5_Timeframe, 1);
         if(close1 < m5Low.price)
         {
            outM5Swing = m5Low;
            return true;
         }
      }
   }
   return false;
}

// Manage lifecycle for a specific setup on a symbol
void ProcessSMCSetupStateMachine(SMCSetup &setup)
{
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
         // Search for CHoCH candidate swing
         SMCSwing chochSwing;
         if(FindCHoCHLevel(symbol, setup.direction, setup.sweepTime, chochSwing))
         {
            setup.m15ChochSwing = chochSwing;
            setup.chochPrice    = chochSwing.price;
            setup.state         = SMC_WAITING_FOR_M15_CHOCH;
         }
         else
         {
            // If no valid preceding swing found within 24 hours, invalidate
            if(now - setup.sweepTime > 86400)
               InvalidateSetup(setup, "No preceding M15 swing found for CHoCH");
         }
         break;
      }

      case SMC_WAITING_FOR_M15_CHOCH:
      {
         if(CheckM15CHoCH(symbol, setup.direction, setup.m15ChochSwing))
         {
            setup.chochTime = iTime(symbol, SMC_M15_Timeframe, 1);
            setup.state     = SMC_M15_CHOCH_CONFIRMED;
         }
         else if(now - setup.sweepTime > (86400 * 2))
         {
            InvalidateSetup(setup, "CHoCH timeout expired");
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
         // Check M5 execution structure break (M5 BOS body close)
         SMCSwing m5Swing;
         if(CheckM5ExecutionBreak(symbol, setup.direction, m5Swing))
         {
            setup.state = SMC_M5_CONFIRMATION;
         }
         break;
      }

      case SMC_M5_CONFIRMATION:
      {
         SMCFVG fvg;
         if(FindM5FVG(symbol, setup.direction, fvg))
         {
            setup.m5FVG = fvg;
            setup.state = SMC_FVG_DETECTED;
         }
         break;
      }

      case SMC_FVG_DETECTED:
      {
         setup.entryPrice = setup.m5FVG.midpoint;

         // Calculate Structural SL
         double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
         if(setup.direction == SIGNAL_BUY)
         {
            setup.slPrice = setup.sweepPrice - spread - (2.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
         }
         else
         {
            setup.slPrice = setup.sweepPrice + spread + (2.0 * SymbolInfoDouble(symbol, SYMBOL_POINT));
         }
         setup.stopDistance = MathAbs(setup.entryPrice - setup.slPrice);

         // Calculate Opposing Structural TP
         SMCSwing oppSwing;
         if(setup.direction == SIGNAL_BUY)
         {
            if(FindMostRecentSwingHigh(symbol, SMC_M15_Timeframe, 50, oppSwing))
               setup.tpPrice = oppSwing.price;
            else
               setup.tpPrice = setup.entryPrice + (setup.stopDistance * 3.0);
         }
         else
         {
            if(FindMostRecentSwingLow(symbol, SMC_M15_Timeframe, 50, oppSwing))
               setup.tpPrice = oppSwing.price;
            else
               setup.tpPrice = setup.entryPrice - (setup.stopDistance * 3.0);
         }

         // Supporting OB
         FindM5OrderBlock(symbol, setup.direction, setup.m5OB);

         // Verify no-chase condition before proceeding to waiting for retrace
         double currentPrice = iClose(symbol, SMC_M5_Timeframe, 0);
         if(setup.direction == SIGNAL_BUY && currentPrice <= setup.entryPrice)
         {
            InvalidateSetup(setup, "NO CHASE: Price already passed through 50% FVG midpoint before order creation");
            break;
         }
         if(setup.direction == SIGNAL_SELL && currentPrice >= setup.entryPrice)
         {
            InvalidateSetup(setup, "NO CHASE: Price already passed through 50% FVG midpoint before order creation");
            break;
         }

         setup.state = SMC_WAITING_FOR_FVG_RETRACE;
         break;
      }

      case SMC_WAITING_FOR_FVG_RETRACE:
      {
         // Check FVG invalidation while waiting for order execution
         if(IsFVGInvalidated(symbol, setup.m5FVG))
         {
            InvalidateSetup(setup, "M5 FVG invalidated by candle body close");
            break;
         }
         break;
      }

      case SMC_ENTRY_SUBMITTED:
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

// Find existing non-invalidated setup or re-use/create setup slot for symbol
int GetOrCreateSetupForSymbol(string symbol)
{
   int total = ArraySize(g_SMCSetups);
   int freeSlot = -1;

   for(int i = 0; i < total; i++)
   {
      if(g_SMCSetups[i].symbol == symbol && g_SMCSetups[i].state != SMC_INVALIDATED)
      {
         return i;
      }
      if(freeSlot == -1 && g_SMCSetups[i].state == SMC_INVALIDATED)
      {
         freeSlot = i;
      }
   }

   // Reuse invalidated slot if available
   int targetSlot = (freeSlot != -1) ? freeSlot : total;
   if(targetSlot == total)
   {
      ArrayResize(g_SMCSetups, total + 1);
   }

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
