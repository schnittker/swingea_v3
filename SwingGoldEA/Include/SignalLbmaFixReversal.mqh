//+------------------------------------------------------------------+
//|                                     SignalLbmaFixReversal.mqh    |
//|   Tier-3-Strategie (experimentell): LBMA-Fix-Reversal.          |
//|   Hypothese (knowledge.md Abschnitt 2, [Q]): die LBMA-Gold-Fixes|
//|   um 10:30 (AM) und 15:00 (PM) London-Zeit sind echte,          |
//|   handelbare Auktionen -> konzentrierter Orderfluss -> kurz-    |
//|   fristige Volatilitaet und Umkehrungen um die Fix-Zeitpunkte. |
//|   Es existiert KEINE dokumentierte Entry/Stop/Target-Regel in   |
//|   strategies.md/ea.md - die Mechanik unten ist eine eigene,     |
//|   aus der Kernidee abgeleitete Konstruktion, eng an das         |
//|   bestehende SignalLiquiditySweep-Muster angelehnt (Impuls ->   |
//|   Extrem -> Bestaetigung).                                       |
//|                                                                   |
//|   Zwei-Phasen-Logik:                                             |
//|   Phase 1 - Fix-Fenster + Pre-Fix-Lauf erkannt (ST_ARMED):      |
//|     In der M15-Fix-Bar: Bewegung Close[1+preFixBars]->Close[1]  |
//|     >= minMoveAtrMult*ATR(M15) -> Reversal in Gegenrichtung     |
//|     erwartet (Lauf rauf -> Short, Lauf runter -> Long).         |
//|   Phase 2 - Bestaetigung binnen confirmBars M15-Bars:           |
//|     Close muss um reversalAtrMult*ATR auf die Gegenseite des    |
//|     Fix-Bar-Closes gelaufen sein.                                |
//|                                                                   |
//|   Stop:   Fix-Bar-Extrem (High/Low) +/- atrStopMult*ATR(M15)    |
//|   Ziel:   Ausgangspunkt des Pre-Fix-Laufs (Close[1+preFixBars]) |
//|   Kein Cooldown-Counter: nur 2 Arm-Zeitpunkte/Tag, kein          |
//|   Overtrading-Risiko wie bei Sweep.                              |
//|   SessionRestricted() = false (hardcoded): die Fix-Fenster-      |
//|   Pruefung IST bereits die Session-Einschraenkung; die generische|
//|   12-16-GMT-Overlap-Pruefung passt semantisch nicht (AM-Fix     |
//|   liegt vor diesem Fenster).                                     |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALLBMAFIXREVERSAL_MQH__
#define __SWINGGOLD_SIGNALLBMAFIXREVERSAL_MQH__

#include "SignalModuleBase.mqh"
#include "TimeContext.mqh"

