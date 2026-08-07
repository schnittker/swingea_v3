//+------------------------------------------------------------------+
//|                                                  TimeContext.mqh |
//|   GMT-Konvertierung, EU-DST, Session-Fenster, Wochentag-Filter. |
//|   Benoetigt fuer SignalOverlapTrend (Session-beschraenkter      |
//|   Einstieg) und FilterStack (Session/Wochentag-Veto).           |
//|                                                                   |
//|   Kritische Design-Entscheidungen (ea.md 7.1):                  |
//|   - TimeCurrent() ist Broker-Server-Zeit, NICHT GMT.            |
//|   - TimeGMT() ist im Strategy Tester unzuverlaessig.            |
//|   - Deshalb: explizite InpGmtOffsetWinter/Summer-Inputs,        |
//|     TimeGMT() nur einmal in LogInitPlausibility() als Warnung.  |
//|   - EU-DST: letzter Sonntag Maerz 01:00 UTC bis                 |
//|     letzter Sonntag Oktober 01:00 UTC.                          |
//|   - US-DST: zweiter Sonntag Maerz 02:00 ET bis                  |
//|     erster Sonntag November 02:00 ET (hier nicht benoetigt,    |
//|     da Einstiegsfenster in GMT geankert ist).                   |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_TIMECONTEXT_MQH__
#define __SWINGGOLD_TIMECONTEXT_MQH__

