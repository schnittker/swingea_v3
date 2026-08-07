//+------------------------------------------------------------------+
//|                                            SignalModuleBase.mqh  |
//|   Abstrakte Basisklasse fuer alle Signalmodule. Enthaelt die     |
//|   gemeinsame State Machine (aus SignalDipBuy hochgezogen) und    |
//|   vier pure-virtual-Methoden, die jedes Modul implementieren    |
//|   muss.                                                           |
//|                                                                   |
//|   WICHTIG (Hazard H1): const-Qualifier der Methoden muessen in  |
//|   den abgeleiteten Klassen VERBATIM uebernommen werden. Ein     |
//|   fehlender const erzeugt in MQL5 stillschweigend eine          |
//|   Ueberladung statt eines Overrides — Aufrufe ueber             |
//|   CSignalModuleBase* landen dann in der Basis (kein Kompiler-   |
//|   Fehler, falsches Laufzeitverhalten).                           |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_SIGNALMODULEBASE_MQH__
#define __SWINGGOLD_SIGNALMODULEBASE_MQH__

#include "Types.mqh"
#include "MarketData.mqh"

class CSignalModuleBase
  {
protected:
   ENUM_SETUP_STATE  m_state;
   ENUM_SIGNAL_DIR   m_dir;
   int               m_magic;
   double            m_targetPrice;

   //--- Zurueck zu IDLE; kann von abgeleiteten Klassen gerufen werden.
   void              ResetToIdle(const string logReason)
     {
      PrintFormat("%s: ST_IDLE (%s)", Name(), logReason);
      m_state = ST_IDLE;
      m_dir   = SIGNAL_FLAT;
     }

public:
                     CSignalModuleBase(void):
                        m_state(ST_IDLE), m_dir(SIGNAL_FLAT), m_magic(0), m_targetPrice(0.0) {}

   virtual          ~CSignalModuleBase(void) {}

   //+------------------------------------------------------------------+
   //| Pure virtuals — jede abgeleitete Klasse MUSS diese mit exakt    |
   //| diesen Signaturen (inkl. const) implementieren.                 |
   //+------------------------------------------------------------------+
   virtual string           Name(void)              const = 0;
   virtual ENUM_TIMEFRAMES  TriggerTimeframe(void)  const = 0;  // PERIOD_H4 | PERIOD_M15
   virtual ENUM_TIMEFRAMES  AtrTimeframe(void)      const = 0;  // PERIOD_D1 | PERIOD_M15
   virtual bool             SessionRestricted(void) const = 0;  // false = kein Session-Zwang

   //--- Hauptmethode: wird pro neuer Bar des jeweiligen TriggerTimeframe
   //--- aufgerufen, solange keine eigene Position offen ist.
   virtual bool             OnBar(CMarketData &md, SignalProposal &outProposal) = 0;

   //+------------------------------------------------------------------+
   //| Konkrete State-Machine-Methoden (aus SignalDipBuy hochgezogen). |
   //| Signaturen VERBATIM beibehalten.                                 |
   //+------------------------------------------------------------------+
   ENUM_SETUP_STATE  GetState(void)      const { return m_state;       }
   ENUM_SIGNAL_DIR   GetDir(void)        const { return m_dir;         }
   double            GetTargetPrice(void) const { return m_targetPrice; }

   void              NotifyFilled(void)
     {
      m_state = ST_IN_POSITION;
     }

   void              NotifyOrderFailed(void)
     {
      ResetToIdle("Order fehlgeschlagen");
     }

   void              NotifyFilterVeto(void)
     {
      m_state = ST_BLOCKED;
      ResetToIdle("FilterStack-Veto");
     }

   void              NotifyPositionClosed(void)
     {
      ResetToIdle("Position geschlossen");
     }

   //--- Nach Neustart/Reattach: Zustand aus vorhandener Position
   //--- rekonstruieren. dir kommt aus der tatsaechlichen Broker-Position.
   void              SyncInPosition(const ENUM_SIGNAL_DIR dir)
     {
      m_dir   = dir;
      m_state = ST_IN_POSITION;
     }
  };

#endif // __SWINGGOLD_SIGNALMODULEBASE_MQH__
