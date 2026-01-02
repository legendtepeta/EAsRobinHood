//+------------------------------------------------------------------+
//|                                                       GapFill.mq5 |
//|                             Gap Fill (Overnight Structure)        |
//|            Capitalizing on market psychology and rebalancing      |
//+------------------------------------------------------------------+
#property copyright "NASDAQ Strategy Portfolio"
#property version   "1.00"
#property description "Gap Fill strategy for NASDAQ/US100"
#property strict

//--- Input Parameters
input group "=== Trading Hours (Broker Server Time) ==="
input int      InpAnalysisHour      = 15;     // Analysis Hour (09:30 EST = 15:30 CET typically)
input int      InpAnalysisMinute    = 30;     // Analysis Minute

input group "=== Gap Settings ==="
input int      InpGapThreshold      = 20;     // Minimum Gap Threshold (points)
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5; // Strategy Timeframe

input group "=== Risk Management ==="
input double   InpLotSize           = 0.1;    // Lot Size

input group "=== General Settings ==="
input ulong    InpMagicNumber       = 100004; // Magic Number
input int      InpSlippage          = 10;     // Slippage (points)

//--- Global Variables
double         g_yesterdayClose     = 0;
bool           g_gapAnalyzed        = false;
bool           g_tradeExecuted      = false;
datetime       g_currentDay         = 0;
datetime       g_lastBarTime        = 0;

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
   Print("Gap Fill EA Initialized");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Gap Threshold: ", InpGapThreshold, " points");
   Print("Magic Number: ", InpMagicNumber);
   Print("===========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Gap Fill EA Deinitialized. Reason: ", reason);
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
   int analysisTime = InpAnalysisHour * 60 + InpAnalysisMinute;
   
   //--- Get yesterday's close at the start of each day
   if(!g_gapAnalyzed && g_yesterdayClose == 0)
   {
      GetYesterdayClose();
   }
   
   //--- At analysis time, check for gap and wait for first candle
   if(currentMinutes >= analysisTime && currentMinutes < analysisTime + 10 && !g_tradeExecuted)
   {
      //--- Only check on new bar
      if(IsNewBar())
      {
         AnalyzeGapAndTrade();
      }
   }
}

//+------------------------------------------------------------------+
//| Check for new bar                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol(), InpTimeframe, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
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
      g_yesterdayClose = 0;
      g_gapAnalyzed = false;
      g_tradeExecuted = false;
      
      Print("New trading day detected: ", TimeToString(today, TIME_DATE));
   }
}

//+------------------------------------------------------------------+
//| Get yesterday's closing price                                      |
//+------------------------------------------------------------------+
void GetYesterdayClose()
{
   //--- Get D1 close from yesterday
   g_yesterdayClose = iClose(Symbol(), PERIOD_D1, 1);
   
   if(g_yesterdayClose > 0)
   {
      Print("Yesterday's Close: ", g_yesterdayClose);
   }
   else
   {
      Print("Error getting yesterday's close");
   }
}

//+------------------------------------------------------------------+
//| Analyze gap and execute trade                                      |
//+------------------------------------------------------------------+
void AnalyzeGapAndTrade()
{
   if(g_tradeExecuted || g_yesterdayClose == 0) return;
   
   //--- We need to wait for the first 5-min candle to close after market open
   //--- So we check bar index 1 (last closed bar)
   double firstCandleOpen = iOpen(Symbol(), InpTimeframe, 1);
   double firstCandleClose = iClose(Symbol(), InpTimeframe, 1);
   double firstCandleHigh = iHigh(Symbol(), InpTimeframe, 1);
   double firstCandleLow = iLow(Symbol(), InpTimeframe, 1);
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double gapSize = (firstCandleOpen - g_yesterdayClose) / point;
   
   Print("Gap Analysis - Yesterday Close: ", g_yesterdayClose, 
         " | Today Open: ", firstCandleOpen, 
         " | Gap Size: ", gapSize, " points");
   
   g_gapAnalyzed = true;
   
   //--- Check if gap is significant
   if(MathAbs(gapSize) < InpGapThreshold)
   {
      Print("Gap too small (", MathAbs(gapSize), " points). No trade today.");
      g_tradeExecuted = true;  // Mark as done for today
      return;
   }
   
   //--- GAP DOWN (Market opens below yesterday's close) -> Look for LONG
   if(gapSize < -InpGapThreshold)
   {
      //--- First candle must be Bullish (Green)
      if(firstCandleClose > firstCandleOpen)
      {
         double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double stopLoss = NormalizeDouble(firstCandleLow - 5 * point, _Digits);
         double takeProfit = NormalizeDouble(g_yesterdayClose, _Digits);
         
         if(trade.Buy(InpLotSize, Symbol(), entryPrice, stopLoss, takeProfit, "GapFill Long"))
         {
            Print("GAP DOWN - LONG Entry: Price=", entryPrice, 
                  " SL=", stopLoss, " TP=", takeProfit, " Gap=", gapSize);
            g_tradeExecuted = true;
         }
         else
         {
            Print("Error opening Long position: ", GetLastError());
         }
      }
      else
      {
         Print("Gap Down detected but first candle is Bearish. No entry.");
         g_tradeExecuted = true;
      }
   }
   
   //--- GAP UP (Market opens above yesterday's close) -> Look for SHORT
   if(gapSize > InpGapThreshold)
   {
      //--- First candle must be Bearish (Red)
      if(firstCandleClose < firstCandleOpen)
      {
         double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double stopLoss = NormalizeDouble(firstCandleHigh + 5 * point, _Digits);
         double takeProfit = NormalizeDouble(g_yesterdayClose, _Digits);
         
         if(trade.Sell(InpLotSize, Symbol(), entryPrice, stopLoss, takeProfit, "GapFill Short"))
         {
            Print("GAP UP - SHORT Entry: Price=", entryPrice, 
                  " SL=", stopLoss, " TP=", takeProfit, " Gap=", gapSize);
            g_tradeExecuted = true;
         }
         else
         {
            Print("Error opening Short position: ", GetLastError());
         }
      }
      else
      {
         Print("Gap Up detected but first candle is Bullish. No entry.");
         g_tradeExecuted = true;
      }
   }
}

//+------------------------------------------------------------------+
