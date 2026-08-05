//+------------------------------------------------------------------+
//|                                               TradeExecution.mqh |
//|   Kapselt CTrade fuer den TrendMomentumEA.                       |
//|   Rebalancing-Logik je Symbol: bringt die Ist-Position auf die   |
//|   gewuenschte Ziel-Richtung/-Groesse (SIGNAL_LONG/SHORT/FLAT).   |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_TRADEEXECUTION_MQH__
#define __TRENDMOMENTUM_TRADEEXECUTION_MQH__

#include <Trade/Trade.mqh>
#include "Types.mqh"
#include "PositionTracker.mqh"

class CTradeExecution
  {
private:
   CTrade            m_trade;
   long              m_magic;
   double            m_lotTolerance; // Rebalancing-Schwelle in Lots

   //--- SL-Preis aus Einstiegspreis, Richtung und SL-Abstand
   double            StopPrice(const string sym,const ENUM_SIGNAL_DIR dir,
                               const double refPrice,const double slDist)
     {
      double digits=(double)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      double sl=(dir==SIGNAL_LONG)? refPrice-slDist : refPrice+slDist;
      return NormalizeDouble(sl,(int)digits);
     }

public:
                     CTradeExecution(void): m_magic(0),m_lotTolerance(0.01) {}

   void              Configure(const long magic,const ulong slippagePts)
     {
      m_magic=magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippagePts);
      m_trade.SetTypeFillingBySymbol(_Symbol);
     }

   void              SetLotTolerance(const double t) { m_lotTolerance=t; }

   //+------------------------------------------------------------------+
   //| Position eines Symbols schliessen (alle EA-Tickets, hedge-safe). |
   //+------------------------------------------------------------------+
   bool              CloseSymbol(const string sym)
     {
      bool allOk=true;
      m_trade.SetTypeFillingBySymbol(sym);
      // Rueckwaerts iterieren, da sich der Pool beim Schliessen aendert.
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(!m_trade.PositionClose(ticket))
           {
            allOk=false;
            PrintFormat("CloseSymbol %s: Close-Fehler retcode=%d",sym,m_trade.ResultRetcode());
           }
        }
      return allOk;
     }

   //+------------------------------------------------------------------+
   //| Position eines Symbols um 'volume' Lots reduzieren (teil-close). |
   //| Iteriert ueber die EA-Tickets und schliesst partiell, bis das    |
   //| Zielvolumen abgebaut ist. Hedge-safe (rueckwaerts iterieren).    |
   //+------------------------------------------------------------------+
   bool              ReducePosition(const string sym,double volume)
     {
      if(volume<=0.0) return false;
      m_trade.SetTypeFillingBySymbol(sym);

      bool allOk=true;
      for(int i=PositionsTotal()-1;i>=0 && volume>0.0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;

         double posVol=PositionGetDouble(POSITION_VOLUME);
         double closeVol=MathMin(posVol,volume);
         closeVol=NormalizeDouble(closeVol,2);
         if(closeVol<=0.0) continue;

         bool ok=(closeVol>=posVol) ? m_trade.PositionClose(ticket)
                                    : m_trade.PositionClosePartial(ticket,closeVol);
         if(!ok)
           {
            allOk=false;
            PrintFormat("ReducePosition %s: Fehler retcode=%d",sym,m_trade.ResultRetcode());
            continue;
           }
         volume-=closeVol;
        }
      return allOk;
     }

   //+------------------------------------------------------------------+
   //| Neue Position in Zielrichtung mit SL eroeffnen.                  |
   //+------------------------------------------------------------------+
   bool              OpenPosition(const string sym,const ENUM_SIGNAL_DIR dir,
                                  const double lots,const double slDist)
     {
      if(lots<=0.0 || dir==SIGNAL_FLAT) return false;

      m_trade.SetTypeFillingBySymbol(sym);

      double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      double bid=SymbolInfoDouble(sym,SYMBOL_BID);
      double price=(dir==SIGNAL_LONG)? ask : bid;
      double sl=StopPrice(sym,dir,price,slDist);

      bool ok;
      if(dir==SIGNAL_LONG)
         ok=m_trade.Buy(lots,sym,0.0,sl,0.0,"TSMOM");
      else
         ok=m_trade.Sell(lots,sym,0.0,sl,0.0,"TSMOM");

      if(!ok)
         PrintFormat("OpenPosition %s dir=%d lots=%.2f: Fehler retcode=%d",
                     sym,dir,lots,m_trade.ResultRetcode());
      return ok;
     }

   //+------------------------------------------------------------------+
   //| Kern-Rebalancing fuer ein Symbol.                                |
   //| Bringt die Ist-Position auf targetDir/targetLots.                |
   //| - FLAT-Ziel  -> schliessen                                       |
   //| - Richtungswechsel -> schliessen + neu eroeffnen                 |
   //| - gleiche Richtung, Lot-Abweichung > Toleranz -> nur Differenz  |
   //|   handeln (aufstocken oder teil-schliessen; spart Spread)       |
   //+------------------------------------------------------------------+
   void              Rebalance(const string sym,const ENUM_SIGNAL_DIR targetDir,
                               const double targetLots,const double slDist,
                               CPositionTracker &tracker)
     {
      ENUM_SIGNAL_DIR curDir=tracker.CurrentDir(sym);
      double curLots=MathAbs(tracker.NetLots(sym));

      //--- Ziel FLAT: alles schliessen
      if(targetDir==SIGNAL_FLAT || targetLots<=0.0)
        {
         if(curDir!=SIGNAL_FLAT) CloseSymbol(sym);
         return;
        }

      //--- Richtungswechsel: erst schliessen, dann neu
      if(curDir!=SIGNAL_FLAT && curDir!=targetDir)
        {
         CloseSymbol(sym);
         OpenPosition(sym,targetDir,targetLots,slDist);
         return;
        }

      //--- Neu-Einstieg aus Flat
      if(curDir==SIGNAL_FLAT)
        {
         OpenPosition(sym,targetDir,targetLots,slDist);
         return;
        }

      //--- Gleiche Richtung: nur bei relevanter Lot-Abweichung nachziehen.
      //    Statt komplett zu flatten+neu (doppelter Spread) nur die
      //    Differenz handeln: aufstocken (Add) oder teil-schliessen.
      double diff=targetLots-curLots;
      if(MathAbs(diff)>m_lotTolerance)
        {
         double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
         if(step<=0.0) step=0.01;
         double delta=MathFloor(MathAbs(diff)/step)*step;
         delta=NormalizeDouble(delta,2);
         if(delta<=0.0) return;

         if(diff>0.0)
            OpenPosition(sym,targetDir,delta,slDist); // aufstocken
         else
            ReducePosition(sym,delta);                // teil-schliessen
        }
     }
  };

#endif // __TRENDMOMENTUM_TRADEEXECUTION_MQH__
