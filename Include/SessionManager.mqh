//+------------------------------------------------------------------+
//| SessionManager.mqh                                               |
//| Handelsfenster + Force-Close. Erzwingt "strikt Intraday": keine  |
//| Position darf ueber die Force-Close-Zeit hinaus offen bleiben,  |
//| an Freitagen gilt eine frueher liegende Force-Close-Zeit gegen   |
//| Wochenend-Gap-Risiko. Laeuft zentral fuer ALLE Strategien/Symbole|
//| unabhaengig vom jeweiligen Signal-Modul.                         |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "TradeExecution.mqh"
#include "MagicNumbers.mqh"

//+------------------------------------------------------------------+
//| Hilfsfunktion: Stunde+Minute -> Minuten seit Mitternacht.        |
//| Fuer die lesbaren Inputs in PortfolioEA.mq5 (z.B. 21/00).       |
//+------------------------------------------------------------------+
int HourMinuteToMinutesOfDay(const int hour, const int minute)
  {
   return hour * 60 + minute;
  }

//+------------------------------------------------------------------+
//| Ermittelt den GMT-Offset der Broker-/Serverzeit in vollen        |
//| Stunden. IC Markets richtet die Serverzeit nach US-DST aus       |
//| (GMT+3 Sommer, GMT+2 Winter); dieser Wert wird live gemessen und |
//| folgt dem DST-Wechsel automatisch, ohne dass die Session-Inputs  |
//| manuell nachgezogen werden muessen.                              |
//|                                                                  |
//| Im Strategy-Tester ist TimeGMT() unzuverlaessig (liefert dort    |
//| meist = Serverzeit -> Offset faelschlich 0); daher wird im       |
//| Tester der uebergebene fallbackOffsetHours verwendet. Ebenso     |
//| wird auf den Fallback zurueckgefallen, wenn der gemessene Offset |
//| ausserhalb des plausiblen Zeitzonen-Bereichs [-12, +14] liegt    |
//| (z.B. TimeGMT()==0). Rundung auf volle Stunden ist fuer          |
//| FX-Broker korrekt (keine 30/45-Min-Zonen).                       |
//+------------------------------------------------------------------+
int GetServerGmtOffsetHours(const int fallbackOffsetHours)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return fallbackOffsetHours;

   datetime gmt = TimeGMT();
   if(gmt <= 0)
     {
      static bool warned = false;
      if(!warned)
        {
         PrintFormat("GetServerGmtOffsetHours: TimeGMT() unplausibel (%s) - "
                     "Fallback-Offset %d h wird verwendet.",
                     TimeToString(gmt), fallbackOffsetHours);
         warned = true;
        }
      return fallbackOffsetHours;
     }

   int offsetSeconds = (int)(TimeCurrent() - gmt);
   int offsetHours   = (int)MathRound(offsetSeconds / 3600.0);

   if(offsetHours < -12 || offsetHours > 14)
     {
      static bool warnedRange = false;
      if(!warnedRange)
        {
         PrintFormat("GetServerGmtOffsetHours: gemessener Offset %d h unplausibel - "
                     "Fallback-Offset %d h wird verwendet.",
                     offsetHours, fallbackOffsetHours);
         warnedRange = true;
        }
      return fallbackOffsetHours;
     }

   return offsetHours;
  }

//+------------------------------------------------------------------+
//| Rechnet eine in GMT definierte Uhrzeit in "Minuten seit Server-  |
//| Mitternacht" um, indem der Server-GMT-Offset addiert und das     |
//| Ergebnis modulo 24h auf [0, 1440) normalisiert wird. Alle        |
//| weiteren Vergleiche laufen danach unveraendert gegen die         |
//| Serverzeit (TimeCurrent()).                                      |
//|                                                                  |
//| HINWEIS: Fuer Fenster, die tatsaechlich die Server-Mitternacht   |
//| kreuzen (Start > Ende nach Umrechnung), sind die Range-Scan-     |
//| Schleifen in den Signal-Modulen NICHT ausgelegt. Mit den         |
//| aktuellen Defaults (Range 23:00-07:00 GMT = 02:00-10:00 Server)  |
//| tritt das nicht auf; ein solches Fenster muesste gesondert       |
//| behandelt werden.                                                |
//+------------------------------------------------------------------+
int GmtHourMinuteToServerMinutesOfDay(const int gmtHour, const int gmtMinute,
                                       const int serverGmtOffsetHours)
  {
   int total = (gmtHour + serverGmtOffsetHours) * 60 + gmtMinute;
   return ((total % 1440) + 1440) % 1440;
  }

//+------------------------------------------------------------------+
//| Minuten seit Mitternacht der Broker-/Serverzeit fuer einen Zeit- |
//| punkt (i.d.R. TimeCurrent()).                                     |
//+------------------------------------------------------------------+
int TimeToMinutesOfDay(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
  }

//+------------------------------------------------------------------+
//| true, wenn der Zeitpunkt auf einen Freitag faellt (Server-Zeit). |
//+------------------------------------------------------------------+
bool IsFriday(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_week == FRIDAY;
  }

//+------------------------------------------------------------------+
//| true, wenn der Zeitpunkt auf ein Wochenende faellt (Server-Zeit).|
//| Dient nur als zusaetzliches Sicherheitsnetz - bei korrekt         |
//| konfiguriertem Force-Close sollte dieser Fall nie eintreten.    |
//+------------------------------------------------------------------+
bool IsWeekend(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_week == SUNDAY || dt.day_of_week == SATURDAY;
  }

