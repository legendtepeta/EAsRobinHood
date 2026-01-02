//+------------------------------------------------------------------+
//|                                                  MomentumORB.mq5 |
//|                           Momentum Opening Range Breakout (ORB)  |
//|                   Exploiting liquidity at the US Market Open     |
//+------------------------------------------------------------------+
#property copyright "NASDAQ Strategy Portfolio"
#property version   "1.00"
#property description "Opening Range Breakout strategy for NASDAQ/US100"
#property strict

//--- Input Parameters
input group "=== Trading Hours (Broker Server Time) ==="
input int      InpRangeStartHour    = 15;     // Range Start Hour (09:30 EST = 15:30 CET typically)
input int      InpRangeStartMinute  = 30;     // Range Start Minute
input int      InpRangeEndHour      = 16;     // Range End Hour (10:00 EST)
input int      InpRangeEndMinute    = 0;      // Range End Minute
input int      InpOrderCancelHour   = 17;     // Cancel Pending Orders Hour (11:00 EST)
input int      InpOrderCancelMinute = 0;      // Cancel Pending Orders Minute
input int      InpSessionEndHour    = 21;     // Session End Hour (15:55 EST - EOD exit)
input int      InpSessionEndMinute  = 55;     // Session End Minute

input group "=== Entry Parameters ==="
input int      InpBreakoutBuffer    = 10;     // Breakout Buffer (points above/below range)
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5; // Strategy Timeframe

input group "=== Risk Management ==="
input double   InpLotSize           = 0.1;    // Lot Size
input int      InpStopLossMode      = 0;      // SL Mode: 0=Fixed, 1=Opposite Range, 2=Mid Range
input int      InpFixedSL           = 50;     // Fixed Stop Loss (points) - if Mode=0
input int      InpTakeProfitMode    = 0;      // TP Mode: 0=RR Ratio, 1=EOD Exit
input double   InpRiskRewardRatio   = 2.0;    // Risk:Reward Ratio (for TP Mode=0)
input int      InpBreakevenPoints   = 30;     // Move SL to Breakeven after X points profit

input group "=== General Settings ==="
input ulong    InpMagicNumber       = 100001; // Magic Number
input int      InpSlippage          = 10;     // Slippage (points)

//--- Global Variables
double         g_rangeHigh          = 0;
double         g_rangeLow           = 0;
bool           g_rangeCalculated    = false;
bool           g_ordersPlaced       = false;
bool           g_tradeExecuted      = false;
datetime       g_lastBarTime        = 0;
datetime       g_currentDay         = 0;

//--- Trade object
#include <Trade\Trade.mqh>
CTrade         trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   Print("===========================================");
   Print("Momentum ORB EA Initialized");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Magic Number: ", InpMagicNumber);
   Print("===========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Momentum ORB EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new day - reset flags
   CheckNewDay();
   
   //--- Get current time
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   
   //--- Define time boundaries in minutes
   int rangeStart = InpRangeStartHour * 60 + InpRangeStartMinute;
   int rangeEnd = InpRangeEndHour * 60 + InpRangeEndMinute;
   int orderCancel = InpOrderCancelHour * 60 + InpOrderCancelMinute;
   int sessionEnd = InpSessionEndHour * 60 + InpSessionEndMinute;
   
   //--- Calculate Opening Range after range period ends
   if(currentMinutes >= rangeEnd && !g_rangeCalculated)
   {
      CalculateOpeningRange();
   }
   
   //--- Place pending orders after range is calculated
   if(g_rangeCalculated && !g_ordersPlaced && !g_tradeExecuted)
   {
      PlacePendingOrders();
   }
   
   //--- Cancel pending orders if not triggered by cancel time
   if(currentMinutes >= orderCancel && g_ordersPlaced && !g_tradeExecuted)
   {
      CancelPendingOrders();
   }
   
   //--- Manage open positions
   ManagePositions();
   
   //--- End of Day Exit
   if(currentMinutes >= sessionEnd && InpTakeProfitMode == 1)
   {
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Check for new trading day                                          |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", 
                                  timeStruct.year, timeStruct.mon, timeStruct.day));
   
   if(today != g_currentDay)
   {
      //--- Reset all flags for new day
      g_currentDay = today;
      g_rangeHigh = 0;
      g_rangeLow = 0;
      g_rangeCalculated = false;
      g_ordersPlaced = false;
      g_tradeExecuted = false;
      
      Print("New trading day detected: ", TimeToString(today, TIME_DATE));
   }
}

//+------------------------------------------------------------------+
//| Calculate Opening Range High and Low                               |
//+------------------------------------------------------------------+
void CalculateOpeningRange()
{
   //--- Get range start and end times for today
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   datetime rangeStartTime = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00",
                              timeStruct.year, timeStruct.mon, timeStruct.day,
                              InpRangeStartHour, InpRangeStartMinute));
   
   datetime rangeEndTime = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00",
                            timeStruct.year, timeStruct.mon, timeStruct.day,
                            InpRangeEndHour, InpRangeEndMinute));
   
   //--- Get bars within the range
   int startBar = iBarShift(Symbol(), InpTimeframe, rangeStartTime);
   int endBar = iBarShift(Symbol(), InpTimeframe, rangeEndTime);
   
   if(startBar < 0 || endBar < 0)
   {
      Print("Error: Could not find bars for range calculation");
      return;
   }
   
   //--- Calculate highest high and lowest low in range
   g_rangeHigh = iHigh(Symbol(), InpTimeframe, iHighest(Symbol(), InpTimeframe, MODE_HIGH, startBar - endBar + 1, endBar));
   g_rangeLow = iLow(Symbol(), InpTimeframe, iLowest(Symbol(), InpTimeframe, MODE_LOW, startBar - endBar + 1, endBar));
   
   g_rangeCalculated = true;
   
   Print("===========================================");
   Print("Opening Range Calculated:");
   Print("Range High: ", g_rangeHigh);
   Print("Range Low: ", g_rangeLow);
   Print("Range Size: ", (g_rangeHigh - g_rangeLow) / _Point, " points");
   Print("===========================================");
}

