//+------------------------------------------------------------------+
//| PortfolioRiskGuard.mqh                                           |
//| Gesamt-Risikobudget ueber alle offenen Positionen als BRUTTO-    |
//| Exposure (nicht Netto): zwei gegenlaeufige Positionen im selben  |
//| Symbol heben sich im Richtungsrisiko auf, aber nicht im Stop-    |
//| Loss-Risiko - bei einem Whipsaw koennen beide unabhaengig         |
//| ausgestoppt werden. Netting wuerde das Budget faelschlich als    |
//| "0% Risiko" ausweisen.                                            |
//|                                                                    |
//| RiskAmount_p wird live aus der AKTUELLEN SL-Position berechnet   |
//| (nicht der urspruenglichen) - Trailing/Breakeven reduziert damit  |
//| automatisch das gebundene Budget.                                 |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "SymbolUtils.mqh"

//+------------------------------------------------------------------+
//| Risikobetrag (Kontowaehrung) fuer eine Lot-Groesse bei gegebener |
//| Entry/SL-Distanz. Basis fuer offene Positionen wie auch fuer die |
//| Vorab-Schaetzung eines noch zu eroeffnenden Trades.              |
//+------------------------------------------------------------------+
double RiskAmountFromLots(const string symbol, const double volume,
                           const double entryPrice, const double slPrice)
  {
   if(volume <= 0.0)
      return 0.0;

   double slDistancePips = PriceDistanceToPips(symbol, entryPrice - slPrice);
   double pipValuePerLot = GetPipValuePerLot(symbol);
   return slDistancePips * pipValuePerLot * volume;
  }

//+------------------------------------------------------------------+
//| Risikobetrag (Kontowaehrung) einer einzelnen offenen Position,   |
//| basierend auf Abstand Entry <-> aktueller SL. Eine offene        |
//| Position ohne gueltigen SL (extern entfernt) traegt theoretisch  |
//| unbegrenztes Risiko - sie wird daher bewusst NICHT als 0, sondern |
//| konservativ mit dem vollen Positionswert (Entry x PipValue x Lot |
//| ueber die gesamte Entry-Distanz) angesetzt, damit der Guard nicht |
//| ein zu grosses Budget freigibt.                                   |
//+------------------------------------------------------------------+
double CalculatePositionRiskAmount(const SStrategyPosition &position, const string symbol)
  {
   if(!position.isOpen)
      return 0.0;

   if(position.slPrice <= 0.0)
     {
      // Kein SL vorhanden: konservativ das gesamte Exposure bis Preis 0 ansetzen.
      double pipValuePerLot = GetPipValuePerLot(symbol);
      double entryPips      = PriceDistanceToPips(symbol, position.openPrice);
      return entryPips * pipValuePerLot * position.volume;
     }

   // Referenzpreis ist der AKTUELLE Marktpreis, mit dem die Position beim SL-Hit
   // glattgestellt wuerde (BUY schliesst zum Bid, SELL zum Ask), NICHT der Entry.
   // Nur so gibt ein ueber den Entry hinaus nachgezogener Trailing-/Breakeven-SL
   // (Position im Gewinn) das gebundene Budget korrekt frei; mit dem Entry als
   // Bezug bliebe faelschlich |Entry - SL| als Risiko stehen. Liegt der SL bereits
   // im Gewinn (kein Restverlust moeglich), ist das Risiko 0.
   double refPrice = (position.direction == SIGNAL_BUY)
      ? SymbolInfoDouble(symbol, SYMBOL_BID)
      : SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(refPrice <= 0.0)
      refPrice = position.openPrice; // Fallback, falls kein gueltiger Tick vorliegt

   bool slInProfit = (position.direction == SIGNAL_BUY)
      ? (position.slPrice >= refPrice)
      : (position.slPrice <= refPrice);
   if(slInProfit)
      return 0.0;

   return RiskAmountFromLots(symbol, position.volume, refPrice, position.slPrice);
  }

//+------------------------------------------------------------------+
//| Aktuell gebundenes Brutto-Risiko ueber alle offenen Positionen,  |
//| als Prozent des aktuellen Equity.                                 |
//+------------------------------------------------------------------+
double CalculateGrossRiskUsedPercent(const SStrategyPosition &positions[], const string &symbols[],
                                      const double equity)
  {
   if(equity <= 0.0)
      return 0.0;

   double totalRiskAmount = 0.0;
   for(int i = 0; i < ArraySize(positions); i++)
     {
      if(!positions[i].isOpen)
         continue;
      string symbol = symbols[positions[i].symbolIndex];
      totalRiskAmount += CalculatePositionRiskAmount(positions[i], symbol);
     }

   return (totalRiskAmount / equity) * 100.0;
  }

//+------------------------------------------------------------------+
//| true, wenn eine neue Position mit newTradeRiskPercent noch in    |
//| das Portfolio-Risikobudget passt (InpMaxPortfolioRiskPercent,    |
//| Default-Korridor 3-5%).                                          |
//|                                                                    |
//| pendingRiskPercent: Risiko-% von Positionen, die im SELBEN Tick  |
//| bereits eroeffnet, aber vom PositionTracker noch nicht resynct    |
//| wurden. Ohne diesen Term koennten mehrere Signale in einem Tick  |
//| den Cap gemeinsam ueberschreiten, weil jedes fuer sich nur gegen  |
//| den (veralteten) Tracker-Stand prueft.                            |
//+------------------------------------------------------------------+
bool CanOpenNewPosition(const SStrategyPosition &positions[], const string &symbols[],
                         const double equity, const double newTradeRiskPercent,
                         const double maxPortfolioRiskPercent,
                         const double pendingRiskPercent = 0.0)
  {
   double currentUsedPercent = CalculateGrossRiskUsedPercent(positions, symbols, equity);
   return (currentUsedPercent + pendingRiskPercent + newTradeRiskPercent) <= maxPortfolioRiskPercent;
  }

//+------------------------------------------------------------------+
