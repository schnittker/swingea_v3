//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|   Fixed-Fractional-Sizing (ea.md 4.9):                          |
//|     riskMoney   = Equity * InpRiskPercent/100                   |
//|     moneyPerLot = tickValue/tickSize * stopDist                 |
//|     lots        = riskMoney / moneyPerLot                       |
//|   Schutzschichten (Uebernahme aus dem Vorgaenger-Modul):        |
//|     1) Mindest-Stop-Abstand >= FrictionSLMult*(Spread+Slippage) |
//|     2) SYMBOL_TRADE_STOPS_LEVEL als harte Untergrenze            |
//|     3) MaxRiskPctPerTrade: Lot-Kappung als % der Equity —       |
//|        kapitalunabhaengig, kein manuelles Anpassen noetig.      |
//|     4) Normalisierung auf VOLUME_STEP, Pruefung Min/Max          |
//|     5) Abbruch bei lots<VOLUME_MIN (kein Aufrunden)              |
//+------------------------------------------------------------------+
#ifndef __SWINGGOLD_RISKMANAGER_MQH__
#define __SWINGGOLD_RISKMANAGER_MQH__

#include "Types.mqh"

class CRiskManager
  {
private:
   string            m_symbol;
   double            m_riskPercent;
   double            m_maxRiskPctPerTrade;  // Lot-Kappung als % der Equity (kapitalunabhaengig)
   double            m_frictionSLMult;
   double            m_slippageBufferPts;

   //--- Live-Friktion in Preis-Einheiten: Spread + Slippage-Puffer.
   double            FrictionPrice(void)
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      long   spreadPts = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      return (double)spreadPts * point + m_slippageBufferPts * point;
     }

public:
                     CRiskManager(void):
                        m_symbol(""), m_riskPercent(1.0), m_maxRiskPctPerTrade(2.0),
                        m_frictionSLMult(15.0), m_slippageBufferPts(20.0) {}

   void              Configure(const string symbol, const double riskPercent, const double maxRiskPctPerTrade,
                               const double frictionSLMult, const double slippageBufferPts)
     {
      m_symbol              = symbol;
      m_riskPercent         = riskPercent;
      m_maxRiskPctPerTrade  = (maxRiskPctPerTrade > 0.0) ? maxRiskPctPerTrade : 2.0;
      m_frictionSLMult      = frictionSLMult;
      m_slippageBufferPts   = slippageBufferPts;
     }

   //+------------------------------------------------------------------+
   //| Erzwingt eine Mindest-SL-Distanz (Friktions-Vielfaches UND       |
   //| Broker-StopsLevel) VOR der Lotberechnung. Ein bereits weiter      |
   //| entfernter Stop wird NICHT verengt.                              |
   //+------------------------------------------------------------------+
   void              EnforceMinStopDistance(const ENUM_SIGNAL_DIR dir, const double refPrice,
                                            double &stopPrice, const int stopsLevelPoints)
     {
      double point            = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minFrictionDist  = m_frictionSLMult * FrictionPrice();
      double minStopsLevelDist = (double)stopsLevelPoints * point;
      double minDist          = MathMax(minFrictionDist, minStopsLevelDist);

      double currentDist = MathAbs(refPrice - stopPrice);
      if(currentDist >= minDist)
         return;

      stopPrice = (dir == SIGNAL_LONG) ? (refPrice - minDist) : (refPrice + minDist);

      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      stopPrice  = NormalizeDouble(stopPrice, digits);
     }

   //+------------------------------------------------------------------+
   //| Fixed-Fractional-Lotberechnung. refPrice ist der aktuelle        |
   //| Marktpreis (Ask/Bid), da die Order als Market-Order (entryPrice  |
   //| =0) ausgefuehrt wird. Gibt 0.0 zurueck, wenn kein sinnvoller     |
   //| Trade moeglich ist (lots < VOLUME_MIN, statt aufzurunden).       |
   //|                                                                   |
   //| riskPercentOverride: wenn > 0.0, wird dieser Wert statt         |
   //| m_riskPercent verwendet (fuer per-Slot-Risiko-Prozentsatz).     |
   //| Default 0.0 = m_riskPercent (rueckwaertskompatibel).            |
   //+------------------------------------------------------------------+
   double            ComputeLots(const double refPrice, const double stopPrice,
                                 const double volumeMin, const double volumeMax,
                                 const double volumeStep,
                                 const double riskPercentOverride = 0.0)
     {
      double stopDist = MathAbs(refPrice - stopPrice);
      if(stopDist <= 0.0)
        {
         Print("RiskManager: stopDist <= 0 - kein Trade.");
         return 0.0;
        }

      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
        {
         Print("RiskManager: TickSize <= 0 - kein Trade.");
         return 0.0;
        }

      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double usedPct    = (riskPercentOverride > 0.0) ? riskPercentOverride : m_riskPercent;
      double riskMoney   = equity * (usedPct / 100.0);
      double moneyPerLot = (tickValue / tickSize) * stopDist;
      if(moneyPerLot <= 0.0)
        {
         Print("RiskManager: moneyPerLot <= 0 - kein Trade.");
         return 0.0;
        }

      double lots = riskMoney / moneyPerLot;

      //--- Lot-Kappung als % der Equity: kapitalunabhaengig, kein manuelles Anpassen noetig.
      //--- maxRiskMoney = equity * maxRiskPctPerTrade / 100
      //--- maxLot       = maxRiskMoney / moneyPerLot
      if(m_maxRiskPctPerTrade > 0.0)
        {
         double maxRiskMoney = equity * (m_maxRiskPctPerTrade / 100.0);
         double maxLot       = maxRiskMoney / moneyPerLot;
         if(lots > maxLot)
            lots = maxLot;
        }

      if(volumeStep > 0.0)
         lots = MathFloor(lots / volumeStep + 1e-8) * volumeStep;

      if(volumeMax > 0.0 && lots > volumeMax)
         lots = volumeMax;

      if(lots < volumeMin)
        {
         PrintFormat("RiskManager: lots %.4f < VOLUME_MIN %.4f - Trade ausgelassen.", lots, volumeMin);
         return 0.0;
        }

      return NormalizeDouble(lots, 2);
     }
  };

#endif // __SWINGGOLD_RISKMANAGER_MQH__