//+------------------------------------------------------------------+
//| Place Buy Stop and Sell Stop pending orders                        |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   if(!g_rangeCalculated) return;
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double buffer = InpBreakoutBuffer * point;
   
   //--- Calculate entry prices
   double buyStopPrice = NormalizeDouble(g_rangeHigh + buffer, _Digits);
   double sellStopPrice = NormalizeDouble(g_rangeLow - buffer, _Digits);
   
   //--- Calculate Stop Loss and Take Profit
   double buySL = 0, buyTP = 0, sellSL = 0, sellTP = 0;
   
   //--- Stop Loss calculation
   switch(InpStopLossMode)
   {
      case 0: // Fixed SL
         buySL = NormalizeDouble(buyStopPrice - InpFixedSL * point, _Digits);
         sellSL = NormalizeDouble(sellStopPrice + InpFixedSL * point, _Digits);
         break;
      case 1: // Opposite side of range
         buySL = NormalizeDouble(g_rangeLow - buffer, _Digits);
         sellSL = NormalizeDouble(g_rangeHigh + buffer, _Digits);
         break;
      case 2: // Middle of range
         {
            double rangeMid = (g_rangeHigh + g_rangeLow) / 2.0;
            buySL = NormalizeDouble(rangeMid, _Digits);
            sellSL = NormalizeDouble(rangeMid, _Digits);
         }
         break;
      default: // Fallback to fixed SL
         buySL = NormalizeDouble(buyStopPrice - InpFixedSL * point, _Digits);
         sellSL = NormalizeDouble(sellStopPrice + InpFixedSL * point, _Digits);
         break;
   }
   
   //--- Take Profit calculation (only for RR mode)
   if(InpTakeProfitMode == 0)
   {
      double buyRisk = buyStopPrice - buySL;
      double sellRisk = sellSL - sellStopPrice;
      
      buyTP = NormalizeDouble(buyStopPrice + buyRisk * InpRiskRewardRatio, _Digits);
      sellTP = NormalizeDouble(sellStopPrice - sellRisk * InpRiskRewardRatio, _Digits);
   }
   else
   {
      //--- EOD exit mode - no TP set
      buyTP = 0;
      sellTP = 0;
   }
   
   //--- Place Buy Stop order
   if(trade.BuyStop(InpLotSize, buyStopPrice, Symbol(), buySL, buyTP, ORDER_TIME_GTC, 0, "ORB Buy Breakout"))
   {
      Print("Buy Stop order placed at: ", buyStopPrice, " SL: ", buySL, " TP: ", buyTP);
   }
   else
   {
      Print("Error placing Buy Stop order: ", GetLastError());
   }
   
   //--- Place Sell Stop order
   if(trade.SellStop(InpLotSize, sellStopPrice, Symbol(), sellSL, sellTP, ORDER_TIME_GTC, 0, "ORB Sell Breakout"))
   {
      Print("Sell Stop order placed at: ", sellStopPrice, " SL: ", sellSL, " TP: ", sellTP);
   }
   else
   {
      Print("Error placing Sell Stop order: ", GetLastError());
   }
   
   g_ordersPlaced = true;
}

//+------------------------------------------------------------------+
//| Cancel all pending orders                                          |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && 
            OrderGetString(ORDER_SYMBOL) == Symbol())
         {
            trade.OrderDelete(ticket);
            Print("Pending order cancelled: ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (breakeven, etc.)                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            //--- Mark that a trade has been executed (for OCO logic)
            if(!g_tradeExecuted)
            {
               g_tradeExecuted = true;
               //--- Cancel the other pending order (OCO - One Cancels Other)
               CancelPendingOrders();
            }
            
            //--- Move to breakeven
            MoveToBreakeven(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Move Stop Loss to breakeven after X points profit                  |
//+------------------------------------------------------------------+
void MoveToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double beLevel = InpBreakevenPoints * point;
   
   if(posType == POSITION_TYPE_BUY)
   {
      //--- Check if price has moved enough for breakeven
      if(currentPrice >= openPrice + beLevel)
      {
         //--- Check if SL is not already at or above breakeven
         if(currentSL < openPrice)
         {
            double newSL = NormalizeDouble(openPrice + 1 * point, _Digits);
            if(trade.PositionModify(ticket, newSL, currentTP))
            {
               Print("Position ", ticket, " moved to breakeven at ", newSL);
            }
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      //--- Check if price has moved enough for breakeven
      if(currentPrice <= openPrice - beLevel)
      {
         //--- Check if SL is not already at or below breakeven
         if(currentSL > openPrice || currentSL == 0)
         {
            double newSL = NormalizeDouble(openPrice - 1 * point, _Digits);
            if(trade.PositionModify(ticket, newSL, currentTP))
            {
               Print("Position ", ticket, " moved to breakeven at ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions (EOD Exit)                                     |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            trade.PositionClose(ticket);
            Print("Position ", ticket, " closed at EOD");
         }
      }
   }
   
   //--- Also cancel any remaining pending orders
   CancelPendingOrders();
}

//+------------------------------------------------------------------+
