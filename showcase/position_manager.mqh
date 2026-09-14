//+------------------------------------------------------------------+
//| Position Manager — Active Trade Management                        |
//|                                                                    |
//| Extends PropGuardian position management logic.                   |
//| Demonstrates break-even (+1.0R), partial TP (50% at +1.5R),      |
//| and ATR trailing stop (ATR*2.5 after partial TP).                 |
//+------------------------------------------------------------------+

#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH

#include "signal_engine.mqh"

// Configuration input parameters if not already declared globally
#ifndef INPUT_PARAMS_DEFINED
#define INPUT_PARAMS_DEFINED
input bool   Use_Stealth_Mode         = false;  // Virtual SL/TP in RAM
input bool   Use_Breakeven            = true;   // Enable break-even
input bool   Use_Partial_TP           = true;   // Enable partial TP
input bool   Use_Trailing_Stop        = true;   // Enable trailing stop
input bool   Use_ATR_Trailing         = true;   // Enable ATR-based trailing
input double Trailing_Start_RR        = 1.5;    // Trailing start threshold in R (starts after partial TP)
input bool   Close_On_Friday          = true;   // Close open trades on Friday
input int    Friday_Trail_Hour        = 20;     // Friday aggressive trail start hour
input int    Friday_Close_Hour        = 21;     // Friday hard close hour
#endif

//+------------------------------------------------------------------+
//| Position State Tracker                                            |
//+------------------------------------------------------------------+
struct PositionTracker
{
   ulong  ticket;             // MT5 position ticket
   double virtualSL;          // In-memory SL (stealth mode)
   double virtualTP;          // In-memory TP (stealth mode)
   bool   partialClosed;      // Has partial TP been taken?
   double originalSLDistance;  // Original SL distance for R calculations (FROZEN at trade open)
};

// Global array or helper functions placeholder for position modification
void ModifyPositionSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return;
   string symbol = PositionGetString(POSITION_SYMBOL);
   double currentTP = PositionGetDouble(POSITION_TP);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = symbol;
   request.sl       = NormalizeDouble(newSL, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   request.tp       = currentTP;

   if(!OrderSend(request, result))
   {
      PrintFormat("[ERROR] Failed to modify SL for #%d: retcode %d", ticket, result.retcode);
   }
}

void ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   string symbol = PositionGetString(POSITION_SYMBOL);
   long posType = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = symbol;
   request.volume    = volume;
   request.type      = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price     = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   request.deviation = 10;

   OrderSend(request, result);
}

void ClosePartial(ulong ticket, double closeVolume)
{
   if(!PositionSelectByTicket(ticket)) return;
   string symbol = PositionGetString(POSITION_SYMBOL);
   long posType = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = symbol;
   request.volume    = closeVolume;
   request.type      = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price     = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   request.deviation = 10;

   OrderSend(request, result);
}

