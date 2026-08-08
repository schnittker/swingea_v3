//+------------------------------------------------------------------+
//|                                        SignalLiquiditySweep.mqh  |
//|   Tier-2.1-Strategie: Liquidity-Sweep-Reclaim.                  |
//|   Level: D1 High[1] und D1 Low[1] (Vortagshoch/-tief).         |
//|                                                                   |
//|   Zwei-Phasen-Logik:                                             |
//|   Phase 1 — Sweep erkannt (ST_ARMED):                           |
//|     Long:  M15[1].Low  < D1Low[1]   (Sweep unter Vortagstief)  |
//|     Short: M15[1].High > D1High[1]  (Sweep ueber Vortagshoch)  |
//|   Phase 2 — Reclaim in den naechsten m_reclaimBars M15-Bars:   |
//|     Long:  M15[1].Close > D1Low[1]                              |
//|     Short: M15[1].Close < D1High[1]                             |
//|                                                                   |
//|   Stop: SweepExtrem +/- atrStopMult * ATR(M15)                  |
//|   Ziel: gegenuberliegende Range-Seite (D1High bzw. D1Low).      |
//|   SessionRestricted: false.                                      |
//|   Verfall: nach m_reclaimBars ohne Reclaim -> zurueck zu IDLE.  |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__
#define __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__

#include "SignalModuleBase.mqh"

