//+------------------------------------------------------------------+
//|                                                  TradeMailer.mq5 |
//|   Eigenstaendiger EA: sendet eine E-Mail bei jedem Oeffnen,      |
//|   Bearbeiten (SL/TP, Volumen-Erhoehung) und Schliessen (auch     |
//|   Teilschluss) eines Trades - fuer ALLE Positionen am Account,   |
//|   unabhaengig von Magic-Nummer oder Symbol.                      |
//|                                                                    |
//|   Voraussetzung (einmalig im Terminal): Tools->Options->Email     |
//|   konfiguriert + "Allow Email" in den EA-Eigenschaften aktiviert. |
//|   SendMail() ist vom Terminal rate-limited (Fehler 4515 bei zu    |
//|   vielen Mails/Zeitfenster) - bei wenigen Trades/Tag unkritisch.  |
//+------------------------------------------------------------------+
#property strict
#property description "Sendet E-Mail-Benachrichtigungen fuer alle Trade-Events (Open/Modify/Close) am Account."

input bool InpEnableNotifications = true;   // einziger Ein/Aus-Schalter

//--- Snapshot einer offenen Position (Positions-ID-keyed, funktioniert fuer
//--- Hedging- und Netting-Konten gleichermassen).
struct SPosSnap
  {
   ulong             ticket;   // Positions-ID
   string            symbol;
   double            volume;
   double            sl;
   double            tp;
   long              posType;  // POSITION_TYPE_BUY / POSITION_TYPE_SELL
  };

SPosSnap g_snaps[];

//+------------------------------------------------------------------+
//| Snapshot-Helfer                                                   |
//+------------------------------------------------------------------+
int FindSnapIndex(const ulong posid)
  {
   for(int i = 0; i < ArraySize(g_snaps); i++)
      if(g_snaps[i].ticket == posid)
         return i;
   return -1;
  }

void UpsertSnap(const ulong posid, const string symbol, const double volume,
                const double sl, const double tp, const long posType)
  {
   int idx = FindSnapIndex(posid);
   if(idx < 0)
     {
      idx = ArraySize(g_snaps);
      ArrayResize(g_snaps, idx + 1);
      g_snaps[idx].ticket = posid;
     }
   g_snaps[idx].symbol  = symbol;
   g_snaps[idx].volume  = volume;
   g_snaps[idx].sl      = sl;
   g_snaps[idx].tp      = tp;
   g_snaps[idx].posType = posType;
  }

void RemoveSnap(const ulong posid)
  {
   int idx = FindSnapIndex(posid);
   if(idx < 0)
      return;
   int last = ArraySize(g_snaps) - 1;
   if(idx != last)
      g_snaps[idx] = g_snaps[last];
   ArrayResize(g_snaps, last);
  }

//+------------------------------------------------------------------+
//| Formatierung/Berechnung                                           |
//+------------------------------------------------------------------+
string DirStr(const long posType)
  {
   return (posType == POSITION_TYPE_BUY) ? "LONG" : "SHORT";
  }

//--- Netto-Profit ueber die gesamte Position (inkl. aller Teilschluesse),
//--- aus der Deal-History summiert (Profit + Swap + Commission).
double ComputePositionNetProfit(const ulong posid)
  {
   double net = 0.0;
   if(!HistorySelectByPosition(posid))
      return net;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      net += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      net += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      net += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
     }
   return net;
  }

void SendNotification(const string subject, const string body)
  {
   if(!InpEnableNotifications)
      return;
   if(!SendMail(subject, body))
      PrintFormat("TradeMailer: SendMail fehlgeschlagen, Fehler=%d", GetLastError());
  }

//+------------------------------------------------------------------+
//| E-Mail-Komponisten (Deutsch, Feldstil wie Notifications.mqh)      |
//+------------------------------------------------------------------+
void NotifyOpened(const string symbol, const ulong posid, const long magic,
                   const long posType, const double lot, const double sl, const double tp)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string dirStr  = DirStr(posType);
   string subject = StringFormat("TradeMailer: %s eroeffnet (%s)", dirStr, symbol);
   string body    = StringFormat("Symbol: %s\nPosition: %I64u\nMagic: %I64d\nRichtung: %s\nLot: %.2f\nSL: %s\nTP: %s\nZeit: %s",
                                  symbol, posid, magic, dirStr, lot,
                                  DoubleToString(sl, digits),
                                  DoubleToString(tp, digits),
                                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   SendNotification(subject, body);
  }

