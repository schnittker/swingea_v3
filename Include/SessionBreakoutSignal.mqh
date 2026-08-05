//+------------------------------------------------------------------+
//| SessionBreakoutSignal.mqh                                        |
//| Strategie 1: Session-Open-Range-Breakout (M15).                  |
//| Bildet eine Range waehrend eines konfigurierbaren Zeitfensters   |
//| (z.B. Asia-Session), und tradet den Ausbruch NUR auf Bar-Close   |
//| (kein Intra-Bar-Trigger, vermeidet False-Breakouts durch          |
//| kurzfristige Spikes). SL = Gegenrange minus Puffer, mit Floor    |
//| auf MinSLDistancePips (>= 15x Friktion). TP per festem RR.       |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "SymbolUtils.mqh"
#include "RiskManager.mqh"

//+------------------------------------------------------------------+
//| Laufender Zustand pro Symbol: berechnete Tagesrange + Sperre    |
//| gegen mehrfaches Traden am selben Tag (Frequenz-Budget).         |
//+------------------------------------------------------------------+
struct SSessionBreakoutState
  {
   datetime          rangeDay;      // Tag (Mitternacht), fuer den die Range gilt
   double            rangeHigh;
   double            rangeLow;
   bool              rangeValid;
   datetime          lastTradeDay;  // Tag der letzten Eroeffnung dieser Strategie
  };

//+------------------------------------------------------------------+
//| Mitternacht (Server-Zeit) des uebergebenen Zeitpunkts.           |
//+------------------------------------------------------------------+
datetime SessionBreakoutDayStart(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Berechnet einmal pro Tag High/Low der M15-Bars innerhalb des     |
//| Range-Fensters [rangeStartMinuteOfDay, rangeEndMinuteOfDay). Tut |
//| nichts, wenn fuer heute schon eine gueltige Range vorliegt oder  |
//| das Range-Fenster noch nicht abgeschlossen ist.                  |
//+------------------------------------------------------------------+
void UpdateSessionRange(SSessionBreakoutState &state, const string symbol,
                         const int rangeStartMinuteOfDay, const int rangeEndMinuteOfDay)
  {
   datetime now   = TimeCurrent();
   datetime today = SessionBreakoutDayStart(now);

   if(state.rangeDay == today && state.rangeValid)
      return;

   MqlDateTime dtNow;
   TimeToStruct(now, dtNow);
   int nowMinutes = dtNow.hour * 60 + dtNow.min;
   if(nowMinutes < rangeEndMinuteOfDay)
      return; // Range-Fenster laeuft noch, noch nichts zu berechnen

   datetime rangeStartTime = today + rangeStartMinuteOfDay * 60;
   datetime rangeEndTime   = today + rangeEndMinuteOfDay * 60;

   double high = -DBL_MAX;
   double low  = DBL_MAX;
   bool   found = false;

   int bars = Bars(symbol, PERIOD_M15);
   for(int i = 0; i < bars; i++)
     {
      datetime barTime = iTime(symbol, PERIOD_M15, i);
      if(barTime < rangeStartTime)
         break; // Bars sind absteigend sortiert (0 = aktuellste) - aelter als Range-Start beendet Suche

      if(barTime >= rangeStartTime && barTime < rangeEndTime)
        {
         double h = iHigh(symbol, PERIOD_M15, i);
         double l = iLow(symbol, PERIOD_M15, i);
         if(h > high)
            high = h;
         if(l < low)
            low = l;
         found = true;
        }
     }

   if(found)
     {
      state.rangeHigh  = high;
      state.rangeLow   = low;
      state.rangeDay   = today;
      state.rangeValid = true;
     }
  }

//+------------------------------------------------------------------+
//| Prueft, ob die zuletzt ABGESCHLOSSENE M15-Bar ausserhalb der     |
//| Tagesrange (+/- Puffer) geschlossen hat. Liefert bei Erfolg ein  |
//| vollstaendiges SSignal (inkl. bereits Min-SL-korrigiertem SL).   |
//+------------------------------------------------------------------+
bool CheckSessionBreakoutSignal(SSessionBreakoutState &state, const string symbol,
                                 const int rangeStartMinuteOfDay, const int rangeEndMinuteOfDay,
                                 const double bufferPips, const double minSLDistancePips,
                                 const double rrRatio, SSignal &outSignal)
  {
   outSignal.direction = SIGNAL_NONE;

   UpdateSessionRange(state, symbol, rangeStartMinuteOfDay, rangeEndMinuteOfDay);
   if(!state.rangeValid)
      return false;

   datetime today = SessionBreakoutDayStart(TimeCurrent());
   if(state.lastTradeDay == today)
      return false; // Frequenzbegrenzung: max. 1 Trade/Tag fuer diese Strategie+Symbol

   datetime rangeEndTime = today + rangeEndMinuteOfDay * 60;
   datetime lastBarTime  = iTime(symbol, PERIOD_M15, 1); // letzte ABGESCHLOSSENE Bar (Index 0 = laufende Bar)
   if(lastBarTime < rangeEndTime)
      return false; // noch keine Bar nach Range-Ende abgeschlossen

   double lastClose   = iClose(symbol, PERIOD_M15, 1);
   double bufferPrice = PipsToPriceDistance(symbol, bufferPips);

   if(lastClose > state.rangeHigh + bufferPrice)
     {
      outSignal.direction  = SIGNAL_BUY;
      outSignal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      outSignal.slPrice    = state.rangeLow - bufferPrice;
      EnforceMinSLDistance(symbol, SIGNAL_BUY, outSignal.entryPrice, outSignal.slPrice, minSLDistancePips);
      double slDistance = outSignal.entryPrice - outSignal.slPrice;
      outSignal.tpPrice = outSignal.entryPrice + slDistance * rrRatio;
      outSignal.reason  = "SessionBreakout BUY: Bar-Close > RangeHigh+Puffer";
      return true;
     }

   if(lastClose < state.rangeLow - bufferPrice)
     {
      outSignal.direction  = SIGNAL_SELL;
      outSignal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      outSignal.slPrice    = state.rangeHigh + bufferPrice;
      EnforceMinSLDistance(symbol, SIGNAL_SELL, outSignal.entryPrice, outSignal.slPrice, minSLDistancePips);
      double slDistance = outSignal.slPrice - outSignal.entryPrice;
      outSignal.tpPrice = outSignal.entryPrice - slDistance * rrRatio;
      outSignal.reason  = "SessionBreakout SELL: Bar-Close < RangeLow-Puffer";
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Muss nach erfolgreicher Order-Eroeffnung aufgerufen werden, um   |
//| die Tages-Frequenzsperre zu aktivieren.                           |
//+------------------------------------------------------------------+
void MarkSessionBreakoutTraded(SSessionBreakoutState &state)
  {
   state.lastTradeDay = SessionBreakoutDayStart(TimeCurrent());
  }

//+------------------------------------------------------------------+
