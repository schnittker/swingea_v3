//+------------------------------------------------------------------+
//| MeanReversionSignal.mqh                                          |
//| Strategie 3: Mean-Reversion (M15) fuer Range-Phasen.             |
//| ADX(14) < adxMaxLevel als Range-Filter (Gegenstueck zum Trend-   |
//| filter der Donchian-Strategie), Bollinger(20,2.0) + RSI(14)       |
//| Extrembereich (>70/<30) GEGEN die Extremrichtung. SL bewusst      |
//| breit: 2.5-3.0xATR14 (Floor MinSLDistancePips wird davon idR      |
//| ohnehin uebertroffen). TP = mittleres Band (SMA20).               |
//| Historisch fehleranfaellig (Vorprojekt: nur 6 Trades, DD 8.06%,  |
//| zu restriktive Filter) - deshalb zuletzt integriert.              |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "SymbolUtils.mqh"
#include "RiskManager.mqh"

#define MEANREV_TIMEFRAME PERIOD_M15
#define MEANREV_ATR_PERIOD 14

//--- iBands()-Puffer-Indizes.
#define MEANREV_BB_BASE  0
#define MEANREV_BB_UPPER 1
#define MEANREV_BB_LOWER 2

//+------------------------------------------------------------------+
//| Laufender Zustand pro Symbol: Indikator-Handles + Frequenzsperre.|
//+------------------------------------------------------------------+
struct SMeanReversionState
  {
   int               handleBB;
   int               handleRSI;
   int               handleATR;
   int               handleADX;
   datetime          lastTradeDay;
  };