double NormalizeVolume(string symbol, double volume)
{
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0) return volume;

   double lots = MathFloor(volume / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
//| Initialize Position Tracker at trade open                         |
//+------------------------------------------------------------------+
void InitPositionTracker(PositionTracker &tracker, ulong ticket, double slDistance, double initialSL = 0.0, double initialTP = 0.0)
{
   tracker.ticket = ticket;
   tracker.originalSLDistance = slDistance; // Freeze original risk distance
   tracker.partialClosed = false;
   tracker.virtualSL = initialSL;
   tracker.virtualTP = initialTP;
}

//+------------------------------------------------------------------+
//| Stealth Mode — Virtual SL/TP in RAM                               |
//+------------------------------------------------------------------+
void ManageStealthMode(PositionTracker &tracker)
{
   if(!Use_Stealth_Mode) return;
   if(tracker.ticket == 0) return;
   
   if(!PositionSelectByTicket(tracker.ticket)) return;
   
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   long posType = PositionGetInteger(POSITION_TYPE);
   
   // Check virtual SL
   bool slHit = false;
   if(posType == POSITION_TYPE_BUY)
      slHit = (currentPrice <= tracker.virtualSL);
   else
      slHit = (currentPrice >= tracker.virtualSL);
   
   if(slHit)
   {
      PrintFormat("[STEALTH] Virtual SL hit for #%d at %.5f — closing",
                  tracker.ticket, currentPrice);
      ClosePosition(tracker.ticket);
      return;
   }
   
   // Check virtual TP
   bool tpHit = false;
   if(posType == POSITION_TYPE_BUY)
      tpHit = (currentPrice >= tracker.virtualTP);
   else
      tpHit = (currentPrice <= tracker.virtualTP);
   
   if(tpHit)
   {
      PrintFormat("[STEALTH] Virtual TP hit for #%d at %.5f — closing",
                  tracker.ticket, currentPrice);
      ClosePosition(tracker.ticket);
   }
}

//+------------------------------------------------------------------+
//| Break-Even — Move SL to entry after X × R profit                  |
//+------------------------------------------------------------------+
void CheckBreakEven(PositionTracker &tracker)
{
   if(!Use_Breakeven) return;
   if(tracker.ticket == 0 || tracker.originalSLDistance <= 0) return;
   
   if(!PositionSelectByTicket(tracker.ticket)) return;
   
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double currentSL = PositionGetDouble(POSITION_SL);
   long posType = PositionGetInteger(POSITION_TYPE);
   
   double profit_R = 0;
   if(posType == POSITION_TYPE_BUY)
      profit_R = (currentPrice - entryPrice) / tracker.originalSLDistance;
   else
      profit_R = (entryPrice - currentPrice) / tracker.originalSLDistance;
   
   // Check if already at breakeven
   if(posType == POSITION_TYPE_BUY && currentSL >= entryPrice) return;
   if(posType == POSITION_TYPE_SELL && currentSL <= entryPrice && currentSL > 0) return;

   // Only trigger if profit exceeds threshold (in R multiples)
   if(profit_R >= Breakeven_Trigger_RR)
   {
      double newSL = entryPrice;  // Move SL to entry
      
      if(Use_Stealth_Mode)
      {
         if(tracker.virtualSL != newSL)
         {
            tracker.virtualSL = newSL;
            PrintFormat("[BE] #%d — Break-even set at %.5f (stealth)",
                        tracker.ticket, newSL);
         }
      }
      else
      {
         ModifyPositionSL(tracker.ticket, newSL);
         PrintFormat("[BE] #%d — Break-even set at %.5f (server)",
                     tracker.ticket, newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Partial Take Profit — Lock profits on first target                |
//+------------------------------------------------------------------+
void CheckPartialTP(PositionTracker &tracker)
{
   if(!Use_Partial_TP || tracker.partialClosed) return;
   if(tracker.ticket == 0 || tracker.originalSLDistance <= 0) return;
   
   if(!PositionSelectByTicket(tracker.ticket)) return;
   
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double volume = PositionGetDouble(POSITION_VOLUME);
   long posType = PositionGetInteger(POSITION_TYPE);
   
   double profit_R = 0;
   if(posType == POSITION_TYPE_BUY)
      profit_R = (currentPrice - entryPrice) / tracker.originalSLDistance;
   else
      profit_R = (entryPrice - currentPrice) / tracker.originalSLDistance;
   
   if(profit_R >= Partial_TP_RR)
   {
      string symbol = PositionGetString(POSITION_SYMBOL);
      double closeVolume = NormalizeVolume(symbol, volume * (Partial_Volume_Pct / 100.0));
      
      if(closeVolume > 0)
      {
         ClosePartial(tracker.ticket, closeVolume);
         tracker.partialClosed = true;
         PrintFormat("[PTP] #%d — Partial close %.2f lots at %.2f R (%.1f%% volume)",
                     tracker.ticket, closeVolume, profit_R, Partial_Volume_Pct);
      }
   }
}

//+------------------------------------------------------------------+
//| ATR Trailing Stop — Dynamic trail based on volatility             |
//| Starts only after partial TP has fired (+1.5R)                   |
//+------------------------------------------------------------------+
void CheckATRTrailing(PositionTracker &tracker, double atrValue)
{
   if(!Use_Trailing_Stop || !Use_ATR_Trailing) return;
   if(tracker.ticket == 0 || tracker.originalSLDistance <= 0) return;
   if(atrValue <= 0) return;
   
   // Trailing starts only after partial TP has fired
   if(!tracker.partialClosed) return;

   if(!PositionSelectByTicket(tracker.ticket)) return;
   
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double currentSL = PositionGetDouble(POSITION_SL);
   long posType = PositionGetInteger(POSITION_TYPE);
   
   double profit_R = 0;
   if(posType == POSITION_TYPE_BUY)
      profit_R = (currentPrice - entryPrice) / tracker.originalSLDistance;
   else
      profit_R = (entryPrice - currentPrice) / tracker.originalSLDistance;
   
   // Double check minimum profit threshold
   if(profit_R < Trailing_Start_RR) return;
   
   double trailDistance = atrValue * ATR_Trailing_Multiplier;
   double newSL = 0;
   
   if(posType == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - trailDistance;
      if(Use_Stealth_Mode)
      {
         if(newSL > tracker.virtualSL)
         {
            tracker.virtualSL = newSL;
            PrintFormat("[TRAIL] #%d — ATR trail: Virtual SL → %.5f", tracker.ticket, newSL);
         }
      }
      else
      {
         if(newSL > currentSL)
         {
            ModifyPositionSL(tracker.ticket, newSL);
            PrintFormat("[TRAIL] #%d — ATR trail: SL → %.5f", tracker.ticket, newSL);
         }
      }
   }
   else // POSITION_TYPE_SELL
   {
      newSL = currentPrice + trailDistance;
      if(Use_Stealth_Mode)
      {
         if(tracker.virtualSL == 0 || newSL < tracker.virtualSL)
         {
            tracker.virtualSL = newSL;
            PrintFormat("[TRAIL] #%d — ATR trail: Virtual SL → %.5f", tracker.ticket, newSL);
         }
      }
      else
      {
         if(currentSL == 0 || newSL < currentSL)
         {
            ModifyPositionSL(tracker.ticket, newSL);
            PrintFormat("[TRAIL] #%d — ATR trail: SL → %.5f", tracker.ticket, newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Friday Close — Weekend risk elimination                           |
//+------------------------------------------------------------------+
void CheckFridayClose(PositionTracker &tracker)
{
   if(!Close_On_Friday) return;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_week != 5) return;  // Not Friday
   
   // Hard close at configured hour
   if(dt.hour >= Friday_Close_Hour)
   {
      if(tracker.ticket > 0 && PositionSelectByTicket(tracker.ticket))
      {
         PrintFormat("[FRIDAY] Closing #%d — weekend risk elimination", tracker.ticket);
         ClosePosition(tracker.ticket);
         tracker.ticket = 0;
      }
   }
}

#endif
