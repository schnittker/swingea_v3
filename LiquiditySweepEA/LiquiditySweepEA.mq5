//+------------------------------------------------------------------+
//| LiquiditySweepEA.mq5                                              |
//| Liquidity-Sweep-Strategie mit EMA-Trendfilter                     |
//| Copyright 2026, Markus Schnittker                                 |
//+------------------------------------------------------------------+
#property copyright "Markus Schnittker"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Include Files                                                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// --- Level-Erkennung (H1) ---
input int    SwingN               = 4;     // Pivot: Bars links/rechts
input double ClusterTolerancePct  = 0.1;   // % Toleranz fürs Clustering
input int    MinPivotsPerLevel    = 4;     // Mindest-Pivots je Level
input int    LevelLookbackBars    = 2000;  // H1-Bars für Level-Rescan

// --- Sweep / Rejection (M15) ---
input int    RejectionWindowBars  = 2;     // Max. Bars bis Rejection
input double RejectionBufferPct   = 0.0;   // Mindestabstand Rejection-Close
input bool   RequireCloseInZone   = false; // verschärfte Sweep-Regel

// --- SL / TP ---
input double SLBufferPct          = 0.05;  // Puffer hinter Sweep-Extremum
input double TP_RR                = 3.0;   // CRV (1.0 / 1.5 / 2.0 testbar)

// --- Risiko ---
input double RiskPercent          = 0.5;   // % Kontorisiko pro Trade

// --- Trade-Richtung ---
input bool   AllowLongTrades      = true;  // Long-Trades zulassen
input bool   AllowShortTrades     = true;  // Short-Trades zulassen

// --- Trend-/Regime-Filter ---
input bool   UseTrendFilter    = true; // EMA-Trendfilter aktivieren
input int    TrendFilterPeriod = 200;  // EMA-Periode
input int    TrendFilterTFIndex = 0;   // Trendfilter-Timeframe: 0=M15, 1=H1, 2=H4, 3=D1 (int statt ENUM_TIMEFRAMES, damit der Optimizer per Start/Step/Stop durchlaufen kann)

// --- Dual-EMA-Regimefilter (Golden/Death-Cross, zusätzlich zu UseTrendFilter) ---
input bool   UseDualEmaFilter  = false; // Dual-EMA-Regimefilter aktivieren (zusätzlicher, unabhängiger Filter)
input int    DualEmaFastPeriod = 100;   // Schnelle EMA-Periode
input int    DualEmaSlowPeriod = 200;   // Langsame EMA-Periode
input int    DualEmaTFIndex    = 2;     // Dual-EMA-Timeframe: 0=M15, 1=H1, 2=H4, 3=D1

// --- Handelszeiten (per Default kein Overnight-/Wochenend-Halten, abschaltbar) ---
input bool   UseDailyCutoff               = true; // Täglicher Handelsschluss aktiv (false = über Nacht/Wochenende halten)
input int    DailyCloseHour               = 21;  // Server-Zeit Stunde: ab hier werden offene Positionen zwangsweise geschlossen
input int    DailyCloseMinute             = 0;   // Server-Zeit Minute für den täglichen Cutoff
input int    NoNewTradeMinutesBeforeClose = 60;  // Keine neuen Trades mehr in diesem Fenster vor dem Cutoff

// --- News-Filter (Economic Calendar) ---
input bool                           UseNewsFilter          = true;                     // News-Filter aktivieren
input ENUM_CALENDAR_EVENT_IMPORTANCE NewsMinImportance      = CALENDAR_IMPORTANCE_HIGH;  // Ab welcher Wichtigkeit blockieren
input int                            NewsBlockMinutesBefore = 30;                        // Minuten vor dem Event blockieren
input int                            NewsBlockMinutesAfter  = 30;                        // Minuten nach dem Event blockieren
input bool                           ForceCloseBeforeNews   = true;                      // Offene Positionen vor High-Impact-News zwangsweise schließen

