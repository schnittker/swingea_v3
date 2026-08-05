//+------------------------------------------------------------------+
//|                                                     PortfolioEA.mq5 |
//| Multi-Strategie-Portfolio-EA fuer IC Markets MT5 Hedge-Konto.    |
//| Strikt Intraday. Strategien: Session-Open-Range-Breakout,        |
//| Donchian-Breakout (+ADX-Trendfilter), Mean-Reversion (Bollinger+ |
//| RSI +ADX-Range-Filter). Details siehe portfolio-ea-konzept.md.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Portfolio-EA: Multi-Strategie, Hedge-Konto, strikt Intraday."

#include "Include/Types.mqh"
#include "Include/MagicNumbers.mqh"
#include "Include/SymbolUtils.mqh"
#include "Include/RiskManager.mqh"
#include "Include/TradeExecution.mqh"
#include "Include/SessionManager.mqh"
#include "Include/PositionTracker.mqh"
#include "Include/PortfolioRiskGuard.mqh"
#include "Include/DrawdownGuard.mqh"
#include "Include/SessionBreakoutSignal.mqh"
#include "Include/DonchianBreakoutSignal.mqh"
#include "Include/MeanReversionSignal.mqh"

//====================================================================
// Inputs
//====================================================================
input group "=== Symbole ==="
input string InpSymbolsCsv                 = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD";
// Standard: im Tester nur das Dropdown-Symbol (100% echte Ticks, sauberer
// Einzeltest). true = im Tester die volle CSV-Liste handeln (Portfolio-Lauf).
// ACHTUNG: Nur das Dropdown-Symbol bekommt echte Ticks, die uebrigen Symbole
// nur interpolierte -> Spread/Slippage/Timing dort ungenau.
input bool   InpTesterForceAllSymbols      = false;  // Tester: alle CSV-Symbole statt nur Dropdown-Symbol

input group "=== Risk ==="
input double InpRiskPercentPerTrade        = 1.0;   // % Equity Risiko pro Trade
input double InpMaxPortfolioRiskPercent    = 8.0;   // Brutto-Risikobudget-Cap (Eigenkapital-Setup; Schutz vor Ueberhebeln)
input double InpMaxLotPerTrade             = 5.0;   // hartes Lot-Cap (Schutz gegen Lot-Explosion)
input double InpCommissionPerLotRoundTurn  = 7.0;   // Kontowaehrung/1.0 Lot Round-Turn (Raw-Konto)
input double InpSlippageBufferPips         = 0.3;   // Sicherheitspuffer fuer Friktionsschaetzung
input double InpMinSLFrictionMultiple      = 15.0;  // SL-Untergrenze = Multiple x Friktion
input double InpDailySoftPauseLossPercent  = 8.0;   // Tagesverlust-Schwelle: Soft-Pause neuer Entries

input group "=== Session / Force-Close ==="
// Alle Uhrzeiten in GMT. Der Server-GMT-Offset (IC Markets: GMT+3 Sommer,
// GMT+2 Winter) wird zur Laufzeit automatisch gemessen und beim DST-Wechsel
// selbsttaetig nachgezogen. Force-Close am US-Session-Ende: 20:00 GMT.
input int    InpForceCloseHour             = 20;    // taegliche Force-Close-Stunde (GMT)
input int    InpForceCloseMinute           = 0;
input int    InpFridayForceCloseHour       = 19;    // frueher an Freitagen (Wochenend-Gap-Schutz, GMT)
input int    InpFridayForceCloseMinute     = 0;
input int    InpNoNewEntryBeforeCloseMin   = 60;    // Entry-Sperre X Min. vor Force-Close
// Fallback-Offset NUR fuer den Strategy-Tester (TimeGMT() dort unzuverlaessig).
// 3 = Sommerzeit (GMT+3), 2 = Winterzeit (GMT+2).
input int    InpTesterServerGmtOffset      = 3;     // Fallback-Offset NUR fuer Strategy-Tester (h)

