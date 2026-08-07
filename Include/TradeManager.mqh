//+------------------------------------------------------------------+
//|                                                  TradeManager.mqh |
//|   Exit-Logik fuer eine offene Dip-Buy-Position: Teilgewinn am    |
//|   alten Swing-Hoch/-Tief, danach Breakeven-Stop, ATR-Trailing    |
//|   ausschliesslich verengend. Bewusst kein Zeit- oder RSI-Exit    |
//|   (ea.md 4.6: "Walking the Band" = Fortsetzung, kein Exit).      |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_TRADEMANAGER_MQH__
#define __SWINGGOLD_TRADEMANAGER_MQH__

#include "Types.mqh"
#include "MarketData.mqh"
#include "PositionTracker.mqh"
#include "TradeExecution.mqh"

class CTradeManager
  {
private:
   string            m_symbol;
   double            m_partialPct;
   double            m_trailAtrMult;
   double            m_volumeMin;
   double            m_volumeStep;
   int               m_stopsLevelPoints;
   ENUM_TIMEFRAMES   m_atrTf;   // ATR vom Entry-TF (strategies.md Teil D "Fehler 1")

   //--- Teilschluss-Volumen auf VOLUME_STEP normiert. Gibt 0.0 zurueck,
   //--- wenn Teil- oder Restvolumen unter VOLUME_MIN faellt (dann lieber
   //--- kein Teilschluss als eine ungueltige Order).
   double            NormalizePartialVolume(const double totalVolume)
     {
      double raw = totalVolume * (m_partialPct / 100.0);
      if(m_volumeStep > 0.0)
         raw = MathFloor(raw / m_volumeStep + 1e-8) * m_volumeStep;

      if(raw < m_volumeMin)
         return 0.0;

      double remainder = totalVolume - raw;
      if(remainder > 0.0 && remainder < m_volumeMin)
         return 0.0;

      return NormalizeDouble(raw, 2);
     }

   //--- Klemmt einen SL-Preis auf die Mindestdistanz (StopsLevel).
   double            ClampMinDistance(const ENUM_SIGNAL_DIR dir, const double refPrice, double slPrice)
     {
      double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits  = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double minDist = (double)m_stopsLevelPoints * point;

      if(MathAbs(refPrice - slPrice) < minDist)
         slPrice = (dir == SIGNAL_LONG) ? (refPrice - minDist) : (refPrice + minDist);

      return NormalizeDouble(slPrice, digits);
     }

public:
                     CTradeManager(void):
                        m_symbol(""), m_partialPct(50.0), m_trailAtrMult(2.5),
                        m_volumeMin(0.01), m_volumeStep(0.01), m_stopsLevelPoints(0),
                        m_atrTf(PERIOD_D1) {}

   //--- atrTf: ATR-Timeframe passend zum Entry-TF des Moduls
   //--- (strategies.md Teil D "Fehler 1": ATR muss vom Entry-TF kommen)
   void              Configure(const string symbol, const double partialPct, const double trailAtrMult,
                               const double volumeMin, const double volumeStep,
                               const int stopsLevelPoints,
                               const ENUM_TIMEFRAMES atrTf = PERIOD_D1)
     {
      m_symbol           = symbol;
      m_partialPct       = partialPct;
      m_trailAtrMult     = trailAtrMult;
      m_volumeMin        = volumeMin;
      m_volumeStep       = volumeStep;
      m_stopsLevelPoints = stopsLevelPoints;
      m_atrTf            = atrTf;
     }

   //+------------------------------------------------------------------+
   //| Verwaltet eine offene Position: Teilgewinn, Breakeven, Trailing. |
   //| targetPrice = altes Swing-Hoch/-Tief aus SignalDipBuy (0 = kein  |
   //| Teilgewinn-Ziel definiert).                                      |
   //+------------------------------------------------------------------+
   void              Manage(const ulong ticket, const ENUM_SIGNAL_DIR dir, const double targetPrice,
                            CMarketData &md, CPositionTracker &tracker, CTradeExecution &exec)
     {
      double volume, openPrice, currentSL, currentTP;
      if(!tracker.GetVolume(ticket, volume))     return;
      if(!tracker.GetOpenPrice(ticket, openPrice)) return;
      if(!tracker.GetSL(ticket, currentSL))       return;
      if(!tracker.GetTP(ticket, currentTP))       return;

      double atr          = md.GetAtr(m_atrTf); // ATR vom konfigurierten Entry-TF
      double currentPrice = (dir == SIGNAL_LONG) ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                                  : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      bool partialDone = tracker.IsPartialDone(ticket);

      //--- 1) Teilgewinn bei Erreichen des alten Swing-Hoch/-Tief.
      if(!partialDone && targetPrice > 0.0)
        {
         bool targetHit = (dir == SIGNAL_LONG) ? (currentPrice >= targetPrice) : (currentPrice <= targetPrice);
         if(targetHit)
           {
            double partialVolume = NormalizePartialVolume(volume);
            if(partialVolume > 0.0 && exec.ClosePartial(ticket, partialVolume))
              {
               tracker.SetPartialDone(ticket, true);
               partialDone = true;
              }
            else
              {
               // Nicht sinnvoll normierbar (z.B. Restvolumen zu klein) - nicht jeden Bar neu versuchen.
               tracker.SetPartialDone(ticket, true);
               partialDone = true;
              }
           }
        }

      //--- 2) Breakeven-Stop nach Teilgewinn.
      double desiredSL = currentSL;
      if(partialDone)
        {
         if(dir == SIGNAL_LONG)
           {
            if(currentSL < openPrice) desiredSL = openPrice;
           }
         else
           {
            if(currentSL > openPrice) desiredSL = openPrice;
           }
        }

      //--- 3) ATR-Trailing, ausschliesslich verengend.
      if(atr > 0.0)
        {
         double trailDist = m_trailAtrMult * atr;
         if(dir == SIGNAL_LONG)
           {
            double trailSL = currentPrice - trailDist;
            if(trailSL > desiredSL) desiredSL = trailSL;
           }
         else
           {
            double trailSL = currentPrice + trailDist;
            if(trailSL < desiredSL) desiredSL = trailSL;
           }
        }

      bool improved = (dir == SIGNAL_LONG) ? (desiredSL > currentSL) : (desiredSL < currentSL);
      if(!improved)
         return;

      desiredSL = ClampMinDistance(dir, currentPrice, desiredSL);

      bool stillImproved = (dir == SIGNAL_LONG) ? (desiredSL > currentSL) : (desiredSL < currentSL);
      if(stillImproved)
         exec.ModifyPosition(ticket, desiredSL, currentTP);
     }
  };

#endif // __SWINGGOLD_TRADEMANAGER_MQH__