// --- Drawdown-Schutz (Soft-Halt mit Auto-Recovery) ---
input bool   UseDrawdownThrottle  = true;   // Drawdown-Risikostaffelung + Kill-Switch aktivieren
input double DDTier1Pct           = 2.0;    // Drawdown-% ab der Risiko auf RiskPercentTier1 reduziert wird
input double DDTier2Pct           = 3.0;    // Drawdown-% ab der Risiko auf RiskPercentTier2 reduziert wird
input double DDHaltPct            = 6.0;    // Drawdown-% ab der neue Trades pausiert werden (Soft-Halt)
input double RiskPercentTier1     = 0.25;   // % Kontorisiko in Tier 1
input double RiskPercentTier2     = 0.125;  // % Kontorisiko in Tier 2

// --- Sonstiges ---
input string TradeComment         = "LiquiditySweepEA";

//+------------------------------------------------------------------+
//| Datenstrukturen                                                   |
//+------------------------------------------------------------------+
struct Level
{
   bool   isResistance;
   double zoneLow;
   double zoneHigh;
   int    pivotCount;
};

struct PendingSweep
{
   bool     isResistanceLevel;
   double   zoneLow;
   double   zoneHigh;
   bool     isLong;         // Trade-Richtung bei Rejection
   double   extreme;        // Sweep-Bar High/Low
   datetime sweepBarTime;
   int      barsElapsed;
};

Level         g_levels[];
PendingSweep  g_pending[];
int           g_trendEmaHandle = INVALID_HANDLE;
int           g_dualEmaFastHandle = INVALID_HANDLE;
int           g_dualEmaSlowHandle = INVALID_HANDLE;