input group "=== Strategie 1: Session-Open-Range-Breakout ==="
// Uhrzeiten in GMT. Asia-Range 23:00-07:00 GMT (= 02:00-10:00 Server bei GMT+3),
// Range endet zum London-Open (07:00 GMT) -> Breakout wird als London-Ausbruch
// der Asia-Range getradet.
input bool   InpEnableSessionBreakout      = true;
input int    InpSB_RangeStartHour          = 23;    // Range-Start GMT (Asia)
input int    InpSB_RangeStartMinute        = 0;
input int    InpSB_RangeEndHour            = 7;     // Range-Ende = London-Open (GMT)
input int    InpSB_RangeEndMinute          = 0;
input double InpSB_BufferPips              = 1.0;   // Puffer ueber/unter Range fuer Trigger + SL
input double InpSB_RRRatio                 = 1.8;   // Risk:Reward (1.5-2.0 Zielkorridor)

input group "=== Strategie 2: Donchian-Breakout ==="
input bool   InpEnableDonchian              = false;
input int    InpDC_Period                   = 20;
input int    InpDC_ADXPeriod                 = 14;
input double InpDC_ADXMinLevel               = 23.0;
input double InpDC_ATRMult                   = 1.5;
input double InpDC_RRRatio                   = 2.5;

input group "=== Strategie 3: Mean-Reversion ==="
input bool   InpEnableMeanReversion          = false;
input int    InpMR_BBPeriod                  = 20;
input double InpMR_BBDeviation                = 2.0;
input int    InpMR_RSIPeriod                  = 14;
input double InpMR_RSIUpperLevel              = 70.0;
input double InpMR_RSILowerLevel              = 30.0;
input int    InpMR_ADXPeriod                  = 14;
input double InpMR_ADXMaxLevel                = 20.0;
input double InpMR_ATRMult                    = 2.75;

//====================================================================
// Globaler Zustand
//====================================================================
string             g_symbols[];
int                g_numSymbols = 0;
SStrategyPosition  g_positions[];
SDrawdownState     g_ddState;
SSessionBreakoutState g_sbState[];
SDonchianState        g_dcState[];
SMeanReversionState   g_mrState[];

// Throttle-State fuer "Budget voll"-Logs: zuletzt geloggte M15-Bar je Symbol,
// damit die Meldung hoechstens 1x pro M15-Bar statt pro Tick geschrieben wird.
datetime           g_lastBudgetLogSB[];
datetime           g_lastBudgetLogDC[];
datetime           g_lastBudgetLogMR[];