class CTimeContext
  {
private:
   int               m_offsetWinter;  // Stunden, Broker-Server vs. GMT (Winter)
   int               m_offsetSummer;  // Stunden, Broker-Server vs. GMT (Sommer)
   int               m_overlapStart;  // GMT-Stunde, Beginn Overlap-Fenster (inkl.)
   int               m_overlapEnd;    // GMT-Stunde, Ende Overlap-Fenster (exkl.)
   int               m_mondayStart;   // GMT-Stunde ab Montag erlaubt
   int               m_fridayStop;    // GMT-Stunde ab Freitag gesperrt

   //+------------------------------------------------------------------+
   //| Letzter Sonntag eines Monats/Jahres (00:00 Server-Zeit).        |
   //| Wird fuer EU-DST-Grenzen benoetigt.                              |
   //+------------------------------------------------------------------+
   datetime          LastSundayOfMonth(const int year, const int month) const
     {
      //--- Erster Tag des Folgemonats
      int nextMonth = month + 1;
      int nextYear  = year;
      if(nextMonth > 12) { nextMonth = 1; nextYear++; }

      MqlDateTime dt;
      dt.year  = nextYear;
      dt.mon   = nextMonth;
      dt.day   = 1;
      dt.hour  = 0;
      dt.min   = 0;
      dt.sec   = 0;
      datetime firstOfNext = StructToTime(dt);

      //--- Gehe rueckwaerts bis zum ersten Sonntag
      //--- MqlDateTime.day_of_week: 0=Sonntag, 1=Montag, ...
      MqlDateTime tmp;
      TimeToStruct(firstOfNext, tmp);
      int dowFirstOfNext = tmp.day_of_week;

      //--- Tage bis zum vorherigen Sonntag: dowFirstOfNext Tage zurueck
      //--- (falls 0 = Sonntag, dann 7 Tage zurueck fuer den Sonntag *davor*)
      int daysBack = (dowFirstOfNext == 0) ? 7 : dowFirstOfNext;
      return firstOfNext - (datetime)(daysBack * 86400);
     }

   //+------------------------------------------------------------------+
   //| Ist der gegebene UTC-Zeitpunkt im EU-Sommerzeit-Fenster?        |
   //| EU-SOMMERZEIT: ab letztem Sonntag Maerz 01:00 UTC               |
   //|               bis letztem Sonntag Oktober 01:00 UTC (exkl.)     |
   //+------------------------------------------------------------------+
   bool              IsEuDstInternal(const datetime utcTime) const
     {
      MqlDateTime dt;
      TimeToStruct(utcTime, dt);
      int year = dt.year;

      //--- Wechsel-Zeitpunkte in UTC (01:00 UTC)
      datetime springChange = LastSundayOfMonth(year, 3)  + 3600; // + 1h
      datetime autumnChange = LastSundayOfMonth(year, 10) + 3600; // + 1h

      return (utcTime >= springChange && utcTime < autumnChange);
     }

public:
                     CTimeContext(void):
                        m_offsetWinter(2), m_offsetSummer(3),
                        m_overlapStart(12), m_overlapEnd(16),
                        m_mondayStart(8), m_fridayStop(18) {}

   //+------------------------------------------------------------------+
   //| Konfiguriert den Zeitkontext. offsetWinter/Summer sind die      |
   //| Stunden, die zur Server-Zeit addiert werden muessen, um GMT zu  |
   //| erhalten (typisch IC Markets: +2 Winter, +3 Sommer).           |
   //+------------------------------------------------------------------+
   void              Configure(const int offsetWinter, const int offsetSummer,
                               const int overlapStartGmtHour, const int overlapEndGmtHour,
                               const int mondayStartGmtHour, const int fridayStopGmtHour)
     {
      m_offsetWinter  = offsetWinter;
      m_offsetSummer  = offsetSummer;
      m_overlapStart  = overlapStartGmtHour;
      m_overlapEnd    = overlapEndGmtHour;
      m_mondayStart   = mondayStartGmtHour;
      m_fridayStop    = fridayStopGmtHour;
     }

   //+------------------------------------------------------------------+
   //| Gibt die aktuelle Zeit als UTC/GMT zurueck, berechnet aus       |
   //| TimeCurrent() und dem konfiguriertem Offset + EU-DST.           |
   //+------------------------------------------------------------------+
   datetime          GmtNow(void) const
     {
      datetime serverNow = TimeCurrent();
      //--- Wir schaetzen UTC zuerst mit Winter-Offset, pruefen dann DST
      datetime utcEst = serverNow - (datetime)(m_offsetWinter * 3600);
      bool     isDst  = IsEuDstInternal(utcEst);
      int      offset = isDst ? m_offsetSummer : m_offsetWinter;
      return serverNow - (datetime)(offset * 3600);
     }

   //--- Prueft EU-DST fuer den uebergebenen UTC-Zeitpunkt (Testbarkeit)
   bool              IsEuDst(const datetime utcTime) const
     {
      return IsEuDstInternal(utcTime);
     }

   //+------------------------------------------------------------------+
   //| Ist der Overlap-Handelszeitraum aktiv?                          |
   //| Prueft auf die konfigurierte GMT-Stunde (12:00-16:00 Default).  |
   //+------------------------------------------------------------------+
   bool              IsInOverlapWindow(void) const
     {
      datetime gmt = GmtNow();
      MqlDateTime dt;
      TimeToStruct(gmt, dt);
      return (dt.hour >= m_overlapStart && dt.hour < m_overlapEnd);
     }

   //+------------------------------------------------------------------+
   //| Ist der aktuelle Wochentag handelbar?                            |
   //| Gesperrt: Sa, So, Montag vor m_mondayStart, Freitag nach        |
   //| m_fridayStop (strategies.md Teil E).                            |
   //+------------------------------------------------------------------+
   bool              IsWeekdayAllowed(void) const
     {
      datetime gmt = GmtNow();
      MqlDateTime dt;
      TimeToStruct(gmt, dt);

      int dow  = dt.day_of_week; // 0=So, 1=Mo, ..., 5=Fr, 6=Sa
      int hour = dt.hour;

      if(dow == 0 || dow == 6) return false; // Wochenende
      if(dow == 1 && hour < m_mondayStart) return false; // Montag zu frueh
      if(dow == 5 && hour >= m_fridayStop) return false;  // Freitag zu spaet

      return true;
     }

   //+------------------------------------------------------------------+
   //| Einziger TimeGMT()-Aufruf im Projekt — nur fuer Plausibilitaets-|
   //| Log beim Init. Darf keine Handelsentscheidung beeinflussen      |
   //| (im Strategy Tester unzuverlaessig, ea.md 7.1).                |
   //+------------------------------------------------------------------+
   void              LogInitPlausibility(void) const
     {
      datetime serverNow = TimeCurrent();
      datetime calcGmt   = GmtNow();
      datetime termGmt   = TimeGMT(); // nur fuer Vergleich

      long diffSec = (long)calcGmt - (long)termGmt;
      if(MathAbs((double)diffSec) > 3600)
        {
         PrintFormat("TimeContext: WARNUNG - berechnetes GMT %s weicht >1h vom Terminal-GMT %s ab "
                     "(Tester: erwartet; Live: Offset-Inputs pruefen)",
                     TimeToString(calcGmt, TIME_DATE | TIME_SECONDS),
                     TimeToString(termGmt, TIME_DATE | TIME_SECONDS));
        }
      else
        {
         PrintFormat("TimeContext: init OK - ServerNow=%s CalcGMT=%s TermGMT=%s EU-DST=%s",
                     TimeToString(serverNow, TIME_DATE | TIME_SECONDS),
                     TimeToString(calcGmt,   TIME_DATE | TIME_SECONDS),
                     TimeToString(termGmt,   TIME_DATE | TIME_SECONDS),
                     IsEuDst(calcGmt) ? "true" : "false");
        }
     }
  };

#endif // __SWINGGOLD_TIMECONTEXT_MQH__
