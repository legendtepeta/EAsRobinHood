//+------------------------------------------------------------------+
//|                                            PriceActionMaster.mq5 |
//|                        Price Action Master (Candlestick Patterns) |
//|                   Pure price behavior at key round numbers        |
//+------------------------------------------------------------------+
#property copyright "RobinHood Proyect"
#property version   "1.00"
#property description "Candlestick Pattern recognition at Key Levels for NASDAQ/US100"
#property strict

//--- Input Parameters
input group "=== Key Level Settings ==="
input int      InpKeyLevelInterval  = 500;    // Key Level Interval (e.g., 500 or 1000 points)
input int      InpLevelProximity    = 10;     // Distance from Key Level (points)

input group "=== Pattern Settings ==="
input double   InpPinBarRatio       = 0.30;   // Pin Bar: Body must be in top/bottom X% of range
input double   InpMinWickRatio      = 2.0;    // Pin Bar: Wick must be X times body size

input group "=== Risk Management ==="
input double   InpLotSize           = 0.1;    // Lot Size
input double   InpRiskRewardRatio   = 3.0;    // Risk:Reward Ratio for Take Profit
input int      InpBreakevenRR       = 1;      // Move to Breakeven at X:1 R:R

input group "=== General Settings ==="
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M15; // Strategy Timeframe
input ulong    InpMagicNumber       = 100005; // Magic Number
input int      InpSlippage          = 10;     // Slippage (points)

//--- Global Variables
datetime       g_lastBarTime        = 0;

//--- Trade object
#include <Trade\Trade.mqh>
CTrade         trade;