class CSignalLiquiditySweep : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   double            m_atrStopMult;
   int               m_reclaimBars;    // Max. M15-Bars bis Reclaim (nach Sweep)

   double            m_d1High;         // D1 High[1] zum Zeitpunkt des Sweeps
   double            m_d1Low;          // D1 Low[1]  zum Zeitpunkt des Sweeps
   double            m_sweepExtreme;   // Tiefster Low (Long) / Hoechstes High (Short)
   int               m_reclaimCounter; // Zaehlt M15-Bars seit Sweep

   //+------------------------------------------------------------------+
   //| D1-Level aktualisieren. Direkter CopyHigh/CopyLow-Aufruf —     |
   //| unabhaengig vom EnsureD1-Cache, immer aktuell.                  |
   //+------------------------------------------------------------------+
   bool              UpdateLevels(CMarketData &md)
     {
      if(!md.GetHighD1(1, m_d1High)) return false;
      if(!md.GetLowD1(1,  m_d1Low))  return false;
      return (m_d1High > 0.0 && m_d1Low > 0.0 && m_d1High > m_d1Low);
     }

   //+------------------------------------------------------------------+
   //| Phase 1: Prueft ob M15[1] einen Sweep (Durchstich) darstellt.  |
   //| Long:  Low[1]  < d1Low  (Stopjagd unter Vortagstief)           |
   //| Short: High[1] > d1High (Stopjagd ueber Vortagshoch)           |
   //+------------------------------------------------------------------+
   bool              CheckSweep(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                double &outSweepExtreme)
     {
      double low1, high1;
      if(!md.GetLow(PERIOD_M15,  1, low1))  return false;
      if(!md.GetHigh(PERIOD_M15, 1, high1)) return false;

      if(dir == SIGNAL_LONG  && low1  < m_d1Low)
        { outSweepExtreme = low1;  return true; }
      if(dir == SIGNAL_SHORT && high1 > m_d1High)
        { outSweepExtreme = high1; return true; }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Phase 2: Prueft ob M15[1] den Reclaim (Close zurueck ueber     |
   //| das Level) liefert. Kann in derselben Bar wie der Sweep oder   |
   //| in einer der folgenden m_reclaimBars Bars eintreten.           |
   //+------------------------------------------------------------------+
   bool              CheckReclaim(CMarketData &md, const ENUM_SIGNAL_DIR dir)
     {
      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      if(dir == SIGNAL_LONG)  return (close1 > m_d1Low);
      if(dir == SIGNAL_SHORT) return (close1 < m_d1High);
      return false;
     }

   //+------------------------------------------------------------------+
   //| Baut das SignalProposal.                                        |
   //| Stop: SweepExtrem +/- atrStopMult * ATR(M15)                    |
   //| Ziel: gegenuberliegende Range-Seite.                             |
   //+------------------------------------------------------------------+
   void              BuildProposal(CMarketData &md, SignalProposal &outProposal)
     {
      double atr = md.GetAtrM15();

      outProposal.Reset();
      outProposal.valid       = true;
      outProposal.dir         = m_dir;
      outProposal.entryPrice  = 0.0; // Market
      outProposal.atrAtSignal = atr;
      outProposal.magic       = m_magic;

      if(m_dir == SIGNAL_LONG)
        {
         outProposal.stopPrice   = m_sweepExtreme - m_atrStopMult * atr;
         outProposal.targetPrice = m_d1High;
         outProposal.reason      = "Sweep Long: Reclaim ueber D1Low";
        }
      else
        {
         outProposal.stopPrice   = m_sweepExtreme + m_atrStopMult * atr;
         outProposal.targetPrice = m_d1Low;
         outProposal.reason      = "Sweep Short: Reclaim unter D1High";
        }

      PrintFormat("SignalLiquiditySweep: ST_PENDING dir=%d sweepExtreme=%.5f stop=%.5f target=%.5f d1Low=%.5f d1High=%.5f reclaimBar=%d",
                  m_dir, m_sweepExtreme, outProposal.stopPrice, outProposal.targetPrice,
                  m_d1Low, m_d1High, m_reclaimCounter);
     }

   void              ArmSweep(const ENUM_SIGNAL_DIR dir, const double sweepExtreme)
     {
      m_dir            = dir;
      m_sweepExtreme   = sweepExtreme;
      m_reclaimCounter = 0;
      m_state          = ST_ARMED;
      PrintFormat("SignalLiquiditySweep: ST_ARMED dir=%d sweepExtreme=%.5f d1Low=%.5f d1High=%.5f",
                  dir, sweepExtreme, m_d1Low, m_d1High);
     }

public:
                     CSignalLiquiditySweep(void):
                        CSignalModuleBase(),
                        m_allowShort(false),
                        m_atrStopMult(1.5),
                        m_reclaimBars(3),
                        m_d1High(0.0), m_d1Low(0.0),
                        m_sweepExtreme(0.0), m_reclaimCounter(0) {}

   void              Configure(const bool allowShort, const double atrStopMult,
                               const int reclaimBars, const int magic)
     {
      m_allowShort  = allowShort;
      m_atrStopMult = atrStopMult;
      m_reclaimBars = reclaimBars;
      m_magic       = magic;
     }

   //--- Pure-virtual-Implementierungen (const-Qualifier VERBATIM, Hazard H1)
   virtual string           Name(void)              const { return "SignalLiquiditySweep"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;             }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;             }
   virtual bool             SessionRestricted(void) const { return false;                  }

   //+------------------------------------------------------------------+
   //| Einmal pro neuer M15-Bar aufgerufen.                            |
   //|                                                                   |
   //| ST_IDLE:  Sweep suchen -> ST_ARMED                              |
   //| ST_ARMED: Reclaim pruefen -> ST_PENDING | Verfall -> ST_IDLE    |
   //+------------------------------------------------------------------+
   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED)
        {
         m_reclaimCounter++;

         //--- Verfall: zu viele Bars ohne Reclaim
         if(m_reclaimCounter > m_reclaimBars)
           {
            ResetToIdle("Reclaim-Verfall");
            return false;
           }

         //--- D1-Level koennte sich inzwischen geaendert haben (D1-Rollover
         //--- waehrend der Reclaim-Wartezeit) — Level neu einlesen
         if(!UpdateLevels(md))
           {
            ResetToIdle("Level-Lesefehler waehrend Reclaim-Warten");
            return false;
           }

         if(CheckReclaim(md, m_dir))
           {
            BuildProposal(md, outProposal);
            m_state = ST_PENDING;
            return true;
           }

         return false;
        }

      if(m_state == ST_IDLE)
        {
         if(!md.IsD1Valid())
            return false;

         if(!UpdateLevels(md))
            return false;

         double sweepExtreme = 0.0;

         if(CheckSweep(md, SIGNAL_LONG, sweepExtreme))
           {
            ArmSweep(SIGNAL_LONG, sweepExtreme);
            //--- Reclaim eventuell bereits in derselben Bar (Eins-Bar-Event)
            if(CheckReclaim(md, SIGNAL_LONG))
              {
               BuildProposal(md, outProposal);
               m_state = ST_PENDING;
               return true;
              }
            return false;
           }

         if(m_allowShort && CheckSweep(md, SIGNAL_SHORT, sweepExtreme))
           {
            ArmSweep(SIGNAL_SHORT, sweepExtreme);
            if(CheckReclaim(md, SIGNAL_SHORT))
              {
               BuildProposal(md, outProposal);
               m_state = ST_PENDING;
               return true;
              }
            return false;
           }
        }

      return false;
     }
  };

#endif // __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__