//+------------------------------------------------------------------+
//| Effektive Force-Close-Zeit fuer "heute": an Freitagen frueher    |
//| (Wochenend-Puffer), sonst die normale taegliche Zeit.            |
//+------------------------------------------------------------------+
int GetEffectiveForceCloseMinuteOfDay(const datetime currentTime,
                                       const int forceCloseMinuteOfDay,
                                       const int fridayForceCloseMinuteOfDay)
  {
   return IsFriday(currentTime) ? fridayForceCloseMinuteOfDay : forceCloseMinuteOfDay;
  }

//+------------------------------------------------------------------+
//| true, wenn jetzt bereits ForceClose-Zeit erreicht/ueberschritten |
//| ist (oder Wochenende, als Sicherheitsnetz).                     |
//+------------------------------------------------------------------+
bool ShouldForceCloseNow(const datetime currentTime,
                          const int forceCloseMinuteOfDay,
                          const int fridayForceCloseMinuteOfDay)
  {
   if(IsWeekend(currentTime))
      return true;

   int nowMin = TimeToMinutesOfDay(currentTime);
   int effectiveClose = GetEffectiveForceCloseMinuteOfDay(currentTime, forceCloseMinuteOfDay,
                                                           fridayForceCloseMinuteOfDay);
   return nowMin >= effectiveClose;
  }

//+------------------------------------------------------------------+
//| true, wenn neue Entries aktuell erlaubt sind. Entries werden     |
//| noNewEntryBeforeCloseMinutes vor der Force-Close-Zeit gesperrt, |
//| damit eine frische Position nicht sofort wieder zwangsweise      |
//| geschlossen werden muss.                                          |
//+------------------------------------------------------------------+
bool IsNewEntryWindowOpen(const datetime currentTime,
                           const int forceCloseMinuteOfDay,
                           const int fridayForceCloseMinuteOfDay,
                           const int noNewEntryBeforeCloseMinutes)
  {
   if(IsWeekend(currentTime))
      return false;

   int nowMin = TimeToMinutesOfDay(currentTime);
   int effectiveClose = GetEffectiveForceCloseMinuteOfDay(currentTime, forceCloseMinuteOfDay,
                                                           fridayForceCloseMinuteOfDay);
   int cutoff = effectiveClose - noNewEntryBeforeCloseMinutes;
   return nowMin < cutoff;
  }

//+------------------------------------------------------------------+
//| Schliesst alle als offen markierten Positionen zwangsweise, wenn |
//| die Force-Close-Zeit erreicht ist. Symbolunabhaengig von Signal- |
//| Modulen - laeuft fuer jede (Strategie, Symbol)-Kombination.      |
//| Bei Erfolg wird positions[i].isOpen lokal auf false gesetzt;     |
//| der naechste PositionTracker-Resync bestaetigt dies endgueltig.  |
//+------------------------------------------------------------------+
void EnforceForceClose(SStrategyPosition &positions[],
                        const int numSymbols,
                        const int forceCloseMinuteOfDay,
                        const int fridayForceCloseMinuteOfDay)
  {
   datetime now = TimeCurrent();
   if(!ShouldForceCloseNow(now, forceCloseMinuteOfDay, fridayForceCloseMinuteOfDay))
      return;

   // Direkter Scan ueber ALLE Terminal-Positionen statt nur ueber das
   // Tracker-Array: "strikt Intraday" ist eine harte Sicherheitsgarantie und
   // darf nicht davon abhaengen, dass eine eigene Position im Tracker gelandet
   // ist (z.B. Alt-Position mit hoeherem SymbolIndex, im selben Tick geoeffnet
   // und noch nicht resynct, oder ein verpasster Sync). Jede Position mit
   // eigener Magic-Number wird geschlossen. Rueckwaerts iterieren, da sich der
   // Positionsindex durch das Schliessen verschiebt.
   //
   // Der Tracker-Slot wird nur dann lokal auf isOpen=false gesetzt, wenn das
   // Close tatsaechlich erfolgreich war. Ein fehlgeschlagenes Close (z.B.
   // Requote) darf eine real weiter offene Position nicht faelschlich als
   // geschlossen markieren - sonst waere der Tracker-Zustand fuer diesen Tick
   // inkonsistent (der naechste Resync korrigiert es zwar, aber der Slot soll
   // den echten Zustand widerspiegeln).
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      ENUM_STRATEGY_ID sid;
      int symIdx;
      if(!MagicDecode(magic, numSymbols, sid, symIdx))
         continue; // fremde Position (anderer EA / manueller Trade) unangetastet lassen

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(ClosePositionByTicket(ticket))
        {
         PrintFormat("EnforceForceClose: Position %I64u (%s) zwangsweise geschlossen.",
                     ticket, symbol);

         int idx = PositionTrackerIndex(sid, symIdx, numSymbols);
         if(idx >= 0 && idx < ArraySize(positions))
            positions[idx].isOpen = false;
        }
      else
        {
         PrintFormat("EnforceForceClose: Close von Position %I64u (%s) FEHLGESCHLAGEN "
                     "- Slot bleibt offen, erneuter Versuch im naechsten Tick.",
                     ticket, symbol);
        }
     }
  }

//+------------------------------------------------------------------+