//+------------------------------------------------------------------+
//| Zerlegt InpSymbolsCsv in g_symbols[] und validiert jedes Symbol  |
//| gegen den Market-Watch (SymbolSelect). Ungueltige Symbole werden |
//| verworfen und geloggt statt den EA abzubrechen.                  |
//+------------------------------------------------------------------+
bool InitSymbols()
  {
   string raw[];
   // Im Strategy-Tester standardmaessig nur das gewaehlte Chart-Symbol handeln,
   // damit der Symbol-Dropdown das gehandelte Symbol steuert und ein echter
   // Einzelsymbol-Test moeglich ist. Mit InpTesterForceAllSymbols=true wird
   // stattdessen die volle CSV-Liste gehandelt (Portfolio-Lauf). Live: immer
   // volle CSV-Liste wie bisher.
   bool testerSingleSymbol = MQLInfoInteger(MQL_TESTER) && !InpTesterForceAllSymbols;
   if(testerSingleSymbol)
     {
      ArrayResize(raw, 1);
      raw[0] = _Symbol;
      PrintFormat("InitSymbols: Tester erkannt - auf Einzelsymbol %s reduziert (InpSymbolsCsv ignoriert).",
                  _Symbol);
     }
   else if(MQLInfoInteger(MQL_TESTER))
      Print("InitSymbols: Tester-Portfolio-Modus (InpTesterForceAllSymbols=true) - volle CSV-Liste. "
            "ACHTUNG: nur das Dropdown-Symbol hat echte Ticks, uebrige Symbole nur interpoliert.");

   int n = testerSingleSymbol ? 1 : StringSplit(InpSymbolsCsv, ',', raw);

   ArrayResize(g_symbols, 0);
   for(int i = 0; i < n; i++)
     {
      string sym = raw[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "")
         continue;

      if(!SymbolSelect(sym, true))
        {
         PrintFormat("InitSymbols: Symbol '%s' konnte nicht selektiert werden - wird ignoriert.", sym);
         continue;
        }

      int idx = ArraySize(g_symbols);
      ArrayResize(g_symbols, idx + 1);
      g_symbols[idx] = sym;
     }

   g_numSymbols = ArraySize(g_symbols);
   return g_numSymbols > 0;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!InitSymbols())
     {
      Print("OnInit: keine gueltigen Symbole - EA wird nicht gestartet.");
      return INIT_FAILED;
     }

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("OnInit: Konto ist NICHT im Hedging-Modus - Architektur (Brutto-Exposure, "
            "gegenlaeufige Positionen pro Strategie) setzt Hedge-Konto voraus!");

   InitPositionTracker(g_positions, g_numSymbols);

   ArrayResize(g_sbState, g_numSymbols);
   for(int i = 0; i < g_numSymbols; i++)
     {
      g_sbState[i].rangeDay     = 0;
      g_sbState[i].rangeHigh    = 0.0;
      g_sbState[i].rangeLow     = 0.0;
      g_sbState[i].rangeValid   = false;
      g_sbState[i].lastTradeDay = 0;
     }

   ArrayResize(g_lastBudgetLogSB, g_numSymbols);
   ArrayResize(g_lastBudgetLogDC, g_numSymbols);
   ArrayResize(g_lastBudgetLogMR, g_numSymbols);
   ArrayInitialize(g_lastBudgetLogSB, 0);
   ArrayInitialize(g_lastBudgetLogDC, 0);
   ArrayInitialize(g_lastBudgetLogMR, 0);

   g_ddState.currentDay     = 0;
   g_ddState.dayStartEquity = 0.0;
   UpdateDrawdownState(g_ddState, AccountInfoDouble(ACCOUNT_EQUITY));

   if(InpEnableDonchian)
     {
      if(!InitDonchianState(g_dcState, g_symbols, g_numSymbols, InpDC_ADXPeriod))
        {
         Print("OnInit: Donchian-Indikator-Handles konnten nicht vollstaendig erzeugt werden.");
         return INIT_FAILED;
        }
     }

   if(InpEnableMeanReversion)
     {
      if(!InitMeanReversionState(g_mrState, g_symbols, g_numSymbols, InpMR_BBPeriod, InpMR_BBDeviation,
                                  InpMR_RSIPeriod, InpMR_ADXPeriod))
        {
         Print("OnInit: MeanReversion-Indikator-Handles konnten nicht vollstaendig erzeugt werden.");
         return INIT_FAILED;
        }
     }

   int gmtOffset = GetServerGmtOffsetHours(InpTesterServerGmtOffset);
   PrintFormat("PortfolioEA: Server-GMT-Offset = %+d h (%s). Alle Uhrzeit-Inputs sind in GMT.",
               gmtOffset,
               MQLInfoInteger(MQL_TESTER) ? "Tester-Fallback-Input" : "live gemessen");

   PrintFormat("PortfolioEA initialisiert: %d Symbole, Risk=%.2f%%/Trade, PortfolioCap=%.2f%%.",
               g_numSymbols, InpRiskPercentPerTrade, InpMaxPortfolioRiskPercent);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpEnableDonchian)
      DeinitDonchianState(g_dcState);
   if(InpEnableMeanReversion)
      DeinitMeanReversionState(g_mrState);
  }

