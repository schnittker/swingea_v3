//+------------------------------------------------------------------+
//|                                   SignalAsiaRangeBreakout.mqh    |
//|   Tier-2-Strategie: Asia-Range-Breakout mit Pflicht-Retest       |
//|   (strategies.md Teil C.4, ea.md 8.1 Hypothese 2 "Retest-Pflicht|
//|   schlaegt Sofort-Entry").                                       |
//|                                                                   |
//|   WICHTIGE EINSCHRAENKUNG (strategies.md C.4): in H1/2026 trieb  |
//|   Asien die Rebounds - die Annahme "Asien = tote Range" gilt    |
//|   nicht mehr uneingeschraenkt, Boxen werden breiter, Fehlsignale|
//|   haeufiger. Groesster Validierungsbedarf in Tier 2.            |
//|                                                                   |
//|   Bias/Box (strategies.md Teil D) = H1, Setup/Trigger = M15.    |
//|   Wie bei LBMA-Fix-Reversal entschieden: kein neuer H1-Infra-   |
//|   Ausbau fuer ein einzelnes Tier-2-Modul - die Box wird direkt  |
//|   aus M15-Daten berechnet (CopyHigh/CopyLow, Muster identisch   |
//|   zu SignalLiquiditySweep::GetW1Levels etc.).                   |
//|                                                                   |
//|   Mechanik:                                                       |
//|   Box-Bildung (einmal/Tag): wenn "jetzt" (GMT) in der M15-Bar   |
//|     liegt, die BoxEndHour:00 enthaelt -> Box-High/-Low ueber    |
//|     die vorangegangenen (BoxEndHour-BoxStartHour)*4 M15-Bars.  |
//|   Breakout (ST_IDLE): Close[1] jenseits Box-High (Long) bzw.    |
//|     Box-Low (Short, nur wenn allowShort). Pro Richtung nur EIN  |
//|     Breakout-Versuch pro Box/Tag (Exhausted-Flags), unabhaengig|
//|     von RequireRetest - vermeidet Whipsaw-Wiederholversuche     |
//|     (analog Sweep's cooldownBars).                               |
//|   RequireRetest=false: sofortiger Entry auf dem Breakout-Bar.  |
//|   RequireRetest=true: armieren (ST_ARMED), Bestaetigung binnen |
//|     confirmBars M15-Bars ueber Retest der Box-Kante.            |
//|                                                                   |
//|   Stop:   gegenueberliegende Boxseite, gekappt auf atrStopMult*|
//|           ATR(M15) Abstand von der gebrochenen Kante.           |
//|   Ziel:   gebrochene Kante +/- Boxhoehe (gemessene Bewegung).   |
//|   SessionRestricted() = false (hardcoded): die Box-Zeit-Logik  |
//|   IST bereits die Session-Einschraenkung; die generische        |
//|   12-16-GMT-Overlap-Pruefung passt nicht (Breakout+Retest laufen|
//|   nach 08:00 GMT, ausserhalb dieses Fensters).                  |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALASIARANGEBREAKOUT_MQH__
#define __SWINGGOLD_SIGNALASIARANGEBREAKOUT_MQH__

#include "SignalModuleBase.mqh"
#include "TimeContext.mqh"

