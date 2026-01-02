//+------------------------------------------------------------------+
//|                                                      SnapBack.mq5 |
//|                         Snap-Back (Bollinger Mean Reversion)      |
//|                  Profiting from choppy, sideways markets          |
//+------------------------------------------------------------------+
#property copyright "NASDAQ Strategy Portfolio"
#property version   "1.00"
#property description "Bollinger Band Mean Reversion with ADX filter for NASDAQ/US100"
#property strict

//--- Input Parameters
input group "=== Bollinger Bands Settings ==="
input int      InpBBPeriod          = 20;     // Bollinger Bands Period
input double   InpBBDeviation       = 2.0;    // Bollinger Bands Deviation
input ENUM_APPLIED_PRICE InpBBPrice = PRICE_CLOSE; // BB Applied Price

input group "=== ADX Filter ==="
input int      InpADXPeriod         = 14;     // ADX Period
input int      InpADXThreshold      = 25;     // ADX Threshold (< this = ranging market)

input group "=== Risk Management ==="
input double   InpLotSize           = 0.1;    // Lot Size
input int      InpSLBuffer          = 10;     // SL Buffer beyond bands (points)
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M15; // Strategy Timeframe

input group "=== General Settings ==="
input ulong    InpMagicNumber       = 100003; // Magic Number
input int      InpSlippage          = 10;     // Slippage (points)

//--- Indicator Handles
int            g_handleBB;
int            g_handleADX;

//--- Indicator Buffers
double         g_bbUpper[];
double         g_bbMiddle[];
double         g_bbLower[];
double         g_adx[];

//--- Global Variables
datetime       g_lastBarTime        = 0;

//--- Trade object
#include <Trade\Trade.mqh>
CTrade         trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create indicator handles
   g_handleBB = iBands(Symbol(), InpTimeframe, InpBBPeriod, 0, InpBBDeviation, InpBBPrice);
   g_handleADX = iADX(Symbol(), InpTimeframe, InpADXPeriod);
   
   if(g_handleBB == INVALID_HANDLE || g_handleADX == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }
   
   //--- Set array as series
   ArraySetAsSeries(g_bbUpper, true);
   ArraySetAsSeries(g_bbMiddle, true);
   ArraySetAsSeries(g_bbLower, true);
   ArraySetAsSeries(g_adx, true);
   
   //--- Set magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   Print("===========================================");
   Print("Snap-Back EA Initialized");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("BB Period: ", InpBBPeriod, " | Deviation: ", InpBBDeviation);
   Print("ADX Threshold: ", InpADXThreshold);
   Print("Magic Number: ", InpMagicNumber);
   Print("===========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   IndicatorRelease(g_handleBB);
   IndicatorRelease(g_handleADX);
   
   Print("Snap-Back EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only trade on new bar
   if(!IsNewBar()) return;
   
   //--- Get indicator values
   if(!GetIndicatorValues()) return;
   
   //--- Manage open positions (check for TP at middle band)
   ManagePositions();
   
   //--- Check for entry signals
   CheckEntrySignals();
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
//| Get indicator values                                               |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
   //--- Bollinger Bands: 0=Middle, 1=Upper, 2=Lower
   if(CopyBuffer(g_handleBB, 0, 0, 3, g_bbMiddle) < 3) return false;
   if(CopyBuffer(g_handleBB, 1, 0, 3, g_bbUpper) < 3) return false;
   if(CopyBuffer(g_handleBB, 2, 0, 3, g_bbLower) < 3) return false;
   
   //--- ADX: 0=Main ADX
   if(CopyBuffer(g_handleADX, 0, 0, 2, g_adx) < 2) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                            |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   //--- Don't enter if already in position
   if(HasOpenPosition()) return;
   
   //--- Check ADX filter - only trade in ranging markets
   double adx_current = g_adx[1];
   if(adx_current >= InpADXThreshold)
   {
      //--- Market is trending, don't trade mean reversion
      return;
   }
   
   //--- Get last closed bar data (index 1)
   double close = iClose(Symbol(), InpTimeframe, 1);
   double open = iOpen(Symbol(), InpTimeframe, 1);
   double high = iHigh(Symbol(), InpTimeframe, 1);
   double low = iLow(Symbol(), InpTimeframe, 1);
   
   double upperBand = g_bbUpper[1];
   double lowerBand = g_bbLower[1];
   double middleBand = g_bbMiddle[1];
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   //--- SHORT Entry: Price touches/closes above Upper Band + Bearish candle
   if(high >= upperBand || close >= upperBand)
   {
      //--- Confirm bearish candle (close < open)
      if(close < open)
      {
         double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double stopLoss = NormalizeDouble(upperBand + InpSLBuffer * point, _Digits);
         double takeProfit = NormalizeDouble(middleBand, _Digits);
         
         if(trade.Sell(InpLotSize, Symbol(), entryPrice, stopLoss, takeProfit, "SnapBack Short"))
         {
            Print("SHORT Entry: Price=", entryPrice, " SL=", stopLoss, " TP=", takeProfit, " ADX=", adx_current);
         }
         else
         {
            Print("Error opening Short position: ", GetLastError());
         }
      }
   }
   
   //--- LONG Entry: Price touches/closes below Lower Band + Bullish candle
   if(low <= lowerBand || close <= lowerBand)
   {
      //--- Confirm bullish candle (close > open)
      if(close > open)
      {
         double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double stopLoss = NormalizeDouble(lowerBand - InpSLBuffer * point, _Digits);
         double takeProfit = NormalizeDouble(middleBand, _Digits);
         
         if(trade.Buy(InpLotSize, Symbol(), entryPrice, stopLoss, takeProfit, "SnapBack Long"))
         {
            Print("LONG Entry: Price=", entryPrice, " SL=", stopLoss, " TP=", takeProfit, " ADX=", adx_current);
         }
         else
         {
            Print("Error opening Long position: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions - update TP to current middle band          |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double currentMiddle = g_bbMiddle[0];
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            double currentTP = PositionGetDouble(POSITION_TP);
            double currentSL = PositionGetDouble(POSITION_SL);
            double newTP = NormalizeDouble(currentMiddle, _Digits);
            
            //--- Update TP if middle band has moved significantly
            if(MathAbs(currentTP - newTP) > _Point * 5)
            {
               if(trade.PositionModify(ticket, currentSL, newTP))
               {
                  Print("TP Updated to current middle band: ", newTP);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there's an open position                                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
