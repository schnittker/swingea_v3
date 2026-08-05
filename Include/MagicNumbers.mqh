//+------------------------------------------------------------------+
//| MagicNumbers.mqh                                                 |
//| Encode/Decode von Magic-Numbers <-> (StrategyID, SymbolIndex).   |
//|                                                                    |
//| Schema: MagicNumber = 10000 + StrategyID * 100 + SymbolIndex      |
//|   StrategyID: 1=SessionBreakout, 2=Donchian, 3=MeanReversion      |
//|   SymbolIndex: 0-4 = Index in InpSymbols[]                        |
//|                                                                    |
//| Granularitaet pro Strategie+Symbol ist notwendig, weil auf einem  |
//| Hedge-Konto mehrere Strategien gegenlaeufige Positionen im selben |
//| Symbol halten koennen - reines Symbol-Filtern reicht dann nicht   |
//| aus, um eine Position beim Force-Close/Trailing/Risk-Guard        |
//| zweifelsfrei einer Strategie zuzuordnen.                          |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"

#define MAGIC_BASE           10000
#define MAGIC_STRATEGY_MULT  100
#define MAGIC_MAX_SYMBOL_IDX 99   // MAGIC_STRATEGY_MULT - 1

//+------------------------------------------------------------------+
//| Baut eine Magic-Number aus StrategyID und SymbolIndex.           |
//+------------------------------------------------------------------+
int MagicEncode(const ENUM_STRATEGY_ID strategyId, const int symbolIndex)
  {
   if(symbolIndex < 0 || symbolIndex > MAGIC_MAX_SYMBOL_IDX)
     {
      Print("MagicEncode: ungueltiger symbolIndex=", symbolIndex);
      return -1;
     }
   return MAGIC_BASE + ((int)strategyId * MAGIC_STRATEGY_MULT) + symbolIndex;
  }

//+------------------------------------------------------------------+
//| Zerlegt eine Magic-Number in StrategyID und SymbolIndex.         |
//| Gibt false zurueck, wenn die Magic-Number nicht aus diesem EA    |
//| stammt (z.B. anderer EA / manueller Trade) oder auf einen        |
//| SymbolIndex ausserhalb der aktuell aktiven Symbole [0,numSymbols)|
//| zeigt (z.B. Alt-Position aus einem Lauf mit mehr Symbolen). Ohne |
//| diese Grenzpruefung wuerde eine solche Position als "eigen"      |
//| akzeptiert, aber vom PositionTracker verworfen (Index -1) - sie  |
//| bliebe damit ungetrackt und wuerde nie force-geschlossen.        |
//+------------------------------------------------------------------+
bool MagicDecode(const long magic, const int numSymbols,
                 ENUM_STRATEGY_ID &outStrategyId, int &outSymbolIndex)
  {
   long rest = magic - MAGIC_BASE;
   if(rest < 0)
      return false;

   int strategyRaw = (int)(rest / MAGIC_STRATEGY_MULT);
   int symbolIndex  = (int)(rest % MAGIC_STRATEGY_MULT);

   if(strategyRaw != (int)STRATEGY_SESSION_BREAKOUT &&
      strategyRaw != (int)STRATEGY_DONCHIAN &&
      strategyRaw != (int)STRATEGY_MEAN_REVERSION)
      return false;

   if(symbolIndex < 0 || symbolIndex >= numSymbols)
      return false;

   outStrategyId  = (ENUM_STRATEGY_ID)strategyRaw;
   outSymbolIndex = symbolIndex;
   return true;
  }

//+------------------------------------------------------------------+
