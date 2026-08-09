//+------------------------------------------------------------------+
//|                                        SignalLiquiditySweep.mqh  |
//|   Tier-2.1-Strategie: Liquidity-Sweep-Reclaim.                  |
//|   Levels: D1 High/Low der letzten m_levelLookback Tage          |
//|   (Default 3: Vortag, Vorvor-, Vorvorvor-Tag).                  |
//|                                                                   |
//|   Zwei-Phasen-Logik:                                             |
//|   Phase 1 — Sweep erkannt (ST_ARMED):                           |
//|     Long:  M15[1].Low  < irgendein D1Low[1..n]                  |
//|     Short: M15[1].High > irgendein D1High[1..n]                 |
//|     Das naechste (naechstgelegene) getroffene Level gewinnt.    |
//|   Phase 2 — Reclaim in den naechsten m_reclaimBars M15-Bars:   |
//|     Long:  M15[1].Close > getroffenes Level                     |
//|     Short: M15[1].Close < getroffenes Level                     |
//|                                                                   |
//|   Stop: SweepExtrem +/- atrStopMult * ATR(M15)                  |
//|   Ziel: gegenuberliegende Seite des getroffenen Tages.          |
//|   SessionRestricted: false.                                      |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__
#define __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__

#include "SignalModuleBase.mqh"

class CSignalLiquiditySweep : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   double            m_atrStopMult;
   int               m_reclaimBars;    // Max. M15-Bars bis Reclaim
   int               m_levelLookback;  // Anzahl D1-Bars rueckwaerts (1..n)

   //--- gemerkte Level des getriggerten Setups
   double            m_hitLevel;       // D1Low (Long) oder D1High (Short) das getroffen wurde
   double            m_targetLevel;    // gegenuberliegende Seite desselben Tages
   double            m_sweepExtreme;   // tiefstes Low / hoechstes High der Sweep-Bar
   int               m_reclaimCounter;

   //+------------------------------------------------------------------+
   //| Sucht das naechstgelegene D1-Level das von M15[1] gesweept      |
   //| wurde. "Naechstgelegen" = geringstem Abstand zum aktuellen Kurs.|
   //| Gibt Level und Gegenseite desselben Tages zurueck.              |
   //+------------------------------------------------------------------+
   bool              FindSweepedLevel(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                      double &outSweepExtreme,
                                      double &outHitLevel, double &outTargetLevel)
     {
      double low1, high1;
      if(!md.GetLow(PERIOD_M15,  1, low1))  return false;
      if(!md.GetHigh(PERIOD_M15, 1, high1)) return false;

      double bestDist = DBL_MAX;
      bool   found    = false;

      for(int shift = 1; shift <= m_levelLookback; shift++)
        {
         double dHigh, dLow;
         if(!md.GetHighD1(shift, dHigh)) continue;
         if(!md.GetLowD1(shift,  dLow))  continue;
         if(dHigh <= 0.0 || dLow <= 0.0 || dHigh <= dLow) continue;

         if(dir == SIGNAL_LONG)
           {
            //--- Sweep: M15-Low durchsticht D1Low dieses Tages
            if(low1 < dLow)
              {
               double dist = dLow - low1; // wie tief unter dem Level
               if(dist < bestDist)
                 {
                  bestDist       = dist;
                  outSweepExtreme = low1;
                  outHitLevel    = dLow;
                  outTargetLevel = dHigh; // Ziel: Hoechstkurs desselben Tages
                  found          = true;
                 }
              }
           }
         else
           {
            //--- Sweep: M15-High durchsticht D1High dieses Tages
            if(high1 > dHigh)
              {
               double dist = high1 - dHigh;
               if(dist < bestDist)
                 {
                  bestDist       = dist;
                  outSweepExtreme = high1;
                  outHitLevel    = dHigh;
                  outTargetLevel = dLow;  // Ziel: Tiefstkurs desselben Tages
                  found          = true;
                 }
              }
           }
        }

      return found;
     }

   //+------------------------------------------------------------------+
   //| Reclaim: Close[1] wieder auf der richtigen Seite des Levels.   |
   //+------------------------------------------------------------------+
   bool              CheckReclaim(CMarketData &md)
     {
      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      if(m_dir == SIGNAL_LONG)  return (close1 > m_hitLevel);
      if(m_dir == SIGNAL_SHORT) return (close1 < m_hitLevel);
      return false;
     }

   void              BuildProposal(CMarketData &md, SignalProposal &outProposal)
     {
      double atr = md.GetAtrM15();

      outProposal.Reset();
      outProposal.valid       = true;
      outProposal.dir         = m_dir;
      outProposal.entryPrice  = 0.0;
      outProposal.atrAtSignal = atr;
      outProposal.magic       = m_magic;
      outProposal.targetPrice = m_targetLevel;

      if(m_dir == SIGNAL_LONG)
        {
         outProposal.stopPrice = m_sweepExtreme - m_atrStopMult * atr;
         outProposal.reason    = "Sweep Long: Reclaim ueber D1Low";
        }
      else
        {
         outProposal.stopPrice = m_sweepExtreme + m_atrStopMult * atr;
         outProposal.reason    = "Sweep Short: Reclaim unter D1High";
        }

      PrintFormat("SignalLiquiditySweep: ST_PENDING dir=%d sweepExtreme=%.5f hitLevel=%.5f stop=%.5f target=%.5f reclaimBar=%d",
                  m_dir, m_sweepExtreme, m_hitLevel,
                  outProposal.stopPrice, outProposal.targetPrice, m_reclaimCounter);
     }

   void              ArmSweep(const ENUM_SIGNAL_DIR dir, const double sweepExtreme,
                              const double hitLevel, const double targetLevel)
     {
      m_dir            = dir;
      m_sweepExtreme   = sweepExtreme;
      m_hitLevel       = hitLevel;
      m_targetLevel    = targetLevel;
      m_reclaimCounter = 0;
      m_state          = ST_ARMED;
      PrintFormat("SignalLiquiditySweep: ST_ARMED dir=%d sweepExtreme=%.5f hitLevel=%.5f target=%.5f",
                  dir, sweepExtreme, hitLevel, targetLevel);
     }

