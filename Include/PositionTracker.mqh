//+------------------------------------------------------------------+
//| PositionTracker.mqh                                              |
//| Haelt den Zustand pro (Strategie, Symbol) - max. 1 offene        |
//| Position je Kombination (kein Pyramiding). Re-Synct diesen        |
//| Zustand pro Tick gegen die tatsaechlichen Terminal-Positionen     |
//| ueber das Magic-Number-Schema, damit externe Aenderungen (SL/TP- |
//| Hit, manuelles Schliessen) zuverlaessig erkannt werden.           |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "MagicNumbers.mqh"

//--- Es gibt genau 3 Strategien (siehe ENUM_STRATEGY_ID). Fix, da
//--- Teil des Index-Schemas dieses Trackers.
#define POSITION_TRACKER_STRATEGY_COUNT 3

//+------------------------------------------------------------------+
//| Array-Index fuer eine (Strategie, Symbol)-Kombination.           |
//+------------------------------------------------------------------+
int PositionTrackerIndex(const ENUM_STRATEGY_ID strategyId, const int symbolIndex, const int numSymbols)
  {
   int strategyOffset = (int)strategyId - 1; // STRATEGY_SESSION_BREAKOUT=1 -> Offset 0
   if(strategyOffset < 0 || strategyOffset >= POSITION_TRACKER_STRATEGY_COUNT)
      return -1;
   if(symbolIndex < 0 || symbolIndex >= numSymbols)
      return -1;
   return strategyOffset * numSymbols + symbolIndex;
  }

//+------------------------------------------------------------------+
//| Initialisiert/dimensioniert das Tracking-Array fuer numSymbols   |
//| Symbole x 3 Strategien.                                           |
//+------------------------------------------------------------------+
void InitPositionTracker(SStrategyPosition &positions[], const int numSymbols)
  {
   int total = POSITION_TRACKER_STRATEGY_COUNT * numSymbols;
   ArrayResize(positions, total);
   for(int i = 0; i < total; i++)
     {
      positions[i].isOpen      = false;
      positions[i].ticket      = 0;
      positions[i].strategyId  = STRATEGY_NONE;
      positions[i].symbolIndex = -1;
      positions[i].direction   = SIGNAL_NONE;
      positions[i].volume      = 0.0;
      positions[i].openPrice   = 0.0;
      positions[i].slPrice     = 0.0;
      positions[i].tpPrice     = 0.0;
      positions[i].openTime    = 0;
     }
  }

//+------------------------------------------------------------------+
//| Gleicht das Tracking-Array mit den tatsaechlich offenen Terminal-|
//| Positionen ab. Positionen mit fremder/unbekannter Magic-Number   |
//| (anderer EA, manueller Trade) werden ignoriert. Slots, deren     |
//| Position nicht mehr existiert (SL/TP-Hit, manuell geschlossen),  |
//| werden auf isOpen=false zurueckgesetzt.                          |
//+------------------------------------------------------------------+
void SyncPositionTracker(SStrategyPosition &positions[], const int numSymbols)
  {
   int total = ArraySize(positions);
   bool stillOpen[];
   ArrayResize(stillOpen, total);
   for(int i = 0; i < total; i++)
      stillOpen[i] = false;

   int posTotal = PositionsTotal();
   for(int p = 0; p < posTotal; p++)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      ENUM_STRATEGY_ID sid;
      int symIdx;
      if(!MagicDecode(magic, numSymbols, sid, symIdx))
         continue; // fremde Magic-Number oder SymbolIndex ausserhalb der aktiven Symbole

      int idx = PositionTrackerIndex(sid, symIdx, numSymbols);
      if(idx < 0 || idx >= total)
         continue;

      positions[idx].isOpen      = true;
      positions[idx].ticket      = ticket;
      positions[idx].strategyId  = sid;
      positions[idx].symbolIndex = symIdx;
      positions[idx].direction   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      positions[idx].volume      = PositionGetDouble(POSITION_VOLUME);
      positions[idx].openPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
      positions[idx].slPrice     = PositionGetDouble(POSITION_SL);
      positions[idx].tpPrice     = PositionGetDouble(POSITION_TP);
      positions[idx].openTime    = (datetime)PositionGetInteger(POSITION_TIME);

      stillOpen[idx] = true;
     }

   for(int i = 0; i < total; i++)
     {
      if(positions[i].isOpen && !stillOpen[i])
         positions[i].isOpen = false; // extern geschlossen seit letztem Sync
     }
  }

//+------------------------------------------------------------------+
//| true, wenn fuer diese (Strategie, Symbol)-Kombination bereits    |
//| eine Position offen ist (Pyramiding-Schutz).                     |
//+------------------------------------------------------------------+
bool HasOpenPosition(SStrategyPosition &positions[], const ENUM_STRATEGY_ID strategyId,
                      const int symbolIndex, const int numSymbols)
  {
   int idx = PositionTrackerIndex(strategyId, symbolIndex, numSymbols);
   if(idx < 0 || idx >= ArraySize(positions))
      return false;
   return positions[idx].isOpen;
  }

//+------------------------------------------------------------------+
