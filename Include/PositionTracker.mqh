//+------------------------------------------------------------------+
//|                                              PositionTracker.mqh |
//|   Liest die aktuelle Netto-Position des EA fuer ein Symbol.       |
//|   Auf einem Hedge-Konto koennte es mehrere Positionen mit dem     |
//|   gleichen Magic geben; der EA haelt aber je Symbol nur eine      |
//|   Richtung, daher wird Netto-Lot + Richtung ermittelt.            |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_POSITIONTRACKER_MQH__
#define __TRENDMOMENTUM_POSITIONTRACKER_MQH__

#include "Types.mqh"

class CPositionTracker
  {
private:
   long              m_magic;

public:
                     CPositionTracker(void): m_magic(0) {}
   void              Configure(const long magic) { m_magic=magic; }

   //+------------------------------------------------------------------+
   //| Netto-Lot des EA fuer ein Symbol (Long positiv, Short negativ).  |
   //| 0.0 = keine EA-Position.                                         |
   //+------------------------------------------------------------------+
   double            NetLots(const string sym)
     {
      double net=0.0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;

         double vol=PositionGetDouble(POSITION_VOLUME);
         long   type=PositionGetInteger(POSITION_TYPE);
         if(type==POSITION_TYPE_BUY)  net+=vol;
         else                          net-=vol;
        }
      return net;
     }

   //--- Aktuelle Richtung des EA fuer ein Symbol
   ENUM_SIGNAL_DIR   CurrentDir(const string sym)
     {
      double net=NetLots(sym);
      if(net>0.0)  return SIGNAL_LONG;
      if(net<0.0)  return SIGNAL_SHORT;
      return SIGNAL_FLAT;
     }

   //--- Anzahl offener EA-Positionen (alle Symbole)
   int               OpenCount(void)
     {
      int cnt=0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC)==m_magic) cnt++;
        }
      return cnt;
     }
  };

#endif // __TRENDMOMENTUM_POSITIONTRACKER_MQH__