//+------------------------------------------------------------------+
//| Strategie 1 fuer ein Symbol pruefen und ggf. eroeffnen.          |
//+------------------------------------------------------------------+
void ProcessSessionBreakout(const int symbolIndex, const string symbol, const double equity,
                            const int serverGmtOffsetHours, double &pendingRiskPercent)
  {
   if(HasOpenPosition(g_positions, STRATEGY_SESSION_BREAKOUT, symbolIndex, g_numSymbols))
      return;

   double frictionPips      = GetFrictionPips(symbol, InpCommissionPerLotRoundTurn, InpSlippageBufferPips);
   double minSLDistancePips = InpMinSLFrictionMultiple * frictionPips;

   int rangeStartMin = GmtHourMinuteToServerMinutesOfDay(InpSB_RangeStartHour, InpSB_RangeStartMinute,
                                                          serverGmtOffsetHours);
   int rangeEndMin   = GmtHourMinuteToServerMinutesOfDay(InpSB_RangeEndHour, InpSB_RangeEndMinute,
                                                          serverGmtOffsetHours);

   SSignal signal;
   bool hasSignal = CheckSessionBreakoutSignal(g_sbState[symbolIndex], symbol,
                                                rangeStartMin, rangeEndMin,
                                                InpSB_BufferPips, minSLDistancePips,
                                                InpSB_RRRatio, signal);
   if(!hasSignal)
      return;

   double lots = CalculateLotSize(symbol, equity, InpRiskPercentPerTrade, signal.entryPrice, signal.slPrice);
   lots = CapLotSize(symbol, lots, InpMaxLotPerTrade);
   if(lots <= 0.0)
      return;

   // Budget-Check auf Basis des TATSAECHLICH gecappten Lots (nicht des nominalen
   // Risiko-%): ein durch CapLotSize begrenztes Lot traegt ggf. weniger Risiko.
   double tradeRiskPercent = (equity > 0.0)
      ? (RiskAmountFromLots(symbol, lots, signal.entryPrice, signal.slPrice) / equity) * 100.0
      : InpRiskPercentPerTrade;

   if(!CanOpenNewPosition(g_positions, g_symbols, equity, tradeRiskPercent,
                          InpMaxPortfolioRiskPercent, pendingRiskPercent))
     {
      datetime bar = iTime(symbol, PERIOD_M15, 0);
      if(g_lastBudgetLogSB[symbolIndex] != bar)
        {
         PrintFormat("PortfolioRiskGuard: SessionBreakout-Signal %s uebersprungen (Budget voll).", symbol);
         g_lastBudgetLogSB[symbolIndex] = bar;
        }
      return;
     }

   long magic = MagicEncode(STRATEGY_SESSION_BREAKOUT, symbolIndex);
   if(magic < 0)
      return;
   ulong ticket = OpenPosition(symbol, signal.direction, lots, signal.slPrice, signal.tpPrice, magic,
                                "SessionBreakout");
   if(ticket > 0)
     {
      pendingRiskPercent += tradeRiskPercent; // im selben Tick gebuchtes Risiko mitfuehren
      MarkSessionBreakoutTraded(g_sbState[symbolIndex]);
      double slDistancePips = PriceDistanceToPips(symbol, signal.entryPrice - signal.slPrice);
      PrintFormat("SessionBreakout ENTRY %s %s Lots=%.2f SL=%.5f TP=%.5f | FrictionPips=%.2f "
                  "MinSLPips=%.1f ActualSLPips=%.1f | %s",
                  symbol, EnumToString(signal.direction), lots, signal.slPrice, signal.tpPrice,
                  frictionPips, minSLDistancePips, slDistancePips, signal.reason);
     }
  }

