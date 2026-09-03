#property strict
#include "Copier_Lock.mqh"

input long MasterMagic = 10001;
input bool CopyAllTrades = true;  // True = copy all trades, False = only MasterMagic
input int  EventsRetentionSeconds = 86400; // Keep events at least this long before trimming (safety window for slow slaves)
input int  MaintenanceIntervalSec = 300;   // How often to check the events file for trimming

// Files are stored in the common MT5 data folder (using FILE_COMMON flag)
string EVENTS_FILE  = "copier_events.csv";
string SEQ_FILE     = "copier_seq.txt";
string BALANCE_FILE = "copier_balance.csv";

long g_seq = 0;

// ---------- SEQ ----------
long LoadSeq()
{
   int h = FileOpen(SEQ_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return 0;
   long s = (long)StringToInteger(FileReadString(h));
   FileClose(h);
   return s;
}

void SaveSeq(long s)
{
   int h = FileOpen(SEQ_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("ERROR: Cannot save sequence file: ", SEQ_FILE, " | Error: ", GetLastError());
      return;
   }
   FileWrite(h, (string)s);
   FileClose(h);
}

// ---------- WRITE EVENT ----------
void Emit(string line)
{
   if(!Lock()) return;

   // First, ensure the file exists (create if it doesn't)
   if(!FileIsExist(EVENTS_FILE, FILE_COMMON))
   {
      int hCreate = FileOpen(EVENTS_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(hCreate != INVALID_HANDLE)
      {
         FileClose(hCreate);
         Print("Created events file: ", EVENTS_FILE);
      }
      else
      {
         Print("ERROR: Cannot create events file: ", EVENTS_FILE, " | Error: ", GetLastError());
         Unlock();
         return;
      }
   }

   int h = FileOpen(EVENTS_FILE,
      FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_COMMON);

   if(h == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open events file: ", EVENTS_FILE, " | Error: ", GetLastError());
      Unlock();
      return;
   }

   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\n");
   FileClose(h);
   WriteBalanceFile();
   Unlock();
}

// ---------- BALANCE ----------
// Writes the Master's current balance + timestamp so Slaves can scale lots
// dynamically instead of relying on a static input. Failure is non-fatal:
// the Slave falls back to its static MasterBalance input if this file is
// missing, invalid, or stale.
void WriteBalanceFile()
{
   int h = FileOpen(BALANCE_FILE, FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("ERROR: Cannot save balance file: ", BALANCE_FILE, " | Error: ", GetLastError());
      return;
   }
   FileWrite(h, DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ";" + (string)(long)TimeCurrent());
   FileClose(h);
}

// ---------- INIT ----------
int OnInit()
{
   g_seq = LoadSeq();
   Print("========================================");
   Print("Master Copier STARTED");
   Print("MasterMagic: ", MasterMagic);
   Print("CopyAllTrades: ", CopyAllTrades ? "YES (all trades)" : "NO (only MasterMagic)");
   Print("Sequence: ", g_seq);
   Print("Events file: ", EVENTS_FILE);
   Print("========================================");

   // Test file creation without truncating any existing content.
   // Use READ|WRITE so an existing file is opened (not recreated) and the
   // file pointer starts at 0; if it doesn't exist yet, WRITE will create it.
   int testHandle = FileOpen(EVENTS_FILE, FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_COMMON);
   if(testHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create/access events file on startup! Error: ", GetLastError());
   }
   else
   {
      FileClose(testHandle);
      Print("SUCCESS: Events file is accessible");
   }

   WriteBalanceFile();
   EventSetTimer(MaintenanceIntervalSec);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveSeq(g_seq);
   Print("Master Copier STOPPED | Seq=", g_seq);
}

// ---------- MAINTENANCE ----------
void OnTimer()
{
   TrimEventsFile();
   WriteBalanceFile();
}

// Removes events older than EventsRetentionSeconds to keep the shared events
// file from growing unbounded. Original sequence numbers are preserved so
// slaves resuming from a saved offset/seq are unaffected.
void TrimEventsFile()
{
   if(!Lock()) return;

   int h = FileOpen(EVENTS_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) { Unlock(); return; }

   datetime cutoff = TimeCurrent() - EventsRetentionSeconds;

   // Events are appended in increasing-timestamp order, so if the oldest
   // (first) line is already within the retention window there is nothing
   // to trim - skip the full read/rewrite pass entirely.
   string firstLine = FileReadString(h);
   string firstFields[];
   if(StringLen(firstLine) == 0 || StringSplit(firstLine, ';', firstFields) < 10 ||
      (datetime)StringToInteger(firstFields[9]) >= cutoff)
   {
      FileClose(h);
      Unlock();
      return;
   }
   FileSeek(h, 0, SEEK_SET);

   string kept = "";
   int totalLines = 0, keptLines = 0;

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) == 0) continue;
      totalLines++;

      string p[];
      if(StringSplit(line, ';', p) < 10) continue;

      datetime evTime = (datetime)StringToInteger(p[9]);
      if(evTime >= cutoff)
      {
         kept += line + "\n";
         keptLines++;
      }
   }
   FileClose(h);

   if(keptLines == totalLines)
   {
      Unlock();
      return;  // Nothing to trim
   }

   int hw = FileOpen(EVENTS_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(hw != INVALID_HANDLE)
   {
      FileWriteString(hw, kept);
      FileClose(hw);
      Print("MAINTENANCE: Trimmed events file - kept ", keptLines, "/", totalLines, " lines (retention=", EventsRetentionSeconds, "s)");
   }
   else
   {
      Print("ERROR: Cannot rewrite events file during trim | Error: ", GetLastError());
   }

   Unlock();
}

