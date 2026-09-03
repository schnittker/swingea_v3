#property strict

// ---------- INPUT ----------
input string MT5CommonPath      = "C:\\Users\\YourUser\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\";  // Path to MT5 Common folder (only for READING events)
input string SlaveID             = "01";  // WICHTIG: Für jeden Slave ändern! (01, 02, 03, ... 10)
input long   MasterMagic         = 10001;
input long   SlaveMagic          = 20001;

input double MasterBalance       = 100000.0;  // Fixes Master-Kapital für die Lot-Skalierung (statisch, kein Live-Sync)
input double SlaveInitialBalance = 10000.0;   // Fixes Startkapital DIESES Slaves für die Lot-Skalierung (nicht die Live-Balance!)
input double MasterRiskPercent   = 0.25;      // Risiko-%, mit dem der Master tatsächlich pro Trade handelt
input double SlaveRiskPercent    = 0.25;      // Ziel-Risiko-% für DIESEN Slave (z.B. 0.15 für Slave 1, 0.1 für Slave 2)
input double MaxAccountDDPct     = 10.0;      // Stop trading at this DD
input int    TimerSeconds        = 1;
input int    PendingTimeoutSec   = 300;       // 5 minutes timeout for pending positions
input int    Slippage            = 3;         // Slippage in points

// ---------- FILES ----------
// Events file: READ from MT5 Common folder (Master writes there)
// State/Map files: WRITE to MT4's own Files folder
string EVENTS_FILE  = "copier_events.csv";  // Read from MT5 Common
string STATE_FILE;                          // Write to MT4 Files
string MAP_FILE;                            // Write to MT4 Files
string EVENTS_PATH;                         // Normalized full path to the events file

long lastSeq = 0;
long lastReadOffset = 0;  // Byte offset into EVENTS_FILE already processed - avoids full-file rescans

// Ensures the path ends with exactly one backslash, so a missing or doubled
// trailing separator in the MT5CommonPath input doesn't silently break reads.
string NormalizePath(string path)
{
   while(StringLen(path) > 0 && StringSubstr(path, StringLen(path) - 1, 1) == "\\")
      path = StringSubstr(path, 0, StringLen(path) - 1);
   return path + "\\";
}

void InitFiles()
{
   STATE_FILE = "slave_" + SlaveID + "_state.txt";
   MAP_FILE   = "slave_" + SlaveID + "_map.csv";
   EVENTS_PATH = NormalizePath(MT5CommonPath) + EVENTS_FILE;

   Print("Slave ", SlaveID, " files initialized");
   Print("MT5 Common Path (read only): ", MT5CommonPath);
   Print("Events file path: ", EVENTS_PATH);
   Print("MT4 Files Path (write): MQL4\\Files\\");

   if(!FileIsExist(EVENTS_PATH))
   {
      Print("WARNING: Events file not found at startup: ", EVENTS_PATH);
      Print("Please verify MT5CommonPath points to the MT5 terminal's Common\\Files folder.");
   }
}

// ---------- PENDING POSITIONS ----------
struct PendingPosition
{
   long masterPosId;
   string symbol;
   string side;
   double masterLot;
   datetime openTime;
};

// Entries are removed (not just flagged) once resolved, so this array stays
// bounded by the number of currently-open pending positions rather than
// growing for the lifetime of the EA.
PendingPosition pending[];

void AddPending(long masterPos, string sym, string orderSide, double mLot)
{
   int size = ArraySize(pending);
   ArrayResize(pending, size + 1);
   pending[size].masterPosId = masterPos;
   pending[size].symbol = sym;
   pending[size].side = orderSide;
   pending[size].masterLot = mLot;
   pending[size].openTime = TimeCurrent();
   Print("PENDING: Added position ", masterPos, " | ", sym, " | ", orderSide, " | MasterLot=", mLot);
}

