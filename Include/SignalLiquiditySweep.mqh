//+------------------------------------------------------------------+
//|                                        SignalLiquiditySweep.mqh  |
//|   Tier-2.1-Strategie: Liquidity-Sweep-Reclaim.                  |
//|   Levels: D1 High/Low der letzten m_levelLookback Tage.         |
//|                                                                   |
//|   Zwei-Phasen-Logik:                                             |
//|   Phase 1 — Sweep erkannt (ST_ARMED):                           |
//|     Long:  M15[1].Low  < D1Low[n]  UND Tiefe >= minSweepAtr*ATR |
//|     Short: M15[1].High > D1High[n] UND Tiefe >= minSweepAtr*ATR |
//|     Das naechstgelegene qualifizierte Level gewinnt.            |
//|   Phase 2 — Reclaim in den naechsten m_reclaimBars M15-Bars:   |
//|     Long:  M15[1].Close > getroffenes Level                     |
//|     Short: M15[1].Close < getroffenes Level                     |
//|                                                                   |
//|   Stop:     SweepExtrem +/- atrStopMult * ATR(M15)              |
//|   Ziel:     gegenuberliegende Seite des getroffenen Tages.      |
//|   Cooldown: m_cooldownBars D1-Bars nach jedem Abschluss.        |
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
   double            m_minSweepAtrMult;  // Mindest-Sweep-Tiefe in ATR-Vielfachen
   int               m_reclaimBars;      // Max. M15-Bars bis Reclaim
   int               m_levelLookback;    // D1-Bars rueckwaerts als aktive Levels
   int               m_cooldownBars;     // D1-Bars Pause nach Abschluss

   //--- gemerkte Werte des aktiven Setups
   double            m_hitLevel;         // D1Low/High das getroffen wurde
   double            m_targetLevel;      // gegenuberliegende Seite desselben Tages
   double            m_sweepExtreme;     // tiefstes Low / hoechstes High der Sweep-Bar
   int               m_reclaimCounter;
   int               m_cooldownCounter;  // verbleibende M15-Bars Cooldown

   //+------------------------------------------------------------------+
   //| Sucht das naechstgelegene D1-Level das von M15[1] mit            |
   //| ausreichender Tiefe (>= minSweepAtr * ATR) gesweept wurde.      |
   //| "Naechstgelegen" = geringster Abstand Level <-> SweepExtrem.    |
   //+------------------------------------------------------------------+
   bool              FindSweepedLevel(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                      double &outSweepExtreme,
                                      double &outHitLevel, double &outTargetLevel)
     {
      double low1, high1;
      if(!md.GetLow(PERIOD_M15,  1, low1))  return false;
      if(!md.GetHigh(PERIOD_M15, 1, high1)) return false;

      double atr      = md.GetAtrM15();
      double minDepth = m_minSweepAtrMult * atr; // Mindesttiefe des Sweeps

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
            double depth = dLow - low1; // positiv wenn low1 < dLow
            if(depth >= minDepth)
              {
               if(depth < bestDist)
                 {
                  bestDist        = depth;
                  outSweepExtreme = low1;
                  outHitLevel     = dLow;
                  outTargetLevel  = dHigh;
                  found           = true;
                 }
              }
           }
         else
           {
            double depth = high1 - dHigh; // positiv wenn high1 > dHigh
            if(depth >= minDepth)
              {
               if(depth < bestDist)
                 {
                  bestDist        = depth;
                  outSweepExtreme = high1;
                  outHitLevel     = dHigh;
                  outTargetLevel  = dLow;
                  found           = true;
                 }
              }
           }
        }

      return found;
     }

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

   void              StartCooldown(void)
     {
      m_cooldownCounter = m_cooldownBars * 96; // 1 D1-Bar = 96 M15-Bars (24h / 15min)
     }

public:
                     CSignalLiquiditySweep(void):
                        CSignalModuleBase(),
                        m_allowShort(false),
                        m_atrStopMult(1.5),
                        m_minSweepAtrMult(0.5),
                        m_reclaimBars(3),
                        m_levelLookback(3),
                        m_cooldownBars(2),
                        m_hitLevel(0.0), m_targetLevel(0.0),
                        m_sweepExtreme(0.0), m_reclaimCounter(0),
                        m_cooldownCounter(0) {}

   void              Configure(const bool allowShort, const double atrStopMult,
                               const double minSweepAtrMult, const int reclaimBars,
                               const int levelLookback, const int cooldownBars,
                               const int magic)
     {
      m_allowShort      = allowShort;
      m_atrStopMult     = atrStopMult;
      m_minSweepAtrMult = minSweepAtrMult;
      m_reclaimBars     = reclaimBars;
      m_levelLookback   = levelLookback;
      m_cooldownBars    = cooldownBars;
      m_magic           = magic;
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
         if(m_cooldownCounter > 0)
           {
            m_cooldownCounter--;
            return false;
           }

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

   virtual void      NotifyPositionClosed(void)
     {
      StartCooldown();
      ResetToIdle("Position geschlossen");
     }

   virtual void      NotifyOrderFailed(void)
     {
      StartCooldown();
      ResetToIdle("Order fehlgeschlagen");
     }

   virtual void      NotifyFilterVeto(void)
     {
      StartCooldown();
      m_state = ST_BLOCKED;
      ResetToIdle("FilterStack-Veto");
     }
  };

#endif // __SWINGGOLD_SIGNALLIQUIDITYSWEEP_MQH__
