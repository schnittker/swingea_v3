//+------------------------------------------------------------------+
//|                                           SignalOverlapTrend.mqh |
//|   Tier-1-Strategie: Overlap-Trendfolge mit Pullback-Einstieg.   |
//|   Bias: H4 EMA-Kreuz + Close-Position.                           |
//|   Zone: M15 EMA-Band (EMA-Fast/Slow auf M15).                   |
//|   Trigger: M15-Umkehrkerze in der Zone (Spiegel zu DipBuy).     |
//|   Session-beschraenkt: Einstieg NUR im Overlap-Fenster          |
//|   (12:00-16:00 GMT, strategies.md Tier 1.1 + Teil D).           |
//|   Kein Zeit-Exit (ea.md 4.11, knowledge.md 4 "Walking the Band")|
//|                                                                   |
//|   Struktur bewusst als Spiegel von SignalDipBuy, damit beide    |
//|   Module vergleichbar sind und denselben TradeManager/           |
//|   FilterStack verwenden koennen.                                 |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALOVERLAP_MQH__
#define __SWINGGOLD_SIGNALOVERLAP_MQH__

#include "SignalModuleBase.mqh"

class CSignalOverlapTrend : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   int               m_swingLookback;
   int               m_swingSearchDepth;
   double            m_atrStopMult;
   int               m_zoneExpiryBars;   // M15-Bars bis Setup-Verfall
   int               m_expiryCounter;

   double            m_zoneLow;
   double            m_zoneHigh;
   double            m_stopSwingPrice;

   //+------------------------------------------------------------------+
   //| H4-Bias: EMA-Kreuz + Close-Position.                            |
   //| Long:  emaFastH4 > emaSlowH4 UND Close(H4,1) > emaFastH4.     |
   //| Short: emaFastH4 < emaSlowH4 UND Close(H4,1) < emaFastH4.     |
   //+------------------------------------------------------------------+
   bool              CheckBias(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      if(!md.IsH4Valid())
         return false;

      double emaFast = md.GetEmaFastH4();
      double emaSlow = md.GetEmaSlowH4();

      double closeH4;
      double openH4;
      if(!md.GetBar(PERIOD_H4, 1, openH4, closeH4))
         return false;

      if(dir == SIGNAL_LONG)
         return (emaFast > emaSlow && closeH4 > emaFast);
      else
         return (emaFast < emaSlow && closeH4 < emaFast);
     }

   //+------------------------------------------------------------------+
   //| Zone auf M15: [min(emaFast, emaSlow), max(emaFast, emaSlow)].  |
   //| Setup gilt als aktiv, wenn der Preis die Zone innerhalb der     |
   //| letzten m_zoneExpiryBars M15-Bars beruehrt hat.                |
   //| Hier: Zone einmalig beim Armen berechnen; Verfall ueber Zaehler.|
   //+------------------------------------------------------------------+
   bool              CheckBiasAndSetup(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      if(!CheckBias(md, dir))
         return false;

      if(!md.IsM15Valid())
         return false;

      double emaFastM15 = md.GetEmaFastM15();
      double emaSlowM15 = md.GetEmaSlowM15();

      m_zoneLow  = MathMin(emaFastM15, emaSlowM15);
      m_zoneHigh = MathMax(emaFastM15, emaSlowM15);

      //--- Stop-Referenz: letztes bestaetigtes Swing-Extremum auf M15
      int    swingShift;
      double swingPrice;
      if(dir == SIGNAL_LONG)
        {
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, m_swingSearchDepth,
                                      PERIOD_M15, swingShift, swingPrice))
            return false;
         m_stopSwingPrice = swingPrice;
         //--- Ziel: letztes bestaetiges Swing-Hoch auf M15
         int    highShift;
         double highPrice;
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, m_swingSearchDepth,
                                       PERIOD_M15, highShift, highPrice))
            highPrice = 0.0; // Teilgewinn faellt auf reines Trailing zurueck
         m_targetPrice = highPrice;
        }
      else
        {
         if(!md.FindConfirmedSwingHigh(m_swingLookback + 1, m_swingSearchDepth,
                                       PERIOD_M15, swingShift, swingPrice))
            return false;
         m_stopSwingPrice = swingPrice;
         int    lowShift;
         double lowPrice;
         if(!md.FindConfirmedSwingLow(m_swingLookback + 1, m_swingSearchDepth,
                                      PERIOD_M15, lowShift, lowPrice))
            lowPrice = 0.0;
         m_targetPrice = lowPrice;
        }

      return true;
     }

   bool              PriceInZone(const double price) const
     {
      return (price >= m_zoneLow && price <= m_zoneHigh);
     }

   //+------------------------------------------------------------------+
   //| M15-Trigger: Umkehrkerze in der Zone.                           |
   //| Spiegel zu SignalDipBuy::CheckTriggerCandle (auf M15-Bars).     |
   //+------------------------------------------------------------------+
   bool              CheckTriggerCandle(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                        double &outRefPrice)
     {
      double open1, close1, open2, close2;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1))
         return false;
      if(!md.GetBar(PERIOD_M15, 2, open2, close2))
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
      m_expiryCounter = m_zoneExpiryBars;
      PrintFormat("SignalOverlapTrend: ST_ARMED dir=%d zone=[%.5f,%.5f] stopSwing=%.5f target=%.5f expiry=%d",
                  dir, m_zoneLow, m_zoneHigh, m_stopSwingPrice, m_targetPrice, m_expiryCounter);
     }

   void              BuildProposal(CMarketData &md, const double refPrice,
                                   SignalProposal &outProposal)
     {
      double atr = md.GetAtrM15();

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
         outProposal.reason    = "Overlap Long: M15-Umkehrkerze in EMA-Zone";
        }
      else
        {
         outProposal.stopPrice = MathMax(m_stopSwingPrice, refPrice + m_atrStopMult * atr);
         outProposal.reason    = "Overlap Short: M15-Umkehrkerze in EMA-Zone";
        }
     }

