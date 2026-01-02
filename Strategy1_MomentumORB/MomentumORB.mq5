//+------------------------------------------------------------------+
//|                                                  MomentumORB.mq5 |
//|                             Momentum ORB (Opening Range Breakout) |
//|                    Exploiting liquidity at US Market Open         |
//+------------------------------------------------------------------+
#property copyright "RobinHood Proyect"
#property version   "1.00"
#property description "Opening Range Breakout Strategy for NASDAQ/US100"
#property strict

//--- Input Parameters
input group "=== Time Settings (Broker Server Time) ==="
input int      InpOpenHour          = 15;     // Open Hour (15:30 CET = 09:30 NY time typically)
input int      InpOpenMinute        = 30;     // Open Minute
input int      InpRangeMinutes      = 30;     // Duration of Opening Range (minutes)

input group "=== Trading Settings ==="
input int      InpBufferPoints      = 5;      // Buffer points above/below range for entry
input int      InpExpirationHours   = 2;      // Pending Order Expiration (hours)
input bool     InpCloseAtEOD        = true;   // Close trades at End of Day?
input int      InpEODHour           = 22;     // End of Day Hour
input int      InpEODMinute         = 55;     // End of Day Minute

input group "=== Risk Management ==="
input double   InpLotSize           = 1.0;    // Lot Size
input int      InpStopLoss          = 50;     // Stop Loss (points)
input int      InpTakeProfit        = 100;    // Take Profit (points)
input bool     InpUseRangeForSL     = false;  // Use Range Low/High for SL instead of fixed points

input group "=== General Settings ==="
input ulong    InpMagicNumber       = 100001; // Magic Number
input int      InpSlippage          = 10;     // Slippage (points)

//--- Global Variables
datetime       g_lastDay            = 0;
bool           g_rangeCalculated    = false;
bool           g_ordersPlaced       = false;
double         g_rangeHigh          = 0;
double         g_rangeLow           = 0;

//--- Trade object
#include <Trade\Trade.mqh>
CTrade         trade;
CPositionInfo  posInfo;
COrderInfo     orderInfo;

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
   Print("Opening Time: ", InpOpenHour, ":", InpOpenMinute);
   Print("Range Duration: ", InpRangeMinutes, " minutes");
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
   //--- Check for new day to reset flags
   CheckNewDay();
   
   //--- Time Management
   MqlDateTime dt;
   TimeCurrent(dt);
   
   int currentMinutes = dt.hour * 60 + dt.min;
   int openTimeMinutes = InpOpenHour * 60 + InpOpenMinute;
   int rangeEndTimeMinutes = openTimeMinutes + InpRangeMinutes;
   int eodTimeMinutes = InpEODHour * 60 + InpEODMinute;
   
   //--- 1. Calculate Range (After range duration has passed)
   if(currentMinutes >= rangeEndTimeMinutes && !g_rangeCalculated && !g_ordersPlaced)
   {
      CalculateOpeningRange(openTimeMinutes, rangeEndTimeMinutes);
   }
   
   //--- 2. Place Orders (Immediately after range calculation)
   if(g_rangeCalculated && !g_ordersPlaced)
   {
      PlaceBreakoutOrders();
   }
   
   //--- 3. OCO Logic (One Cancels Other)
   ManageOCO();
   
   //--- 4. End of Day Close
   if(InpCloseAtEOD && currentMinutes >= eodTimeMinutes)
   {
      CloseAllPositions();
      CancelAllOrders();
   }
}

//+------------------------------------------------------------------+
//| Check for new trading day                                          |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   
   if(today != g_lastDay)
   {
      g_lastDay = today;
      g_rangeCalculated = false;
      g_ordersPlaced = false;
      g_rangeHigh = 0;
      g_rangeLow = 0;
      Print("New Day Detected: Resetting Flags.");
   }
}

