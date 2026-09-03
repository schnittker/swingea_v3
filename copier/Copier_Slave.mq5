#property strict
#include <Trade/Trade.mqh>
#include "Copier_Lock.mqh"
CTrade trade;

// ---------- INPUT ----------
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

// ---------- FILES ----------
// Files are stored in the common MT5 data folder (using FILE_COMMON flag)
string EVENTS_FILE  = "copier_events.csv";  // Gemeinsam für alle
string STATE_FILE;                          // Pro Slave
string MAP_FILE;                            // Pro Slave

long lastSeq = 0;
long lastReadOffset = 0;  // Byte offset into EVENTS_FILE already processed - avoids full-file rescans

void InitFiles()
{
   STATE_FILE = "slave_" + SlaveID + "_state.txt";
   MAP_FILE   = "slave_" + SlaveID + "_map.csv";
   Print("Slave ", SlaveID, " files initialized");
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

// ---------- STATE ----------
// Loads lastSeq and lastReadOffset (format: "seq;offset") into the globals.
void LoadState()
{
   int h = FileOpen(STATE_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
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
   int h = FileOpen(STATE_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("ERROR: Cannot save state file: ", STATE_FILE, " | Error: ", GetLastError());
      return;
   }
   FileWrite(h, (string)lastSeq + ";" + (string)lastReadOffset);
   FileClose(h);
}

// ---------- MAP ----------
void MapPut(long master, ulong slave)
{
   // Read existing map and update/add entry
   string map_content = "";
   bool found = false;

   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
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
   h = FileOpen(MAP_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
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

   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
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
      h = FileOpen(MAP_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
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

ulong MapGet(long master)
{
   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return 0;

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      string p[];
      if(StringSplit(line,';',p)==2)
         if((long)StringToInteger(p[0])==master)
         {
            FileClose(h);
            return (ulong)StringToInteger(p[1]);
         }
   }
   FileClose(h);
   return 0;
}

bool MapHasSlaveTicket(ulong slaveTicket)
{
   int h = FileOpen(MAP_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return false;

   bool found = false;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      string p[];
      if(StringSplit(line, ';', p) == 2 && (ulong)StringToInteger(p[1]) == slaveTicket)
      {
         found = true;
         break;
      }
   }
   FileClose(h);
   return found;
}

// Resolves the slave position ticket for a just-executed trade. Normally the
// deal is immediately visible in history, but under load it can lag - retry a
// few times before falling back to scanning open positions for this symbol.
ulong ResolvePositionTicket(ulong dealTicket, string sym)
{
   for(int attempt = 0; attempt < 5; attempt++)
   {
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
         return (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      Sleep(50);
   }

   Print("WARNING: HistoryDealSelect failed for deal ", dealTicket, " | Symbol=", sym,
         " - falling back to open position scan");

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != SlaveMagic) continue;
      if(MapHasSlaveTicket(ticket)) continue;

      return ticket;
   }

   return 0;
}

// ---------- RISK ----------
double DD()
{
   double b = AccountInfoDouble(ACCOUNT_BALANCE);
   if(b <= 0) return 0;

   double e = AccountInfoDouble(ACCOUNT_EQUITY);
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
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
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
   double min = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
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
         trade.SetExpertMagicNumber((ulong)SlaveMagic);
         bool success = false;
         if(pending[i].side == "BUY")
            success = trade.Buy(lot, pending[i].symbol, 0, 0, 0);
         else
            success = trade.Sell(lot, pending[i].symbol, 0, 0, 0);

         if(success)
         {
            ulong dealTicket = trade.ResultDeal();
            ulong pos_ticket = ResolvePositionTicket(dealTicket, pending[i].symbol);
            if(pos_ticket > 0)
            {
               MapPut(pending[i].masterPosId, pos_ticket);
               Print("OPEN (timeout): Mapped Master=", pending[i].masterPosId, " to Slave=", pos_ticket,
                     " | MasterLot=", pending[i].masterLot, " | SlaveLot=", lot, " | Symbol=", pending[i].symbol);
            }
            else
            {
               Print("ERROR OPEN (timeout): Could not resolve position ticket for Master=", pending[i].masterPosId,
                     " | Symbol=", pending[i].symbol, " - mapping missing, manual reconciliation required");
            }
         }
         else
         {
            Print("ERROR OPEN (timeout): Failed to open position for ", pending[i].symbol,
                  " | Master=", pending[i].masterPosId, " | Error=", GetLastError(), " | RetCode=", trade.ResultRetcode());
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
   if(SlaveMagic < 0 || MasterMagic < 0)
   {
      Print("ERROR: MasterMagic/SlaveMagic must be non-negative (magic numbers are unsigned) | MasterMagic=",
            MasterMagic, " | SlaveMagic=", SlaveMagic);
      return INIT_PARAMETERS_INCORRECT;
   }

   InitFiles();  // Initialize file paths with SlaveID
   LoadState();
   EventSetTimer(TimerSeconds);
   Print("Slave ", SlaveID, " initialized | State=", lastSeq, " | Offset=", lastReadOffset);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   EventKillTimer();
   SaveState();
   Print("Slave ", SlaveID, " stopped | LastSeq=", lastSeq);
}

// ---------- EXEC ----------
void OnTimer()
{
   // Cleanup timed-out pending positions
   CleanupTimedOutPending();

   // Read new lines while holding the lock - keep this critical section as
   // short as possible so we don't block the Master or other slaves while
   // we execute trades below.
   string newLines[];
   int newLinesCount = 0;

   if(!Lock()) return;
   int h = FileOpen(EVENTS_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h==INVALID_HANDLE){ Unlock(); return; }

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

      ArrayResize(newLines, newLinesCount + 1);
      newLines[newLinesCount] = line;
      newLinesCount++;
   }

   long newReadOffset = FileTell(h);
   FileClose(h);
   Unlock();

   // Process the buffered lines (execute trades) without holding the lock.
   // lastReadOffset is only committed once the whole batch has been fully
   // processed below - if the EA crashes mid-batch, the next run re-reads
   // this batch from the old offset and safely re-skips already-applied
   // events via the seq<=lastSeq check above, instead of permanently
   // skipping unprocessed events.
   for(int li = 0; li < newLinesCount; li++)
   {
      string p[];
      StringSplit(newLines[li], ';', p);

      long seq = StringToInteger(p[0]);

      string ev=p[1];
      long mp = StringToInteger(p[2]);
      string sym=p[3];
      string side=p[4];
      double masterLot=StringToDouble(p[5]);
      double sl=StringToDouble(p[6]);
      double tp=StringToDouble(p[7]);
      long magic=StringToInteger(p[8]);

      if(magic!=MasterMagic){ lastSeq=seq; continue; }

      trade.SetExpertMagicNumber((ulong)SlaveMagic);

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
               bool success = false;
               if(side == "BUY")
                  success = trade.Buy(lot, sym, 0, sl, tp);
               else
                  success = trade.Sell(lot, sym, 0, sl, tp);

               if(success)
               {
                  // Get the actual position ticket from the trade result
                  ulong dealTicket = trade.ResultDeal();
                  ulong pos_ticket = ResolvePositionTicket(dealTicket, sym);
                  if(pos_ticket > 0)
                  {
                     MapPut(mp, pos_ticket);
                     Print("OPEN (immediate): Mapped Master=", mp, " to Slave=", pos_ticket,
                           " | MasterLot=", masterLot, " | SlaveLot=", lot, " | Symbol=", sym,
                           " | SL=", sl, " | TP=", tp);
                  }
                  else
                  {
                     Print("ERROR OPEN (immediate): Could not resolve position ticket for Master=", mp,
                           " | Symbol=", sym, " - mapping missing, manual reconciliation required");
                  }
               }
               else
               {
                  Print("ERROR OPEN (immediate): Failed to open position for ", sym,
                        " | Master=", mp, " | Error=", GetLastError(), " | RetCode=", trade.ResultRetcode());
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
                  bool success = false;
                  if(pendingPos.side == "BUY")
                     success = trade.Buy(lot, pendingPos.symbol, 0, sl, tp);
                  else
                     success = trade.Sell(lot, pendingPos.symbol, 0, sl, tp);

                  if(success)
                  {
                     // Get the actual position ticket from the trade result
                     ulong dealTicket = trade.ResultDeal();
                     ulong pos_ticket = ResolvePositionTicket(dealTicket, pendingPos.symbol);
                     if(pos_ticket > 0)
                     {
                        MapPut(mp, pos_ticket);
                        Print("OPEN (from MODIFY): Mapped Master=", mp, " to Slave=", pos_ticket,
                              " | MasterLot=", pendingPos.masterLot, " | SlaveLot=", lot, " | Symbol=", pendingPos.symbol,
                              " | SL=", sl, " | TP=", tp);
                     }
                     else
                     {
                        Print("ERROR OPEN (from MODIFY): Could not resolve position ticket for Master=", mp,
                              " | Symbol=", pendingPos.symbol, " - mapping missing, manual reconciliation required");
                     }
                     RemovePending(mp);
                  }
                  else
                  {
                     Print("ERROR OPEN (from MODIFY): Failed to open position for ", pendingPos.symbol,
                           " | Master=", mp, " | Error=", GetLastError(), " | RetCode=", trade.ResultRetcode());
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
            ulong t = MapGet(mp);
            if(t > 0)
            {
               if(!trade.PositionModify(t, sl, tp))
               {
                  Print("ERROR MODIFY: Failed to modify position ", t, " | Master=", mp,
                        " | Error=", GetLastError(), " | RetCode=", trade.ResultRetcode());
               }
               else
               {
                  Print("MODIFY: Position ", t, " modified | Master=", mp, " | SL=", sl, " | TP=", tp);
               }
            }
            else
            {
               Print("WARNING MODIFY: No slave position found for Master=", mp);
            }
         }
      }

      if(ev=="PARTIAL")
      {
         // Master partially closed the position - scale the remaining master
         // lot to get our target remaining volume and close the difference.
         ulong t = MapGet(mp);
         if(t > 0 && PositionSelectByTicket(t))
         {
            double targetLot = ScaleLot(sym, masterLot);  // masterLot holds remaining lot for PARTIAL events
            double currentLot = PositionGetDouble(POSITION_VOLUME);
            double closeLot = RoundLotDownToStep(sym, currentLot - targetLot);
            double min = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);

            if(closeLot >= min)
            {
               if(!trade.PositionClosePartial(t, closeLot))
               {
                  Print("ERROR PARTIAL: Failed to partially close position ", t, " | Master=", mp,
                        " | CloseLot=", closeLot, " | Error=", GetLastError(), " | RetCode=", trade.ResultRetcode());
               }
               else
               {
                  Print("PARTIAL: Position ", t, " reduced by ", closeLot, " | Master=", mp, " | RemainingTarget=", targetLot);
               }
            }
         }
         else
         {
            Print("WARNING PARTIAL: No slave position found for Master=", mp);
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
            ulong t = MapGet(mp);
            if(t > 0)
            {
               if(!trade.PositionClose(t))
               {
                  Print("ERROR CLOSE: Failed to close position ", t, " | Master=", mp,
                        " | Error=", GetLastError(), " | RetCode=", trade.ResultRetcode());
               }
               else
               {
                  Print("CLOSE: Position ", t, " closed | Master=", mp);
                  // Clean up the mapping after successful close
                  MapDelete(mp);
               }
            }
            else
            {
               Print("WARNING CLOSE: No slave position found for Master=", mp);
            }
         }
      }

      lastSeq=seq;
      SaveState();
   }

   // Whole batch processed successfully - now safe to advance the read offset.
   lastReadOffset = newReadOffset;
   SaveState();
}
