//+------------------------------------------------------------------+
//|                                     SignalLondonBreakout.mqh    |
//|   Tier-3-Strategie: klassischer London-Range-Breakout (M15),    |
//|   neu/unvalidiert - fuer eine dedizierte Prop-Firm-Challenge     |
//|   (200k$, 10% Ziel, 3% Tages-/10% Gesamt-Limit).                |
//|                                                                   |
//|   Mechanik:                                                       |
//|   Range-Bildung (RangeStartHour..RangeEndHour, GMT, Default      |
//|     08-13): Box-High/-Low laufend ueber die geschlossenen M15-   |
//|     Bars aktualisiert (md.GetHigh/GetLow, shift=1). Sobald die   |
//|     GMT-Stunde RangeEndHour erreicht ist, wird die Range EINMAL  |
//|     eingefroren (m_rangeFrozen) - danach keine weiteren Updates  |
//|     mehr, auch wenn die Stunde spaeter nochmal geprueft wird.    |
//|   Entry-Fenster (EntryStartHour..EntryEndHour, GMT, Default      |
//|     13-14): Breakout-Check auf Basis des letzten geschlossenen   |
//|     M15-Bar-Close (kein Intra-Bar-Trigger, ea.md 7.7). Long bei  |
//|     Close > RangeHigh + MinBreakoutAtrMult*ATR(M15), Short bei   |
//|     Close < RangeLow - MinBreakoutAtrMult*ATR(M15).              |
//|   Max. 1 Versuch/Tag (m_tradedToday wird SOFORT beim Ausbruchs-  |
//|     signal gesetzt, unabhaengig von einer spaeteren FilterStack/ |
//|     DrawdownGuard/ClusterRiskGuard-Ablehnung - "kein Retry nach  |
//|     Fehlausbruch").                                               |
//|   Stop:   ATR(M15)*AtrStopMult vom Entry-Close.                  |
//|   Ziel:   fester Broker-TP im Verhaeltnis RRMult (Default 1:2)  |
//|     zum Stop-Abstand - wird in EvaluateAndExecute() als echter   |
//|     TP an den Broker gesendet (CStrategySlot.useBrokerTP=true)   |
//|     und danach NICHT mehr verändert (CStrategySlot.manageEnabled |
//|     =false, kein Trailing/Teilgewinn, Spec Punkt 6/7).           |
//|   SessionRestricted() = false (hardcoded): die Range-/Entry-    |
//|   Fensterlogik IST bereits die Session-Einschraenkung - die      |
//|   generische 12-16-GMT-Overlap-Pruefung passt nicht.            |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALLONDONBREAKOUT_MQH__
#define __SWINGGOLD_SIGNALLONDONBREAKOUT_MQH__

#include "SignalModuleBase.mqh"
#include "TimeContext.mqh"

