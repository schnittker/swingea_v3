//+------------------------------------------------------------------+
//|                                                TradeExecution.mqh |
//|   Kapselt CTrade fuer den SwingGoldEA. SL/TP werden vor jedem     |
//|   Versand gegen StopsLevel/FreezeLevel normalisiert, der Filling- |
//|   Modus wird aus der SYMBOL_FILLING_MODE-Bitmaske abgeleitet      |
//|   (FOK bevorzugt, dann IOC, sonst RETURN). Bis zu 3 Retries bei   |
//|   REQUOTE/REQUEUE/PRICE_CHANGED mit frischem Preis (ea.md 7.5).   |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_TRADEEXECUTION_MQH__
#define __SWINGGOLD_TRADEEXECUTION_MQH__

#include <Trade/Trade.mqh>
#include "Types.mqh"

class CTradeExecution
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   int               m_stopsLevelPoints;
   int               m_freezeLevelPoints;
   int               m_maxRetries;
   string            m_orderComment;  // Telemetrie, KEINE Identitaet (Identitaet = Magic)

   //--- Leitet den unterstuetzten Filling-Modus aus der Bitmaske ab.
   ENUM_ORDER_TYPE_FILLING DetectFillingMode(void)
     {
      long filling = SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         return ORDER_FILLING_FOK;
      if((filling & SYMBOL_FILLING_IOC) != 0)
         return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
     }

   //--- SL/TP gegen die Mindestdistanz (max. von StopsLevel/FreezeLevel) normalisieren.
   //--- Ein bereits weiter entfernter Stop wird NICHT verengt.
   void              NormalizeStops(const ENUM_SIGNAL_DIR dir, const double refPrice, double &sl, double &tp)
     {
      double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits   = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double minDist = (double)MathMax(m_stopsLevelPoints, m_freezeLevelPoints) * point;

      if(sl != 0.0)
        {
         if(MathAbs(refPrice - sl) < minDist)
            sl = (dir == SIGNAL_LONG) ? (refPrice - minDist) : (refPrice + minDist);
         sl = NormalizeDouble(sl, digits);
        }

      if(tp != 0.0)
        {
         if(MathAbs(tp - refPrice) < minDist)
            tp = (dir == SIGNAL_LONG) ? (refPrice + minDist) : (refPrice - minDist);
         tp = NormalizeDouble(tp, digits);
        }
     }

public:
                     CTradeExecution(void):
                        m_symbol(""), m_stopsLevelPoints(0), m_freezeLevelPoints(0),
                        m_maxRetries(3), m_orderComment("SwingGoldEA") {}

   void              Configure(const string symbol, const int magic, const int stopsLevelPoints,
                               const int freezeLevelPoints, const int slippagePts,
                               const string orderComment = "SwingGoldEA")
     {
      m_symbol            = symbol;
      m_stopsLevelPoints  = stopsLevelPoints;
      m_freezeLevelPoints = freezeLevelPoints;
      m_orderComment      = orderComment;

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippagePts);
     }

   //+------------------------------------------------------------------+
   //| Sendet eine Market-Order in Richtung dir. sl/tp sind bereits von |
   //| RiskManager auf Friktion/StopsLevel vorgepruefte Preise; hier    |
   //| erfolgt die finale Normalisierung unmittelbar vor dem Versand.   |
   //| Bei Erfolg liegt das Deal-Ticket in outDealTicket (das Positions-|
   //| Ticket wird danach ueber PositionTracker gelesen).               |
   //+------------------------------------------------------------------+
   bool              SendMarket(const ENUM_SIGNAL_DIR dir, const double lots, const double sl, const double tp,
                                ulong &outDealTicket)
     {
      outDealTicket = 0;
      if(dir == SIGNAL_FLAT || lots <= 0.0)
         return false;

      m_trade.SetTypeFilling(DetectFillingMode());

      for(int attempt = 0; attempt <= m_maxRetries; attempt++)
        {
         double refPrice = (dir == SIGNAL_LONG) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(m_symbol, SYMBOL_BID);

         double slNorm = sl, tpNorm = tp;
         NormalizeStops(dir, refPrice, slNorm, tpNorm);

         bool ok = (dir == SIGNAL_LONG)
                     ? m_trade.Buy(lots, m_symbol, 0.0, slNorm, tpNorm, m_orderComment)
                     : m_trade.Sell(lots, m_symbol, 0.0, slNorm, tpNorm, m_orderComment);

         if(ok)
           {
            outDealTicket = m_trade.ResultDeal();
            return true;
           }

         uint retcode   = m_trade.ResultRetcode();
         bool retryable = (retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_CHANGED);

         PrintFormat("TradeExecution: SendMarket Versuch %d/%d fehlgeschlagen, retcode=%u%s",
                     attempt + 1, m_maxRetries + 1, retcode, retryable ? " - retry" : " - Abbruch");

         if(!retryable)
            break;
        }

      return false;
     }

   //--- SL/TP einer bestehenden Position aendern (TradeManager: Breakeven/Trailing).
   bool              ModifyPosition(const ulong ticket, const double sl, const double tp)
     {
      if(!PositionSelectByTicket(ticket))
         return false;

      bool ok = m_trade.PositionModify(ticket, sl, tp);
      if(!ok)
         PrintFormat("TradeExecution: ModifyPosition Ticket=%I64u fehlgeschlagen, retcode=%u",
                     ticket, m_trade.ResultRetcode());
      return ok;
     }

   //--- Teilschluss einer Position um 'volume' Lots (Teilgewinn).
   bool              ClosePartial(const ulong ticket, const double volume)
     {
      if(!PositionSelectByTicket(ticket))
         return false;

      m_trade.SetTypeFilling(DetectFillingMode());
      bool ok = m_trade.PositionClosePartial(ticket, volume);
      if(!ok)
         PrintFormat("TradeExecution: ClosePartial Ticket=%I64u Volume=%.2f fehlgeschlagen, retcode=%u",
                     ticket, volume, m_trade.ResultRetcode());
      return ok;
     }
  };

#endif // __SWINGGOLD_TRADEEXECUTION_MQH__
