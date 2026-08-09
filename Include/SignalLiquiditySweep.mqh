//+------------------------------------------------------------------+
//|                                        SignalLiquiditySweep.mqh  |
//|   Tier-2.1-Strategie: Liquidity-Sweep-Reclaim.                  |
//|   Levels: W1 High/Low, MN1 High/Low, Yearly High/Low            |
//|   (Jahreshoch/-tief via 13 abgeschlossene MN1-Bars).            |
//|                                                                   |
//|   Zwei-Phasen-Logik:                                             |
//|   Phase 1 — Sweep erkannt (ST_ARMED):                           |
//|     Long:  M15[1].Low  < Level UND Tiefe >= minSweepAtr*ATR     |
//|     Short: M15[1].High > Level UND Tiefe >= minSweepAtr*ATR     |
//|     Das naechstgelegene qualifizierte Level gewinnt.            |
//|   Phase 2 — Reclaim in den naechsten m_reclaimBars M15-Bars:   |
//|     Long:  M15[1].Close > getroffenes Level                     |
//|     Short: M15[1].Close < getroffenes Level                     |
//|                                                                   |
//|   Stop:     SweepExtrem +/- atrStopMult * ATR(M15)              |
//|   Ziel:     gegenuberliegende Seite desselben Levels.           |
//|   Cooldown: m_cooldownBars * 96 M15-Bars nach jedem Abschluss.  |
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
   bool              m_useWeekly;        // W1 High/Low als Levels verwenden
   bool              m_useMonthly;       // MN1 High/Low als Levels verwenden
   bool              m_useYearly;        // Yearly High/Low (13 MN1-Bars) als Levels verwenden
   int               m_reclaimBars;      // Max. M15-Bars bis Reclaim
   int               m_cooldownBars;     // D1-Bars Pause nach Abschluss (in 96 M15-Bars je Bar)

   //--- gemerkte Werte des aktiven Setups
   double            m_hitLevel;         // Level das getroffen wurde
   double            m_targetLevel;      // gegenuberliegende Seite desselben Levels
   double            m_sweepExtreme;     // tiefstes Low / hoechstes High der Sweep-Bar
   string            m_levelType;        // z.B. "W1-High", "MN1-Low", "Yearly-High"
   int               m_reclaimCounter;
   int               m_cooldownCounter;  // verbleibende M15-Bars Cooldown

   //+------------------------------------------------------------------+
   //| Holt W1 High und Low der letzten abgeschlossenen Woche.         |
   //+------------------------------------------------------------------+
   bool              GetW1Levels(double &outHigh, double &outLow) const
     {
      double hBuf[1], lBuf[1];
      if(CopyHigh(_Symbol, PERIOD_W1, 1, 1, hBuf) != 1) return false;
      if(CopyLow (_Symbol, PERIOD_W1, 1, 1, lBuf) != 1) return false;
      outHigh = hBuf[0];
      outLow  = lBuf[0];
      return (outHigh > 0.0 && outLow > 0.0 && outHigh > outLow);
     }

   //+------------------------------------------------------------------+
   //| Holt MN1 High und Low des letzten abgeschlossenen Monats.       |
   //+------------------------------------------------------------------+
   bool              GetMN1Levels(double &outHigh, double &outLow) const
     {
      double hBuf[1], lBuf[1];
      if(CopyHigh(_Symbol, PERIOD_MN1, 1, 1, hBuf) != 1) return false;
      if(CopyLow (_Symbol, PERIOD_MN1, 1, 1, lBuf) != 1) return false;
      outHigh = hBuf[0];
      outLow  = lBuf[0];
      return (outHigh > 0.0 && outLow > 0.0 && outHigh > outLow);
     }

   //+------------------------------------------------------------------+
   //| Holt Jahreshoch/-tief aus 13 abgeschlossenen MN1-Bars.          |
   //| PERIOD_Y1 existiert in MT5 nicht; 13 MN1-Bars ab shift=1        |
   //| decken ~1 Jahr ab.                                               |
   //+------------------------------------------------------------------+
   bool              GetYearlyLevels(double &outHigh, double &outLow) const
     {
      double hBuf[13], lBuf[13];
      if(CopyHigh(_Symbol, PERIOD_MN1, 1, 13, hBuf) != 13) return false;
      if(CopyLow (_Symbol, PERIOD_MN1, 1, 13, lBuf) != 13) return false;
      int hiIdx = ArrayMaximum(hBuf, 0, 13);
      int loIdx = ArrayMinimum(lBuf, 0, 13);
      outHigh = hBuf[hiIdx];
      outLow  = lBuf[loIdx];
      return (outHigh > 0.0 && outLow > 0.0 && outHigh > outLow);
     }

   //+------------------------------------------------------------------+
   //| Sucht das naechstgelegene Level das von M15[1] mit ausreichender |
   //| Tiefe (>= minSweepAtr * ATR) gesweept wurde.                    |
   //| "Naechstgelegen" = geringster Abstand Level <-> SweepExtrem.    |
   //+------------------------------------------------------------------+
   bool              FindSweepedLevel(CMarketData &md, const ENUM_SIGNAL_DIR dir,
                                      double &outSweepExtreme,
                                      double &outHitLevel, double &outTargetLevel,
                                      string &outLevelType)
     {
      double low1, high1;
      if(!md.GetLow(PERIOD_M15,  1, low1))  return false;
      if(!md.GetHigh(PERIOD_M15, 1, high1)) return false;

      double atr      = md.GetAtrM15();
      double minDepth = m_minSweepAtrMult * atr;

      //--- Bis zu 6 Levels sammeln: W1H, W1L, MN1H, MN1L, YearH, YearL
      double levels [6];
      double targets[6];
      string labels [6];
      int    count = 0;

      double w1H, w1L, mn1H, mn1L, yrH, yrL;

      if(m_useWeekly && GetW1Levels(w1H, w1L))
        {
         levels[count]  = w1H; targets[count]  = w1L; labels[count]  = "W1-High";  count++;
         levels[count]  = w1L; targets[count]  = w1H; labels[count]  = "W1-Low";   count++;
        }

      if(m_useMonthly && GetMN1Levels(mn1H, mn1L))
        {
         levels[count]  = mn1H; targets[count]  = mn1L; labels[count]  = "MN1-High"; count++;
         levels[count]  = mn1L; targets[count]  = mn1H; labels[count]  = "MN1-Low";  count++;
        }

      if(m_useYearly && GetYearlyLevels(yrH, yrL))
        {
         levels[count]  = yrH; targets[count]  = yrL; labels[count]  = "Yearly-High"; count++;
         levels[count]  = yrL; targets[count]  = yrH; labels[count]  = "Yearly-Low";  count++;
        }

      if(count == 0) return false;

      double bestDist = DBL_MAX;
      bool   found    = false;

      for(int i = 0; i < count; i++)
        {
         double lvl    = levels[i];
         double target = targets[i];
         string lbl    = labels[i];

         if(dir == SIGNAL_LONG)
           {
            //--- Nur Low-Levels koennen von unten gesweept werden
            if(StringFind(lbl, "-Low") < 0) continue;
            double depth = lvl - low1;
            if(depth >= minDepth)
              {
               if(depth < bestDist)
                 {
                  bestDist        = depth;
                  outSweepExtreme = low1;
                  outHitLevel     = lvl;
                  outTargetLevel  = target;
                  outLevelType    = lbl;
                  found           = true;
                 }
              }
           }
         else
           {
            //--- Nur High-Levels koennen von oben gesweept werden
            if(StringFind(lbl, "-High") < 0) continue;
            double depth = high1 - lvl;
            if(depth >= minDepth)
              {
               if(depth < bestDist)
                 {
                  bestDist        = depth;
                  outSweepExtreme = high1;
                  outHitLevel     = lvl;
                  outTargetLevel  = target;
                  outLevelType    = lbl;
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
         outProposal.reason    = StringFormat("Sweep Long: Reclaim ueber %s", m_levelType);
        }
      else
        {
         outProposal.stopPrice = m_sweepExtreme + m_atrStopMult * atr;
         outProposal.reason    = StringFormat("Sweep Short: Reclaim unter %s", m_levelType);
        }

      PrintFormat("SignalLiquiditySweep: ST_PENDING levelType=%s dir=%d sweepExtreme=%.5f hitLevel=%.5f stop=%.5f target=%.5f reclaimBar=%d",
                  m_levelType, m_dir, m_sweepExtreme, m_hitLevel,
                  outProposal.stopPrice, outProposal.targetPrice, m_reclaimCounter);
     }

   void              ArmSweep(const ENUM_SIGNAL_DIR dir, const double sweepExtreme,
                              const double hitLevel, const double targetLevel,
                              const string levelType)
     {
      m_dir            = dir;
      m_sweepExtreme   = sweepExtreme;
      m_hitLevel       = hitLevel;
      m_targetLevel    = targetLevel;
      m_levelType      = levelType;
      m_reclaimCounter = 0;
      m_state          = ST_ARMED;
      PrintFormat("SignalLiquiditySweep: ST_ARMED levelType=%s dir=%d sweepExtreme=%.5f hitLevel=%.5f target=%.5f",
                  levelType, dir, sweepExtreme, hitLevel, targetLevel);
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
                        m_useWeekly(true),
                        m_useMonthly(true),
                        m_useYearly(true),
                        m_reclaimBars(3),
                        m_cooldownBars(2),
                        m_hitLevel(0.0), m_targetLevel(0.0),
                        m_sweepExtreme(0.0), m_levelType(""),
                        m_reclaimCounter(0), m_cooldownCounter(0) {}

   void              Configure(const bool allowShort, const double atrStopMult,
                               const double minSweepAtrMult,
                               const bool useWeekly, const bool useMonthly, const bool useYearly,
                               const int reclaimBars, const int cooldownBars,
                               const int magic)
     {
      m_allowShort      = allowShort;
      m_atrStopMult     = atrStopMult;
      m_minSweepAtrMult = minSweepAtrMult;
      m_useWeekly       = useWeekly;
      m_useMonthly      = useMonthly;
      m_useYearly       = useYearly;
      m_reclaimBars     = reclaimBars;
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
         string levelType = "";

         if(FindSweepedLevel(md, SIGNAL_LONG, sweepExtreme, hitLevel, targetLevel, levelType))
           {
            ArmSweep(SIGNAL_LONG, sweepExtreme, hitLevel, targetLevel, levelType);
            if(CheckReclaim(md))
              {
               BuildProposal(md, outProposal);
               m_state = ST_PENDING;
               return true;
              }
            return false;
           }

         if(m_allowShort &&
            FindSweepedLevel(md, SIGNAL_SHORT, sweepExtreme, hitLevel, targetLevel, levelType))
           {
            ArmSweep(SIGNAL_SHORT, sweepExtreme, hitLevel, targetLevel, levelType);
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