//+------------------------------------------------------------------+
//| Calculate the High/Low of the opening range                        |
//+------------------------------------------------------------------+
void CalculateOpeningRange(int startTimeMinutes, int endTimeMinutes)
{
   //--- We need to look back at M1 bars to get precise High/Low
   //--- Or we can use current timeframe if it aligns (e.g. M30 on M30 timeframe)
   //--- For robustness, let's use CopyRates on M1
   
   datetime startDt = GetTimeFromMinutes(startTimeMinutes);
   datetime endDt = GetTimeFromMinutes(endTimeMinutes);
   
   MqlRates rates[];
   // Get rates from start to end
   int count = CopyRates(Symbol(), PERIOD_M1, startDt, endDt, rates);
   
   if(count > 0)
   {
      double maxH = -DBL_MAX;
      double minL = DBL_MAX;
      
      for(int i=0; i<count; i++)
      {
         if(rates[i].high > maxH) maxH = rates[i].high;
         if(rates[i].low < minL) minL = rates[i].low;
      }
      
      g_rangeHigh = maxH;
      g_rangeLow = minL;
      g_rangeCalculated = true;
      
      Print("Range Calculated: High=", g_rangeHigh, " Low=", g_rangeLow);
   }
   else
   {
      Print("Error copying rates for range calculation");
   }
}

//+------------------------------------------------------------------+
//| Helper to convert minutes of day to datetime for today             |
//+------------------------------------------------------------------+
datetime GetTimeFromMinutes(int totalMinutes)
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   dt.hour = totalMinutes / 60;
   dt.min = totalMinutes % 60;
   dt.sec = 0;
   
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Place Buy Stop and Sell Stop Orders                                |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   
   //--- Buy Stop
   double buyStopPrice = NormalizeDouble(g_rangeHigh + InpBufferPoints * point, digits);
   double buySL = InpUseRangeForSL ? g_rangeLow : buyStopPrice - (InpStopLoss * point);
   double buyTP = buyStopPrice + (InpTakeProfit * point);
   
   //--- Sell Stop
   double sellStopPrice = NormalizeDouble(g_rangeLow - InpBufferPoints * point, digits);
   double sellSL = InpUseRangeForSL ? g_rangeHigh : sellStopPrice + (InpStopLoss * point);
   double sellTP = sellStopPrice - (InpTakeProfit * point);
   
   //--- Expiration
   datetime expiration = TimeCurrent() + (InpExpirationHours * 3600);
   
   bool buySent = trade.BuyStop(InpLotSize, buyStopPrice, Symbol(), buySL, buyTP, ORDER_TIME_SPECIFIED, expiration, "ORB Buy");
   bool sellSent = trade.SellStop(InpLotSize, sellStopPrice, Symbol(), sellSL, sellTP, ORDER_TIME_SPECIFIED, expiration, "ORB Sell");
   
   if(buySent && sellSent)
   {
      Print("Breakout Orders Placed. Buy Stop: ", buyStopPrice, " Sell Stop: ", sellStopPrice);
      g_ordersPlaced = true;
   }
}

//+------------------------------------------------------------------+
//| One Cancels Other (OCO) Logic                                      |
//+------------------------------------------------------------------+
void ManageOCO()
{
   //--- If we have a position, delete remaining pending orders
   bool hasPosition = false;
   
   if(PositionSelect(Symbol()))
   {
      if(posInfo.Magic() == InpMagicNumber) hasPosition = true;
   }
   else
   {
      // Check all positions manually to be safe
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(posInfo.SelectByIndex(i))
         {
            if(posInfo.Symbol() == Symbol() && posInfo.Magic() == InpMagicNumber)
            {
               hasPosition = true;
               break;
            }
         }
      }
   }
   
   if(hasPosition)
   {
      // Delete any pending orders with my magic number
      CancelAllOrders();
   }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                              |
//+------------------------------------------------------------------+
void CancelAllOrders()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == Symbol() && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            trade.OrderDelete(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions for this EA                                    |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}
