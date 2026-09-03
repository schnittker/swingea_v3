//+------------------------------------------------------------------+
//|                                                     NewsGuard.mqh |
//|   E8-News-Blackout: verbietet neue Orders, Schliessungen und     |
//|   SL/TP-Aenderungen in einem Fenster um hochwirksame News-Events |
//|   (E8 One Performance-Konto, 5 Min vor/nach High-Impact-News).   |
//|   Standardmaessig deaktiviert (Hazard H14).                     |
//|                                                                    |
//|   Zwei Modi ueber MQLInfoInteger(MQL_TESTER):                    |
//|   - Live: CalendarValueHistory() in einem +-90-Minuten-Fenster   |
//|     um "jetzt" (GMT), gefiltert auf CALENDAR_IMPORTANCE_HIGH.    |
//|   - Tester: CalendarValueHistory() liefert im Strategy Tester    |
//|     dokumentiert keine Daten (ea.md 7.2) -> CSV-Fallback          |
//|     (datetime;event;impact, GMT-verankert), einmalig geparst.    |
//|     CSV bleibt fuer dieses Ticket unbefuellt - Modul ist im       |
//|     Tester dadurch faktisch wirkungslos bis eine echte CSV-      |
//|     Datei existiert.                                              |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_NEWSGUARD_MQH__
#define __SWINGGOLD_NEWSGUARD_MQH__

class CNewsGuard
  {
private:
   bool              m_enabled;
   int               m_blackoutMinBefore;
   int               m_blackoutMinAfter;
   string            m_csvPath;
   datetime          m_csvEvents[];
   bool              m_csvLoaded;

   //+------------------------------------------------------------------+
   //| Parst die CSV-Datei einmalig (Format: datetime;event;impact,    |
   //| nur "High"-Zeilen werden uebernommen). Analog DecisionLog-Muster|
   //| (FileOpen mit FILE_CSV|FILE_READ|FILE_SHARE_READ).              |
   //+------------------------------------------------------------------+
   void              LoadCsvIfNeeded(void)
     {
      if(m_csvLoaded)
         return;
      m_csvLoaded = true; // nur einmal versuchen, auch bei Fehler nicht wiederholen

      ArrayResize(m_csvEvents, 0);

      if(m_csvPath == "" || !FileIsExist(m_csvPath))
        {
         PrintFormat("NewsGuard: CSV '%s' nicht gefunden - Blackout im Tester inaktiv.", m_csvPath);
         return;
        }

      int handle = FileOpen(m_csvPath, FILE_CSV | FILE_READ | FILE_SHARE_READ, ';');
      if(handle == INVALID_HANDLE)
        {
         PrintFormat("NewsGuard: FileOpen fehlgeschlagen fuer '%s', Fehler=%d", m_csvPath, GetLastError());
         return;
        }

      int count = 0;
      while(!FileIsEnding(handle))
        {
         string dtStr    = FileReadString(handle);
         string eventStr = FileReadString(handle);
         string impact   = FileReadString(handle);

         if(dtStr == "" || impact != "High")
            continue;

         datetime eventTime = StringToTime(dtStr);
         if(eventTime <= 0)
            continue; // z.B. Header-Zeile "datetime;event;impact"

         count++;
         ArrayResize(m_csvEvents, count);
         m_csvEvents[count - 1] = eventTime;
        }

      FileClose(handle);
      ArraySort(m_csvEvents);

      PrintFormat("NewsGuard: %d High-Impact-Events aus '%s' geladen.", count, m_csvPath);
     }

   //+------------------------------------------------------------------+
   //| Live-Pfad: CalendarValueHistory in +-90-Minuten-Fenster um GMT- |
   //| "jetzt", gefiltert auf High-Impact (CalendarEventById).        |
   //+------------------------------------------------------------------+
   bool              IsBlackoutLive(string &outReason)
     {
      datetime now  = TimeGMT();
      datetime from = now - 90 * 60;
      datetime to   = now + 90 * 60;

      MqlCalendarValue values[];
      if(!CalendarValueHistory(values, from, to))
         return false;

      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;

         datetime eventTime     = values[i].time;
         datetime blackoutStart = eventTime - (datetime)(m_blackoutMinBefore * 60);
         datetime blackoutEnd   = eventTime + (datetime)(m_blackoutMinAfter * 60);

         if(now >= blackoutStart && now <= blackoutEnd)
           {
            outReason = StringFormat("NewsGuard: Blackout-Fenster (Live-Kalender) um %s - %s",
                                      TimeToString(eventTime, TIME_DATE | TIME_MINUTES), ev.name);
            return true;
           }
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Tester-Pfad: sortiertes CSV-Array, linearer Scan mit Fruehab-    |
   //| bruch (sortiert -> keine weiteren Treffer nach erstem Event, das|
   //| noch in der Zukunft liegt).                                     |
   //+------------------------------------------------------------------+
   bool              IsBlackoutCsv(string &outReason)
     {
      LoadCsvIfNeeded();
      if(ArraySize(m_csvEvents) == 0)
         return false;

      datetime now = TimeCurrent(); // Tester: TimeGMT() unzuverlaessig (ea.md 7.1) - CSV-Zeiten
                                     // muessen vom Nutzer GMT-verankert gepflegt werden.

      for(int i = 0; i < ArraySize(m_csvEvents); i++)
        {
         datetime eventTime     = m_csvEvents[i];
         datetime blackoutStart = eventTime - (datetime)(m_blackoutMinBefore * 60);
         datetime blackoutEnd   = eventTime + (datetime)(m_blackoutMinAfter * 60);

         if(now >= blackoutStart && now <= blackoutEnd)
           {
            outReason = StringFormat("NewsGuard: Blackout-Fenster (CSV) um %s",
                                      TimeToString(eventTime, TIME_DATE | TIME_MINUTES));
            return true;
           }

         if(eventTime > blackoutEnd)
            break; // sortiert - alle weiteren Events liegen noch weiter in der Zukunft
        }

      return false;
     }

public:
                     CNewsGuard(void):
                        m_enabled(false), m_blackoutMinBefore(5), m_blackoutMinAfter(5),
                        m_csvPath(""), m_csvLoaded(false) {}

   void              Configure(const bool enabled, const int blackoutMinBefore,
                               const int blackoutMinAfter, const string csvPath)
     {
      m_enabled           = enabled;
      m_blackoutMinBefore = blackoutMinBefore;
      m_blackoutMinAfter  = blackoutMinAfter;
      m_csvPath           = csvPath;
     }

   //+------------------------------------------------------------------+
   //| true = Blackout aktiv (outReason gefuellt), false = kein Veto.  |
   //| Master-Schalter zuerst: wenn deaktiviert, sofort false ohne     |
   //| Live-/CSV-Zugriff (Hazard H14: Default-aus muss verhaltens-      |
   //| identisch zum Stand vor diesem Modul sein).                     |
   //+------------------------------------------------------------------+
   bool              IsBlackoutNow(string &outReason)
     {
      outReason = "";

      if(!m_enabled)
         return false;

      if(MQLInfoInteger(MQL_TESTER))
         return IsBlackoutCsv(outReason);

      return IsBlackoutLive(outReason);
     }
  };

#endif // __SWINGGOLD_NEWSGUARD_MQH__
