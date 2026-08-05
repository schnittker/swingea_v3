//+------------------------------------------------------------------+
//| TradeExecution.mqh                                               |
//| Order-Wrapper fuer das Hedge-Konto. ALLE Operationen adressieren |
//| eine Position ausdruecklich per Ticket (request.position), nie   |
//| implizit per Symbol - auf einem Hedge-Konto koennen mehrere      |
//| Positionen verschiedener Strategien im selben Symbol liegen und  |
//| ein symbolbasiertes Close/Modify wuerde die falsche treffen.    |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"

#define TRADE_DEFAULT_DEVIATION_POINTS 20

//+------------------------------------------------------------------+
//| Ermittelt den vom Broker fuer dieses Symbol unterstuetzten       |
//| Order-Filling-Modus (nicht jeder Broker unterstuetzt FOK/IOC).   |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(const string symbol)
  {
   int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   // ORDER_FILLING_RETURN ist bei Market-Execution NICHT zulaessig und wuerde
   // die Order mit TRADE_RETCODE_INVALID_FILL abweisen. IOC ist der sichere
   // Fallback fuer Market-Deals, wenn der Broker im SYMBOL_FILLING_MODE weder
   // FOK noch IOC explizit meldet (praktisch von allen Market-Brokern akzeptiert).
   return ORDER_FILLING_IOC;
  }

//+------------------------------------------------------------------+
//| Kompaktes Diagnose-Logging fuer fehlgeschlagene Trade-Requests.  |
//+------------------------------------------------------------------+
void LogTradeFailure(const string context, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   PrintFormat("%s FEHLGESCHLAGEN: symbol=%s retcode=%d comment=%s lasterror=%d",
               context, request.symbol, result.retcode, result.comment, GetLastError());
  }

//+------------------------------------------------------------------+
//| Eroeffnet eine neue Market-Position. Gibt das Ticket zurueck     |
//| (0 = Fehler). SL/TP werden gleich mit der Eroeffnung gesetzt.    |
//+------------------------------------------------------------------+
ulong OpenPosition(const string symbol,
                    const ENUM_SIGNAL_DIR direction,
                    const double volume,
                    const double slPrice,
                    const double tpPrice,
                    const long magic,
                    const string comment)
  {
   if(direction == SIGNAL_NONE || volume <= 0.0)
      return 0;

   MqlTradeRequest request={};
   MqlTradeResult  result={};

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = symbol;
   request.volume       = volume;
   request.type         = (direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price        = (direction == SIGNAL_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                                      : SymbolInfoDouble(symbol, SYMBOL_BID);
   request.sl            = slPrice;
   request.tp            = tpPrice;
   request.deviation     = TRADE_DEFAULT_DEVIATION_POINTS;
   request.magic         = magic;
   request.comment       = comment;
   request.type_filling  = GetFillingMode(symbol);
   request.type_time      = ORDER_TIME_GTC;

   // Erfolg wird ueber den RETCODE festgestellt, nicht ueber result.deal:
   // bei synchronem OrderSend darf result.deal auch bei erfolgreichem Fill
   // 0 sein (Deal-Ticket zum Antwortzeitpunkt noch nicht bekannt) - ein
   // deal==0-Check wuerde gueltige Fills verwerfen. TRADE_RETCODE_DONE = voll
   // ausgefuehrt. TRADE_RETCODE_PLACED wird NICHT als Fill gewertet (Order nur
   // angenommen, keine Position) - sonst wuerde die Tages-Frequenzsperre
   // gesetzt, obwohl der PositionTracker die Position (noch) nicht sieht.
   if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
     {
      LogTradeFailure("OpenPosition", request, result);
      return 0;
     }

   // Rueckgabe > 0 signalisiert dem Aufrufer nur "Fill erfolgreich" (Erfolg
   // steht bereits durch den DONE-Retcode fest). Das konkrete Positions-Ticket
   // loest der PositionTracker beim naechsten Re-Sync ueber die Magic-Number
   // auf. Falls weder deal noch order in der Antwort gesetzt sind, wird 1
   // zurueckgegeben, damit ein gueltiger Fill nie faelschlich als Fehler (0)
   // interpretiert wird.
   if(result.deal > 0)
      return result.deal;
   if(result.order > 0)
      return (ulong)result.order;
   return 1;
  }

//+------------------------------------------------------------------+
//| Schliesst eine konkrete Position per Ticket (voll oder teilweise|
//| ueber volume). Selektiert die Position vorher explizit, um      |
//| Symbol/Typ/Magic korrekt aus dem aktuellen Positionszustand zu   |
//| lesen statt sie zu erraten.                                      |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(const ulong ticket, const double volume = 0.0)
  {
   if(!PositionSelectByTicket(ticket))
     {
      PrintFormat("ClosePositionByTicket: Ticket %I64u nicht gefunden (bereits geschlossen?).", ticket);
      return false;
     }

   string symbol      = PositionGetString(POSITION_SYMBOL);
   long   posType     = PositionGetInteger(POSITION_TYPE);
   double posVolume   = PositionGetDouble(POSITION_VOLUME);
   double closeVolume = (volume > 0.0 && volume < posVolume) ? volume : posVolume;

   MqlTradeRequest request={};
   MqlTradeResult  result={};

   request.action       = TRADE_ACTION_DEAL;
   request.position     = ticket;
   request.symbol       = symbol;
   request.volume       = closeVolume;
   request.type         = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price        = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                                           : SymbolInfoDouble(symbol, SYMBOL_ASK);
   request.deviation    = TRADE_DEFAULT_DEVIATION_POINTS;
   request.magic        = PositionGetInteger(POSITION_MAGIC);
   request.type_filling = GetFillingMode(symbol);

   if(!OrderSend(request, result) || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED))
     {
      LogTradeFailure("ClosePositionByTicket", request, result);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Aendert SL/TP einer bestehenden Position per Ticket (z.B. fuer  |
//| Trailing/Breakeven). request.position stellt sicher, dass bei    |
//| mehreren Positionen im selben Symbol die richtige getroffen wird.|
//+------------------------------------------------------------------+
bool ModifyPositionSLTP(const ulong ticket, const double newSL, const double newTP)
  {
   if(!PositionSelectByTicket(ticket))
     {
      PrintFormat("ModifyPositionSLTP: Ticket %I64u nicht gefunden.", ticket);
      return false;
     }

   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   if(MathAbs(currentSL - newSL) < 1e-8 && MathAbs(currentTP - newTP) < 1e-8)
      return true; // keine Aenderung notwendig

   MqlTradeRequest request={};
   MqlTradeResult  result={};

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = PositionGetString(POSITION_SYMBOL);
   request.sl       = newSL;
   request.tp       = newTP;

   if(!OrderSend(request, result) || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED))
     {
      LogTradeFailure("ModifyPositionSLTP", request, result);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
