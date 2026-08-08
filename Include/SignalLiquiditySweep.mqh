//+------------------------------------------------------------------+
//|                                        SignalLiquiditySweep.mqh  |
//|   Tier-2.1-Strategie: Liquidity-Sweep-Reclaim.                  |
//|   Level: D1 High[1] und D1 Low[1] (Vortagshoch/-tief).         |
//|   Sweep+Reclaim in einer M15-Bar:                                |
//|     Long:  M15[1].Low  < D1Low[1]  UND M15[1].Close > D1Low[1] |
//|     Short: M15[1].High > D1High[1] UND M15[1].Close < D1High[1]|
//|   Stop: SweepExtrem +/- atrStopMult * ATR(M15)                  |
//|   Ziel: gegenuberliegende Range-Seite.                           |
//|   SessionRestricted: false (globale Verfuegbarkeit).             |
//|   Kein ST_ARMED: Sweep+Reclaim ist ein Eins-Bar-Event.           |
//|   ST_IDLE -> ST_PENDING direkt.                                  |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__
#define __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__

#include "SignalModuleBase.mqh"

class CSignalLiquiditySweep : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   double            m_atrStopMult;

   double            m_d1High;   // D1 High[1] — Vortagshoch
   double            m_d1Low;    // D1 Low[1]  — Vortagstief

   //+------------------------------------------------------------------+
   //| D1-Level aktualisieren (einmal pro neuer M15-Bar genuegt,       |
   //| da D1[1] sich nur bei neuem D1-Bar aendert — wird aber bei     |
   //| jedem M15-Tick neu gelesen, um beim ersten D1-Rollover sofort  |
   //| das korrekte Level zu haben).                                    |
   //+------------------------------------------------------------------+
   bool              UpdateLevels(CMarketData &md)
     {
      if(!md.GetHighD1(1, m_d1High)) return false;
      if(!md.GetLowD1(1,  m_d1Low))  return false;
      return (m_d1High > 0.0 && m_d1Low > 0.0 && m_d1High > m_d1Low);
     }

   //+------------------------------------------------------------------+
   //| Prueft ob in M15[1] ein Sweep+Reclaim stattgefunden hat.       |
   //| Long:  Low[1] < d1Low  UND Close[1] > d1Low                    |
   //| Short: High[1] > d1High UND Close[1] < d1High                  |
   //| outSweepExtreme: der extreme Sweep-Punkt (Low[1] bzw. High[1]) |
   //+------------------------------------------------------------------+
   bool              CheckSweepReclaim(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                       double &outSweepExtreme)
     {
      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1))
         return false;

      double low1, high1;
      if(!md.GetLow(PERIOD_M15, 1, low1))
         return false;
      if(!md.GetHigh(PERIOD_M15, 1, high1))
         return false;

      if(dir == SIGNAL_LONG)
        {
         if(low1 < m_d1Low && close1 > m_d1Low)
           {
            outSweepExtreme = low1;
            return true;
           }
        }
      else
        {
         if(high1 > m_d1High && close1 < m_d1High)
           {
            outSweepExtreme = high1;
            return true;
           }
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Baut das SignalProposal aus dem Sweep-Extrem.                   |
   //| Stop: SweepExtrem +/- atrStopMult * ATR(M15)                    |
   //| Ziel: gegenuberliegende Range-Seite.                             |
   //+------------------------------------------------------------------+
   void              BuildProposal(CMarketData &md, const double sweepExtreme,
                                   const ENUM_SIGNAL_DIR dir, SignalProposal &outProposal)
     {
      double atr = md.GetAtrM15();

      outProposal.Reset();
      outProposal.valid       = true;
      outProposal.dir         = dir;
      outProposal.entryPrice  = 0.0; // Market
      outProposal.atrAtSignal = atr;
      outProposal.magic       = m_magic;

      if(dir == SIGNAL_LONG)
        {
         outProposal.stopPrice   = sweepExtreme - m_atrStopMult * atr;
         outProposal.targetPrice = m_d1High;  // gegenuberliegende Range-Seite
         outProposal.reason      = "Sweep Long: M15-Reclaim ueber D1Low";
        }
      else
        {
         outProposal.stopPrice   = sweepExtreme + m_atrStopMult * atr;
         outProposal.targetPrice = m_d1Low;   // gegenuberliegende Range-Seite
         outProposal.reason      = "Sweep Short: M15-Reclaim unter D1High";
        }

      PrintFormat("SignalLiquiditySweep: ST_PENDING dir=%d sweepExtreme=%.5f stop=%.5f target=%.5f d1Low=%.5f d1High=%.5f",
                  dir, sweepExtreme, outProposal.stopPrice, outProposal.targetPrice, m_d1Low, m_d1High);
     }

public:
                     CSignalLiquiditySweep(void):
                        CSignalModuleBase(),
                        m_allowShort(false),
                        m_atrStopMult(1.5),
                        m_d1High(0.0), m_d1Low(0.0) {}

   void              Configure(const bool allowShort, const double atrStopMult,
                               const int magic)
     {
      m_allowShort  = allowShort;
      m_atrStopMult = atrStopMult;
      m_magic       = magic;
     }

   //--- Pure-virtual-Implementierungen (const-Qualifier VERBATIM, Hazard H1)
   virtual string           Name(void)              const { return "SignalLiquiditySweep"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;             }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;             }
   virtual bool             SessionRestricted(void) const { return false;                  }

   //+------------------------------------------------------------------+
   //| Einmal pro neuer M15-Bar aufgerufen, solange keine eigene       |
   //| Position offen ist.                                              |
   //| Sweep+Reclaim ist Eins-Bar-Event: ST_IDLE -> ST_PENDING direkt. |
   //| Kein ST_ARMED-Zwischenschritt.                                   |
   //+------------------------------------------------------------------+
   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state != ST_IDLE)
         return false;

      if(!md.IsD1Valid())
         return false;

      if(!UpdateLevels(md))
         return false;

      double sweepExtreme = 0.0;

      if(CheckSweepReclaim(md, SIGNAL_LONG, sweepExtreme))
        {
         BuildProposal(md, sweepExtreme, SIGNAL_LONG, outProposal);
         m_dir   = SIGNAL_LONG;
         m_state = ST_PENDING;
         return true;
        }

      if(m_allowShort && CheckSweepReclaim(md, SIGNAL_SHORT, sweepExtreme))
        {
         BuildProposal(md, sweepExtreme, SIGNAL_SHORT, outProposal);
         m_dir   = SIGNAL_SHORT;
         m_state = ST_PENDING;
         return true;
        }

      return false;
     }
  };

#endif // __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__