//+------------------------------------------------------------------+
//| Mitternacht (Server-Zeit) des uebergebenen Zeitpunkts.           |
//+------------------------------------------------------------------+
datetime MeanReversionDayStart(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Erzeugt Bollinger/RSI/ATR/ADX-Indikator-Handles fuer jedes       |
//| Symbol. Muss einmalig in OnInit aufgerufen werden.                |
//+------------------------------------------------------------------+
bool InitMeanReversionState(SMeanReversionState &states[], const string &symbols[], const int numSymbols,
                             const int bbPeriod, const double bbDeviation, const int rsiPeriod,
                             const int adxPeriod)
  {
   ArrayResize(states, numSymbols);
   bool allOk = true;

   for(int i = 0; i < numSymbols; i++)
     {
      states[i].handleBB      = iBands(symbols[i], MEANREV_TIMEFRAME, bbPeriod, 0, bbDeviation, PRICE_CLOSE);
      states[i].handleRSI     = iRSI(symbols[i], MEANREV_TIMEFRAME, rsiPeriod, PRICE_CLOSE);
      states[i].handleATR     = iATR(symbols[i], MEANREV_TIMEFRAME, MEANREV_ATR_PERIOD);
      states[i].handleADX     = iADX(symbols[i], MEANREV_TIMEFRAME, adxPeriod);
      states[i].lastTradeDay  = 0;

      if(states[i].handleBB == INVALID_HANDLE || states[i].handleRSI == INVALID_HANDLE ||
         states[i].handleATR == INVALID_HANDLE || states[i].handleADX == INVALID_HANDLE)
        {
         PrintFormat("InitMeanReversionState: Indikator-Handle fuer %s fehlgeschlagen.", symbols[i]);
         allOk = false;
        }
     }

   return allOk;
  }

//+------------------------------------------------------------------+
//| Gibt alle Indikator-Handles frei. Muss in OnDeinit aufgerufen    |
//| werden.                                                            |
//+------------------------------------------------------------------+
void DeinitMeanReversionState(SMeanReversionState &states[])
  {
   for(int i = 0; i < ArraySize(states); i++)
     {
      if(states[i].handleBB != INVALID_HANDLE)
         IndicatorRelease(states[i].handleBB);
      if(states[i].handleRSI != INVALID_HANDLE)
         IndicatorRelease(states[i].handleRSI);
      if(states[i].handleATR != INVALID_HANDLE)
         IndicatorRelease(states[i].handleATR);
      if(states[i].handleADX != INVALID_HANDLE)
         IndicatorRelease(states[i].handleADX);
     }
  }

//+------------------------------------------------------------------+
//| Liest einen einzelnen Indikator-Puffer-Wert an shift. Gibt false |
//| zurueck, wenn (noch) nicht genug Historie vorhanden ist.          |
//+------------------------------------------------------------------+
bool GetMeanReversionIndicatorValue(const int handle, const int bufferIndex, const int shift, double &outValue)
  {
   double buf[];
   if(CopyBuffer(handle, bufferIndex, shift, 1, buf) <= 0)
      return false;
   outValue = buf[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Prueft auf ein Mean-Reversion-Signal. Basis sind ausschliesslich |
//| ABGESCHLOSSENE M15-Bars (Shift >= 1).                             |
//+------------------------------------------------------------------+
bool CheckMeanReversionSignal(SMeanReversionState &state, const string symbol,
                               const double adxMaxLevel, const double rsiUpperLevel,
                               const double rsiLowerLevel, const double atrMult,
                               const double minSLDistancePips, SSignal &outSignal)
  {
   outSignal.direction = SIGNAL_NONE;

   datetime today = MeanReversionDayStart(TimeCurrent());
   if(state.lastTradeDay == today)
      return false; // Frequenzbegrenzung: max. 1 Trade/Tag fuer diese Strategie+Symbol

   double adxValue;
   if(!GetMeanReversionIndicatorValue(state.handleADX, 0, 1, adxValue))
      return false;
   if(adxValue >= adxMaxLevel)
      return false; // Markt trendet -> Mean-Reversion bewusst NICHT gehandelt

   double upperBand, lowerBand, baseBand;
   if(!GetMeanReversionIndicatorValue(state.handleBB, MEANREV_BB_UPPER, 1, upperBand))
      return false;
   if(!GetMeanReversionIndicatorValue(state.handleBB, MEANREV_BB_LOWER, 1, lowerBand))
      return false;
   if(!GetMeanReversionIndicatorValue(state.handleBB, MEANREV_BB_BASE, 1, baseBand))
      return false;

   double rsiValue;
   if(!GetMeanReversionIndicatorValue(state.handleRSI, 0, 1, rsiValue))
      return false;

   double atrValue;
   if(!GetMeanReversionIndicatorValue(state.handleATR, 0, 1, atrValue) || atrValue <= 0.0)
      return false;

   double lastClose = iClose(symbol, MEANREV_TIMEFRAME, 1); // letzte abgeschlossene Bar

   if(lastClose < lowerBand && rsiValue < rsiLowerLevel)
     {
      outSignal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(baseBand <= outSignal.entryPrice)
         return false; // Sicherheitscheck: TP muss ueber Entry liegen, sonst kein valider Long-Trade

      outSignal.direction = SIGNAL_BUY;
      outSignal.slPrice   = outSignal.entryPrice - atrMult * atrValue;
      EnforceMinSLDistance(symbol, SIGNAL_BUY, outSignal.entryPrice, outSignal.slPrice, minSLDistancePips);
      outSignal.tpPrice = baseBand;
      outSignal.reason  = "MeanReversion BUY: Close<UnteresBand, RSI ueberverkauft, ADX-Rangefilter erfuellt";
      return true;
     }

   if(lastClose > upperBand && rsiValue > rsiUpperLevel)
     {
      outSignal.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(baseBand >= outSignal.entryPrice)
         return false; // Sicherheitscheck: TP muss unter Entry liegen, sonst kein valider Short-Trade

      outSignal.direction = SIGNAL_SELL;
      outSignal.slPrice   = outSignal.entryPrice + atrMult * atrValue;
      EnforceMinSLDistance(symbol, SIGNAL_SELL, outSignal.entryPrice, outSignal.slPrice, minSLDistancePips);
      outSignal.tpPrice = baseBand;
      outSignal.reason  = "MeanReversion SELL: Close>OberesBand, RSI ueberkauft, ADX-Rangefilter erfuellt";
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Muss nach erfolgreicher Order-Eroeffnung aufgerufen werden, um   |
//| die Tages-Frequenzsperre zu aktivieren.                           |
//+------------------------------------------------------------------+
void MarkMeanReversionTraded(SMeanReversionState &state)
  {
   state.lastTradeDay = MeanReversionDayStart(TimeCurrent());
  }

//+------------------------------------------------------------------+