//+------------------------------------------------------------------+
//| Strategie 2 fuer ein Symbol pruefen und ggf. eroeffnen.          |
//+------------------------------------------------------------------+
void ProcessDonchian(const int symbolIndex, const string symbol, const double equity,
                     double &pendingRiskPercent)
  {
   if(HasOpenPosition(g_positions, STRATEGY_DONCHIAN, symbolIndex, g_numSymbols))
      return;

   double frictionPips      = GetFrictionPips(symbol, InpCommissionPerLotRoundTurn, InpSlippageBufferPips);
   double minSLDistancePips = InpMinSLFrictionMultiple * frictionPips;

   SSignal signal;
   bool hasSignal = CheckDonchianBreakoutSignal(g_dcState[symbolIndex], symbol,
                                                 InpDC_Period, InpDC_ADXMinLevel, InpDC_ATRMult,
                                                 minSLDistancePips, InpDC_RRRatio, signal);
   if(!hasSignal)
      return;

   double lots = CalculateLotSize(symbol, equity, InpRiskPercentPerTrade, signal.entryPrice, signal.slPrice);
   lots = CapLotSize(symbol, lots, InpMaxLotPerTrade);
   if(lots <= 0.0)
      return;

   double tradeRiskPercent = (equity > 0.0)
      ? (RiskAmountFromLots(symbol, lots, signal.entryPrice, signal.slPrice) / equity) * 100.0
      : InpRiskPercentPerTrade;

   if(!CanOpenNewPosition(g_positions, g_symbols, equity, tradeRiskPercent,
                          InpMaxPortfolioRiskPercent, pendingRiskPercent))
     {
      datetime bar = iTime(symbol, PERIOD_M15, 0);
      if(g_lastBudgetLogDC[symbolIndex] != bar)
        {
         PrintFormat("PortfolioRiskGuard: Donchian-Signal %s uebersprungen (Budget voll).", symbol);
         g_lastBudgetLogDC[symbolIndex] = bar;
        }
      return;
     }

   long magic = MagicEncode(STRATEGY_DONCHIAN, symbolIndex);
   if(magic < 0)
      return;
   ulong ticket = OpenPosition(symbol, signal.direction, lots, signal.slPrice, signal.tpPrice, magic,
                                "Donchian");
   if(ticket > 0)
     {
      pendingRiskPercent += tradeRiskPercent;
      MarkDonchianTraded(g_dcState[symbolIndex]);
      double slDistancePips = PriceDistanceToPips(symbol, signal.entryPrice - signal.slPrice);
      PrintFormat("Donchian ENTRY %s %s Lots=%.2f SL=%.5f TP=%.5f | FrictionPips=%.2f "
                  "MinSLPips=%.1f ActualSLPips=%.1f | %s",
                  symbol, EnumToString(signal.direction), lots, signal.slPrice, signal.tpPrice,
                  frictionPips, minSLDistancePips, slDistancePips, signal.reason);
     }
  }