bool IsPending(long masterPos)
{
   for(int i = 0; i < ArraySize(pending); i++)
   {
      if(pending[i].masterPosId == masterPos)
         return true;
   }
   return false;
}

bool GetPending(long masterPos, PendingPosition &pos)
{
   for(int i = 0; i < ArraySize(pending); i++)
   {
      if(pending[i].masterPosId == masterPos)
      {
         pos = pending[i];
         return true;
      }
   }
   return false;
}

void RemovePending(long masterPos)
{
   int size = ArraySize(pending);
   for(int i = 0; i < size; i++)
   {
      if(pending[i].masterPosId == masterPos)
      {
         pending[i] = pending[size - 1];
         ArrayResize(pending, size - 1);
         Print("PENDING: Removed position ", masterPos);
         return;
      }
   }
}

// ---------- LOCK ----------
// MT4 Slave only READS events, no lock needed for reading
// Master (MT5) handles locking when writing
bool Lock()
{
   // No lock needed - we only READ the events file
   return true;
}

void Unlock()
{
   // No lock needed - we only READ the events file
}

// ---------- STATE ----------
// State file is stored in MT4's own Files folder
// Loads lastSeq and lastReadOffset (format: "seq;offset") into the globals.
void LoadState()
{
   int h = FileOpen(STATE_FILE, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;

   string line = FileReadString(h);
   FileClose(h);

   string p[];
   int n = StringSplit(line, ';', p);
   lastSeq = (n >= 1) ? (long)StringToInteger(p[0]) : 0;
   lastReadOffset = (n >= 2) ? (long)StringToInteger(p[1]) : 0;
}

void SaveState()
{
   int h = FileOpen(STATE_FILE, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("ERROR: Cannot save state file: ", STATE_FILE, " | Error: ", GetLastError());
      return;
   }
   FileWrite(h, (string)lastSeq + ";" + (string)lastReadOffset);
   FileClose(h);
}

// ---------- MAP ----------
// Map file is stored in MT4's own Files folder
void MapPut(long master, int slave)
{
   // Read existing map and update/add entry
   string map_content = "";
   bool found = false;

   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      while(!FileIsEnding(h))
      {
         string line = FileReadString(h);
         string p[];
         if(StringSplit(line, ';', p) == 2)
         {
            long m = (long)StringToInteger(p[0]);
            if(m == master)
            {
               // Update existing entry
               map_content += (string)master + ";" + (string)slave + "\n";
               found = true;
            }
            else
            {
               // Keep other entries
               map_content += line + "\n";
            }
         }
      }
      FileClose(h);
   }

   // If not found, add new entry
   if(!found)
      map_content += (string)master + ";" + (string)slave + "\n";

   // Write back
   h = FileOpen(MAP_FILE, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, map_content);
      FileClose(h);
   }
   else
   {
      Print("ERROR: Cannot write map file: ", MAP_FILE, " | Error: ", GetLastError());
   }
}

void MapDelete(long master)
{
   string map_content = "";

   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      while(!FileIsEnding(h))
      {
         string line = FileReadString(h);
         string p[];
         if(StringSplit(line, ';', p) == 2)
         {
            long m = (long)StringToInteger(p[0]);
            if(m != master)
            {
               // Keep all entries except the one we want to delete
               map_content += line + "\n";
            }
         }
      }
      FileClose(h);

      // Write back
      h = FileOpen(MAP_FILE, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h != INVALID_HANDLE)
      {
         FileWriteString(h, map_content);
         FileClose(h);
      }
      else
      {
         Print("ERROR: Cannot write map file (delete): ", MAP_FILE, " | Error: ", GetLastError());
      }
   }
}

int MapGet(long master)
{
   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return 0;

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      string p[];
      if(StringSplit(line,';',p)==2)
         if((long)StringToInteger(p[0])==master)
         {
            FileClose(h);
            return (int)StringToInteger(p[1]);
         }
   }
   FileClose(h);
   return 0;
}

