//+------------------------------------------------------------------+
//|                                                    TrendRider.mq5 |
//|                              Trend-Rider (Dual EMA + RSI Filter)  |
//|                            Capturing sustained intraday moves     |
//+------------------------------------------------------------------+
#property copyright "RobinHood Proyect"
#property version   "1.00"
#property description "Dual EMA Crossover with RSI filter for NASDAQ/US100"
#property strict

//--- Input Parameters
input group "=== EMA Settings ==="
input int      InpFastEMA           = 9;      // Fast EMA Period
input int      InpSlowEMA           = 21;     // Slow EMA Period
input ENUM_APPLIED_PRICE InpEMAPrice = PRICE_CLOSE; // EMA Applied Price

input group "=== RSI Settings ==="
input int      InpRSIPeriod         = 14;     // RSI Period
input int      InpRSIOverbought     = 70;     // RSI Overbought Level
input int      InpRSIOversold       = 30;     // RSI Oversold Level

input group "=== ATR Stop Loss ==="
input int      InpATRPeriod         = 14;     // ATR Period
input double   InpATRMultiplier     = 2.0;    // ATR Multiplier for Stop Loss

input group "=== Risk Management ==="
input double   InpLotSize           = 0.1;    // Lot Size
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_H1; // Strategy Timeframe

input group "=== General Settings ==="
input ulong    InpMagicNumber       = 100002; // Magic Number
input int      InpSlippage          = 10;     // Slippage (points)

//--- Indicator Handles
int            g_handleFastEMA;
int            g_handleSlowEMA;
int            g_handleRSI;
int            g_handleATR;

//--- Indicator Buffers
double         g_fastEMA[];
double         g_slowEMA[];
double         g_rsi[];
double         g_atr[];

//--- Global Variables
datetime       g_lastBarTime        = 0;
int            g_prevSignal         = 0;  // -1 = Short, 0 = None, 1 = Long

//--- Trade object
#include <Trade\Trade.mqh>
CTrade         trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create indicator handles
   g_handleFastEMA = iMA(Symbol(), InpTimeframe, InpFastEMA, 0, MODE_EMA, InpEMAPrice);
   g_handleSlowEMA = iMA(Symbol(), InpTimeframe, InpSlowEMA, 0, MODE_EMA, InpEMAPrice);
   g_handleRSI = iRSI(Symbol(), InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   g_handleATR = iATR(Symbol(), InpTimeframe, InpATRPeriod);
   
   if(g_handleFastEMA == INVALID_HANDLE || g_handleSlowEMA == INVALID_HANDLE || 
      g_handleRSI == INVALID_HANDLE || g_handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }
   
   //--- Set array as series
   ArraySetAsSeries(g_fastEMA, true);
   ArraySetAsSeries(g_slowEMA, true);
   ArraySetAsSeries(g_rsi, true);
   ArraySetAsSeries(g_atr, true);
   
   //--- Set magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   Print("===========================================");
   Print("Trend-Rider EA Initialized");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Fast EMA: ", InpFastEMA, " | Slow EMA: ", InpSlowEMA);
   Print("RSI Period: ", InpRSIPeriod);
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
   IndicatorRelease(g_handleFastEMA);
   IndicatorRelease(g_handleSlowEMA);
   IndicatorRelease(g_handleRSI);
   IndicatorRelease(g_handleATR);
   
   Print("Trend-Rider EA Deinitialized. Reason: ", reason);
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
   
   //--- Check for exit signals first
   CheckExitSignals();
   
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
   //--- Copy indicator data (need at least 3 bars for crossover detection)
   if(CopyBuffer(g_handleFastEMA, 0, 0, 3, g_fastEMA) < 3) return false;
   if(CopyBuffer(g_handleSlowEMA, 0, 0, 3, g_slowEMA) < 3) return false;
   if(CopyBuffer(g_handleRSI, 0, 0, 2, g_rsi) < 2) return false;
   if(CopyBuffer(g_handleATR, 0, 0, 2, g_atr) < 2) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                            |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   //--- Don't enter if already in position
   if(HasOpenPosition()) return;
   
   //--- Get current values (bar index 1 = last closed bar)
   double fastEMA_current = g_fastEMA[1];
   double fastEMA_prev = g_fastEMA[2];
   double slowEMA_current = g_slowEMA[1];
   double slowEMA_prev = g_slowEMA[2];
   double rsi_current = g_rsi[1];
   double atr_current = g_atr[1];
   
   //--- Check for LONG entry
   // Fast EMA crosses ABOVE Slow EMA AND RSI is NOT overbought
   if(fastEMA_prev <= slowEMA_prev && fastEMA_current > slowEMA_current)
   {
      if(rsi_current < InpRSIOverbought)
      {
         //--- Calculate Stop Loss using ATR
         double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double stopLoss = NormalizeDouble(entryPrice - (atr_current * InpATRMultiplier), _Digits);
         
         if(trade.Buy(InpLotSize, Symbol(), entryPrice, stopLoss, 0, "TrendRider Long"))
         {
            Print("LONG Entry: Price=", entryPrice, " SL=", stopLoss, " RSI=", rsi_current);
            g_prevSignal = 1;
         }
         else
         {
            Print("Error opening Long position: ", GetLastError());
         }
      }
      else
      {
         Print("Long signal filtered - RSI overbought: ", rsi_current);
      }
   }
   
   //--- Check for SHORT entry
   // Fast EMA crosses BELOW Slow EMA AND RSI is NOT oversold
   if(fastEMA_prev >= slowEMA_prev && fastEMA_current < slowEMA_current)
   {
      if(rsi_current > InpRSIOversold)
      {
         //--- Calculate Stop Loss using ATR
         double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double stopLoss = NormalizeDouble(entryPrice + (atr_current * InpATRMultiplier), _Digits);
         
         if(trade.Sell(InpLotSize, Symbol(), entryPrice, stopLoss, 0, "TrendRider Short"))
         {
            Print("SHORT Entry: Price=", entryPrice, " SL=", stopLoss, " RSI=", rsi_current);
            g_prevSignal = -1;
         }
         else
         {
            Print("Error opening Short position: ", GetLastError());
         }
      }
      else
      {
         Print("Short signal filtered - RSI oversold: ", rsi_current);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for exit signals                                             |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   //--- Get current EMA values
   double fastEMA_current = g_fastEMA[1];
   double fastEMA_prev = g_fastEMA[2];
   double slowEMA_current = g_slowEMA[1];
   double slowEMA_prev = g_slowEMA[2];
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            //--- Exit LONG when Fast EMA crosses back BELOW Slow EMA
            if(posType == POSITION_TYPE_BUY)
            {
               if(fastEMA_prev >= slowEMA_prev && fastEMA_current < slowEMA_current)
               {
                  if(trade.PositionClose(ticket))
                  {
                     Print("LONG Exit: EMA crossover reversal");
                     g_prevSignal = 0;
                  }
               }
            }
            
            //--- Exit SHORT when Fast EMA crosses back ABOVE Slow EMA
            if(posType == POSITION_TYPE_SELL)
            {
               if(fastEMA_prev <= slowEMA_prev && fastEMA_current > slowEMA_current)
               {
                  if(trade.PositionClose(ticket))
                  {
                     Print("SHORT Exit: EMA crossover reversal");
                     g_prevSignal = 0;
                  }
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