class CSignalLondonBreakout : public CSignalModuleBase
  {
private:
   int               m_rangeStartHour, m_rangeEndHour;   // GMT-Stunden, Default 8/13
   int               m_entryStartHour, m_entryEndHour;    // GMT-Stunden, Default 13/14
   double            m_atrStopMult;                       // Default 1.0
   double            m_rrMult;                             // Default 2.0
   double            m_minBreakoutAtrMult;                 // Default 0.0 (Puffer ueber Range-Kante)
   bool              m_disableFriday;                      // Default false
   CTimeContext      m_timeCtx;                             // eigene Instanz, nur GmtNow()

   //--- Range-Zustand (einmal/Tag gesetzt)
   double            m_rangeHigh, m_rangeLow;
   bool              m_rangeFrozen;
   bool              m_tradedToday;
   int               m_lastProcessedDay;   // year*10000+mon*100+day, Tageswechsel-Erkennung

   //+------------------------------------------------------------------+
   //| Tageswechsel (GMT-Datum) pruefen und bei Bedarf Range/Flags     |
   //| zuruecksetzen. dt wird vom Aufrufer einmalig ermittelt.         |
   //+------------------------------------------------------------------+
   void              CheckDayRollover(const MqlDateTime &dt)
     {
      int todayKey = dt.year * 10000 + dt.mon * 100 + dt.day;
      if(todayKey == m_lastProcessedDay)
         return;

      m_lastProcessedDay = todayKey;
      m_tradedToday       = false;
      m_rangeHigh         = -1.0;
      m_rangeLow          = DBL_MAX;
      m_rangeFrozen        = false;
     }

   //+------------------------------------------------------------------+
   //| Erweitert die laufende Range um die letzte geschlossene M15-   |
   //| Bar (shift=1).                                                   |
   //+------------------------------------------------------------------+
   void              UpdateRange(CMarketData &md)
     {
      double h, l;
      if(!md.GetHigh(PERIOD_M15, 1, h)) return;
      if(!md.GetLow(PERIOD_M15, 1, l))  return;

      if(h > m_rangeHigh) m_rangeHigh = h;
      if(l < m_rangeLow)  m_rangeLow  = l;
     }

   //+------------------------------------------------------------------+
   //| Prueft Breakout jenseits der eingefrorenen Range (Close[1]).   |
   //+------------------------------------------------------------------+
   bool              CheckBreakout(CMarketData &md, ENUM_SIGNAL_DIR &outDir, double &outClose)
     {
      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      double atr = md.GetAtrM15();
      double buf = m_minBreakoutAtrMult * atr;

      if(close1 > m_rangeHigh + buf)
        {
         outDir   = SIGNAL_LONG;
         outClose = close1;
         return true;
        }

      if(close1 < m_rangeLow - buf)
        {
         outDir   = SIGNAL_SHORT;
         outClose = close1;
         return true;
        }

      return false;
     }

   void              BuildProposal(const ENUM_SIGNAL_DIR dir, const double entryClose,
                                    const double atr, SignalProposal &outProposal)
     {
      double slDist = atr * m_atrStopMult;

      outProposal.Reset();
      outProposal.valid       = true;
      outProposal.dir         = dir;
      outProposal.entryPrice  = 0.0;
      outProposal.atrAtSignal = atr;
      outProposal.magic       = m_magic;

      if(dir == SIGNAL_LONG)
        {
         outProposal.stopPrice   = entryClose - slDist;
         outProposal.targetPrice = entryClose + m_rrMult * slDist;
         outProposal.reason      = StringFormat("London-Breakout Long: Close %.5f ueber Range-High %.5f",
                                                 entryClose, m_rangeHigh);
        }
      else
        {
         outProposal.stopPrice   = entryClose + slDist;
         outProposal.targetPrice = entryClose - m_rrMult * slDist;
         outProposal.reason      = StringFormat("London-Breakout Short: Close %.5f unter Range-Low %.5f",
                                                 entryClose, m_rangeLow);
        }

      PrintFormat("SignalLondonBreakout: ST_PENDING dir=%d rangeHigh=%.5f rangeLow=%.5f stop=%.5f target=%.5f",
                  dir, m_rangeHigh, m_rangeLow, outProposal.stopPrice, outProposal.targetPrice);
     }

public:
                     CSignalLondonBreakout(void):
                        CSignalModuleBase(),
                        m_rangeStartHour(8), m_rangeEndHour(13),
                        m_entryStartHour(13), m_entryEndHour(14),
                        m_atrStopMult(1.0), m_rrMult(2.0),
                        m_minBreakoutAtrMult(0.0),
                        m_disableFriday(false),
                        m_rangeHigh(-1.0), m_rangeLow(DBL_MAX),
                        m_rangeFrozen(false), m_tradedToday(false),
                        m_lastProcessedDay(0) {}

   void              Configure(const int rangeStartHour, const int rangeEndHour,
                                const int entryStartHour, const int entryEndHour,
                                const double atrStopMult, const double rrMult,
                                const double minBreakoutAtrMult, const bool disableFriday,
                                const int gmtOffsetWinter, const int gmtOffsetSummer,
                                const int magic)
     {
      m_rangeStartHour     = rangeStartHour;
      m_rangeEndHour       = rangeEndHour;
      m_entryStartHour     = entryStartHour;
      m_entryEndHour       = entryEndHour;
      m_atrStopMult        = atrStopMult;
      m_rrMult             = rrMult;
      m_minBreakoutAtrMult = minBreakoutAtrMult;
      m_disableFriday      = disableFriday;
      m_magic              = magic;

      //--- Overlap-/Wochentag-Parameter der eingebetteten Instanz ungenutzt,
      //--- nur GmtNow() wird gebraucht.
      m_timeCtx.Configure(gmtOffsetWinter, gmtOffsetSummer, 0, 0, 0, 0);
     }

   virtual string           Name(void)              const { return "SignalLondonBreakout"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;             }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;             }
   virtual bool             SessionRestricted(void) const { return false;                  }

   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state != ST_IDLE)
         return false;

      if(!md.IsM15Valid())
         return false;

      datetime gmt = m_timeCtx.GmtNow();
      MqlDateTime dt;
      TimeToStruct(gmt, dt);

      CheckDayRollover(dt);

      int dow  = dt.day_of_week; // 0=So, 1=Mo, ..., 5=Fr, 6=Sa
      int hour = dt.hour;

      //--- Freitag optional komplett deaktiviert (kein Range-/Entry-Aufbau, Spec Punkt 11)
      if(m_disableFriday && dow == 5)
         return false;

      //--- 1) Range-Fenster: laufend erweitern
      if(hour >= m_rangeStartHour && hour < m_rangeEndHour)
        {
         UpdateRange(md);
         return false;
        }

      //--- 2) Range einfrieren (einmalig, sobald das Range-Fenster vorbei ist)
      if(hour >= m_rangeEndHour && !m_rangeFrozen)
        {
         m_rangeFrozen = true;
         PrintFormat("SignalLondonBreakout: Range eingefroren High=%.5f Low=%.5f",
                     m_rangeHigh, m_rangeLow);
        }

      //--- 3) Entry-Fenster: Breakout-Check, max. 1 Versuch/Tag
      if(hour >= m_entryStartHour && hour < m_entryEndHour && m_rangeFrozen && !m_tradedToday)
        {
         if(m_rangeHigh <= 0.0 || m_rangeLow >= DBL_MAX)
            return false; // Range nie gebildet (z.B. Datenluecke) - kein Trade

         ENUM_SIGNAL_DIR breakoutDir;
         double          entryClose;
         if(!CheckBreakout(md, breakoutDir, entryClose))
            return false;

         //--- SOFORT setzen - unabhaengig davon, ob der Trade spaeter von
         //--- FilterStack/DrawdownGuard/ClusterRiskGuard abgelehnt wird
         //--- (Spec Punkt 5/9: kein Retry nach Fehlausbruch).
         m_tradedToday = true;

         m_dir = breakoutDir;
         BuildProposal(breakoutDir, entryClose, md.GetAtrM15(), outProposal);
         m_state = ST_PENDING;
         return true;
        }

      return false;
     }
  };

#endif // __SWINGGOLD_SIGNALLONDONBREAKOUT_MQH__