void NotifyVolumeIncreased(const string symbol, const ulong posid, const long magic, const long posType,
                            const double oldLot, const double newLot, const double sl, const double tp)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string dirStr  = DirStr(posType);
   string subject = StringFormat("TradeMailer: %s Volumen erhoeht (%s)", dirStr, symbol);
   string body    = StringFormat("Symbol: %s\nPosition: %I64u\nMagic: %I64d\nRichtung: %s\nLot: %.2f -> %.2f\nSL: %s\nTP: %s\nZeit: %s",
                                  symbol, posid, magic, dirStr, oldLot, newLot,
                                  DoubleToString(sl, digits),
                                  DoubleToString(tp, digits),
                                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   SendNotification(subject, body);
  }

void NotifyPartialClosed(const string symbol, const ulong posid, const long magic, const long posType,
                          const double oldLot, const double remainingLot)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string dirStr  = DirStr(posType);
   string subject = StringFormat("TradeMailer: %s teilweise geschlossen (%s)", dirStr, symbol);
   string body    = StringFormat("Symbol: %s\nPosition: %I64u\nMagic: %I64d\nRichtung: %s\nLot: %.2f -> %.2f\nZeit: %s",
                                  symbol, posid, magic, dirStr, oldLot, remainingLot,
                                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   SendNotification(subject, body);
  }

void NotifySLTPModified(const string symbol, const ulong posid, const long magic, const long posType,
                         const double oldSl, const double newSl, const double oldTp, const double newTp)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string dirStr  = DirStr(posType);
   string subject = StringFormat("TradeMailer: %s SL/TP geaendert (%s)", dirStr, symbol);
   string body    = StringFormat("Symbol: %s\nPosition: %I64u\nMagic: %I64d\nRichtung: %s\nSL: %s -> %s\nTP: %s -> %s\nZeit: %s",
                                  symbol, posid, magic, dirStr,
                                  DoubleToString(oldSl, digits), DoubleToString(newSl, digits),
                                  DoubleToString(oldTp, digits), DoubleToString(newTp, digits),
                                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   SendNotification(subject, body);
  }

