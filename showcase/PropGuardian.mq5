//+------------------------------------------------------------------+
//| PropGuardian.mq5                                                  |
//| Core Expert Advisor Entry Point for PropGuardian                   |
//+------------------------------------------------------------------+
#property copyright "PropGuardian"
#property link      "https://propguardian.ai"
#property version   "1.00"
#property strict

#include "risk_manager.mqh"
#include "position_manager.mqh"

// Input Parameters
input int Magic_Number = 20260914;   // for order tagging/log filtering

// Global State
RiskState       g_riskState;
PositionTracker g_tracker;     // ticket == 0 means "no open position"

//+------------------------------------------------------------------+
//| Expert Initialization Function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   ZeroMemory(g_riskState);
   g_riskState.equityPeak            = AccountInfoDouble(ACCOUNT_EQUITY);
   g_riskState.dailyReferenceBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_tracker.ticket                  = 0;

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
         CheckATRTrailing(g_tracker, atrValue);
         CheckFridayClose(g_tracker);
      }
   }
   else
   {
      // 4. Scan for new trade opportunities (no open position)
      static datetime lastBarTimes[5] = {0, 0, 0, 0, 0};

      for(int i = 0; i < 5; i++)
      {
         string symbol = TradeableSymbols[i];
         datetime completedBarTime = iTime(symbol, PERIOD_H1, 1);
         if(completedBarTime <= 0 || completedBarTime == lastBarTimes[i])
            continue;

         lastBarTimes[i] = completedBarTime;

         SignalResult signal;
         if(CanOpenTrade(g_riskState, symbol, signal))
         {
            double lots = CalculateLotSize(symbol, signal.stopDistance, g_riskState);
            if(lots <= 0)
               continue;

            MqlTradeRequest request;
            MqlTradeResult  result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action       = TRADE_ACTION_DEAL;
            request.symbol       = symbol;
            request.volume       = lots;
            request.type         = (signal.type == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.price        = signal.entryPrice;
            request.sl           = signal.slPrice;
            request.tp           = 0.0;
            request.deviation    = 10;
            request.magic        = Magic_Number;
            request.type_filling = GetSupportedFillingMode(symbol);

            if(OrderSend(request, result))
            {
               if(result.retcode == TRADE_RETCODE_DONE)
               {
                  InitPositionTracker(g_tracker, result.order, signal.stopDistance, signal.slPrice, 0.0);
                  g_riskState.tradesToday++;
                  break;
               }
               else
               {
                  PrintFormat("[ERROR] OrderSend failed for %s: retcode %d", symbol, result.retcode);
               }
            }
            else
            {
               PrintFormat("[ERROR] OrderSend execution error for %s: retcode %d", symbol, result.retcode);
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
               g_riskState.consecutiveLosses++;

            g_tracker.ticket = 0;
         }
      }
   }
}
