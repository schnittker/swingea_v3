//+------------------------------------------------------------------+
//| DonchianBreakoutSignal.mqh                                       |
//| Strategie 2: Donchian-Breakout (H1) + ADX(14)-Trendfilter.       |
//| Der ADX-Filter adressiert das historische Ergebnis (PF 0.44,     |
//| Donchian ohne Trendfilter im Range-Markt) - nur bei ADX >=        |
//| adxMinLevel (Default-Korridor 22-25) wird der Breakout gehandelt.|
//| SL = max(Gegenband-Distanz, 1.5xATR14), Floor MinSLDistancePips. |
//| TP per festem RR (Start 2.5-3.0), Trailing als spaetere Ausbaustufe.|
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "SymbolUtils.mqh"
#include "RiskManager.mqh"

//--- ATR-Periode ist bewusst fix auf 14 (Kernzahl-Referenz "1.5xATR14"
//--- aus dem Konzept), waehrend der ADX-Periode ueber Input einstellbar bleibt.
#define DONCHIAN_ATR_PERIOD 14

//+------------------------------------------------------------------+
//| Laufender Zustand pro Symbol: Indikator-Handles (einmalig in     |
//| OnInit erzeugt, in OnDeinit freigegeben) + Frequenzsperre.       |
//+------------------------------------------------------------------+
struct SDonchianState
  {
   int               handleADX;
   int               handleATR;
   datetime          lastTradeDay;
  };