void NotifyClosed(const string symbol, const ulong posid, const long magic, const long posType,
                   const double volume, const double profit)
  {
   string dirStr  = DirStr(posType);
   string subject = StringFormat("TradeMailer: %s geschlossen (%s) - %.2f %s",
                                  dirStr, symbol, profit, AccountInfoString(ACCOUNT_CURRENCY));
   string body    = StringFormat("Symbol: %s\nPosition: %I64u\nMagic: %I64d\nRichtung: %s\nLot: %.2f\nProfit: %.2f %s\nZeit: %s",
                                  symbol, posid, magic, dirStr, volume, profit, AccountInfoString(ACCOUNT_CURRENCY),
                                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   SendNotification(subject, body);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Seedet g_snaps[] aus den aktuell offenen Positionen - KEINE Mails
   // beim Seeding, sonst Mail-Flut bei jedem Terminal-Neustart!
   ArrayResize(g_snaps, 0);
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      UpsertSnap(ticket,
                 PositionGetString(POSITION_SYMBOL),
                 PositionGetDouble(POSITION_VOLUME),
                 PositionGetDouble(POSITION_SL),
                 PositionGetDouble(POSITION_TP),
                 PositionGetInteger(POSITION_TYPE));
     }

   PrintFormat("TradeMailer gestartet | Benachrichtigungen=%s | Seeded=%d offene Position(en)",
               InpEnableNotifications ? "AN" : "AUS", ArraySize(g_snaps));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Keine Persistenz noetig - Snapshots werden bei jedem Start neu geseedet.
  }

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   //--- Pfad A: reine SL/TP-Bearbeitung (kein Volumen-/Symbolwechsel).
   if(request.action == TRADE_ACTION_SLTP && result.retcode == TRADE_RETCODE_DONE)
     {
      int idx = FindSnapIndex(request.position);
      if(idx < 0)
         return;   // unbekannte Position (z.B. vor EA-Start bereits offen und nie geseeded) - ignorieren

      double oldSl = g_snaps[idx].sl;
      double oldTp = g_snaps[idx].tp;

      NotifySLTPModified(g_snaps[idx].symbol, request.position, request.magic, g_snaps[idx].posType,
                          oldSl, request.sl, oldTp, request.tp);

      UpsertSnap(request.position, g_snaps[idx].symbol, g_snaps[idx].volume,
                 request.sl, request.tp, g_snaps[idx].posType);
      return;
     }

   //--- Pfad B: Deal-basierte Events (Open/Volumen-Erhoehung/Close/Partial/Reversal).
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return;   // Balance-/Credit-/Sonstige-Deals ausblenden

   long entry   = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong posid  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string sym   = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long magic   = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

   if(entry == DEAL_ENTRY_IN)
     {
      double sl = 0, tp = 0, lot = 0;
      long posType = dealType;   // Fallback, falls Position nicht mehr selektierbar ist
      if(PositionSelectByTicket(posid))
        {
         sl      = PositionGetDouble(POSITION_SL);
         tp      = PositionGetDouble(POSITION_TP);
         lot     = PositionGetDouble(POSITION_VOLUME);
         posType = PositionGetInteger(POSITION_TYPE);
        }

      int idx = FindSnapIndex(posid);
      if(idx < 0)
        {
         NotifyOpened(sym, posid, magic, posType, lot, sl, tp);
        }
      else
        {
         double oldLot = g_snaps[idx].volume;
         NotifyVolumeIncreased(sym, posid, magic, posType, oldLot, lot, sl, tp);
        }

      UpsertSnap(posid, sym, lot, sl, tp, posType);
      return;
     }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
     {
      int idx = FindSnapIndex(posid);
      long posType = (idx >= 0) ? g_snaps[idx].posType : (dealType == DEAL_TYPE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
      double oldLot = (idx >= 0) ? g_snaps[idx].volume : 0.0;

      bool stillOpen = PositionSelectByTicket(posid);
      if(stillOpen)
        {
         double remainingLot = PositionGetDouble(POSITION_VOLUME);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);

         NotifyPartialClosed(sym, posid, magic, posType, oldLot, remainingLot);
         UpsertSnap(posid, sym, remainingLot, sl, tp, posType);
        }
      else
        {
         double profit = ComputePositionNetProfit(posid);
         NotifyClosed(sym, posid, magic, posType, oldLot, profit);
         RemoveSnap(posid);
        }
      return;
     }

   if(entry == DEAL_ENTRY_INOUT)
     {
      //--- Netting-Reversal: bestehende Position wird geschlossen und in
      //--- Gegenrichtung neu eroeffnet - synthetisches Close + Open.
      int idx = FindSnapIndex(posid);
      long oldPosType = (idx >= 0) ? g_snaps[idx].posType : (dealType == DEAL_TYPE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
      double oldLot   = (idx >= 0) ? g_snaps[idx].volume : 0.0;

      double profit = ComputePositionNetProfit(posid);
      NotifyClosed(sym, posid, magic, oldPosType, oldLot, profit);
      RemoveSnap(posid);

      double sl = 0, tp = 0, lot = 0;
      long newPosType = dealType;
      if(PositionSelectByTicket(posid))
        {
         sl         = PositionGetDouble(POSITION_SL);
         tp         = PositionGetDouble(POSITION_TP);
         lot        = PositionGetDouble(POSITION_VOLUME);
         newPosType = PositionGetInteger(POSITION_TYPE);
        }

      NotifyOpened(sym, posid, magic, newPosType, lot, sl, tp);
      UpsertSnap(posid, sym, lot, sl, tp, newPosType);
      return;
     }
  }
//+------------------------------------------------------------------+