// ---------- RISK ----------
double DD()
{
   double b = AccountBalance();
   if(b <= 0) return 0;

   double e = AccountEquity();
   double dd = (b - e) / b * 100.0;

   return MathMax(0, dd);
}

bool IsTradingAllowed()
{
   double dd = DD();
   if(dd >= MaxAccountDDPct)
   {
      Print("WARNING: Trading stopped - DD ", DoubleToString(dd, 2), "% >= Max ", MaxAccountDDPct, "%");
      return false;
   }
   return true;
}

// Rounds down to the broker's lot step (e.g. 0.13 -> 0.1 for step=0.1).
double RoundLotDownToStep(string sym, double lot)
{
   double step = MarketInfo(sym, MODE_LOTSTEP);
   if(step <= 0) return lot;
   return MathFloor(lot / step) * step;
}

double ScaleLot(string sym, double masterLot)
{
   // Check if trading is allowed (DD limit)
   if(!IsTradingAllowed())
      return 0;

   double slaveBalance = SlaveInitialBalance;
   double masterBalance = MasterBalance;
   if(slaveBalance <= 0 || masterBalance <= 0)
   {
      Print("ERROR: Invalid balance - check SlaveInitialBalance/MasterBalance input parameters | Slave=", slaveBalance, " Master=", masterBalance);
      return 0;
   }

   // Scale lot proportionally by balance, then adjust for this slave's target
   // risk relative to the risk% the master actually trades with:
   // SlaveLot = MasterLot * (SlaveBalance / MasterBalance) * (SlaveRiskPercent / MasterRiskPercent)
   double riskFactor = 1.0;
   if(MasterRiskPercent > 0)
      riskFactor = SlaveRiskPercent / MasterRiskPercent;
   else
      Print("WARNING: MasterRiskPercent <= 0 - ignoring risk scaling, using balance ratio only");

   double lot = masterLot * (slaveBalance / masterBalance) * riskFactor;

   // Normalize to broker requirements
   double min = MarketInfo(sym, MODE_MINLOT);
   double max = MarketInfo(sym, MODE_MAXLOT);
   double step = MarketInfo(sym, MODE_LOTSTEP);
   int lotDigits = (step > 0) ? (int)MathMax(0, MathRound(-MathLog10(step))) : 2;

   lot = RoundLotDownToStep(sym, MathMin(max, lot));

   if(lot < min)
   {
      Print("WARNING: Scaled lot ", DoubleToString(lot, lotDigits), " for ", sym,
            " is below broker minimum ", DoubleToString(min, lotDigits), " - skipping trade");
      return 0;
   }

   return NormalizeDouble(lot, lotDigits);
}

// ---------- MT4 TRADE FUNCTIONS ----------
int OpenBuy(string sym, double lot, double sl, double tp)
{
   double price = MarketInfo(sym, MODE_ASK);
   if(price == 0)
   {
      Print("ERROR: Cannot get ASK price for ", sym);
      return -1;
   }

   int ticket = OrderSend(sym, OP_BUY, lot, price, Slippage, sl, tp, "Copier", (int)SlaveMagic, 0, clrGreen);
   if(ticket < 0)
   {
      Print("ERROR: OrderSend BUY failed | Symbol=", sym, " | Lot=", lot, " | Error=", GetLastError());
   }
   return ticket;
}

int OpenSell(string sym, double lot, double sl, double tp)
{
   double price = MarketInfo(sym, MODE_BID);
   if(price == 0)
   {
      Print("ERROR: Cannot get BID price for ", sym);
      return -1;
   }

   int ticket = OrderSend(sym, OP_SELL, lot, price, Slippage, sl, tp, "Copier", (int)SlaveMagic, 0, clrRed);
   if(ticket < 0)
   {
      Print("ERROR: OrderSend SELL failed | Symbol=", sym, " | Lot=", lot, " | Error=", GetLastError());
   }
   return ticket;
}

