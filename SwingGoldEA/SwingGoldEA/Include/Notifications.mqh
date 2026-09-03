//+------------------------------------------------------------------+
//|                                                Notifications.mqh |
//|   E-Mail-Benachrichtigung bei Trade-Open/-Close ueber SendMail().|
//|   Voraussetzung (einmalig im Terminal): Tools->Options->Email    |
//|   konfiguriert + "Allow Email" in den EA-Eigenschaften aktiviert.|
//|   SendMail() ist vom Terminal rate-limited (Fehler 4515 bei zu   |
//|   vielen Mails/Zeitfenster) - bei wenigen Trades/Tag unkritisch. |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_NOTIFICATIONS_MQH__
#define __SWINGGOLD_NOTIFICATIONS_MQH__

#include "Types.mqh"

class CNotifications
  {
private:
   bool              m_enabled;

   void              Send(const string subject, const string body)
     {
      if(!SendMail(subject, body))
         PrintFormat("Notifications: SendMail fehlgeschlagen, Fehler=%d", GetLastError());
     }

public:
                     CNotifications(void): m_enabled(false) {}

   void              Configure(const bool enabled)
     {
      m_enabled = enabled;
     }

   //--- Trade eroeffnet. targetPrice = Teilgewinn-Ziel (0 = keins definiert).
   void              TradeOpened(const string moduleName, const string symbol, const ENUM_SIGNAL_DIR dir,
                                 const double lots, const double entry, const double sl, const double targetPrice)
     {
      if(!m_enabled)
         return;

      string dirStr  = (dir == SIGNAL_LONG) ? "LONG" : "SHORT";
      string subject = StringFormat("SwingGoldEA: %s eroeffnet (%s)", dirStr, moduleName);
      string body    = StringFormat("Symbol: %s\nModul: %s\nRichtung: %s\nLot: %.2f\nEntry: %s\nSL: %s\nTeilgewinn-Ziel: %s\nZeit: %s",
                                    symbol, moduleName, dirStr, lots,
                                    DoubleToString(entry, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
                                    DoubleToString(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
                                    targetPrice > 0.0 ? DoubleToString(targetPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)) : "-",
                                    TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
      Send(subject, body);
     }

   //--- Trade vollstaendig geschlossen (SL/TP-Hit oder manuell). profit = Netto
   //--- ueber die gesamte Position (inkl. Teilschluesse), aus History summiert.
   void              TradeClosed(const string moduleName, const string symbol, const ENUM_SIGNAL_DIR dir,
                                 const double volume, const double profit)
     {
      if(!m_enabled)
         return;

      string dirStr  = (dir == SIGNAL_LONG) ? "LONG" : "SHORT";
      string subject = StringFormat("SwingGoldEA: %s geschlossen (%s) - %.2f %s",
                                    dirStr, moduleName, profit, AccountInfoString(ACCOUNT_CURRENCY));
      string body    = StringFormat("Symbol: %s\nModul: %s\nRichtung: %s\nLot: %.2f\nProfit: %.2f %s\nZeit: %s",
                                    symbol, moduleName, dirStr, volume, profit, AccountInfoString(ACCOUNT_CURRENCY),
                                    TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
      Send(subject, body);
     }
  };

#endif // __SWINGGOLD_NOTIFICATIONS_MQH__
