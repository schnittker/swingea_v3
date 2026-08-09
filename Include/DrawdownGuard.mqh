//+------------------------------------------------------------------+
//|                                                 DrawdownGuard.mqh |
//|   Tages-/Gesamt-Kill-Switch. Persistiert Tagesstart-Equity und   |
//|   Peak-Equity per GlobalVariable (Name inkl. Symbol+MagicBase,   |
//|   ueberlebt Terminal-Neustart). AllowNewTrade() ist ein reines   |
//|   Veto fuer NEUE Trades - offene Positionen werden NICHT          |
//|   zwangsweise geschlossen (nicht spezifiziert in Phase 1).       |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_DRAWDOWNGUARD_MQH__
#define __SWINGGOLD_DRAWDOWNGUARD_MQH__

class CDrawdownGuard
  {
private:
   string            m_symbol;
   int               m_magicBase;
   double            m_maxDailyLossPct;
   double            m_maxTotalDDPct;

   string            VarDayStamp(void)    const { return StringFormat("SwingGold_%s_%d_DayStamp", m_symbol, m_magicBase); }
   string            VarDayStartEq(void)  const { return StringFormat("SwingGold_%s_%d_DayStartEquity", m_symbol, m_magicBase); }
   string            VarPeakEq(void)      const { return StringFormat("SwingGold_%s_%d_PeakEquity", m_symbol, m_magicBase); }

   datetime          DayStart(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 0;
      dt.min  = 0;
      dt.sec  = 0;
      return StructToTime(dt);
     }

public:
                     CDrawdownGuard(void):
                        m_symbol(""), m_magicBase(0), m_maxDailyLossPct(3.0), m_maxTotalDDPct(20.0) {}

   void              Configure(const string symbol, const int magicBase,
                               const double maxDailyLossPct, const double maxTotalDDPct)
     {
      m_symbol          = symbol;
      m_magicBase       = magicBase;
      m_maxDailyLossPct = maxDailyLossPct;
      m_maxTotalDDPct   = maxTotalDDPct;
     }

   //+------------------------------------------------------------------+
   //| Aktualisiert Tagesstart-Equity (bei Tageswechsel) und Peak-      |
   //| Equity. Muss regelmaessig aufgerufen werden (z.B. pro H4-Bar).  |
   //+------------------------------------------------------------------+
   void              Update(void)
     {
      double   equity = AccountInfoDouble(ACCOUNT_EQUITY);
      datetime today  = DayStart(TimeCurrent());

      string dayStampVar   = VarDayStamp();
      string dayStartEqVar = VarDayStartEq();
      string peakEqVar     = VarPeakEq();

      bool needNewDay = true;
      if(GlobalVariableCheck(dayStampVar))
        {
         datetime storedDay = (datetime)GlobalVariableGet(dayStampVar);
         if(storedDay == today)
            needNewDay = false;
        }

      if(needNewDay)
        {
         GlobalVariableSet(dayStampVar, (double)today);
         GlobalVariableSet(dayStartEqVar, equity);
        }

      if(!GlobalVariableCheck(peakEqVar))
        {
         GlobalVariableSet(peakEqVar, equity);
        }
      else
        {
         double peak = GlobalVariableGet(peakEqVar);
         if(equity > peak)
            GlobalVariableSet(peakEqVar, equity);
        }
     }

   //+------------------------------------------------------------------+
   //| Gibt den Risiko-Skalierungsfaktor basierend auf dem laufenden   |
   //| Gesamt-DD vom Peak zurueck:                                     |
   //|   DD <  2% -> 1.00 (volles Risiko)                              |
   //|   DD <  4% -> 0.50 (halbiertes Risiko)                          |
   //|   DD >= 4% -> 0.25 (stark reduziertes Risiko)                   |
   //+------------------------------------------------------------------+
   double            GetRiskScale(void) const
     {
      string peakEqVar = VarPeakEq();
      if(!GlobalVariableCheck(peakEqVar))
         return 1.0;

      double peakEquity = GlobalVariableGet(peakEqVar);
      if(peakEquity <= 0.0)
         return 1.0;

      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double ddPct     = (peakEquity - equity) / peakEquity * 100.0;

      if(ddPct < 2.0) return 1.00;
      if(ddPct < 4.0) return 0.50;
      return 0.25;
     }

   //+------------------------------------------------------------------+
   //| Veto fuer NEUE Trades. true = erlaubt, false = gesperrt          |
   //| (outReason gefuellt).                                            |
   //+------------------------------------------------------------------+
   bool              AllowNewTrade(string &outReason)
     {
      outReason = "";
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      string dayStartEqVar = VarDayStartEq();
      if(GlobalVariableCheck(dayStartEqVar))
        {
         double dayStartEquity = GlobalVariableGet(dayStartEqVar);
         if(dayStartEquity > 0.0)
           {
            double dailyLossPct = (dayStartEquity - equity) / dayStartEquity * 100.0;
            if(dailyLossPct >= m_maxDailyLossPct)
              {
               outReason = StringFormat("Tages-Kill-Switch: Verlust %.2f%% >= InpMaxDailyLossPct %.2f%%",
                                         dailyLossPct, m_maxDailyLossPct);
               return false;
              }
           }
        }

      string peakEqVar = VarPeakEq();
      if(GlobalVariableCheck(peakEqVar))
        {
         double peakEquity = GlobalVariableGet(peakEqVar);
         if(peakEquity > 0.0)
           {
            double totalDDPct = (peakEquity - equity) / peakEquity * 100.0;
            if(totalDDPct >= m_maxTotalDDPct)
              {
               outReason = StringFormat("Gesamt-Kill-Switch: DD %.2f%% >= InpMaxTotalDDPct %.2f%%",
                                         totalDDPct, m_maxTotalDDPct);
               return false;
              }
           }
        }

      return true;
     }
  };

#endif // __SWINGGOLD_DRAWDOWNGUARD_MQH__