public:
                     CSignalOverlapTrend(void):
                        CSignalModuleBase(),
                        m_allowShort(false), m_swingLookback(3), m_swingSearchDepth(250),
                        m_atrStopMult(1.75), m_zoneExpiryBars(8), m_expiryCounter(0),
                        m_zoneLow(0.0), m_zoneHigh(0.0), m_stopSwingPrice(0.0) {}

   void              Configure(const bool allowShort, const int swingLookback,
                               const double atrStopMult, const int zoneExpiryBars,
                               const int magic)
     {
      m_allowShort     = allowShort;
      m_swingLookback  = swingLookback;
      m_atrStopMult    = atrStopMult;
      m_zoneExpiryBars = zoneExpiryBars;
      m_magic          = magic;
     }

   //--- Pure-virtual-Implementierungen (const-Qualifier VERBATIM, Hazard H1)
   virtual string           Name(void)              const { return "SignalOverlapTrend"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;           }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;           }
   virtual bool             SessionRestricted(void) const { return true;                 }

   //+------------------------------------------------------------------+
   //| Vom Haupt-EA einmal pro neuer M15-Bar aufgerufen, solange KEINE |
   //| eigene Position offen ist.                                       |
   //| Session-Beschraenkung wird vom FilterStack geprueft (nicht hier)|
   //| — dieses Modul signalisiert nur, ob Session-Pruefen noetig ist. |
   //+------------------------------------------------------------------+
   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED || m_state == ST_WAIT_TRIGGER)
        {
         //--- Bias verloren? -> zurueck zu IDLE
         if(!CheckBias(md, m_dir))
           {
            ResetToIdle("Bias verloren");
            return false;
           }

         //--- Verfall pro M15-Bar dekrementieren (kein D1-Takt hier)
         m_expiryCounter--;
         if(m_expiryCounter <= 0)
           {
            ResetToIdle("Setup abgelaufen (InpOvZoneExpiryBars)");
            return false;
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

      return false;
     }
  };

#endif // __SWINGGOLD_SIGNALOVERLAP_MQH__