// --- Drawdown-Throttle State ---
double        g_equityPeak      = 0.0;
double        g_currentDD       = 0.0;
double        g_currentRisk     = 0.0;
bool          g_ddHalted        = false;
string        g_ddGlobalVarName = "";

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(UseTrendFilter)
   {
      g_trendEmaHandle = iMA(_Symbol, IndexToTimeframe(TrendFilterTFIndex), TrendFilterPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_trendEmaHandle == INVALID_HANDLE)
      {
         Print("[OnInit] Failed to create trend EMA handle");
         return INIT_FAILED;
      }
   }

   if(UseDualEmaFilter)
   {
      g_dualEmaFastHandle = iMA(_Symbol, IndexToTimeframe(DualEmaTFIndex), DualEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_dualEmaSlowHandle = iMA(_Symbol, IndexToTimeframe(DualEmaTFIndex), DualEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_dualEmaFastHandle == INVALID_HANDLE || g_dualEmaSlowHandle == INVALID_HANDLE)
      {
         Print("[OnInit] Failed to create dual-EMA filter handle(s)");
         return INIT_FAILED;
      }
   }

   g_ddGlobalVarName = "LiquiditySweepEA_" + _Symbol + "_EquityPeak";
   g_currentRisk = RiskPercent;

   Print("[OnInit] LiquiditySweepEA initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_trendEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_trendEmaHandle);

   if(g_dualEmaFastHandle != INVALID_HANDLE)
      IndicatorRelease(g_dualEmaFastHandle);

   if(g_dualEmaSlowHandle != INVALID_HANDLE)
      IndicatorRelease(g_dualEmaSlowHandle);

   Print("[OnDeinit] LiquiditySweepEA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| OnTick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateTrailingDD();
   CheckForceClose();

   static datetime lastH1BarTime = 0;
   datetime currentH1BarTime = iTime(_Symbol, PERIOD_H1, 0);
   if(currentH1BarTime != lastH1BarTime)
   {
      lastH1BarTime = currentH1BarTime;
      RebuildLevels();
   }

   static datetime lastM15BarTime = 0;
   datetime currentM15BarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentM15BarTime != lastM15BarTime)
   {
      lastM15BarTime = currentM15BarTime;
      ProcessM15Signal();
   }
}

//+------------------------------------------------------------------+
//| Pivot-Erkennung (H1) - analog IsSwingHigh/IsSwingLow, Shift-basiert|
//+------------------------------------------------------------------+
bool IsSwingHighH1(int shift, int n)
{
   double h = iHigh(_Symbol, PERIOD_H1, shift);
   for(int i = 1; i <= n; i++)
   {
      if(h <= iHigh(_Symbol, PERIOD_H1, shift - i)) return false; // rechts (näher an jetzt)
      if(h <= iHigh(_Symbol, PERIOD_H1, shift + i)) return false; // links (weiter zurück)
   }
   return true;
}

bool IsSwingLowH1(int shift, int n)
{
   double l = iLow(_Symbol, PERIOD_H1, shift);
   for(int i = 1; i <= n; i++)
   {
      if(l >= iLow(_Symbol, PERIOD_H1, shift - i)) return false;
      if(l >= iLow(_Symbol, PERIOD_H1, shift + i)) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| RebuildLevels - H1-Level-Rescan (nur abgeschlossene Bars)         |
//+------------------------------------------------------------------+
void RebuildLevels()
{
   ArrayFree(g_levels);

   int totalBars = Bars(_Symbol, PERIOD_H1);
   int maxShift = LevelLookbackBars;
   if(maxShift > totalBars - SwingN - 1) maxShift = totalBars - SwingN - 1;
   if(maxShift < SwingN + 1)
   {
      Print("[RebuildLevels] Not enough H1 history yet (bars=", totalBars, ")");
      return;
   }

   double highPivots[];
   double lowPivots[];

   for(int s = SwingN + 1; s <= maxShift; s++)
   {
      if(IsSwingHighH1(s, SwingN))
      {
         int sz = ArraySize(highPivots);
         ArrayResize(highPivots, sz + 1);
         highPivots[sz] = iHigh(_Symbol, PERIOD_H1, s);
      }
      if(IsSwingLowH1(s, SwingN))
      {
         int sz = ArraySize(lowPivots);
         ArrayResize(lowPivots, sz + 1);
         lowPivots[sz] = iLow(_Symbol, PERIOD_H1, s);
      }
   }

   ClusterAndAppend(highPivots, true);
   ClusterAndAppend(lowPivots, false);

   Print("[RebuildLevels] Levels rebuilt: ", ArraySize(g_levels),
         " (highPivots=", ArraySize(highPivots), ", lowPivots=", ArraySize(lowPivots), ")");
}

//+------------------------------------------------------------------+
//| Greedy-1D-Clustering (analog strategy.cluster_pivots)             |
//+------------------------------------------------------------------+
void ClusterAndAppend(double &prices[], bool isResistance)
{
   int n = ArraySize(prices);
   if(n == 0) return;

   ArraySort(prices); // aufsteigend

   double clusterSum = prices[0];
   int    clusterCount = 1;
   double clusterMin = prices[0];
   double clusterMax = prices[0];

   for(int i = 1; i < n; i++)
   {
      double avg = clusterSum / clusterCount;
      double tol = ClusterTolerancePct / 100.0 * avg;
      if(MathAbs(prices[i] - avg) <= tol)
      {
         clusterSum += prices[i];
         clusterCount++;
         if(prices[i] < clusterMin) clusterMin = prices[i];
         if(prices[i] > clusterMax) clusterMax = prices[i];
      }
      else
      {
         AppendLevelIfValid(clusterMin, clusterMax, clusterCount, isResistance);
         clusterSum = prices[i];
         clusterCount = 1;
         clusterMin = prices[i];
         clusterMax = prices[i];
      }
   }
   AppendLevelIfValid(clusterMin, clusterMax, clusterCount, isResistance);
}

void AppendLevelIfValid(double zoneLow, double zoneHigh, int count, bool isResistance)
{
   if(count < MinPivotsPerLevel) return;

   int sz = ArraySize(g_levels);
   ArrayResize(g_levels, sz + 1);
   g_levels[sz].isResistance = isResistance;
   g_levels[sz].zoneLow = zoneLow;
   g_levels[sz].zoneHigh = zoneHigh;
   g_levels[sz].pivotCount = count;
}

//+------------------------------------------------------------------+
//| ProcessM15Signal - M15-Signal-Loop                                |
//+------------------------------------------------------------------+
void ProcessM15Signal()
{
   if(HasOpenPosition())
      return;

   // 1. Abgelaufene Pending-Sweeps entfernen
   RemoveExpiredPending();

   // aktuelle abgeschlossene M15-Kerze
   double barHigh  = iHigh(_Symbol, PERIOD_M15, 1);
   double barLow   = iLow(_Symbol, PERIOD_M15, 1);
   double barClose = iClose(_Symbol, PERIOD_M15, 1);
   datetime barTime = iTime(_Symbol, PERIOD_M15, 1);

   bool blockNewTrades = IsWithinNoNewTradeWindow() || IsNewsBlackout() || g_ddHalted;

   if(!blockNewTrades)
   {
      // 2. Rejection-Check auf bestehenden Pending-Setups
      for(int i = 0; i < ArraySize(g_pending); i++)
      {
         if(CheckRejection(barClose, g_pending[i]) && IsTrendAligned(g_pending[i].isLong, barClose) && IsDualEmaAligned(g_pending[i].isLong))
         {
            OpenTrade(g_pending[i].isLong, g_pending[i].extreme);
            ArrayFree(g_pending);
            return;
         }
      }

      // 3. Neue Sweeps an Levelzonen ohne bestehenden Pending-Eintrag erkennen
      for(int i = 0; i < ArraySize(g_levels); i++)
      {
         if(HasPendingForLevel(g_levels[i]))
            continue;

         bool   isLong = false;
         double extreme = 0.0;
         if(CheckSweep(barHigh, barLow, barClose, g_levels[i], isLong, extreme))
         {
            if((isLong && !AllowLongTrades) || (!isLong && !AllowShortTrades))
               continue;

            int sz = ArraySize(g_pending);
            ArrayResize(g_pending, sz + 1);
            g_pending[sz].isResistanceLevel = g_levels[i].isResistance;
            g_pending[sz].zoneLow = g_levels[i].zoneLow;
            g_pending[sz].zoneHigh = g_levels[i].zoneHigh;
            g_pending[sz].isLong = isLong;
            g_pending[sz].extreme = extreme;
            g_pending[sz].sweepBarTime = barTime;
            g_pending[sz].barsElapsed = 0;
         }
      }
   }

   // 4. barsElapsed aller verbleibenden Pending-Einträge inkrementieren
   for(int i = 0; i < ArraySize(g_pending); i++)
      g_pending[i].barsElapsed++;
}

//+------------------------------------------------------------------+
//| Pending-Verwaltung                                                 |
//+------------------------------------------------------------------+
void RemoveExpiredPending()
{
   PendingSweep kept[];
   for(int i = 0; i < ArraySize(g_pending); i++)
   {
      if(g_pending[i].barsElapsed <= RejectionWindowBars)
      {
         int sz = ArraySize(kept);
         ArrayResize(kept, sz + 1);
         kept[sz] = g_pending[i];
      }
   }
   ArrayFree(g_pending);
   ArrayResize(g_pending, ArraySize(kept));
   for(int i = 0; i < ArraySize(kept); i++)
      g_pending[i] = kept[i];
}

bool HasPendingForLevel(Level &level)
{
   for(int i = 0; i < ArraySize(g_pending); i++)
   {
      if(g_pending[i].isResistanceLevel != level.isResistance)
         continue;
      // Zonenüberlappung
      if(level.zoneLow <= g_pending[i].zoneHigh && level.zoneHigh >= g_pending[i].zoneLow)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sweep-/Rejection-Erkennung (1:1 Port aus strategy.py)             |
//+------------------------------------------------------------------+
bool CheckSweep(double barHigh, double barLow, double barClose, Level &level, bool &isLongOut, double &extremeOut)
{
   if(level.isResistance)
   {
      bool pierced   = barHigh > level.zoneHigh;
      bool notBeyond = barClose <= level.zoneHigh;
      bool inZone    = barClose >= level.zoneLow;
      if(pierced && notBeyond && (!RequireCloseInZone || inZone))
      {
         isLongOut = false; // short
         extremeOut = barHigh;
         return true;
      }
   }
   else
   {
      bool pierced   = barLow < level.zoneLow;
      bool notBeyond = barClose >= level.zoneLow;
      bool inZone    = barClose <= level.zoneHigh;
      if(pierced && notBeyond && (!RequireCloseInZone || inZone))
      {
         isLongOut = true; // long
         extremeOut = barLow;
         return true;
      }
   }
   return false;
}

bool CheckRejection(double barClose, PendingSweep &p)
{
   if(!p.isLong) // short: Rejection = Close wieder unter der Zone
   {
      double threshold = p.zoneLow - RejectionBufferPct / 100.0 * p.zoneLow;
      return barClose <= threshold;
   }
   else // long: Rejection = Close wieder über der Zone
   {
      double threshold = p.zoneHigh + RejectionBufferPct / 100.0 * p.zoneHigh;
      return barClose >= threshold;
   }
}

//+------------------------------------------------------------------+
//| IndexToTimeframe - mappt einen TF-Index auf ENUM_TIMEFRAMES       |
//| (int statt ENUM_TIMEFRAMES, damit der Optimizer per Start/Step/   |
//| Stop durchlaufen kann; genutzt von TrendFilterTFIndex und         |
//| DualEmaTFIndex)                                                   |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES IndexToTimeframe(int idx)
{
   switch(idx)
   {
      case 1:  return PERIOD_H1;
      case 2:  return PERIOD_H4;
      case 3:  return PERIOD_D1;
      default: return PERIOD_M15;
   }
}

//+------------------------------------------------------------------+
//| IsTrendAligned - EMA-Regime-Filter (fail-safe: false bei Fehler)  |
//+------------------------------------------------------------------+
bool IsTrendAligned(bool isLong, double barClose)
{
   if(!UseTrendFilter)
      return true;

   double emaBuf[];
   if(CopyBuffer(g_trendEmaHandle, 0, 1, 1, emaBuf) <= 0)
   {
      Print("[IsTrendAligned] CopyBuffer failed, blocking trade as fail-safe");
      return false;
   }

   double ema = emaBuf[0];
   return isLong ? (barClose > ema) : (barClose < ema);
}

//+------------------------------------------------------------------+
//| IsDualEmaAligned - Golden-/Death-Cross-Regimefilter               |
//| (fail-safe: false bei Fehler)                                    |
//+------------------------------------------------------------------+
bool IsDualEmaAligned(bool isLong)
{
   if(!UseDualEmaFilter)
      return true;

   double fastBuf[];
   double slowBuf[];
   if(CopyBuffer(g_dualEmaFastHandle, 0, 1, 1, fastBuf) <= 0 ||
      CopyBuffer(g_dualEmaSlowHandle, 0, 1, 1, slowBuf) <= 0)
   {
      Print("[IsDualEmaAligned] CopyBuffer failed, blocking trade as fail-safe");
      return false;
   }

   double fast = fastBuf[0];
   double slow = slowBuf[0];
   return isLong ? (fast > slow) : (fast < slow);
}

//+------------------------------------------------------------------+
//| SL/TP-Berechnung (1:1 Port aus strategy.compute_sl_tp)            |
//+------------------------------------------------------------------+
bool ComputeSLTP(double entryPrice, double extreme, bool isLong, double &slOut, double &tpOut)
{
   double sl, risk, tp;
   if(!isLong) // short
   {
      sl = extreme * (1.0 + SLBufferPct / 100.0);
      risk = sl - entryPrice;
      if(risk <= 0) return false;
      tp = entryPrice - TP_RR * risk;
   }
   else // long
   {
      sl = extreme * (1.0 - SLBufferPct / 100.0);
      risk = entryPrice - sl;
      if(risk <= 0) return false;
      tp = entryPrice + TP_RR * risk;
   }
   slOut = NormalizeDouble(sl, _Digits);
   tpOut = NormalizeDouble(tp, _Digits);
   return true;
}

//+------------------------------------------------------------------+
//| CalculateLotSize - 1:1 Port aus SwingEA_v1.mq5                   |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double slDistanceInPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (g_currentRisk / 100.0);

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(balance <= 0 || tickValue <= 0 || tickSize <= 0 || point <= 0)
   {
      Print("[CalculateLotSize] Invalid symbol info for ", symbol);
      return 0;
   }

   double slDistanceInPrice = slDistanceInPoints * point;
   double slDistanceInTicks = slDistanceInPrice / tickSize;

   if(slDistanceInTicks <= 0)
   {
      Print("[CalculateLotSize] Invalid SL distance for ", symbol);
      return 0;
   }

   double lotSize = riskAmount / (slDistanceInTicks * tickValue);

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minLot <= 0 || maxLot <= 0 || lotStep <= 0)
   {
      Print("[CalculateLotSize] Invalid lot limits for ", symbol);
      return 0;
   }

   lotSize = MathMax(minLot, lotSize);
   lotSize = MathMin(maxLot, lotSize);
   lotSize = NormalizeDouble(MathFloor(lotSize / lotStep) * lotStep, 2);

   if(lotSize < minLot || lotSize > maxLot)
   {
      Print("[CalculateLotSize] Final lot size ", lotSize, " out of range [", minLot, ",", maxLot, "]");
      return 0;
   }

   Print("[CalculateLotSize] ", symbol, " | Risk: ", g_currentRisk, "% | SL: ", slDistanceInPoints,
         "pts | Lot: ", lotSize);

   return lotSize;
}

//+------------------------------------------------------------------+
//| OpenTrade - Entry/SL/TP/Lotgröße bestimmen und Order senden       |
//+------------------------------------------------------------------+
void OpenTrade(bool isLong, double extreme)
{
   double entryPrice = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;
   if(!ComputeSLTP(entryPrice, extreme, isLong, sl, tp))
   {
      Print("[OpenTrade] Invalid SL/TP (risk <= 0), skipping trade");
      return;
   }

   double slDistanceInPoints = MathAbs(entryPrice - sl) / _Point;
   double lot = CalculateLotSize(_Symbol, slDistanceInPoints);
   if(lot <= 0)
   {
      Print("[OpenTrade] Invalid lot size, skipping trade");
      return;
   }

   bool ok;
   if(isLong)
      ok = trade.Buy(lot, _Symbol, 0, sl, tp, TradeComment);
   else
      ok = trade.Sell(lot, _Symbol, 0, sl, tp, TradeComment);

   if(!ok)
      Print("[OpenTrade] Order failed: ", trade.ResultRetcodeDescription());
   else
      Print("[OpenTrade] ", (isLong ? "BUY" : "SELL"), " ", _Symbol, " lot=", lot,
            " sl=", sl, " tp=", tp);
}

//+------------------------------------------------------------------+
//| HasOpenPosition - eigene Position über POSITION_COMMENT filtern  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      string posSymbol = PositionGetSymbol(i);
      if(posSymbol != _Symbol)
         continue;
      if(PositionGetString(POSITION_COMMENT) == TradeComment)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetTodayCutoffTime - heutiger Daily-Cutoff-Zeitpunkt (Server-Zeit)|
//+------------------------------------------------------------------+
datetime GetTodayCutoffTime()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   tm.hour = DailyCloseHour;
   tm.min  = DailyCloseMinute;
   tm.sec  = 0;
   return StructToTime(tm);
}

//+------------------------------------------------------------------+
//| IsWithinNoNewTradeWindow - true im Vorlauf-Fenster + nach Cutoff |
//+------------------------------------------------------------------+
bool IsWithinNoNewTradeWindow()
{
   if(!UseDailyCutoff)
      return false;

   datetime cutoffTime = GetTodayCutoffTime();
   datetime windowStart = cutoffTime - NoNewTradeMinutesBeforeClose * 60;
   return TimeCurrent() >= windowStart;
}

//+------------------------------------------------------------------+
//| ForceCloseAllPositions - 1:1 Pattern aus SwingEA_v1::CloseAllPositions|
//+------------------------------------------------------------------+
void ForceCloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetString(POSITION_COMMENT) != TradeComment) continue;

      trade.PositionClose(ticket);

      if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
         Print("[ForceCloseAllPositions] Closed position ", ticket, " | Reason: ", reason);
      else
         Print("[ForceCloseAllPositions] Failed to close ", ticket, ": ", trade.ResultRetcodeDescription(),
               " | Reason: ", reason);
   }
}

