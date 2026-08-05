//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|            Basis-Datentypen und Konstanten fuer den TrendMomentumEA |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_TYPES_MQH__
#define __TRENDMOMENTUM_TYPES_MQH__

//--- Ziel-Richtung eines Symbols aus dem TSMOM-Signal
enum ENUM_SIGNAL_DIR
  {
   SIGNAL_FLAT = 0,   // keine Position gewuenscht
   SIGNAL_LONG = 1,   // Long gewuenscht
   SIGNAL_SHORT= -1   // Short gewuenscht
  };

//--- Pro-Symbol-Zustand: Handles + zuletzt berechnete Kennzahlen.
//    Wird einmal in OnInit befuellt und beim Rebalancing aktualisiert.
//    Als class (nicht struct) definiert, weil der SymbolManager Pointer
//    darauf ausgibt und GetPointer() in MQL5 nur fuer Klassen zulaessig ist.
class SymbolState
  {
public:
   string            name;         // Symbolname wie beim Broker
   bool              valid;        // Symbol im MarketWatch verfuegbar & selektiert
   int               maFastHandle; // Handle schnelle MA (Daily)
   int               maSlowHandle; // Handle langsame MA (Daily)
   int               atrHandle;    // Handle ATR (Daily) fuer Vola-Sizing
   ENUM_SIGNAL_DIR   targetDir;    // aktuell gewuenschte Richtung
   double            atr;          // letzter ATR-Wert (Preis-Einheiten)
   double            stopDistance; // SL-Abstand in Preis-Einheiten
  };

#endif // __TRENDMOMENTUM_TYPES_MQH__