//+------------------------------------------------------------------+
//| Strategie 3 fuer ein Symbol pruefen und ggf. eroeffnen.          |
//+------------------------------------------------------------------+
void ProcessMeanReversion(const int symbolIndex, const string symbol, const double equity,
                          double &pendingRiskPercent)
  {
   if(HasOpenPosition(g_positions, STRATEGY_MEAN_REVERSION, symbolIndex, g_numSymbols))
      return;

   double frictionPips      = GetFrictionPips(symbol, InpCommissionPerLotRoundTurn, InpSlippageBufferPips);
   double minSLDistancePips = InpMinSLFrictionMultiple * frictionPips;

   SSignal signal;
   bool hasSignal = CheckMeanReversionSignal(g_mrState[symbolIndex], symbol, InpMR_ADXMaxLevel,
                                              InpMR_RSIUpperLevel, InpMR_RSILowerLevel, InpMR_ATRMult,
                                              minSLDistancePips, signal);
   if(!hasSignal)
      return;

   double lots = CalculateLotSize(symbol, equity, InpRiskPercentPerTrade, signal.entryPrice, signal.slPrice);
   lots = CapLotSize(symbol, lots, InpMaxLotPerTrade);
   if(lots <= 0.0)
      return;

   double tradeRiskPercent = (equity > 0.0)
      ? (RiskAmountFromLots(symbol, lots, signal.entryPrice, signal.slPrice) / equity) * 100.0
      : InpRiskPercentPerTrade;

   if(!CanOpenNewPosition(g_positions, g_symbols, equity, tradeRiskPercent,
                          InpMaxPortfolioRiskPercent, pendingRiskPercent))
     {
      datetime bar = iTime(symbol, PERIOD_M15, 0);
      if(g_lastBudgetLogMR[symbolIndex] != bar)
        {
         PrintFormat("PortfolioRiskGuard: MeanReversion-Signal %s uebersprungen (Budget voll).", symbol);
         g_lastBudgetLogMR[symbolIndex] = bar;
        }
      return;
     }

   long magic = MagicEncode(STRATEGY_MEAN_REVERSION, symbolIndex);
   if(magic < 0)
      return;
   ulong ticket = OpenPosition(symbol, signal.direction, lots, signal.slPrice, signal.tpPrice, magic,
                                "MeanReversion");
   if(ticket > 0)
     {
      pendingRiskPercent += tradeRiskPercent;
      MarkMeanReversionTraded(g_mrState[symbolIndex]);
      double slDistancePips = PriceDistanceToPips(symbol, signal.entryPrice - signal.slPrice);
      PrintFormat("MeanReversion ENTRY %s %s Lots=%.2f SL=%.5f TP=%.5f | FrictionPips=%.2f "
                  "MinSLPips=%.1f ActualSLPips=%.1f | %s",
                  symbol, EnumToString(signal.direction), lots, signal.slPrice, signal.tpPrice,
                  frictionPips, minSLDistancePips, slDistancePips, signal.reason);
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   UpdateDrawdownState(g_ddState, equity);
   SyncPositionTracker(g_positions, g_numSymbols);

   // Server-GMT-Offset live messen (im Tester: Fallback-Input). Alle Uhrzeit-
   // Inputs sind in GMT definiert und werden hiermit in Server-Minuten umgerechnet.
   int gmtOffset = GetServerGmtOffsetHours(InpTesterServerGmtOffset);

   int forceCloseMin       = GmtHourMinuteToServerMinutesOfDay(InpForceCloseHour, InpForceCloseMinute,
                                                               gmtOffset);
   int fridayForceCloseMin = GmtHourMinuteToServerMinutesOfDay(InpFridayForceCloseHour,
                                                               InpFridayForceCloseMinute, gmtOffset);

   // Force-Close hat Vorrang vor allem anderen - strikt Intraday.
   EnforceForceClose(g_positions, g_numSymbols, forceCloseMin, fridayForceCloseMin);

   bool entryWindowOpen = IsNewEntryWindowOpen(TimeCurrent(), forceCloseMin, fridayForceCloseMin,
                                                InpNoNewEntryBeforeCloseMin);
   bool softPauseActive = IsSoftPauseActive(g_ddState, equity, InpDailySoftPauseLossPercent);

   if(!entryWindowOpen || softPauseActive)
      return; // keine neuen Entries; bestehende Positionen laufen bis SL/TP/Force-Close weiter

   // Risiko der in DIESEM Tick bereits eroeffneten Positionen. Der
   // PositionTracker resynct erst im naechsten Tick, daher wird das Budget
   // hier laufend mitgezaehlt, damit mehrere Entries in einem Tick den
   // Portfolio-Cap nicht gemeinsam ueberschreiten koennen.
   double pendingRiskPercent = 0.0;

   for(int s = 0; s < g_numSymbols; s++)
     {
      string symbol = g_symbols[s];

      if(InpEnableSessionBreakout)
         ProcessSessionBreakout(s, symbol, equity, gmtOffset, pendingRiskPercent);

      if(InpEnableDonchian)
         ProcessDonchian(s, symbol, equity, pendingRiskPercent);

      if(InpEnableMeanReversion)
         ProcessMeanReversion(s, symbol, equity, pendingRiskPercent);
     }
  }
//+------------------------------------------------------------------+
