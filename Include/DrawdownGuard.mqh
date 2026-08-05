//+------------------------------------------------------------------+
//| DrawdownGuard.mqh                                                |
//| Tagesverlust-Regler als SOFT-Pause (kein Hard-Kill): sperrt bei  |
//| Ueberschreiten der Schwelle nur neue Entries fuer den Rest des   |
//| Handelstags. Bestehende Positionen laufen unangetastet weiter    |
//| bis SL/TP oder Force-Close (SessionManager) - kein Notabverkauf. |
//| Daily/Total-DD sind laut Vorgabe nur sekundaerer Regler, nicht    |
//| Kill-Switch.                                                      |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Laufender Zustand des Tagesverlust-Reglers.                      |
//+------------------------------------------------------------------+
struct SDrawdownState
  {
   datetime          currentDay;      // Mitternacht (Server-Zeit) des erfassten Tages
   double            dayStartEquity;  // Equity beim ersten Tick dieses Tages
  };

//+------------------------------------------------------------------+
//| Setzt currentDay auf Mitternacht (Server-Zeit) des Zeitpunkts t. |
//+------------------------------------------------------------------+
datetime GetDayStart(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Muss jeden Tick aufgerufen werden. Erkennt Tageswechsel und      |
//| setzt dayStartEquity fuer den neuen Tag neu.                     |
//+------------------------------------------------------------------+
void UpdateDrawdownState(SDrawdownState &state, const double currentEquity)
  {
   datetime todayStart = GetDayStart(TimeCurrent());
   if(state.currentDay != todayStart)
     {
      state.currentDay     = todayStart;
      state.dayStartEquity = currentEquity;
     }
  }

//+------------------------------------------------------------------+
//| Bisheriger Tagesverlust in Prozent (0, wenn Equity gestiegen).   |
//+------------------------------------------------------------------+
double GetDailyLossPercent(const SDrawdownState &state, const double currentEquity)
  {
   if(state.dayStartEquity <= 0.0)
      return 0.0;

   double loss = state.dayStartEquity - currentEquity;
   if(loss <= 0.0)
      return 0.0;

   return (loss / state.dayStartEquity) * 100.0;
  }

//+------------------------------------------------------------------+
//| true, wenn die Soft-Pause-Schwelle erreicht ist -> keine neuen   |
//| Entries mehr fuer den Rest des Handelstags.                      |
//+------------------------------------------------------------------+
bool IsSoftPauseActive(const SDrawdownState &state, const double currentEquity,
                        const double softPauseThresholdPercent)
  {
   return GetDailyLossPercent(state, currentEquity) >= softPauseThresholdPercent;
  }

//+------------------------------------------------------------------+
