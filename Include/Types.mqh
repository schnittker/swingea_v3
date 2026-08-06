//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|   Gemeinsame Enums/Klassen fuer den SwingGoldEA.                 |
//|   Reine Datenstrukturen, keine Logik, keine Abhaengigkeiten.     |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_TYPES_MQH__
#define __SWINGGOLD_TYPES_MQH__

//--- Signalrichtung, wie sie ein Signal-Modul liefert.
enum ENUM_SIGNAL_DIR
  {
   SIGNAL_FLAT  = 0,   // keine Position gewuenscht
   SIGNAL_LONG  = 1,   // Long gewuenscht
   SIGNAL_SHORT = -1   // Short gewuenscht
  };

//--- Zustand der Dip-Buy-Setup-State-Machine (ea.md Abschnitt 5).
enum ENUM_SETUP_STATE
  {
   ST_IDLE = 0,        // kein Bias/Setup erkannt
   ST_ARMED,           // Zone definiert, Preis noch nicht in der Zone
   ST_WAIT_TRIGGER,    // Preis in der Zone, wartet auf Trigger-Kerze
   ST_PENDING,         // Order gesendet, wartet auf Fill
   ST_IN_POSITION,     // Position offen, TradeManager uebernimmt
   ST_BLOCKED          // FilterStack-Veto (nur fuer Log, faellt danach auf ST_IDLE zurueck)
  };

//--- Vorschlag eines Signalmoduls - noch ohne Lots, ohne Filterpruefung.
//--- Als class (nicht struct) definiert, damit sie per Referenz durch
//--- FilterStack/RiskManager/TradeExecution gereicht werden kann, ohne
//--- dass MQL5 bei jeder Uebergabe eine Kopie der Strings erzwingt.
class SignalProposal
  {
public:
   bool              valid;
   ENUM_SIGNAL_DIR   dir;
   double            entryPrice;     // 0 = Market
   double            stopPrice;      // Pflicht, nie 0
   double            targetPrice;    // 0 = kein Fix-TP (Trailing)
   double            atrAtSignal;    // fuer Sizing und Telemetrie
   int               magic;          // Herkunftsmodul
   string            reason;         // Klartext fuer DecisionLog

                     SignalProposal(void):
                        valid(false), dir(SIGNAL_FLAT), entryPrice(0.0),
                        stopPrice(0.0), targetPrice(0.0), atrAtSignal(0.0),
                        magic(0), reason("") {}

   //--- Setzt alle Felder auf den ungueltigen Ausgangszustand zurueck.
   void              Reset(void)
     {
      valid       = false;
      dir         = SIGNAL_FLAT;
      entryPrice  = 0.0;
      stopPrice   = 0.0;
      targetPrice = 0.0;
      atrAtSignal = 0.0;
      magic       = 0;
      reason      = "";
     }
  };

#endif // __SWINGGOLD_TYPES_MQH__