public:
                     CSignalLiquiditySweep(void):
                        CSignalModuleBase(),
                        m_allowShort(false),
                        m_atrStopMult(1.5),
                        m_reclaimBars(3),
                        m_levelLookback(3),
                        m_hitLevel(0.0), m_targetLevel(0.0),
                        m_sweepExtreme(0.0), m_reclaimCounter(0) {}

   void              Configure(const bool allowShort, const double atrStopMult,
                               const int reclaimBars, const int levelLookback,
                               const int magic)
     {
      m_allowShort    = allowShort;
      m_atrStopMult   = atrStopMult;
      m_reclaimBars   = reclaimBars;
      m_levelLookback = levelLookback;
      m_magic         = magic;
     }

   virtual string           Name(void)              const { return "SignalLiquiditySweep"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;             }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;             }
   virtual bool             SessionRestricted(void) const { return false;                  }

   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED)
        {
         m_reclaimCounter++;

         if(m_reclaimCounter > m_reclaimBars)
           {
            ResetToIdle("Reclaim-Verfall");
            return false;
           }

         if(!md.IsD1Valid())
            return false;

         if(CheckReclaim(md))
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

         double sweepExtreme = 0.0, hitLevel = 0.0, targetLevel = 0.0;

         if(FindSweepedLevel(md, SIGNAL_LONG, sweepExtreme, hitLevel, targetLevel))
           {
            ArmSweep(SIGNAL_LONG, sweepExtreme, hitLevel, targetLevel);
            if(CheckReclaim(md))
              {
               BuildProposal(md, outProposal);
               m_state = ST_PENDING;
               return true;
              }
            return false;
           }

         if(m_allowShort &&
            FindSweepedLevel(md, SIGNAL_SHORT, sweepExtreme, hitLevel, targetLevel))
           {
            ArmSweep(SIGNAL_SHORT, sweepExtreme, hitLevel, targetLevel);
            if(CheckReclaim(md))
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
