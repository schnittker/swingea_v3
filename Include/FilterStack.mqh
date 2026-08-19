//+------------------------------------------------------------------+
//|                                                  FilterStack.mqh |
//|   Veto-Schichten fuer eine SignalProposal. Ein Filter kann einen |
//|   Trade nur ablehnen, nie ausloesen (ea.md 2.5). Jede Schicht  |
//|   ist einzeln abschaltbar (ea.md 4.7 — Voraussetzung fuer die   |
//|   A/B-Hypothesen-Tests in ea.md 8.1).                           |
//|                                                                   |
//|   Session- und Wochentag-Filter werden nur geprueft, wenn das   |
//|   Modul session-beschraenkt ist (sessionRestricted=true) und    |
//|   der jeweilige Filter aktiv ist. Der Swing-Pfad bleibt dadurch |
//|   unveraendert (plan Verhaltensgleichheit-Check 1).             |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_FILTERSTACK_MQH__
#define __SWINGGOLD_FILTERSTACK_MQH__

#include "Types.mqh"
#include "TimeContext.mqh"

class CFilterStack
  {
private:
   string            m_symbol;
   bool              m_useSpreadFilter;
   int               m_maxSpreadPoints;
   bool              m_useSessionFilter;
   bool              m_useWeekdayFilter;

public:
                     CFilterStack(void):
                        m_symbol(""), m_useSpreadFilter(true), m_maxSpreadPoints(50),
                        m_useSessionFilter(true), m_useWeekdayFilter(true) {}

   void              Configure(const string symbol,
                               const bool useSpreadFilter, const int maxSpreadPoints,
                               const bool useSessionFilter, const bool useWeekdayFilter)
     {
      m_symbol           = symbol;
      m_useSpreadFilter  = useSpreadFilter;
      m_maxSpreadPoints  = maxSpreadPoints;
      m_useSessionFilter = useSessionFilter;
      m_useWeekdayFilter = useWeekdayFilter;
     }

   //+------------------------------------------------------------------+
   //| Prueft die uebergebene Proposal gegen alle aktiven Filter.      |
   //| sessionRestricted: true = Session/Wochentag-Filter anwenden     |
   //|                    (nur fuer Overlap-Modul, ea.md 4.7).        |
   //| timeCtx: Zeitkontext (fuer Session + Wochentag-Check).          |
   //| Rueckgabe true = akzeptiert, false = abgelehnt (outReason).    |
   //+------------------------------------------------------------------+
   bool              Evaluate(const SignalProposal &proposal,
                              const bool sessionRestricted,
                              const CTimeContext &timeCtx,
                              const bool newsBlackout,
                              string &outReason)
     {
      outReason = "";

      if(!proposal.valid)
        {
         outReason = "Proposal ungueltig";
         return false;
        }

      //--- 1. Spread-Filter
      if(m_useSpreadFilter)
        {
         long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
         if(spreadPoints > m_maxSpreadPoints)
           {
            outReason = StringFormat("Spread %d > InpMaxSpreadPoints %d", spreadPoints, m_maxSpreadPoints);
            return false;
           }
        }

      //--- NewsGuard-Blackout: gilt fuer ALLE Module, nicht nur session-beschraenkte
      //--- (E8 One verbietet neue Orders 5 Min vor/nach High-Impact-News).
      if(newsBlackout)
        {
         outReason = "NewsGuard: Blackout-Fenster aktiv";
         return false;
        }

      //--- 2+3. Session/Wochentag: NUR fuer session-beschraenkte Module
      if(sessionRestricted)
        {
         if(m_useWeekdayFilter && !timeCtx.IsWeekdayAllowed())
           {
            outReason = "WeekdayFilter: Montag/Freitag/Wochenende gesperrt";
            return false;
           }

         if(m_useSessionFilter && !timeCtx.IsInOverlapWindow())
           {
            outReason = "SessionFilter: ausserhalb Overlap-Fenster (12:00-16:00 GMT)";
            return false;
           }
        }

      return true;
     }
  };

#endif // __SWINGGOLD_FILTERSTACK_MQH__
