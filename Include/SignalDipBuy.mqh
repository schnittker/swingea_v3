//+------------------------------------------------------------------+
//|                                                 SignalDipBuy.mqh |
//|   Phase-1-Strategie: struktureller Dip-Buy (D1-Bias/Setup,       |
//|   H4-Trigger). Long-Bias = Close>EMA(Slow) + hoehere Tiefs,    |
//|   gespiegelt fuer Short (nur wenn m_allowShort). Setup-Zone ist |
//|   die Vereinigung aus EMA(Mid)-Beruehrung und Fib 0.382-0.618  |
//|   des letzten Impulses (ea.md 4.6). Kein RSI-/Zeit-Exit.       |
//|                                                                   |
//|   Erbt von CSignalModuleBase (gemeinsame State Machine,         |
//|   Notify*/Get*/Sync). Bias/Setup/Trigger-Ruempfe und            |
//|   BuildProposal bleiben unveraendert (Referenz fuer             |
//|   Verhaltensgleichheit, Plan-Check 1-4).                        |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALDIPBUY_MQH__
#define __SWINGGOLD_SIGNALDIPBUY_MQH__

#include "SignalModuleBase.mqh"

class CSignalDipBuy : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   int               m_swingLookback;
   int               m_swingSearchDepth;
   double            m_atrStopMult;
   int               m_armedExpiryBars;
   int               m_expiryCounter;

   double            m_zoneLow;
   double            m_zoneHigh;
   double            m_stopSwingPrice;

   //+------------------------------------------------------------------+
   //| D1-Bias: Trend (Close vs. EMA-Slow) + Struktur (hoehere Tiefs  |
   //| fuer Long, tiefere Hochs fuer Short, fraktalbasiert).           |
   //+------------------------------------------------------------------+
   bool              CheckBias(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      double close1;
      if(!md.GetCloseD1(1, close1))
         return false;

      double emaSlow = md.GetEmaSlowD1();

      if(dir == SIGNAL_LONG)
        {
         if(close1 <= emaSlow)
            return false;

         int    shift1, shift0;
         double price1, price0;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, m_swingSearchDepth, shift1, price1))
            return false;
         if(!md.FindConfirmedSwingLow(shift1 + 1, m_swingSearchDepth, shift0, price0))
            return false;

         return (price1 > price0); // hoehere Tiefs
        }
      else // SIGNAL_SHORT
        {
         if(close1 >= emaSlow)
            return false;

         int    shift1, shift0;
         double price1, price0;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, m_swingSearchDepth, shift1, price1))
            return false;
         if(!md.FindConfirmedSwingHigh(shift1 + 1, m_swingSearchDepth, shift0, price0))
            return false;

         return (price1 < price0); // tiefere Hochs
        }
     }

   //+------------------------------------------------------------------+
   //| D1-Setup: Impuls + Zone (Fib 0.382-0.618, erweitert um EMA-Mid)|
   //+------------------------------------------------------------------+
   bool              CheckBiasAndSetup(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      if(!CheckBias(md, dir))
         return false;

      double emaMid = md.GetEmaMidD1();

      if(dir == SIGNAL_LONG)
        {
         int    lowShift;
         double lowPrice;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, m_swingSearchDepth, lowShift, lowPrice))
            return false;

         if(lowShift - 1 < m_swingLookback + 1)
            return false;

         int    highShift;
         double highPrice;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, lowShift - 1, highShift, highPrice))
            return false;

         double impulseRange = highPrice - lowPrice;
         if(impulseRange <= 0.0)
            return false;

         double fibLow  = highPrice - 0.618 * impulseRange;
         double fibHigh = highPrice - 0.382 * impulseRange;

         double zoneLow  = fibLow;
         double zoneHigh = fibHigh;
         if(emaMid > lowPrice && emaMid < highPrice)
           {
            zoneLow  = MathMin(zoneLow, emaMid);
            zoneHigh = MathMax(zoneHigh, emaMid);
           }

         m_zoneLow        = zoneLow;
         m_zoneHigh       = zoneHigh;
         m_stopSwingPrice = lowPrice;
         m_targetPrice    = highPrice;
         return true;
        }
      else // SIGNAL_SHORT
        {
         int    highShift;
         double highPrice;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, m_swingSearchDepth, highShift, highPrice))
            return false;

         if(highShift - 1 < m_swingLookback + 1)
            return false;

         int    lowShift;
         double lowPrice;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, highShift - 1, lowShift, lowPrice))
            return false;

         double impulseRange = highPrice - lowPrice;
         if(impulseRange <= 0.0)
            return false;

         double fibLow  = lowPrice + 0.382 * impulseRange;
         double fibHigh = lowPrice + 0.618 * impulseRange;

         double zoneLow  = fibLow;
         double zoneHigh = fibHigh;
         if(emaMid > lowPrice && emaMid < highPrice)
           {
            zoneLow  = MathMin(zoneLow, emaMid);
            zoneHigh = MathMax(zoneHigh, emaMid);
           }

         m_zoneLow        = zoneLow;
         m_zoneHigh       = zoneHigh;
         m_stopSwingPrice = highPrice;
         m_targetPrice    = lowPrice;
         return true;
        }
     }

   bool              PriceInZone(const double price) const
     {
      return (price >= m_zoneLow && price <= m_zoneHigh);
     }

   //+------------------------------------------------------------------+
   //| H4-Trigger: Umkehrkerze in der Zone.                            |
   //+------------------------------------------------------------------+
   bool              CheckTriggerCandle(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                        double &outRefPrice)
     {
      double open1, close1, open2, close2;
      if(!md.GetH4Bar(1, open1, close1))
         return false;
      if(!md.GetH4Bar(2, open2, close2))
         return false;

      double mid2 = (open2 + close2) / 2.0;
      outRefPrice = close1;

      if(dir == SIGNAL_LONG)
         return (close1 > open1 && close1 > mid2);
      else
         return (close1 < open1 && close1 < mid2);
     }

   void              Arm(const ENUM_SIGNAL_DIR dir)
     {
      m_dir           = dir;
      m_state         = ST_ARMED;
      m_expiryCounter = m_armedExpiryBars;
      PrintFormat("SignalDipBuy: ST_ARMED dir=%d zone=[%.5f,%.5f] stopSwing=%.5f target=%.5f expiry=%d",
                  dir, m_zoneLow, m_zoneHigh, m_stopSwingPrice, m_targetPrice, m_expiryCounter);
     }

   void              BuildProposal(CMarketData &md, const double refPrice,
                                   SignalProposal &outProposal)
     {
      double atr = md.GetAtrD1();

      outProposal.Reset();
      outProposal.valid       = true;
      outProposal.dir         = m_dir;
      outProposal.entryPrice  = 0.0; // Market
      outProposal.atrAtSignal = atr;
      outProposal.magic       = m_magic;
      outProposal.targetPrice = m_targetPrice;

      if(m_dir == SIGNAL_LONG)
        {
         outProposal.stopPrice = MathMin(m_stopSwingPrice, refPrice - m_atrStopMult * atr);
         outProposal.reason    = "DipBuy Long: Umkehrkerze in Zone";
        }
      else
        {
         outProposal.stopPrice = MathMax(m_stopSwingPrice, refPrice + m_atrStopMult * atr);
         outProposal.reason    = "DipBuy Short: Umkehrkerze in Zone";
        }
     }