bool ModifyOrder(int ticket, double sl, double tp)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("ERROR: Cannot select order ", ticket, " for modification");
      return false;
   }

   double openPrice = OrderOpenPrice();
   bool result = OrderModify(ticket, openPrice, sl, tp, 0, clrBlue);

   if(!result)
   {
      Print("ERROR: OrderModify failed | Ticket=", ticket, " | Error=", GetLastError());
   }

   return result;
}

bool CloseOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("ERROR: Cannot select order ", ticket, " for closing");
      return false;
   }

   double lot = OrderLots();
   double closePrice;

   if(OrderType() == OP_BUY)
      closePrice = MarketInfo(OrderSymbol(), MODE_BID);
   else
      closePrice = MarketInfo(OrderSymbol(), MODE_ASK);

   if(closePrice == 0)
   {
      Print("ERROR: Cannot get close price for ", OrderSymbol());
      return false;
   }

   bool result = OrderClose(ticket, lot, closePrice, Slippage, clrYellow);

   if(!result)
   {
      Print("ERROR: OrderClose failed | Ticket=", ticket, " | Error=", GetLastError());
   }

   return result;
}

bool ClosePartialOrder(int ticket, double closeLot)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("ERROR: Cannot select order ", ticket, " for partial closing");
      return false;
   }

   double closePrice;
   if(OrderType() == OP_BUY)
      closePrice = MarketInfo(OrderSymbol(), MODE_BID);
   else
      closePrice = MarketInfo(OrderSymbol(), MODE_ASK);

   if(closePrice == 0)
   {
      Print("ERROR: Cannot get close price for ", OrderSymbol());
      return false;
   }

   bool result = OrderClose(ticket, closeLot, closePrice, Slippage, clrYellow);

   if(!result)
   {
      Print("ERROR: OrderClose (partial) failed | Ticket=", ticket, " | CloseLot=", closeLot, " | Error=", GetLastError());
   }

   return result;
}

// ---------- PENDING TIMEOUT ----------
void CleanupTimedOutPending()
{
   datetime now = TimeCurrent();
   // Iterate backwards since resolved entries are swap-removed from the array.
   for(int i = ArraySize(pending) - 1; i >= 0; i--)
   {
      if(now - pending[i].openTime <= PendingTimeoutSec) continue;

      Print("WARNING: Pending position ", pending[i].masterPosId,
            " timed out after ", PendingTimeoutSec, " seconds - opening without SL/TP");

      double lot = ScaleLot(pending[i].symbol, pending[i].masterLot);
      if(lot > 0)
      {
         int ticket = -1;
         if(pending[i].side == "BUY")
            ticket = OpenBuy(pending[i].symbol, lot, 0, 0);
         else
            ticket = OpenSell(pending[i].symbol, lot, 0, 0);

         if(ticket > 0)
         {
            MapPut(pending[i].masterPosId, ticket);
            Print("OPEN (timeout): Mapped Master=", pending[i].masterPosId, " to Slave=", ticket,
                  " | MasterLot=", pending[i].masterLot, " | SlaveLot=", lot, " | Symbol=", pending[i].symbol);
         }
         else
         {
            Print("ERROR OPEN (timeout): Failed to open position for ", pending[i].symbol,
                  " | Master=", pending[i].masterPosId);
         }
      }
      else
      {
         Print("WARNING: ScaleLot returned 0 for ", pending[i].symbol,
               " | Master=", pending[i].masterPosId, " - DD limit reached or invalid parameters, pending position dropped");
      }

      int last = ArraySize(pending) - 1;
      pending[i] = pending[last];
      ArrayResize(pending, last);
   }
}