// ---------- EVENTS ----------
void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest &r,
                        const MqlTradeResult &res)
{
   // Debug: Log all incoming events
   static int eventCounter = 0;
   eventCounter++;

   // --- SL / TP modification ---
   if(r.action == TRADE_ACTION_SLTP && res.retcode == TRADE_RETCODE_DONE)
   {
      Print("Event #", eventCounter, " - SLTP Modification detected | Magic=", r.magic, " | Expected=", MasterMagic, " | CopyAll=", CopyAllTrades);
      if(!CopyAllTrades && r.magic != MasterMagic)
      {
         Print("  -> Skipped (wrong magic)");
         return;
      }

      int symDigits = (int)SymbolInfoInteger(r.symbol, SYMBOL_DIGITS);

      g_seq++;
      string event = (string)g_seq + ";MODIFY;" +
         (string)r.position + ";" +
         r.symbol + ";0;0;" +
         DoubleToString(r.sl, symDigits) + ";" +
         DoubleToString(r.tp, symDigits) + ";" +
         (string)MasterMagic + ";" +
         (string)(long)TimeCurrent();

      Print("  -> Writing MODIFY event: Seq=", g_seq, " | Pos=", r.position, " | SL=", r.sl, " | TP=", r.tp);
      Emit(event);
      SaveSeq(g_seq);
      return;
   }

   // --- Deal events (OPEN / CLOSE) ---
   if(t.type != TRADE_TRANSACTION_DEAL_ADD)
   {
      // Uncomment for very verbose debugging:
      // Print("Event #", eventCounter, " - Skipped (not DEAL_ADD, type=", t.type, ")");
      return;
   }

   if(!HistoryDealSelect(t.deal))
   {
      Print("Event #", eventCounter, " - ERROR: Cannot select deal ", t.deal);
      return;
   }

   long dealMagic = (long)HistoryDealGetInteger(t.deal, DEAL_MAGIC);
   Print("Event #", eventCounter, " - Deal detected | Magic=", dealMagic, " | Expected=", MasterMagic, " | CopyAll=", CopyAllTrades, " | Deal=", t.deal);

   if(!CopyAllTrades && dealMagic != MasterMagic)
   {
      Print("  -> Skipped (wrong magic)");
      return;
   }

   long entry = (long)HistoryDealGetInteger(t.deal, DEAL_ENTRY);
   long dtype = (long)HistoryDealGetInteger(t.deal, DEAL_TYPE);
   long posid = (long)HistoryDealGetInteger(t.deal, DEAL_POSITION_ID);
   string sym = HistoryDealGetString(t.deal, DEAL_SYMBOL);

   if(entry == DEAL_ENTRY_IN)
   {
      // Get SL/TP and LOT from the opened position
      double sl = 0, tp = 0, lot = 0;
      if(PositionSelectByTicket(posid))
      {
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
         lot = PositionGetDouble(POSITION_VOLUME);
      }

      int symDigits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

      g_seq++;
      string event = (string)g_seq + ";OPEN;" +
         (string)posid + ";" +
         sym + ";" +
         (dtype==DEAL_TYPE_BUY ? "BUY" : "SELL") + ";" +
         DoubleToString(lot, 2) + ";" +
         DoubleToString(sl, symDigits) + ";" +
         DoubleToString(tp, symDigits) + ";" +
         (string)MasterMagic + ";" +
         (string)(long)TimeCurrent();

      Print("  -> Writing OPEN event: Seq=", g_seq, " | Pos=", posid, " | ", sym, " | Lot=", lot, " | SL=", sl, " | TP=", tp);
      Emit(event);
      SaveSeq(g_seq);
      return;
   }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      // Check whether the position still exists with remaining volume -
      // if so this was only a partial close, not a full close.
      bool stillOpen = PositionSelectByTicket(posid);
      g_seq++;

      string event;
      if(stillOpen)
      {
         double remainingLot = PositionGetDouble(POSITION_VOLUME);
         event = (string)g_seq + ";PARTIAL;" +
            (string)posid + ";" +
            sym + ";" +
            (dtype==DEAL_TYPE_BUY ? "SELL" : "BUY") + ";" +   // remaining position's original side
            DoubleToString(remainingLot, 2) + ";0;0;" +
            (string)MasterMagic + ";" +
            (string)(long)TimeCurrent();

         Print("  -> Writing PARTIAL event: Seq=", g_seq, " | Pos=", posid, " | ", sym, " | RemainingLot=", remainingLot);
      }
      else
      {
         event = (string)g_seq + ";CLOSE;" +
            (string)posid + ";" +
            sym + ";0;0;0;0;" +
            (string)MasterMagic + ";" +
            (string)(long)TimeCurrent();

         Print("  -> Writing CLOSE event: Seq=", g_seq, " | Pos=", posid, " | ", sym);
      }

      Emit(event);
      SaveSeq(g_seq);
      return;
   }

   if(entry == DEAL_ENTRY_INOUT)
   {
      // Reversal: the existing position was closed and a new one opened in
      // the opposite direction within the same deal (netting account).
      g_seq++;
      string closeEvent = (string)g_seq + ";CLOSE;" +
         (string)posid + ";" +
         sym + ";0;0;0;0;" +
         (string)MasterMagic + ";" +
         (string)(long)TimeCurrent();

      Print("  -> Writing CLOSE event (reversal): Seq=", g_seq, " | Pos=", posid, " | ", sym);
      Emit(closeEvent);
      SaveSeq(g_seq);

      double sl = 0, tp = 0, lot = 0;
      if(PositionSelectByTicket(posid))
      {
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
         lot = PositionGetDouble(POSITION_VOLUME);
      }

      int symDigits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

      g_seq++;
      string openEvent = (string)g_seq + ";OPEN;" +
         (string)posid + ";" +
         sym + ";" +
         (dtype==DEAL_TYPE_BUY ? "BUY" : "SELL") + ";" +
         DoubleToString(lot, 2) + ";" +
         DoubleToString(sl, symDigits) + ";" +
         DoubleToString(tp, symDigits) + ";" +
         (string)MasterMagic + ";" +
         (string)(long)TimeCurrent();

      Print("  -> Writing OPEN event (reversal): Seq=", g_seq, " | Pos=", posid, " | ", sym, " | Lot=", lot);
      Emit(openEvent);
      SaveSeq(g_seq);
      return;
   }
}

