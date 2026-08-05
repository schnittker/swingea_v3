//+------------------------------------------------------------------+
//| SymbolUtils.mqh                                                  |
//| Pip/Point-Konvertierung (inkl. JPY-Sonderfall) und               |
//| Friktionsschaetzung (Spread + Kommission + Slippage-Puffer).     |
//| Keine Abhaengigkeit auf andere Include-Module.                   |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Groesse eines "Pips" in Preiseinheiten fuer ein Symbol.          |
//| Broker liefern meist 5 Nachkommastellen (Nicht-JPY) bzw. 3        |
//| (JPY-Paare) statt der klassischen 4/2 - dann ist 1 Pip = 10       |
//| Points. Bei klassischer 4/2-Notierung ist 1 Pip = 1 Point.       |
//+------------------------------------------------------------------+
double GetPipSize(const string symbol)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
  }

//+------------------------------------------------------------------+
//| Rechnet eine Preisdistanz (z.B. |EntryPrice - SLPrice|) in Pips. |
//+------------------------------------------------------------------+
double PriceDistanceToPips(const string symbol, const double priceDistance)
  {
   double pipSize = GetPipSize(symbol);
   if(pipSize <= 0.0)
      return 0.0;
   return MathAbs(priceDistance) / pipSize;
  }

//+------------------------------------------------------------------+
//| Rechnet eine Pip-Distanz in eine Preisdistanz um.                |
//+------------------------------------------------------------------+
double PipsToPriceDistance(const string symbol, const double pips)
  {
   return pips * GetPipSize(symbol);
  }

//+------------------------------------------------------------------+
//| Aktueller Spread in Pips (aus dem Broker-Tick, nicht statisch).  |
//+------------------------------------------------------------------+
double GetCurrentSpreadPips(const string symbol)
  {
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return 0.0;
   return PriceDistanceToPips(symbol, ask - bid);
  }

//+------------------------------------------------------------------+
//| Wert eines Pips fuer 1.0 Lot in Kontowaehrung. Basis fuer         |
//| Lotgroessenberechnung (RiskManager) und Kommissions-Umrechnung.  |
//+------------------------------------------------------------------+
double GetPipValuePerLot(const string symbol)
  {
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize   = GetPipSize(symbol);
   if(tickSize <= 0.0)
      return 0.0;
   return tickValue * (pipSize / tickSize);
  }

//+------------------------------------------------------------------+
//| Schaetzt die Round-Turn-Friktion in Pips: aktueller Spread +     |
//| Kommission (umgerechnet ueber PipValuePerLot) + ein fester        |
//| Slippage-Puffer (v.a. fuer Breakout-Entries relevant, siehe       |
//| Kernzahl-Analyse: Slippage bei Breakouts > Spread + Kommission). |
//|                                                                    |
//| commissionPerLotRoundTurn: Kommission in Kontowaehrung pro 1.0    |
//|   Lot fuer eine komplette Round-Turn (Open+Close), aus Input.     |
//| slippageBufferPips: fester Sicherheitspuffer aus Input.           |
//+------------------------------------------------------------------+
double GetFrictionPips(const string symbol,
                        const double commissionPerLotRoundTurn,
                        const double slippageBufferPips)
  {
   double spreadPips = GetCurrentSpreadPips(symbol);

   double commissionPips = 0.0;
   double pipValuePerLot = GetPipValuePerLot(symbol);
   if(pipValuePerLot > 0.0)
      commissionPips = commissionPerLotRoundTurn / pipValuePerLot;

   return spreadPips + commissionPips + slippageBufferPips;
  }

//+------------------------------------------------------------------+
//| Normalisiert einen Preis auf die Tick-Groesse des Symbols.       |
//+------------------------------------------------------------------+
double NormalizePriceToTick(const string symbol, const double price)
  {
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   return MathRound(price / tickSize) * tickSize;
  }

//+------------------------------------------------------------------+
