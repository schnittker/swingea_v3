//+------------------------------------------------------------------+
//|                                                  FilterStack.mqh |
//|   Veto-Schichten fuer eine SignalProposal. Ein Filter kann einen |
//|   Trade nur ablehnen, nie auslösen (ea.md 2.5). Phase 1 enthaelt |
//|   ausschliesslich den Spread-Filter; das Interface ist so        |
//|   gehalten, dass Phase 2 weitere Layer anhaengen kann, ohne die  |
//|   Call-Sites zu aendern.                                          |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_FILTERSTACK_MQH__
#define __SWINGGOLD_FILTERSTACK_MQH__

#include "Types.mqh"

class CFilterStack
  {
private:
   string            m_symbol;
   bool              m_useSpreadFilter;
   int               m_maxSpreadPoints;

public:
                     CFilterStack(void):
                        m_symbol(""), m_useSpreadFilter(true), m_maxSpreadPoints(50) {}

   void              Configure(const string symbol, const bool useSpreadFilter, const int maxSpreadPoints)
     {
      m_symbol          = symbol;
      m_useSpreadFilter = useSpreadFilter;
      m_maxSpreadPoints = maxSpreadPoints;
     }

   //+------------------------------------------------------------------+
   //| Prueft die uebergebene Proposal gegen alle aktiven Filter.       |
   //| Rueckgabe true = akzeptiert, false = abgelehnt (outReason gefuellt).|
   //+------------------------------------------------------------------+
   bool              Evaluate(const SignalProposal &proposal, string &outReason)
     {
      outReason = "";

      if(!proposal.valid)
        {
         outReason = "Proposal ungueltig";
         return false;
        }

      if(m_useSpreadFilter)
        {
         long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
         if(spreadPoints > m_maxSpreadPoints)
           {
            outReason = StringFormat("Spread %d > InpMaxSpreadPoints %d", spreadPoints, m_maxSpreadPoints);
            return false;
           }
        }

      return true;
     }
  };

#endif // __SWINGGOLD_FILTERSTACK_MQH__
