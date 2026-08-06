//+------------------------------------------------------------------+
//|                                                   DecisionLog.mqh |
//|   CSV-Telemetrie: jede Signal-Evaluierung (auch abgelehnte),     |
//|   damit sich spaeter messen laesst, ob ein Filter Edge liefert   |
//|   oder nur Trades kostet (ea.md 4.12). Header und Platzhalter-   |
//|   Spalten (regime, clusterRiskPct) sind bewusst identisch mit    |
//|   dem Phase-2-Schema, damit spaetere Auswertungen kompatibel     |
//|   bleiben.                                                        |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_DECISIONLOG_MQH__
#define __SWINGGOLD_DECISIONLOG_MQH__

#include "Types.mqh"

class CDecisionLog
  {
private:
   bool              m_enabled;
   string            m_fileName;
   int               m_handle;
   int               m_digits;

public:
                     CDecisionLog(void):
                        m_enabled(true), m_fileName("SwingGoldEA_DecisionLog.csv"),
                        m_handle(INVALID_HANDLE), m_digits(5) {}

   //+------------------------------------------------------------------+
   //| Oeffnet die CSV-Datei (Standard-\Files-Pfad) und schreibt den    |
   //| Header, falls die Datei neu/leer ist. Bereits vorhandene         |
   //| Inhalte werden fortgesetzt (Anhaengen), nicht ueberschrieben.    |
   //+------------------------------------------------------------------+
   bool              Init(const bool enabled, const string fileName, const int digits)
     {
      m_enabled  = enabled;
      m_fileName = fileName;
      m_digits   = digits;

      if(!m_enabled)
         return true;

      bool fileExisted = FileIsExist(m_fileName);

      m_handle = FileOpen(m_fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ, ';');
      if(m_handle == INVALID_HANDLE)
        {
         PrintFormat("DecisionLog: FileOpen fehlgeschlagen fuer '%s', Fehler=%d", m_fileName, GetLastError());
         return false;
        }

      FileSeek(m_handle, 0, SEEK_END);

      if(!fileExisted || FileTell(m_handle) == 0)
        {
         FileWrite(m_handle, "timestamp", "regime", "signalModule", "dir", "entry", "sl", "tp",
                   "atr", "spread", "lots", "clusterRiskPct", "accepted", "rejectReason");
         FileFlush(m_handle);
        }

      return true;
     }

   void              Deinit(void)
     {
      if(m_handle != INVALID_HANDLE)
        {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
        }
     }

   //+------------------------------------------------------------------+
   //| Schreibt eine Zeile fuer eine Signal-Evaluierung. regime bleibt  |
   //| "UNKNOWN" und clusterRiskPct "0" als Platzhalter (Phase 2).      |
   //+------------------------------------------------------------------+
   void              Write(const string signalModule, const ENUM_SIGNAL_DIR dir, const double entry,
                           const double sl, const double tp, const double atr, const long spread,
                           const double lots, const bool accepted, const string rejectReason)
     {
      if(!m_enabled || m_handle == INVALID_HANDLE)
         return;

      string dirStr = (dir == SIGNAL_LONG) ? "LONG" : (dir == SIGNAL_SHORT ? "SHORT" : "FLAT");

      FileWrite(m_handle,
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                "UNKNOWN",
                signalModule,
                dirStr,
                DoubleToString(entry, m_digits),
                DoubleToString(sl, m_digits),
                DoubleToString(tp, m_digits),
                DoubleToString(atr, m_digits),
                (long)spread,
                DoubleToString(lots, 2),
                "0",
                accepted ? "true" : "false",
                rejectReason);
      FileFlush(m_handle);
     }
  };

#endif // __SWINGGOLD_DECISIONLOG_MQH__