//--- Pattern types
enum ENUM_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_BULLISH_PINBAR,
   PATTERN_BEARISH_PINBAR,
   PATTERN_BULLISH_ENGULFING,
   PATTERN_BEARISH_ENGULFING
};

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
   Print("Price Action Master EA Initialized");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Key Level Interval: ", InpKeyLevelInterval);
   Print("Level Proximity: ", InpLevelProximity, " points");
   Print("Magic Number: ", InpMagicNumber);
   Print("===========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Price Action Master EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only trade on new bar
   if(!IsNewBar()) return;
   
   //--- Manage existing positions
   ManagePositions();
   
   //--- Don't enter if already in position
   if(HasOpenPosition()) return;
   
   //--- Check for pattern at key level
   CheckPatternAtKeyLevel();
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
//| Get nearest key level                                              |
//+------------------------------------------------------------------+
double GetNearestKeyLevel(double price)
{
   //--- Round to nearest key level
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double interval = InpKeyLevelInterval * point;
   
   double nearestLevel = MathRound(price / interval) * interval;
   return NormalizeDouble(nearestLevel, _Digits);
}

//+------------------------------------------------------------------+
//| Check if price is near a key level                                 |
//+------------------------------------------------------------------+
bool IsNearKeyLevel(double price, double &keyLevel)
{
   keyLevel = GetNearestKeyLevel(price);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double proximity = InpLevelProximity * point;
   
   return (MathAbs(price - keyLevel) <= proximity);
}

//+------------------------------------------------------------------+
//| Detect Pin Bar pattern                                             |
//+------------------------------------------------------------------+
ENUM_PATTERN DetectPinBar(int barIndex)
{
   double open = iOpen(Symbol(), InpTimeframe, barIndex);
   double high = iHigh(Symbol(), InpTimeframe, barIndex);
   double low = iLow(Symbol(), InpTimeframe, barIndex);
   double close = iClose(Symbol(), InpTimeframe, barIndex);
   
   double range = high - low;
   if(range == 0) return PATTERN_NONE;
   
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   //--- Bullish Pin Bar (Hammer): Long lower wick, body at top
   if(body <= range * InpPinBarRatio)  // Small body
   {
      if(lowerWick >= body * InpMinWickRatio)  // Long lower wick
      {
         double bodyTop = MathMax(open, close);
         if((high - bodyTop) <= range * InpPinBarRatio)  // Body at top
         {
            return PATTERN_BULLISH_PINBAR;
         }
      }
      
      //--- Bearish Pin Bar (Shooting Star): Long upper wick, body at bottom
      if(upperWick >= body * InpMinWickRatio)  // Long upper wick
      {
         double bodyBottom = MathMin(open, close);
         if((bodyBottom - low) <= range * InpPinBarRatio)  // Body at bottom
         {
            return PATTERN_BEARISH_PINBAR;
         }
      }
   }
   
   return PATTERN_NONE;
}

//+------------------------------------------------------------------+
//| Detect Engulfing pattern                                           |
//+------------------------------------------------------------------+
ENUM_PATTERN DetectEngulfing(int barIndex)
{
   //--- Current candle
   double open1 = iOpen(Symbol(), InpTimeframe, barIndex);
   double close1 = iClose(Symbol(), InpTimeframe, barIndex);
   double body1 = MathAbs(close1 - open1);
   
   //--- Previous candle
   double open2 = iOpen(Symbol(), InpTimeframe, barIndex + 1);
   double close2 = iClose(Symbol(), InpTimeframe, barIndex + 1);
   double body2 = MathAbs(close2 - open2);
   
   if(body1 == 0 || body2 == 0) return PATTERN_NONE;
   
   //--- Bullish Engulfing: Previous bearish, current bullish engulfs previous body
   if(close2 < open2 && close1 > open1)  // Previous bearish, current bullish
   {
      if(open1 <= close2 && close1 >= open2)  // Current body engulfs previous body
      {
         return PATTERN_BULLISH_ENGULFING;
      }
   }
   
   //--- Bearish Engulfing: Previous bullish, current bearish engulfs previous body
   if(close2 > open2 && close1 < open1)  // Previous bullish, current bearish
   {
      if(open1 >= close2 && close1 <= open2)  // Current body engulfs previous body
      {
         return PATTERN_BEARISH_ENGULFING;
      }
   }
   
   return PATTERN_NONE;
}

//+------------------------------------------------------------------+
//| Check for pattern at key level                                     |
//+------------------------------------------------------------------+
void CheckPatternAtKeyLevel()
{
   //--- Get last closed bar data
   double close = iClose(Symbol(), InpTimeframe, 1);
   double high = iHigh(Symbol(), InpTimeframe, 1);
   double low = iLow(Symbol(), InpTimeframe, 1);
   
   double keyLevel = 0;
   
   //--- Check if candle touched a key level
   bool nearUpperLevel = IsNearKeyLevel(high, keyLevel);
   bool nearLowerLevel = IsNearKeyLevel(low, keyLevel);
   
   if(!nearUpperLevel && !nearLowerLevel) return;
   
   //--- Check for patterns
   ENUM_PATTERN pinBar = DetectPinBar(1);
   ENUM_PATTERN engulfing = DetectEngulfing(1);
   
   ENUM_PATTERN pattern = PATTERN_NONE;
   if(pinBar != PATTERN_NONE) pattern = pinBar;
   else if(engulfing != PATTERN_NONE) pattern = engulfing;
   
   if(pattern == PATTERN_NONE) return;
   
   //--- Execute trade based on pattern
   ExecuteTrade(pattern, 1);
}

//+------------------------------------------------------------------+
//| Execute trade based on pattern                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_PATTERN pattern, int barIndex)
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double high = iHigh(Symbol(), InpTimeframe, barIndex);
   double low = iLow(Symbol(), InpTimeframe, barIndex);
   
   double entryPrice, stopLoss, takeProfit, risk;
   string comment;
   
   switch(pattern)
   {
      case PATTERN_BULLISH_PINBAR:
      case PATTERN_BULLISH_ENGULFING:
         entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         stopLoss = NormalizeDouble(low - 5 * point, _Digits);
         risk = entryPrice - stopLoss;
         takeProfit = NormalizeDouble(entryPrice + risk * InpRiskRewardRatio, _Digits);
         comment = (pattern == PATTERN_BULLISH_PINBAR) ? "PA Bullish PinBar" : "PA Bullish Engulf";
         
         if(trade.Buy(InpLotSize, Symbol(), entryPrice, stopLoss, takeProfit, comment))
         {
            Print("LONG Entry: Pattern=", comment, " Price=", entryPrice, 
                  " SL=", stopLoss, " TP=", takeProfit);
         }
         else
         {
            Print("Error opening Long position: ", GetLastError());
         }
         break;
         
      case PATTERN_BEARISH_PINBAR:
      case PATTERN_BEARISH_ENGULFING:
         entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         stopLoss = NormalizeDouble(high + 5 * point, _Digits);
         risk = stopLoss - entryPrice;
         takeProfit = NormalizeDouble(entryPrice - risk * InpRiskRewardRatio, _Digits);
         comment = (pattern == PATTERN_BEARISH_PINBAR) ? "PA Bearish PinBar" : "PA Bearish Engulf";
         
         if(trade.Sell(InpLotSize, Symbol(), entryPrice, stopLoss, takeProfit, comment))
         {
            Print("SHORT Entry: Pattern=", comment, " Price=", entryPrice, 
                  " SL=", stopLoss, " TP=", takeProfit);
         }
         else
         {
            Print("Error opening Short position: ", GetLastError());
         }
         break;
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (trailing, breakeven)                        |
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
            MoveToBreakeven(ticket);
            TrailingStop(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Move to breakeven at 1:1 R:R                                       |
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
   double originalRisk = MathAbs(openPrice - currentSL);
   double beTarget = originalRisk * InpBreakevenRR;
   
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentPrice >= openPrice + beTarget)
      {
         if(currentSL < openPrice)
         {
            double newSL = NormalizeDouble(openPrice + 1 * point, _Digits);
            trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(currentPrice <= openPrice - beTarget)
      {
         if(currentSL > openPrice || currentSL == 0)
         {
            double newSL = NormalizeDouble(openPrice - 1 * point, _Digits);
            trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Aggressive trailing stop (candle by candle)                        |
//+------------------------------------------------------------------+
void TrailingStop(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double originalRisk = MathAbs(openPrice - currentSL);
   
   //--- Only trail after 1:1 is reached
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentSL >= openPrice)  // Already at breakeven
      {
         //--- Trail to previous candle's low
         double prevLow = iLow(Symbol(), InpTimeframe, 1);
         double newSL = NormalizeDouble(prevLow - 2 * point, _Digits);
         
         if(newSL > currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print("Trailing SL updated for LONG: ", newSL);
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(currentSL <= openPrice && currentSL != 0)  // Already at breakeven
      {
         //--- Trail to previous candle's high
         double prevHigh = iHigh(Symbol(), InpTimeframe, 1);
         double newSL = NormalizeDouble(prevHigh + 2 * point, _Digits);
         
         if(newSL < currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print("Trailing SL updated for SHORT: ", newSL);
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