//+------------------------------------------------------------------+
//| UpdateTrailingDD - Drawdown-Soft-Halt mit Auto-Recovery           |
//| Adaptiert aus SwingEA_v1::UpdateTrailingDD (namespaced GlobalVar, |
//| Soft-Halt statt ExpertRemove())                                   |
//+------------------------------------------------------------------+
void UpdateTrailingDD()
{
   if(!UseDrawdownThrottle)
   {
      g_currentRisk = RiskPercent;
      g_ddHalted = false;
      return;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!GlobalVariableCheck(g_ddGlobalVarName))
   {
      GlobalVariableSet(g_ddGlobalVarName, equity);
      g_equityPeak = equity;
      g_currentDD = 0.0;
      g_currentRisk = RiskPercent;
      Print("[UpdateTrailingDD] Initialized | Peak: ", equity, " | Risk: ", g_currentRisk, "%");
      return;
   }

   g_equityPeak = GlobalVariableGet(g_ddGlobalVarName);

   if(equity > g_equityPeak)
   {
      g_equityPeak = equity;
      GlobalVariableSet(g_ddGlobalVarName, g_equityPeak);
      g_currentDD = 0.0;
      g_currentRisk = RiskPercent;
      if(g_ddHalted)
         Print("[UpdateTrailingDD] NEW PEAK - Auto-Recovery, Halt aufgehoben | Peak: ", equity);
      g_ddHalted = false;
      return;
   }

   g_currentDD = (g_equityPeak > 0) ? ((g_equityPeak - equity) / g_equityPeak) * 100.0 : 0.0;

   if(g_currentDD >= DDHaltPct)
   {
      if(!g_ddHalted)
      {
         Print("[UpdateTrailingDD] DD-KILL-SWITCH | DD: ", DoubleToString(g_currentDD, 2),
               "% >= ", DDHaltPct, "% | Closing all positions, blocking new entries");
         ForceCloseAllPositions("DD-Kill-Switch");
      }
      g_ddHalted = true;
      g_currentRisk = RiskPercentTier2;
   }
   else if(g_currentDD >= DDTier2Pct)
   {
      g_currentRisk = RiskPercentTier2;
   }
   else if(g_currentDD >= DDTier1Pct)
   {
      g_currentRisk = RiskPercentTier1;
   }
   else
   {
      g_currentRisk = RiskPercent;
   }
}