class CSignalAsiaRangeBreakout : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   bool              m_requireRetest;
   int               m_boxStartHour, m_boxEndHour;  // GMT-Stunden, Default 0/8
   double            m_retestToleranceAtrMult;      // Default 0.2
   int               m_confirmBars;                 // Default 8
   double            m_atrStopMult;                 // Default 1.5
   CTimeContext      m_timeCtx;                      // eigene Instanz, nur GmtNow()

   //--- Box-Zustand (einmal/Tag gesetzt)
   double            m_boxHigh, m_boxLow, m_boxHeight;
   bool              m_boxValid;
   bool              m_longExhausted, m_shortExhausted; // je Box/Tag nur 1 Versuch/Richtung

   //--- gemerkte Werte des aktiven Setups
   double            m_breakoutEdge;   // gebrochene Boxkante (Box-High bei Long, Box-Low bei Short)
   int               m_confirmCounter;

   //+------------------------------------------------------------------+
   //| Ist "jetzt" (GMT) innerhalb der M15-Bar, die BoxEndHour:00      |
   //| enthaelt? Die Box ist direkt in GMT verankert (im Gegensatz zu |
   //| LBMA-Fix, das London-Zeit/DST braucht), daher keine DST-Logik. |
   //+------------------------------------------------------------------+
   bool              IsInBoxCloseBar(void) const
     {
      datetime gmt = m_timeCtx.GmtNow();
      MqlDateTime dt;
      TimeToStruct(gmt, dt);
      return (dt.hour == m_boxEndHour && dt.min < 15);
     }

   //+------------------------------------------------------------------+
   //| Bildet die Box aus den vorangegangenen (BoxEndHour-BoxStartHour)|
   //| *4 abgeschlossenen M15-Bars (direktes CopyHigh/CopyLow, Muster  |
   //| identisch zu SignalLiquiditySweep::GetW1Levels etc.).           |
   //| Setzt m_longExhausted/m_shortExhausted zurueck - neue Box =     |
   //| neue Versuche erlaubt.                                          |
   //+------------------------------------------------------------------+
   void              UpdateBox(void)
     {
      int barsInBox = (m_boxEndHour - m_boxStartHour) * 4;
      if(barsInBox <= 0)
        {
         m_boxValid = false;
         return;
        }

      double hBuf[], lBuf[];
      ArraySetAsSeries(hBuf, true);
      ArraySetAsSeries(lBuf, true);
      if(CopyHigh(_Symbol, PERIOD_M15, 1, barsInBox, hBuf) != barsInBox)
        {
         m_boxValid = false;
         return;
        }
      if(CopyLow(_Symbol, PERIOD_M15, 1, barsInBox, lBuf) != barsInBox)
        {
         m_boxValid = false;
         return;
        }

      int hiIdx = ArrayMaximum(hBuf, 0, barsInBox);
      int loIdx = ArrayMinimum(lBuf, 0, barsInBox);

      m_boxHigh   = hBuf[hiIdx];
      m_boxLow    = lBuf[loIdx];
      m_boxHeight = m_boxHigh - m_boxLow;
      m_boxValid  = (m_boxHigh > 0.0 && m_boxLow > 0.0 && m_boxHeight > 0.0);

      m_longExhausted  = false;
      m_shortExhausted = false;

      if(m_boxValid)
         PrintFormat("SignalAsiaRangeBreakout: Box gebildet High=%.5f Low=%.5f Height=%.5f",
                     m_boxHigh, m_boxLow, m_boxHeight);
     }

   //+------------------------------------------------------------------+
   //| Prueft Breakout jenseits der Box (Close[1]). Pro Richtung nur   |
   //| EIN Versuch pro Box/Tag (Exhausted-Flags).                      |
   //+------------------------------------------------------------------+
   bool              CheckBreakout(CMarketData &md, ENUM_SIGNAL_DIR &outDir)
     {
      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      if(!m_longExhausted && close1 > m_boxHigh)
        {
         outDir = SIGNAL_LONG;
         return true;
        }

      if(m_allowShort && !m_shortExhausted && close1 < m_boxLow)
        {
         outDir = SIGNAL_SHORT;
         return true;
        }

      return false;
     }

   void              MarkExhausted(const ENUM_SIGNAL_DIR dir)
     {
      if(dir == SIGNAL_LONG)  m_longExhausted  = true;
      if(dir == SIGNAL_SHORT) m_shortExhausted = true;
     }

   //+------------------------------------------------------------------+
   //| Retest-Bestaetigung: Kante wird von der Breakout-Seite aus      |
   //| angetestet (Low bei Long/High bei Short <= Toleranz) UND haelt |
   //| als Unterstuetzung/Widerstand (Close jenseits der Kante).       |
   //+------------------------------------------------------------------+
   bool              CheckRetestConfirmed(CMarketData &md)
     {
      double atr = md.GetAtrM15();
      if(atr <= 0.0) return false;

      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      if(m_dir == SIGNAL_LONG)
        {
         double low1;
         if(!md.GetLow(PERIOD_M15, 1, low1)) return false;
         bool touched = (low1 <= m_breakoutEdge + m_retestToleranceAtrMult * atr);
         bool held    = (close1 >= m_breakoutEdge);
         return touched && held;
        }

      if(m_dir == SIGNAL_SHORT)
        {
         double high1;
         if(!md.GetHigh(PERIOD_M15, 1, high1)) return false;
         bool touched = (high1 >= m_breakoutEdge - m_retestToleranceAtrMult * atr);
         bool held    = (close1 <= m_breakoutEdge);
         return touched && held;
        }

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

      string entryLabel = m_requireRetest ? "Retest bestaetigt" : "Sofort-Entry";

      if(m_dir == SIGNAL_LONG)
        {
         outProposal.stopPrice   = MathMax(m_boxLow, m_boxHigh - m_atrStopMult * atr);
         outProposal.targetPrice = m_breakoutEdge + m_boxHeight;
         outProposal.reason      = StringFormat("Asia-Range-Breakout Long: %s ueber Box-High %.5f",
                                                 entryLabel, m_boxHigh);
        }
      else
        {
         outProposal.stopPrice   = MathMin(m_boxHigh, m_boxLow + m_atrStopMult * atr);
         outProposal.targetPrice = m_breakoutEdge - m_boxHeight;
         outProposal.reason      = StringFormat("Asia-Range-Breakout Short: %s unter Box-Low %.5f",
                                                 entryLabel, m_boxLow);
        }

      PrintFormat("SignalAsiaRangeBreakout: ST_PENDING dir=%d boxHigh=%.5f boxLow=%.5f stop=%.5f target=%.5f",
                  m_dir, m_boxHigh, m_boxLow, outProposal.stopPrice, outProposal.targetPrice);
     }

