//+------------------------------------------------------------------+
//|                                               PositionTracker.mqh |
//|   Liest die eigene offene Position (Symbol+Magic). Pro Modul     |
//|   wird max. 1 Position gehalten (kein Pyramiding). Vor jedem     |
//|   Read wird explizit PositionSelectByTicket() aufgerufen          |
//|   (ea.md 7.5-Stil). Das Teilgewinn-Flag wird per GlobalVariable  |
//|   persistiert, da MQL5 keine Custom-Flags an Positionen haengt.  |
//|                                                                   |
//|   WICHTIG (Hazard H12): PositionSelectByTicket() mutiert den     |
//|   globalen Selektionszustand. Bei zwei Slots verschraenken sich  |
//|   die Aufrufe. DESHALB ruft JEDER Getter PositionSelectByTicket  |
//|   selbst auf — diese Re-Select-Disziplin darf NICHT "optimiert"  |
//|   werden (sonst liest ein Getter die Position des anderen Slots).|
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_POSITIONTRACKER_MQH__
#define __SWINGGOLD_POSITIONTRACKER_MQH__

class CPositionTracker
  {
private:
   string            m_symbol;
   int               m_magic;

   string            PartialFlagName(const ulong ticket) const
     {
      return StringFormat("SwingGold_Partial_%s_%d_%I64u", m_symbol, m_magic, ticket);
     }

public:
                     CPositionTracker(void): m_symbol(""), m_magic(0) {}

   void              Configure(const string symbol, const int magic)
     {
      m_symbol = symbol;
      m_magic  = magic;
     }

   //--- Sucht die eigene offene Position (Symbol+Magic). Liefert die erste
   //--- passende Position (es existiert je Modul immer nur eine).
   bool              FindOwnPosition(ulong &outTicket)
     {
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         outTicket = ticket;
         return true;
        }

      outTicket = 0;
      return false;
     }

   bool              GetVolume(const ulong ticket, double &outVolume)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      outVolume = PositionGetDouble(POSITION_VOLUME);
      return true;
     }

   bool              GetOpenPrice(const ulong ticket, double &outPrice)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      outPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      return true;
     }

   bool              GetSL(const ulong ticket, double &outSL)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      outSL = PositionGetDouble(POSITION_SL);
      return true;
     }

   bool              GetTP(const ulong ticket, double &outTP)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      outTP = PositionGetDouble(POSITION_TP);
      return true;
     }

   bool              GetType(const ulong ticket, ENUM_POSITION_TYPE &outType)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      outType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return true;
     }

   //--- Teilgewinn-Flag je Ticket, persistiert per GlobalVariable (ueberlebt Terminal-Neustart).
   bool              IsPartialDone(const ulong ticket)
     {
      string name = PartialFlagName(ticket);
      if(!GlobalVariableCheck(name))
         return false;
      return (GlobalVariableGet(name) != 0.0);
     }

   void              SetPartialDone(const ulong ticket, const bool done)
     {
      GlobalVariableSet(PartialFlagName(ticket), done ? 1.0 : 0.0);
     }

   void              ClearPartialFlag(const ulong ticket)
     {
      string name = PartialFlagName(ticket);
      if(GlobalVariableCheck(name))
         GlobalVariableDel(name);
     }
  };

#endif // __SWINGGOLD_POSITIONTRACKER_MQH__
