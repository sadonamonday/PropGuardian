//+------------------------------------------------------------------+
//| PropGuardian.mq5                                                  |
//| Core Expert Advisor Entry Point for PropGuardian                   |
//+------------------------------------------------------------------+
#property copyright "PropGuardian"
#property link      "https://propguardian.ai"
#property version   "1.00"
#property strict

#include "smc_engine.mqh"
#include "risk_manager.mqh"
#include "position_manager.mqh"

// Input Parameters
input int Magic_Number = 20260914;   // for order tagging/log filtering

// Global State
RiskState       g_riskState;
PositionTracker g_tracker;     // ticket == 0 means "no open position"
ulong           g_pendingOrderTicket     = 0;   // 0 means no pending stop order active
datetime        g_pendingOrderExpiryTime = 0;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   ZeroMemory(g_riskState);
   g_riskState.equityPeak            = AccountInfoDouble(ACCOUNT_EQUITY);
   g_riskState.dailyReferenceBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_tracker.ticket                  = 0;
   g_pendingOrderTicket              = 0;
   g_pendingOrderExpiryTime          = 0;

   EventSetTimer(5);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseSignalEngineHandles();
   ReleaseSafetyFilterHandles();
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_tracker.ticket == 0 && g_pendingOrderTicket == 0)
   {
      SMCEngine_OnTick();
   }
}