public:
                     CSignalAsiaRangeBreakout(void):
                        CSignalModuleBase(),
                        m_allowShort(false),
                        m_requireRetest(true),
                        m_boxStartHour(0), m_boxEndHour(8),
                        m_retestToleranceAtrMult(0.2),
                        m_confirmBars(8),
                        m_atrStopMult(1.5),
                        m_boxHigh(0.0), m_boxLow(0.0), m_boxHeight(0.0),
                        m_boxValid(false),
                        m_longExhausted(false), m_shortExhausted(false),
                        m_breakoutEdge(0.0),
                        m_confirmCounter(0) {}

   void              Configure(const bool allowShort, const bool requireRetest,
                                const int boxStartHour, const int boxEndHour,
                                const double retestToleranceAtrMult, const int confirmBars,
                                const double atrStopMult,
                                const int gmtOffsetWinter, const int gmtOffsetSummer,
                                const int magic)
     {
      m_allowShort             = allowShort;
      m_requireRetest          = requireRetest;
      m_boxStartHour           = boxStartHour;
      m_boxEndHour             = boxEndHour;
      m_retestToleranceAtrMult = retestToleranceAtrMult;
      m_confirmBars            = confirmBars;
      m_atrStopMult            = atrStopMult;
      m_magic                  = magic;

      //--- Overlap-/Wochentag-Parameter der eingebetteten Instanz ungenutzt,
      //--- nur GmtNow() wird gebraucht.
      m_timeCtx.Configure(gmtOffsetWinter, gmtOffsetSummer, 0, 0, 0, 0);
     }

   virtual string           Name(void)              const { return "SignalAsiaRangeBreakout"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;                }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;                }
   virtual bool             SessionRestricted(void) const { return false;                     }

   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED)
        {
         m_confirmCounter++;

         if(m_confirmCounter > m_confirmBars)
           {
            ResetToIdle("Retest-Verfall");
            return false;
           }

         if(!md.IsM15Valid())
            return false;

         if(CheckRetestConfirmed(md))
           {
            BuildProposal(md, outProposal);
            m_state = ST_PENDING;
            return true;
           }

         return false;
        }

      if(m_state == ST_IDLE)
        {
         if(!md.IsM15Valid())
            return false;

         if(IsInBoxCloseBar())
           {
            UpdateBox();
            return false; // Box gerade erst gebildet, kein Breakout-Check in dieser Bar
           }

         if(!m_boxValid)
            return false;

         ENUM_SIGNAL_DIR breakoutDir;
         if(!CheckBreakout(md, breakoutDir))
            return false;

         m_dir          = breakoutDir;
         m_breakoutEdge = (breakoutDir == SIGNAL_LONG) ? m_boxHigh : m_boxLow;
         MarkExhausted(breakoutDir);

         if(m_requireRetest)
           {
            m_confirmCounter = 0;
            m_state          = ST_ARMED;
            PrintFormat("SignalAsiaRangeBreakout: ST_ARMED dir=%d breakoutEdge=%.5f boxHigh=%.5f boxLow=%.5f",
                        m_dir, m_breakoutEdge, m_boxHigh, m_boxLow);
            return false;
           }

         BuildProposal(md, outProposal);
         m_state = ST_PENDING;
         return true;
        }

      return false;
     }
  };

#endif // __SWINGGOLD_SIGNALASIARANGEBREAKOUT_MQH__
