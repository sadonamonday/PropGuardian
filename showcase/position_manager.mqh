//+------------------------------------------------------------------+
//| Position Manager — Active Trade Management (Sanitized Excerpt)    |
//|                                                                    |
//| This is a sanitized excerpt from PropGuardian V2.8.1.             |
//| Demonstrates break-even, partial TP, and ATR trailing stop.       |
//| Exact R:R ratios and multipliers use input parameters.            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Position State Tracker                                            |
//+------------------------------------------------------------------+
struct PositionTracker
{
   ulong  ticket;             // MT5 position ticket
   double virtualSL;          // In-memory SL (stealth mode)
   double virtualTP;          // In-memory TP (stealth mode)
   bool   partialClosed;      // Has partial TP been taken?
   double originalSLDistance;  // Original SL distance for R calculations
};

//+------------------------------------------------------------------+
//| Stealth Mode — Virtual SL/TP in RAM                               |
//|                                                                    |
//| Problem: Some brokers hunt stop losses by temporarily widening    |
//| spreads to trigger clustered SL orders.                           |
//|                                                                    |
//| Solution: Keep the real SL/TP in RAM. Only a wide "emergency"    |
//| hard SL is placed on the server as catastrophic protection.       |
//| The EA monitors price and closes when virtual levels are hit.     |
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
   long posType = PositionGetInteger(POSITION_TYPE);
   
   double profit_R = 0;
   if(posType == POSITION_TYPE_BUY)
      profit_R = (currentPrice - entryPrice) / tracker.originalSLDistance;
   else
      profit_R = (entryPrice - currentPrice) / tracker.originalSLDistance;
   
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
      double closeVolume = NormalizeVolume(volume * (Partial_Volume_Pct / 100.0));
      
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
//|                                                                    |
//| The trailing stop uses ATR to adapt to current market volatility. |
//| In calm markets: tight trail → lock more profit.                  |
//| In volatile markets: wider trail → avoid noise stop-outs.         |
//+------------------------------------------------------------------+
void CheckATRTrailing(PositionTracker &tracker, double atrValue)
{
   if(!Use_Trailing_Stop || !Use_ATR_Trailing) return;
   if(tracker.ticket == 0 || tracker.originalSLDistance <= 0) return;
   if(atrValue <= 0) return;
   
   if(!PositionSelectByTicket(tracker.ticket)) return;
   
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   long posType = PositionGetInteger(POSITION_TYPE);
   
   double profit_R = 0;
   if(posType == POSITION_TYPE_BUY)
      profit_R = (currentPrice - entryPrice) / tracker.originalSLDistance;
   else
      profit_R = (entryPrice - currentPrice) / tracker.originalSLDistance;
   
   // Only start trailing after reaching threshold
   if(profit_R < Trailing_Start_RR) return;
   
   double trailDistance = atrValue * ATR_Trailing_Multiplier;
   double newSL = 0;
   
   if(posType == POSITION_TYPE_BUY)
      newSL = currentPrice - trailDistance;
   else
      newSL = currentPrice + trailDistance;
   
   // Only move SL in favorable direction
   bool shouldUpdate = false;
   if(Use_Stealth_Mode)
   {
      if(posType == POSITION_TYPE_BUY && newSL > tracker.virtualSL)
         shouldUpdate = true;
      if(posType == POSITION_TYPE_BUY == false && newSL < tracker.virtualSL)
         shouldUpdate = true;
   }
   
   if(shouldUpdate)
   {
      if(Use_Stealth_Mode)
      {
         tracker.virtualSL = newSL;
         PrintFormat("[TRAIL] #%d — ATR trail: SL → %.5f (ATR=%.5f × %.1f, stealth)",
                     tracker.ticket, newSL, atrValue, ATR_Trailing_Multiplier);
      }
      else
      {
         ModifyPositionSL(tracker.ticket, newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Friday Close — Weekend risk elimination                           |
//|                                                                    |
//| Forex markets close Friday and reopen Sunday with potential gaps. |
//| PropGuardian closes all positions before the weekend to avoid     |
//| gap risk that could blow through stop losses.                     |
//+------------------------------------------------------------------+
void CheckFridayClose(PositionTracker &tracker)
{
   if(!Close_On_Friday) return;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_week != 5) return;  // Not Friday
   
   // Aggressive trailing before hard close
   if(dt.hour >= Friday_Trail_Hour && dt.hour < Friday_Close_Hour)
   {
      // Tighten trails — not shown (proprietary logic)
      return;
   }
   
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
