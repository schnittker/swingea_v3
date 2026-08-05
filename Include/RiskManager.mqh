//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| Equity-% -> Lotgroesse, mit zwei Schutzmechanismen gegen die     |
//| aus dem Vorprojekt bekannte Lot-Explosion bei zu engem SL:       |
//|   1) EnforceMinSLDistance() - VOR der Lotberechnung, drueckt den |
//|      SL auf eine Mindestdistanz (>= 15x Friktion) nach aussen.  |
//|   2) CapLotSize()          - NACH der Lotberechnung, hartes Cap  |
//|      auf InpMaxLotPerTrade + Broker-Limits (SYMBOL_VOLUME_MAX).  |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "SymbolUtils.mqh"

//+------------------------------------------------------------------+
//| Erzwingt eine Mindest-SL-Distanz. Wenn der uebergebene SL naeher |
//| am Entry liegt als minSLDistancePips, wird er auf die Mindest-   |
//| distanz nach aussen (vom Entry weg) verschoben. Ein bereits      |
//| weiter entfernter SL wird NICHT verengt.                         |
//+------------------------------------------------------------------+
void EnforceMinSLDistance(const string symbol,
                           const ENUM_SIGNAL_DIR direction,
                           const double entryPrice,
                           double &slPrice,
                           const double minSLDistancePips)
  {
   if(direction == SIGNAL_NONE || minSLDistancePips <= 0.0)
      return;

   double minDistancePrice = PipsToPriceDistance(symbol, minSLDistancePips);
   double currentDistance  = MathAbs(entryPrice - slPrice);

   if(currentDistance >= minDistancePrice)
      return; // bereits ausreichend weit entfernt, nicht verengen

   if(direction == SIGNAL_BUY)
      slPrice = entryPrice - minDistancePrice;
   else // SIGNAL_SELL
      slPrice = entryPrice + minDistancePrice;

   slPrice = NormalizePriceToTick(symbol, slPrice);
  }

//+------------------------------------------------------------------+
//| Rundet ein Lot-Volumen auf den erlaubten Volume-Step des Symbols |
//| und begrenzt es auf [SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX].     |
//+------------------------------------------------------------------+
double NormalizeVolume(const string symbol, double volume)
  {
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step > 0.0)
      volume = MathFloor(volume / step + 1e-8) * step;

   if(volume < minVol)
      volume = minVol;
   if(volume > maxVol)
      volume = maxVol;

   return NormalizeDouble(volume, 2);
  }

//+------------------------------------------------------------------+
//| Berechnet die Lotgroesse aus Equity, Risiko-% und SL-Distanz.    |
//| Erwartet, dass slPrice bereits durch EnforceMinSLDistance() auf  |
//| eine sichere Mindestdistanz gebracht wurde - diese Funktion      |
//| selbst nimmt keine Distanzkorrektur vor.                          |
//+------------------------------------------------------------------+
double CalculateLotSize(const string symbol,
                         const double equity,
                         const double riskPercent,
                         const double entryPrice,
                         const double slPrice)
  {
   double slDistancePips = PriceDistanceToPips(symbol, entryPrice - slPrice);
   if(slDistancePips <= 0.0)
     {
      Print("CalculateLotSize: SL-Distanz <= 0 fuer ", symbol, " - kein Trade.");
      return 0.0;
     }

   double pipValuePerLot = GetPipValuePerLot(symbol);
   if(pipValuePerLot <= 0.0)
     {
      Print("CalculateLotSize: PipValuePerLot <= 0 fuer ", symbol, " - kein Trade.");
      return 0.0;
     }

   double riskAmount = equity * (riskPercent / 100.0);
   double rawLots    = riskAmount / (slDistancePips * pipValuePerLot);

   return NormalizeVolume(symbol, rawLots);
  }

//+------------------------------------------------------------------+
//| Hartes Cap NACH der Lotberechnung: begrenzt auf maxLotPerTrade   |
//| (Input) und normalisiert erneut auf Symbol-Limits/Step. Letzte  |
//| Verteidigungslinie gegen Fehler in der Distanzberechnung.        |
//+------------------------------------------------------------------+
double CapLotSize(const string symbol, const double lots, const double maxLotPerTrade)
  {
   double capped = lots;
   if(maxLotPerTrade > 0.0 && capped > maxLotPerTrade)
      capped = maxLotPerTrade;

   return NormalizeVolume(symbol, capped);
  }

//+------------------------------------------------------------------+