//+------------------------------------------------------------------+
//| Mitternacht (Server-Zeit) des uebergebenen Zeitpunkts.           |
//+------------------------------------------------------------------+
datetime DonchianDayStart(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Erzeugt ADX- und ATR-Indikator-Handles fuer jedes Symbol. Muss   |
//| einmalig in OnInit aufgerufen werden. Gibt false zurueck, wenn   |
//| mindestens ein Handle nicht erzeugt werden konnte.                |
//+------------------------------------------------------------------+
bool InitDonchianState(SDonchianState &states[], const string &symbols[], const int numSymbols,
                        const int adxPeriod)
  {
   ArrayResize(states, numSymbols);
   bool allOk = true;

   for(int i = 0; i < numSymbols; i++)
     {
      states[i].handleADX     = iADX(symbols[i], PERIOD_H1, adxPeriod);
      states[i].handleATR     = iATR(symbols[i], PERIOD_H1, DONCHIAN_ATR_PERIOD);
      states[i].lastTradeDay  = 0;

      if(states[i].handleADX == INVALID_HANDLE || states[i].handleATR == INVALID_HANDLE)
        {
         PrintFormat("InitDonchianState: Indikator-Handle fuer %s fehlgeschlagen (ADX=%d, ATR=%d).",
                     symbols[i], states[i].handleADX, states[i].handleATR);
         allOk = false;
        }
     }

   return allOk;
  }

//+------------------------------------------------------------------+
//| Gibt alle Indikator-Handles frei. Muss in OnDeinit aufgerufen    |
//| werden.                                                            |
//+------------------------------------------------------------------+
void DeinitDonchianState(SDonchianState &states[])
  {
   for(int i = 0; i < ArraySize(states); i++)
     {
      if(states[i].handleADX != INVALID_HANDLE)
         IndicatorRelease(states[i].handleADX);
      if(states[i].handleATR != INVALID_HANDLE)
         IndicatorRelease(states[i].handleATR);
     }
  }

//+------------------------------------------------------------------+
//| Liest einen einzelnen Indikator-Puffer-Wert an shift. Gibt false |
//| zurueck, wenn (noch) nicht genug Historie vorhanden ist.          |
//+------------------------------------------------------------------+
bool GetIndicatorValue(const int handle, const int bufferIndex, const int shift, double &outValue)
  {
   double buf[];
   if(CopyBuffer(handle, bufferIndex, shift, 1, buf) <= 0)
      return false;
   outValue = buf[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Prueft auf einen Donchian-Breakout mit ADX-Trendfilter. Basis    |
//| sind ausschliesslich ABGESCHLOSSENE H1-Bars (Shift >= 1).        |
//+------------------------------------------------------------------+
bool CheckDonchianBreakoutSignal(SDonchianState &state, const string symbol,
                                  const int donchianPeriod, const double adxMinLevel,
                                  const double atrMult, const double minSLDistancePips,
                                  const double rrRatio, SSignal &outSignal)
  {
   outSignal.direction = SIGNAL_NONE;

   datetime today = DonchianDayStart(TimeCurrent());
   if(state.lastTradeDay == today)
      return false; // Frequenzbegrenzung: max. 1 Trade/Tag fuer diese Strategie+Symbol

   double adxValue;
   if(!GetIndicatorValue(state.handleADX, 0, 1, adxValue))
      return false;
   if(adxValue < adxMinLevel)
      return false; // kein ausreichender Trend -> Breakout wird bewusst NICHT gehandelt

   double atrValue;
   if(!GetIndicatorValue(state.handleATR, 0, 1, atrValue) || atrValue <= 0.0)
      return false;

   // start=2, NICHT 1: der Donchian-Kanal muss die letzte abgeschlossene Bar
   // (Shift 1, = lastClose) ausschliessen. Mit start=1 waere lastClose immer
   // Teil des eigenen Kanals -> lastClose > donchianHigh koennte nie eintreten.
   int highestShift = iHighest(symbol, PERIOD_H1, MODE_HIGH, donchianPeriod, 2);
   int lowestShift   = iLowest(symbol, PERIOD_H1, MODE_LOW, donchianPeriod, 2);
   if(highestShift < 0 || lowestShift < 0)
      return false;

   double donchianHigh = iHigh(symbol, PERIOD_H1, highestShift);
   double donchianLow  = iLow(symbol, PERIOD_H1, lowestShift);
   double lastClose    = iClose(symbol, PERIOD_H1, 1); // letzte abgeschlossene Bar

   if(lastClose > donchianHigh)
     {
      outSignal.direction  = SIGNAL_BUY;
      outSignal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);

      double slDistanceBand = outSignal.entryPrice - donchianLow;
      double slDistanceATR  = atrMult * atrValue;
      double slDistance     = MathMax(slDistanceBand, slDistanceATR);

      outSignal.slPrice = outSignal.entryPrice - slDistance;
      EnforceMinSLDistance(symbol, SIGNAL_BUY, outSignal.entryPrice, outSignal.slPrice, minSLDistancePips);

      double finalSLDistance = outSignal.entryPrice - outSignal.slPrice;
      outSignal.tpPrice = outSignal.entryPrice + finalSLDistance * rrRatio;
      outSignal.reason  = "Donchian BUY: Close>DonchianHigh, ADX-Trendfilter erfuellt";
      return true;
     }

   if(lastClose < donchianLow)
     {
      outSignal.direction  = SIGNAL_SELL;
      outSignal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

      double slDistanceBand = donchianHigh - outSignal.entryPrice;
      double slDistanceATR  = atrMult * atrValue;
      double slDistance     = MathMax(slDistanceBand, slDistanceATR);

      outSignal.slPrice = outSignal.entryPrice + slDistance;
      EnforceMinSLDistance(symbol, SIGNAL_SELL, outSignal.entryPrice, outSignal.slPrice, minSLDistancePips);

      double finalSLDistance = outSignal.slPrice - outSignal.entryPrice;
      outSignal.tpPrice = outSignal.entryPrice - finalSLDistance * rrRatio;
      outSignal.reason  = "Donchian SELL: Close<DonchianLow, ADX-Trendfilter erfuellt";
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Muss nach erfolgreicher Order-Eroeffnung aufgerufen werden, um   |
//| die Tages-Frequenzsperre zu aktivieren.                           |
//+------------------------------------------------------------------+
void MarkDonchianTraded(SDonchianState &state)
  {
   state.lastTradeDay = DonchianDayStart(TimeCurrent());
  }

//+------------------------------------------------------------------+
