//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|   TSMOM-Signal per MA-Cross-Proxy auf GESCHLOSSENEN Daily-Bars.   |
//|   Long  wenn schnelle MA > langsame MA                           |
//|   Short wenn schnelle MA < langsame MA                           |
//|   Es wird ausschliesslich Bar[1] (letzte geschlossene) gelesen,  |
//|   also kein Look-Ahead/Repainting.                               |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_SIGNALENGINE_MQH__
#define __TRENDMOMENTUM_SIGNALENGINE_MQH__

#include "Types.mqh"

class CSignalEngine
  {
private:
   bool              m_allowShort; // false = nur Long/Flat (Long-only-Modus)

   //--- Einen geschlossenen Indikatorwert (Shift=1) lesen
   bool              ReadClosed(const int handle,double &out)
     {
      double buf[];
      if(CopyBuffer(handle,0,1,1,buf)!=1)
         return false;
      out=buf[0];
      return true;
     }

public:
                     CSignalEngine(void): m_allowShort(true) {}

   void              Configure(const bool allowShort)
     {
      m_allowShort=allowShort;
     }

   //+------------------------------------------------------------------+
   //| Signal + ATR fuer ein Symbol aktualisieren.                      |
   //| Schreibt targetDir und atr in den uebergebenen State.            |
   //| Gibt false bei Datenluecke zurueck (State bleibt dann unveraendert). |
   //+------------------------------------------------------------------+
   bool              Evaluate(SymbolState &st)
     {
      if(!st.valid) return false;

      double maFast=0.0, maSlow=0.0, atr=0.0;
      if(!ReadClosed(st.maFastHandle,maFast)) return false;
      if(!ReadClosed(st.maSlowHandle,maSlow)) return false;
      if(!ReadClosed(st.atrHandle,atr))       return false;

      if(atr<=0.0) return false; // Vola-Sizing braucht positive ATR

      st.atr=atr;

      if(maFast>maSlow)
         st.targetDir=SIGNAL_LONG;
      else if(maFast<maSlow)
         st.targetDir=(m_allowShort ? SIGNAL_SHORT : SIGNAL_FLAT);
      else
         st.targetDir=SIGNAL_FLAT;

      return true;
     }
  };

#endif // __TRENDMOMENTUM_SIGNALENGINE_MQH__