class CSignalLbmaFixReversal : public CSignalModuleBase
  {
private:
   bool              m_allowShort;
   double            m_atrStopMult;
   double            m_minMoveAtrMult;
   double            m_reversalAtrMult;
   int               m_preFixBars;
   int               m_confirmBars;
   int               m_fixAmHour, m_fixAmMinute;
   int               m_fixPmHour, m_fixPmMinute;
   CTimeContext      m_timeCtx;          // eigene, lokal konfigurierte Instanz (nur GmtNow()/IsEuDst())

   //--- gemerkte Werte des aktiven Setups
   double            m_fixExtreme;       // High/Low der Fix-Bar (Stop-Referenz)
   double            m_fixClose;         // Close der Fix-Bar (Bestaetigungs-Referenz)
   double            m_runStartPrice;    // Close vor dem Pre-Fix-Lauf (Retracement-Ziel)
   string            m_fixLabel;         // "AM-Fix" / "PM-Fix" (Journal/Log)
   int               m_confirmCounter;

   //+------------------------------------------------------------------+
   //| Ist "jetzt" (GMT, umgerechnet nach London-Zeit) innerhalb der    |
   //| M15-Bar, die den gegebenen Fix-Zeitpunkt enthaelt?               |
   //| UK-BST wird ueber die EU-DST-Erkennung angenaehert (ea.md 7.1   |
   //| dokumentiert UK/EU als synchron umschaltend, Stand aktueller    |
   //| Regelung).                                                        |
   //+------------------------------------------------------------------+
   bool              IsInFixBar(const int fixHour, const int fixMinute) const
     {
      datetime gmt = m_timeCtx.GmtNow();
      bool     bst = m_timeCtx.IsEuDst(gmt); // UK-BST ~ EU-DST angenaehert (ea.md 7.1)
      datetime london = gmt + (bst ? (datetime)3600 : (datetime)0);
      MqlDateTime dt;
      TimeToStruct(london, dt);
      return (dt.hour == fixHour && dt.min >= fixMinute && dt.min < fixMinute + 15);
     }

   //+------------------------------------------------------------------+
   //| Prueft Pre-Fix-Lauf und armiert bei ausreichender Bewegung.     |
   //| fixLabel: "AM-Fix" / "PM-Fix" fuer Journal/Log.                 |
   //+------------------------------------------------------------------+
   bool              CheckAndArm(CMarketData &md, const string fixLabel)
     {
      double atr = md.GetAtrM15();
      if(atr <= 0.0) return false;

      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      double openN, closeN;
      if(!md.GetBar(PERIOD_M15, 1 + m_preFixBars, openN, closeN)) return false;

      double move = close1 - closeN;
      if(MathAbs(move) < m_minMoveAtrMult * atr)
         return false; // Pre-Fix-Lauf zu klein

      double extreme;

      if(move > 0.0)
        {
         //--- Lauf rauf -> erwarteter Short
         if(!m_allowShort) return false;
         if(!md.GetHigh(PERIOD_M15, 1, extreme)) return false;

         m_dir = SIGNAL_SHORT;
        }
      else
        {
         //--- Lauf runter -> erwarteter Long
         if(!md.GetLow(PERIOD_M15, 1, extreme)) return false;

         m_dir = SIGNAL_LONG;
        }

      m_fixExtreme     = extreme;
      m_fixClose        = close1;
      m_runStartPrice   = closeN;
      m_fixLabel        = fixLabel;
      m_confirmCounter  = 0;
      m_state           = ST_ARMED;

      PrintFormat("SignalLbmaFixReversal: ST_ARMED %s dir=%d fixClose=%.5f fixExtreme=%.5f runStart=%.5f move=%.5f",
                  m_fixLabel, m_dir, m_fixClose, m_fixExtreme, m_runStartPrice, move);
      return true;
     }

   bool              CheckReversalConfirmed(CMarketData &md)
     {
      double atr = md.GetAtrM15();
      if(atr <= 0.0) return false;

      double open1, close1;
      if(!md.GetBar(PERIOD_M15, 1, open1, close1)) return false;

      if(m_dir == SIGNAL_SHORT) return (close1 < m_fixClose - m_reversalAtrMult * atr);
      if(m_dir == SIGNAL_LONG)  return (close1 > m_fixClose + m_reversalAtrMult * atr);
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
      outProposal.targetPrice = m_runStartPrice;

      if(m_dir == SIGNAL_LONG)
        {
         outProposal.stopPrice = m_fixExtreme - m_atrStopMult * atr;
         outProposal.reason    = StringFormat("LBMA %s Reversal Long: Umkehr nach Pre-Fix-Lauf", m_fixLabel);
        }
      else
        {
         outProposal.stopPrice = m_fixExtreme + m_atrStopMult * atr;
         outProposal.reason    = StringFormat("LBMA %s Reversal Short: Umkehr nach Pre-Fix-Lauf", m_fixLabel);
        }

      PrintFormat("SignalLbmaFixReversal: ST_PENDING %s dir=%d fixExtreme=%.5f stop=%.5f target=%.5f confirmBar=%d",
                  m_fixLabel, m_dir, m_fixExtreme, outProposal.stopPrice, outProposal.targetPrice, m_confirmCounter);
     }

public:
                     CSignalLbmaFixReversal(void):
                        CSignalModuleBase(),
                        m_allowShort(false),
                        m_atrStopMult(1.0),
                        m_minMoveAtrMult(0.5),
                        m_reversalAtrMult(0.3),
                        m_preFixBars(2),
                        m_confirmBars(3),
                        m_fixAmHour(10), m_fixAmMinute(30),
                        m_fixPmHour(15), m_fixPmMinute(0),
                        m_fixExtreme(0.0), m_fixClose(0.0),
                        m_runStartPrice(0.0), m_fixLabel(""),
                        m_confirmCounter(0) {}

   void              Configure(const bool allowShort, const double atrStopMult,
                                const double minMoveAtrMult, const double reversalAtrMult,
                                const int preFixBars, const int confirmBars,
                                const int fixAmHour, const int fixAmMinute,
                                const int fixPmHour, const int fixPmMinute,
                                const int gmtOffsetWinter, const int gmtOffsetSummer,
                                const int magic)
     {
      m_allowShort      = allowShort;
      m_atrStopMult     = atrStopMult;
      m_minMoveAtrMult  = minMoveAtrMult;
      m_reversalAtrMult = reversalAtrMult;
      m_preFixBars      = preFixBars;
      m_confirmBars     = confirmBars;
      m_fixAmHour       = fixAmHour;
      m_fixAmMinute     = fixAmMinute;
      m_fixPmHour       = fixPmHour;
      m_fixPmMinute     = fixPmMinute;
      m_magic           = magic;

      //--- Overlap-/Wochentag-Parameter der eingebetteten Instanz ungenutzt,
      //--- nur GmtNow()/IsEuDst() werden gebraucht.
      m_timeCtx.Configure(gmtOffsetWinter, gmtOffsetSummer, 0, 0, 0, 0);
     }

   virtual string           Name(void)              const { return "SignalLbmaFixReversal"; }
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const { return PERIOD_M15;              }
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const { return PERIOD_M15;              }
   virtual bool             SessionRestricted(void) const { return false;                   }

   virtual bool OnBar(CMarketData &md, SignalProposal &outProposal)
     {
      outProposal.Reset();

      if(m_state == ST_ARMED)
        {
         m_confirmCounter++;

         if(m_confirmCounter > m_confirmBars)
           {
            ResetToIdle("Reversal-Verfall");
            return false;
           }

         if(!md.IsM15Valid())
            return false;

         if(CheckReversalConfirmed(md))
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

         if(IsInFixBar(m_fixAmHour, m_fixAmMinute))
           {
            if(CheckAndArm(md, "AM-Fix"))
              {
               if(CheckReversalConfirmed(md))
                 {
                  BuildProposal(md, outProposal);
                  m_state = ST_PENDING;
                  return true;
                 }
               return false;
              }
           }
         else if(IsInFixBar(m_fixPmHour, m_fixPmMinute))
           {
            if(CheckAndArm(md, "PM-Fix"))
              {
               if(CheckReversalConfirmed(md))
                 {
                  BuildProposal(md, outProposal);
                  m_state = ST_PENDING;
                  return true;
                 }
               return false;
              }
           }
        }

      return false;
     }
  };

#endif // __SWINGGOLD_SIGNALLBMAFIXREVERSAL_MQH__