// ---------- INIT ----------
int OnInit()
{
   InitFiles();  // Initialize file paths with SlaveID
   LoadState();
   EventSetTimer(TimerSeconds);
   Print("========================================");
   Print("MT4 Slave ", SlaveID, " initialized");
   Print("State: ", lastSeq, " | Offset: ", lastReadOffset);
   Print("MasterMagic: ", MasterMagic);
   Print("SlaveMagic: ", SlaveMagic);
   Print("========================================");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   EventKillTimer();
   SaveState();
   Print("MT4 Slave ", SlaveID, " stopped | LastSeq=", lastSeq);
}

// ---------- EXEC ----------
void OnTimer()
{
   // Cleanup timed-out pending positions
   CleanupTimedOutPending();

   // Read events from MT5 Common folder (no lock needed for reading)
   int h = FileOpen(EVENTS_PATH, FILE_READ|FILE_TXT|FILE_SHARE_READ|FILE_ANSI);

   if(h==INVALID_HANDLE)
   {
      // File doesn't exist yet or path is wrong - warn periodically so a
      // persistent misconfiguration doesn't go unnoticed after the first tick.
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 60)
      {
         Print("WARNING: Cannot read events file: ", EVENTS_PATH);
         Print("Please check MT5CommonPath parameter. Error: ", GetLastError());
         lastWarning = TimeCurrent();
      }
      return;
   }

   // Resume from the byte offset we already processed instead of rescanning
   // the whole (ever-growing) file every tick. If the file shrank (e.g. the
   // Master trimmed old events), fall back to a full rescan.
   ulong fileSize = FileSize(h);
   if((ulong)lastReadOffset > fileSize)
   {
      Print("WARNING: Events file shrank (offset=", lastReadOffset, ", size=", fileSize, ") - resetting read offset");
      lastReadOffset = 0;
   }
   FileSeek(h, lastReadOffset, SEEK_SET);

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      string p[];
      if(StringSplit(line,';',p)<10) continue;

      long seq = StringToInteger(p[0]);
      if(seq<=lastSeq) continue;

      string ev=p[1];
      long mp = StringToInteger(p[2]);
      string sym=p[3];
      string side=p[4];
      double masterLot=StringToDouble(p[5]);
      double sl=StringToDouble(p[6]);
      double tp=StringToDouble(p[7]);
      long magic=StringToInteger(p[8]);

      if(magic!=MasterMagic){ lastSeq=seq; continue; }

      if(ev=="OPEN")
      {
         // Skip if we already have a mapping or pending entry for this master
         // position (e.g. duplicate event, re-read of an already processed line).
         if(MapGet(mp) > 0 || IsPending(mp))
         {
            Print("WARNING OPEN: Skipped - Master=", mp, " already mapped or pending");
         }
         else if(sl != 0 || tp != 0)
         {
            // Position was opened with SL/TP - open immediately
            double lot = ScaleLot(sym, masterLot);

            if(lot > 0)
            {
               int ticket = -1;
               if(side == "BUY")
                  ticket = OpenBuy(sym, lot, sl, tp);
               else
                  ticket = OpenSell(sym, lot, sl, tp);

               if(ticket > 0)
               {
                  MapPut(mp, ticket);
                  Print("OPEN (immediate): Mapped Master=", mp, " to Slave=", ticket,
                        " | MasterLot=", masterLot, " | SlaveLot=", lot, " | Symbol=", sym,
                        " | SL=", sl, " | TP=", tp);
               }
               else
               {
                  Print("ERROR OPEN (immediate): Failed to open position for ", sym,
                        " | Master=", mp);
               }
            }
            else
            {
               Print("WARNING: ScaleLot returned 0 for ", sym,
                     " | Master=", mp, " | MasterLot=", masterLot, " - DD limit reached or invalid parameters");
            }
         }
         else
         {
            // No SL/TP yet - wait for MODIFY event
            // Add to pending list with master's lot size
            AddPending(mp, sym, side, masterLot);
         }
      }

      if(ev=="MODIFY")
      {
         // Check if this is a pending position that needs to be opened
         if(IsPending(mp))
         {
            PendingPosition pendingPos;
            if(GetPending(mp, pendingPos))
            {
               // Now we have SL/TP - scale lot size from master's lot
               double lot = ScaleLot(pendingPos.symbol, pendingPos.masterLot);

               if(lot > 0)
               {
                  int ticket = -1;
                  if(pendingPos.side == "BUY")
                     ticket = OpenBuy(pendingPos.symbol, lot, sl, tp);
                  else
                     ticket = OpenSell(pendingPos.symbol, lot, sl, tp);

                  if(ticket > 0)
                  {
                     MapPut(mp, ticket);
                     Print("OPEN (from MODIFY): Mapped Master=", mp, " to Slave=", ticket,
                           " | MasterLot=", pendingPos.masterLot, " | SlaveLot=", lot, " | Symbol=", pendingPos.symbol,
                           " | SL=", sl, " | TP=", tp);
                     RemovePending(mp);
                  }
                  else
                  {
                     Print("ERROR OPEN (from MODIFY): Failed to open position for ", pendingPos.symbol,
                           " | Master=", mp);
                  }
               }
               else
               {
                  Print("WARNING: ScaleLot returned 0 for ", pendingPos.symbol,
                        " | Master=", mp, " | MasterLot=", pendingPos.masterLot, " - DD limit reached or invalid parameters");
                  RemovePending(mp);  // Remove from pending since we can't open it
               }
            }
         }
         else
         {
            // Normal modification of existing position
            int ticket = MapGet(mp);
            if(ticket > 0)
            {
               if(ModifyOrder(ticket, sl, tp))
               {
                  Print("MODIFY: Order ", ticket, " modified | Master=", mp, " | SL=", sl, " | TP=", tp);
               }
               else
               {
                  Print("ERROR MODIFY: Failed to modify order ", ticket, " | Master=", mp);
               }
            }
            else
            {
               Print("WARNING MODIFY: No slave order found for Master=", mp);
            }
         }
      }

      if(ev=="PARTIAL")
      {
         // Master partially closed the position - scale the remaining master
         // lot to get our target remaining volume and close the difference.
         int t = MapGet(mp);
         if(t > 0 && OrderSelect(t, SELECT_BY_TICKET))
         {
            double targetLot = ScaleLot(sym, masterLot);  // masterLot holds remaining lot for PARTIAL events
            double currentLot = OrderLots();
            double closeLot = RoundLotDownToStep(sym, currentLot - targetLot);
            double min = MarketInfo(sym, MODE_MINLOT);

            if(closeLot >= min)
            {
               if(ClosePartialOrder(t, closeLot))
               {
                  Print("PARTIAL: Order ", t, " reduced by ", closeLot, " | Master=", mp, " | RemainingTarget=", targetLot);
               }
            }
         }
         else
         {
            Print("WARNING PARTIAL: No slave order found for Master=", mp);
         }
      }

      if(ev=="CLOSE")
      {
         // Check if this position is still pending (closed before SL/TP was set)
         if(IsPending(mp))
         {
            RemovePending(mp);
            Print("CLOSE: Removed pending position ", mp, " (closed before SL/TP was set)");
         }
         else
         {
            // Normal close of existing position
            int ticket = MapGet(mp);
            if(ticket > 0)
            {
               if(CloseOrder(ticket))
               {
                  Print("CLOSE: Order ", ticket, " closed | Master=", mp);
                  // Clean up the mapping after successful close
                  MapDelete(mp);
               }
               else
               {
                  Print("ERROR CLOSE: Failed to close order ", ticket, " | Master=", mp);
               }
            }
            else
            {
               Print("WARNING CLOSE: No slave order found for Master=", mp);
            }
         }
      }

      lastSeq=seq;
      SaveState();
   }

   lastReadOffset = FileTell(h);
   FileClose(h);
   // No unlock needed - we don't use locks for reading
}