//+------------------------------------------------------------------+
//| CheckForceClose - erzwingt täglichen Cutoff (kein Overnight-Halten)|
//+------------------------------------------------------------------+
void CheckForceClose()
{
   if(!HasOpenPosition())
      return;

   if(UseDailyCutoff)
   {
      datetime cutoffTime = GetTodayCutoffTime();
      if(TimeCurrent() >= cutoffTime)
         ForceCloseAllPositions("Daily-Cutoff");
   }

   if(ForceCloseBeforeNews && IsInNewsWindow())
      ForceCloseAllPositions("News-Blackout");
}

//+------------------------------------------------------------------+
//| HasHighImpactNews - prüft Calendar-Events einer Währung im Fenster|
//+------------------------------------------------------------------+
bool HasHighImpactNews(datetime from, datetime to, string currency)
{
   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, from, to, NULL, currency);
   if(count <= 0)
      return false;

   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      if(event.importance >= NewsMinImportance)
      {
         Print("[HasHighImpactNews] ", currency, " | ", event.name, " @ ", TimeToString(values[i].time));
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsInNewsWindow - true, wenn High-Impact-News im Blockfenster liegt|
//| (reine Fensterprüfung, unabhängig von UseNewsFilter/ForceClose)  |
//+------------------------------------------------------------------+
bool IsInNewsWindow()
{
   datetime from = TimeCurrent() - NewsBlockMinutesAfter * 60;
   datetime to   = TimeCurrent() + NewsBlockMinutesBefore * 60;

   string baseCurrency  = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string quoteCurrency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

   return HasHighImpactNews(from, to, baseCurrency) || HasHighImpactNews(from, to, quoteCurrency);
}

//+------------------------------------------------------------------+
//| IsNewsBlackout - blockiert neue Trades, wenn UseNewsFilter aktiv  |
//+------------------------------------------------------------------+
bool IsNewsBlackout()
{
   if(!UseNewsFilter)
      return false;

   return IsInNewsWindow();
}
