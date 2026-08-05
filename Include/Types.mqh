//+------------------------------------------------------------------+
//| Types.mqh                                                        |
//| Gemeinsame Structs/Enums fuer den Portfolio-EA.                  |
//| Reine Datenstrukturen, keine Logik, keine Abhaengigkeiten.       |
//+------------------------------------------------------------------+
#property strict

//--- Strategie-IDs. Werte sind fix, da sie Teil des Magic-Number-
//--- Schemas sind (siehe MagicNumbers.mqh). Nicht umsortieren!
enum ENUM_STRATEGY_ID
  {
   STRATEGY_NONE             = 0,
   STRATEGY_SESSION_BREAKOUT = 1,
   STRATEGY_DONCHIAN         = 2,
   STRATEGY_MEAN_REVERSION   = 3
  };

//--- Signalrichtung, wie sie ein Signal-Modul liefert.
enum ENUM_SIGNAL_DIR
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
  };

//--- Ergebnis eines Signal-Moduls: Ob und wie eroeffnet werden soll.
//--- SL/TP sind bereits absolute Preise (nicht Pips), damit jedes
//--- Signal-Modul seine eigene Preislogik (Range, Band, ATR) kapselt.
struct SSignal
  {
   ENUM_SIGNAL_DIR   direction;      // SIGNAL_NONE = kein Trade
   double            entryPrice;     // Referenzpreis fuer Order (Market)
   double            slPrice;        // absoluter Stop-Loss-Preis
   double            tpPrice;        // absoluter Take-Profit-Preis (0 = kein TP)
   string            reason;         // kurzer Debug-Text fuer Logs
  };

//--- Laufender Zustand einer offenen Position pro (Strategie, Symbol).
//--- Wird vom PositionTracker gepflegt und ueber Ticket referenziert,
//--- da auf einem Hedge-Konto mehrere Positionen im selben Symbol
//--- parallel existieren koennen.
struct SStrategyPosition
  {
   bool              isOpen;         // true = Position aktuell offen
   ulong             ticket;         // Positions-Ticket
   ENUM_STRATEGY_ID  strategyId;
   int               symbolIndex;    // Index in InpSymbols[]
   ENUM_SIGNAL_DIR   direction;
   double            volume;         // Lots
   double            openPrice;
   double            slPrice;        // aktueller (nicht urspruenglicher) SL
   double            tpPrice;
   datetime          openTime;
  };

//+------------------------------------------------------------------+
