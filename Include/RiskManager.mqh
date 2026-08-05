//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|   Volatilitaets-getargetetes Position-Sizing (invers zur ATR).   |
//|                                                                  |
//|   Idee: Jede Position soll denselben Geld-Vola-Beitrag liefern.  |
//|   - Ziel-Portfolio-Jahresvol (z.B. 10%) wird gleichmaessig auf   |
//|     die N Symbole verteilt -> Ziel-Vol pro Symbol.               |
//|   - Aus der taeglichen ATR (Preis) wird eine annualisierte       |
//|     Geld-Vola je 1.0 Lot geschaetzt und die Lotzahl so gewaehlt, |
//|     dass sie das Symbol-Vola-Budget trifft.                      |
//|                                                                  |
//|   Zwei Schutzschichten gegen Lot-Explosion bei winziger ATR:     |
//|   1) Mindest-SL-Abstand (>= Friktions-Vielfaches)                |
//|   2) CapLotSize (Broker-Limits + InpMaxLotPerTrade)              |
//+------------------------------------------------------------------+
#ifndef __TRENDMOMENTUM_RISKMANAGER_MQH__
#define __TRENDMOMENTUM_RISKMANAGER_MQH__

#include "Types.mqh"

class CRiskManager
  {
private:
   double            m_targetAnnualVolPct; // Ziel-Portfolio-Jahresvol in % (z.B. 10)
   double            m_atrStopMult;        // SL = m_atrStopMult * ATR (Default 3.0, per Configure gesetzt)
   double            m_maxLotPerTrade;     // harte Obergrenze pro Trade
   double            m_frictionSLMult;     // Mindest-SL >= m_frictionSLMult * Friktion
   double            m_slippageBufferPts;  // Slippage-Puffer in Points

   //--- Annualisierungsfaktor: sqrt(Handelstage/Jahr)
   double            AnnualFactor(void) const { return MathSqrt(252.0); }

   //--- Geldwert einer Preisbewegung von 1.0 Preis-Einheit je 1.0 Lot
   //    ueber tickValue/tickSize (broker-genau, auch fuer JPY/XAU/Index).
   double            MoneyPerPricePerLot(const string sym)
     {
      double tickValue=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
      double tickSize =SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      if(tickSize<=0.0) return 0.0;
      return tickValue/tickSize; // Geld pro (1 Preis-Einheit * 1 Lot)
     }

   //--- Live-Friktion in Preis-Einheiten: Spread + Slippage-Puffer
   double            FrictionPrice(const string sym)
     {
      double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      long   spreadPts=0;
      SymbolInfoInteger(sym,SYMBOL_SPREAD,spreadPts);
      double spreadPrice=(double)spreadPts*point;
      double slipPrice  =m_slippageBufferPts*point;
      return spreadPrice+slipPrice;
     }

public:
                     CRiskManager(void):
                        m_targetAnnualVolPct(10.0),m_atrStopMult(3.0),
                        m_maxLotPerTrade(1.0),m_frictionSLMult(15.0),
                        m_slippageBufferPts(20.0) {}

   void              Configure(const double targetAnnualVolPct,const double atrStopMult,
                               const double maxLotPerTrade,const double frictionSLMult,
                               const double slippageBufferPts)
     {
      m_targetAnnualVolPct=targetAnnualVolPct;
      m_atrStopMult       =atrStopMult;
      m_maxLotPerTrade    =maxLotPerTrade;
      m_frictionSLMult    =frictionSLMult;
      m_slippageBufferPts =slippageBufferPts;
     }

   //+------------------------------------------------------------------+
   //| SL-Abstand in Preis-Einheiten bestimmen und dabei die            |
   //| Mindestdistanz (Friktions-Vielfaches) erzwingen.                 |
   //+------------------------------------------------------------------+
   double            ComputeStopDistance(const string sym,const double atr)
     {
      double sl=m_atrStopMult*atr;
      double minSL=m_frictionSLMult*FrictionPrice(sym);
      if(sl<minSL) sl=minSL;
      return sl;
     }

   //+------------------------------------------------------------------+
   //| Vola-getargetete Lotzahl fuer ein Symbol.                        |
   //| equity        : aktuelles Kontokapital                           |
   //| symbolCount   : Anzahl aktiver Symbole (Vola-Budget-Split)       |
   //| atr           : taegliche ATR in Preis-Einheiten                 |
   //| Rueckgabe: normierte, gecappte Lotzahl (>=0).                    |
   //+------------------------------------------------------------------+
   double            ComputeLots(const string sym,const double equity,
                                 const int symbolCount,const double atr)
     {
      if(equity<=0.0 || symbolCount<=0 || atr<=0.0) return 0.0;

      //--- 1) Ziel-Geld-Vola pro Symbol (annualisiert)
      //    Gesamt-Ziel-Vol gleichmaessig auf N Symbole verteilt.
      double portVolMoney = equity*(m_targetAnnualVolPct/100.0);
      double perSymVolMoney = portVolMoney/(double)symbolCount;

      //--- 2) Annualisierte Geld-Vola je 1.0 Lot aus der Tages-ATR
      //    (ATR ~ taegliche Preisbewegung -> annualisieren mit sqrt(252))
      double moneyPerPricePerLot = MoneyPerPricePerLot(sym);
      if(moneyPerPricePerLot<=0.0) return 0.0;
      double dailyMoneyVolPerLot = atr*moneyPerPricePerLot;
      double annualMoneyVolPerLot= dailyMoneyVolPerLot*AnnualFactor();
      if(annualMoneyVolPerLot<=0.0) return 0.0;

      //--- 3) Lots so, dass Symbol-Vola-Budget getroffen wird
      double lots = perSymVolMoney/annualMoneyVolPerLot;

      return CapLotSize(sym,lots);
     }

   //+------------------------------------------------------------------+
   //| Lotzahl auf Broker-Limits + InpMaxLotPerTrade normieren.         |
   //+------------------------------------------------------------------+
   double            CapLotSize(const string sym,double lots)
     {
      double minLot =SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
      double maxLot =SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
      double lotStep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
      if(lotStep<=0.0) lotStep=0.01;

      //--- eigene Obergrenze
      if(m_maxLotPerTrade>0.0 && lots>m_maxLotPerTrade)
         lots=m_maxLotPerTrade;

      //--- auf Lot-Step runden (abrunden = konservativ)
      lots=MathFloor(lots/lotStep)*lotStep;

      //--- Broker-Grenzen
      if(maxLot>0.0 && lots>maxLot) lots=maxLot;
      if(lots<minLot) lots=0.0; // unter Min -> kein Trade (statt aufblaehen)

      //--- Rundungsartefakte glaetten
      lots=NormalizeDouble(lots,2);
      return lots;
     }
  };

#endif // __TRENDMOMENTUM_RISKMANAGER_MQH__