//+------------------------------------------------------------------+
//| Expert Timer Function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Daily Reset Check (must run first)
   CheckNewDay(g_riskState);

   // 2. Drawdown State Update
   UpdateDrawdownState(g_riskState);

   // 3. Manage Open Position
   if(g_tracker.ticket > 0)
   {
      if(!PositionSelectByTicket(g_tracker.ticket))
      {
         // Position no longer exists — fully closed.
         // Circuit breaker & win/loss detection are handled in OnTradeTransaction.
      }
      else
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         int atrHandle = GetCachedATRHandle(symbol);
         double atrValue = 0.0;

         if(atrHandle != INVALID_HANDLE)
         {
            double atrBuffer[];
            ArraySetAsSeries(atrBuffer, true);
            if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) > 0)
               atrValue = atrBuffer[0];
         }

         ManageStealthMode(g_tracker);
         CheckBreakEven(g_tracker);
         CheckPartialTP(g_tracker);
         CheckPartialTP2(g_tracker);   // NEW
         CheckATRTrailing(g_tracker, atrValue);
         CheckFridayClose(g_tracker);
      }
   }
   else if(g_pendingOrderTicket > 0)
   {
      // 4. A pending order is active. Safety-net expiry check in case the
      // broker doesn't auto-cancel on ORDER_TIME_SPECIFIED.
      if(TimeCurrent() >= g_pendingOrderExpiryTime)
      {
         bool clearPending = true;

         if(OrderSelect(g_pendingOrderTicket))
         {
            MqlTradeRequest delRequest;
            MqlTradeResult  delResult;
            ZeroMemory(delRequest);
            ZeroMemory(delResult);
            delRequest.action = TRADE_ACTION_REMOVE;
            delRequest.order  = g_pendingOrderTicket;

            if(OrderSend(delRequest, delResult) && delResult.retcode == TRADE_RETCODE_DONE)
            {
               PrintFormat("[PENDING] Manually cancelled expired order #%d", g_pendingOrderTicket);
            }
            else
            {
               // Cancel failed: keep tracking the order and retry on the next timer tick
               PrintFormat("[ERROR] Failed to cancel expired order #%d: retcode %d",
                           g_pendingOrderTicket, delResult.retcode);
               clearPending = false;
            }
         }

         if(clearPending)
         {
            g_pendingOrderTicket     = 0;
            g_pendingOrderExpiryTime = 0;
         }
      }
   }
   else
   {
      // 5. Advance SMC Engine State Machine for all tradeable symbols (PropGuardian SMC Strategy v0.1)
      SMCEngine_OnTick();

      // Cancel active pending limit order if its setup was invalidated
      if(g_pendingOrderTicket > 0)
      {
         for(int s = 0; s < ArraySize(g_SMCSetups); s++)
         {
            if(g_SMCSetups[s].orderTicket == g_pendingOrderTicket && g_SMCSetups[s].state == SMC_INVALIDATED)
            {
               if(OrderSelect(g_pendingOrderTicket))
               {
                  MqlTradeRequest delRequest;
                  MqlTradeResult  delResult;
                  ZeroMemory(delRequest);
                  ZeroMemory(delResult);
                  delRequest.action = TRADE_ACTION_REMOVE;
                  delRequest.order  = g_pendingOrderTicket;
                  if(OrderSend(delRequest, delResult) && delResult.retcode == TRADE_RETCODE_DONE)
                  {
                     PrintFormat("[PENDING] Cancelled pending order #%d due to setup invalidation (%s)",
                                 g_pendingOrderTicket, g_SMCSetups[s].invalidationReason);
                  }
               }
               g_pendingOrderTicket     = 0;
               g_pendingOrderExpiryTime = 0;
               break;
            }
         }
      }

      for(int i = 0; i < 5; i++)
      {
         string symbol = TradeableSymbols[i];
         int setupIdx = GetOrCreateSetupForSymbol(symbol);

         if(g_SMCSetups[setupIdx].state == SMC_WAITING_FOR_FVG_RETRACE || g_SMCSetups[setupIdx].state == SMC_FVG_DETECTED)
         {
            if(!g_SMCSetups[setupIdx].m5FVG.isValid || IsFVGInvalidated(symbol, g_SMCSetups[setupIdx].m5FVG))
            {
               InvalidateSetup(g_SMCSetups[setupIdx], "M5 FVG invalidated prior to order placement");
               continue;
            }

            SignalResult signal;
            signal.type         = g_SMCSetups[setupIdx].direction;
            signal.entryPrice   = g_SMCSetups[setupIdx].entryPrice;
            signal.slPrice      = g_SMCSetups[setupIdx].slPrice;
            signal.stopDistance = g_SMCSetups[setupIdx].stopDistance;
            signal.levelSwept   = "SMC_M15_SWEEP";

            if(CanOpenTrade(g_riskState, symbol))
            {
               double lots = CalculateLotSize(symbol, signal.stopDistance, g_riskState);
               if(lots <= 0)
               {
                  InvalidateSetup(g_SMCSetups[setupIdx], "Calculated lot size <= 0");
                  continue;
               }

               int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

               MqlTradeRequest request;
               MqlTradeResult  result;
               ZeroMemory(request);
               ZeroMemory(result);

               request.action       = TRADE_ACTION_PENDING;
               request.symbol       = symbol;
               request.volume       = lots;
               request.type         = (signal.type == SIGNAL_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
               request.price        = NormalizeDouble(signal.entryPrice, digits);
               request.sl           = NormalizeDouble(signal.slPrice, digits);
               request.tp           = NormalizeDouble(g_SMCSetups[setupIdx].tpPrice, digits);
               request.deviation    = 10;
               request.magic        = Magic_Number;
               request.type_filling = GetSupportedFillingMode(symbol);
               request.type_time    = ORDER_TIME_SPECIFIED;
               request.expiration   = TimeCurrent() + (Pending_Order_Expiry_Bars * PeriodSeconds(PERIOD_H1));

               if(OrderSend(request, result))
               {
                  if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
                  {
                     g_pendingOrderTicket               = result.order;
                     g_pendingOrderExpiryTime           = request.expiration;
                     g_SMCSetups[setupIdx].orderTicket  = result.order;
                     g_SMCSetups[setupIdx].state        = SMC_ENTRY_SUBMITTED;
                     g_riskState.tradesToday++;

                     SMCLog(g_SMCSetups[setupIdx].setupID, symbol, "ENTRY_ORDER_CREATED",
                            StringFormat("%s Limit at %.5f, SL %.5f, TP %.5f, Lots %.2f",
                                         signal.type == SIGNAL_BUY ? "BUY" : "SELL",
                                         request.price, request.sl, request.tp, lots));
                     break;
                  }
                  else
                  {
                     PrintFormat("[ERROR] Pending OrderSend failed for %s: retcode %d", symbol, result.retcode);
                     InvalidateSetup(g_SMCSetups[setupIdx], StringFormat("OrderSend failed retcode %d", result.retcode));
                  }
               }
               else
               {
                  PrintFormat("[ERROR] Pending OrderSend execution error for %s: retcode %d", symbol, result.retcode);
                  InvalidateSetup(g_SMCSetups[setupIdx], StringFormat("OrderSend execution error retcode %d", result.retcode));
               }
            }
            else
            {
               SMCLog(g_SMCSetups[setupIdx].setupID, symbol, "TRADE_REJECTED_BY_RISK", "Pre-trade risk gate blocked execution");
               InvalidateSetup(g_SMCSetups[setupIdx], "Pre-trade risk gate blocked execution");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // --- Pending order triggered: detect the resulting position ---
   if(g_pendingOrderTicket > 0 && trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         long dealOrder = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

         if(dealOrder == (long)g_pendingOrderTicket && dealEntry == DEAL_ENTRY_IN)
         {
            long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            if(positionId > 0 && PositionSelectByTicket((ulong)positionId))
            {
               double actualOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double actualSL        = PositionGetDouble(POSITION_SL);
               double actualDistance  = MathAbs(actualOpenPrice - actualSL);

               InitPositionTracker(g_tracker, (ulong)positionId, actualDistance, actualSL, 0.0);
               PrintFormat("[FILL] Pending order #%d triggered — position #%d opened at %.5f, SL %.5f",
                           g_pendingOrderTicket, (ulong)positionId, actualOpenPrice, actualSL);

               // Update SMC Setup state if applicable
               for(int s = 0; s < ArraySize(g_SMCSetups); s++)
               {
                  if(g_SMCSetups[s].orderTicket == g_pendingOrderTicket)
                  {
                     g_SMCSetups[s].positionTicket = (ulong)positionId;
                     g_SMCSetups[s].state          = SMC_TRADE_ACTIVE;
                     SMCLog(g_SMCSetups[s].setupID, g_SMCSetups[s].symbol, "ENTRY_FILLED",
                            StringFormat("Position #%d filled at %.5f", (ulong)positionId, actualOpenPrice));
                     break;
                  }
               }
            }

            g_pendingOrderTicket     = 0;
            g_pendingOrderExpiryTime = 0;
            return;
         }
      }
   }

   // --- Pending order removed (cancelled, expired, or rejected) without filling ---
   if(g_pendingOrderTicket > 0 && trans.type == TRADE_TRANSACTION_ORDER_DELETE)
   {
      if(trans.order == g_pendingOrderTicket)
      {
         PrintFormat("[PENDING] Order #%d removed without filling (expired/cancelled)", g_pendingOrderTicket);

         for(int s = 0; s < ArraySize(g_SMCSetups); s++)
         {
            if(g_SMCSetups[s].orderTicket == g_pendingOrderTicket)
            {
               InvalidateSetup(g_SMCSetups[s], "Pending order expired/cancelled before fill");
               break;
            }
         }

         g_pendingOrderTicket     = 0;
         g_pendingOrderExpiryTime = 0;
         return;
      }
   }

   // --- Existing position close-detection logic (unchanged) ---
   if(g_tracker.ticket == 0) return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         long dealEntry  = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

         if(positionId == (long)g_tracker.ticket && dealEntry == DEAL_ENTRY_OUT)
         {
            if(PositionSelectByTicket(g_tracker.ticket))
            {
               // Partial close only — position still open
               return;
            }

            // Position fully closed — sum profit across all deals for this position
            double totalProfit = 0.0;
            if(HistorySelectByPosition(g_tracker.ticket))
            {
               int totalDeals = HistoryDealsTotal();
               for(int i = 0; i < totalDeals; i++)
               {
                  ulong dTicket = HistoryDealGetTicket(i);
                  if(dTicket > 0)
                  {
                     double profit     = HistoryDealGetDouble(dTicket, DEAL_PROFIT);
                     double swap       = HistoryDealGetDouble(dTicket, DEAL_SWAP);
                     double commission = HistoryDealGetDouble(dTicket, DEAL_COMMISSION);
                     totalProfit += (profit + swap + commission);
                  }
               }
            }

            if(totalProfit > 0.0)
               g_riskState.consecutiveLosses = 0;
            else
            {
               g_riskState.consecutiveLosses++;
               if(g_riskState.consecutiveLosses >= Max_Consecutive_Losses)
                  g_riskState.circuitBreakerResetTime = TimeCurrent() + (Circuit_Breaker_Cooldown_Days * 86400);
            }

            for(int s = 0; s < ArraySize(g_SMCSetups); s++)
            {
               if(g_SMCSetups[s].positionTicket == g_tracker.ticket)
               {
                  SMCLog(g_SMCSetups[s].setupID, g_SMCSetups[s].symbol, "TRADE_COMPLETED",
                         StringFormat("Position #%d closed with total profit $%.2f", g_tracker.ticket, totalProfit));
                  g_SMCSetups[s].state = SMC_COMPLETED;
                  g_SMCSetups[s].lastUpdatedTime = TimeCurrent();
                  break;
               }
            }

            g_tracker.ticket = 0;
         }
      }
   }
}
