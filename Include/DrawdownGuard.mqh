//+------------------------------------------------------------------+
//|                                                DrawdownGuard.mqh |
//|   Drawdown-Kill-Switch (Go-Live-Checkliste, Punkt 5).            |
//|   Verfolgt den Equity-Hochpunkt und sperrt neue Entries, wenn    |
//|   der Ruecksetzer eine Schwelle ueberschreitet (Soft-Pause).     |
//|   Bestehende Positionen bleiben offen; Wiederaufnahme per         |
//|   Hysterese, sobald der DD unter die halbe Schwelle faellt.       |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_DRAWDOWNGUARD_MQH__
#define __TRENDMOMENTUM_DRAWDOWNGUARD_MQH__

class CDrawdownGuard
  {
private:
   double            m_peakEquity;   // hoechster gesehener Equity-Stand
   double            m_maxDDPct;     // Schwelle in % (z.B. 20)
   bool              m_paused;       // Soft-Pause aktiv?

public:
                     CDrawdownGuard(void): m_peakEquity(0.0),m_maxDDPct(20.0),m_paused(false) {}

   void              Configure(const double maxDDPct)
     {
      m_maxDDPct=maxDDPct;
     }

   void              Init(const double startEquity)
     {
      m_peakEquity=startEquity;
      m_paused=false;
     }

   bool              IsPaused(void) const { return m_paused; }
   double            CurrentDDPct(void) const
     {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity<=0.0) return 0.0;
      return (m_peakEquity-eq)/m_peakEquity*100.0;
     }

   //+------------------------------------------------------------------+
   //| Pro Rebalancing aufrufen. Aktualisiert Peak und Pause-Status.    |
   //| Rueckgabe: true = Entries erlaubt, false = pausiert.             |
   //+------------------------------------------------------------------+
   bool              Update(void)
     {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_peakEquity) m_peakEquity=eq;

      double dd=CurrentDDPct();

      if(!m_paused && dd>=m_maxDDPct)
        {
         m_paused=true;
         PrintFormat("DrawdownGuard: PAUSE - DD %.2f%% >= Limit %.2f%%",dd,m_maxDDPct);
        }
      else if(m_paused && dd< (m_maxDDPct*0.5))
        {
         // Erholung auf < halbe Schwelle -> Pause aufheben (Hysterese)
         m_paused=false;
         PrintFormat("DrawdownGuard: WEITER - DD %.2f%% erholt",dd);
        }

      return !m_paused;
     }
  };

#endif // __TRENDMOMENTUM_DRAWDOWNGUARD_MQH__