public:
                     CSignalDipBuy(void):
                        CSignalModuleBase(),
                        m_allowShort(false), m_swingLookback(5), m_swingSearchDepth(250),
                        m_atrStopMult(2.0), m_armedExpiryBars(10), m_expiryCounter(0),
                        m_zoneLow(0.0), m_zoneHigh(0.0), m_stopSwingPrice(0.0) {}

   void              Configure(const bool allowShort, const int swingLookback,
                               const double atrStopMult, const int armedExpiryBars,
                               const int magic)
     {
      m_allowShort      = allowShort;
      m_swingLookback   = swingLookback;
      m_atrStopMult     = atrStopMult;
      m_armedExpiryBars = armedExpiryBars;
      m_magic           = magic;
     }

   //--- Pure-virtual-Implementierungen (const-Qualifier VERBATIM, Hazard H1)
   virtual string           Name(void)              const { return "SignalDipBuy"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_H4;      }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_D1;      }
   virtual bool             SessionRestricted(void) const { return false;          }

   //+------------------------------------------------------------------+
   //| Vom Haupt-EA einmal pro neuer H4-Bar aufgerufen, solange KEINE  |
   //| eigene Position offen ist.                                       |
   //+------------------------------------------------------------------+
   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED || m_state == ST_WAIT_TRIGGER)
        {
         if(!CheckBias(md, m_dir))
           {
            ResetToIdle("Bias verloren");
            return false;
           }

         double close1;
         if(md.GetCloseD1(1, close1))
           {
            bool zoneInvalid = (m_dir == SIGNAL_LONG) ? (close1 < m_stopSwingPrice)
                                                       : (close1 > m_stopSwingPrice);
            if(zoneInvalid)
              {
               ResetToIdle("Zone ungueltig - Swing-Extremum verletzt");
               return false;
              }
           }

         //--- Verfall nur bei echtem D1-Bar-Wechsel (via Latch, deterministisch)
         if(md.IsNewD1Bar())
           {
            m_expiryCounter--;
            if(m_expiryCounter <= 0)
              {
               ResetToIdle("Setup abgelaufen (InpArmedExpiryBars)");
               return false;
              }
           }

         double refPrice;
         bool   triggerMatch = CheckTriggerCandle(md, m_dir, refPrice);

         if(PriceInZone(refPrice))
           {
            if(m_state == ST_ARMED)
               m_state = ST_WAIT_TRIGGER;

            if(triggerMatch)
              {
               BuildProposal(md, refPrice, outProposal);
               m_state = ST_PENDING;
               return true;
              }
           }

         return false;
        }

      if(m_state == ST_IDLE)
        {
         if(CheckBiasAndSetup(md, SIGNAL_LONG))
            Arm(SIGNAL_LONG);
         else if(m_allowShort && CheckBiasAndSetup(md, SIGNAL_SHORT))
            Arm(SIGNAL_SHORT);

         return false;
        }

      return false; // ST_PENDING/ST_IN_POSITION/ST_BLOCKED: vom Aufrufer verwaltet
     }
  };

#endif // __SWINGGOLD_SIGNALDIPBUY_MQH__
