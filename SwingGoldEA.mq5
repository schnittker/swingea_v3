//+------------------------------------------------------------------+
//|                                                    SwingGoldEA.mq5 |
//|   Tier-1/2-EA: DipBuy (D1/H4), Overlap-Trendfolge (H4/M15),    |
//|   LiquiditySweep-Reclaim (M15), einzeln abschaltbar.            |
//|                                                                    |
//|   Risiko wird ueber alle Strategien hinweg per ClusterRiskGuard   |
//|   gemessen und begrenzt (strategies.md Teil F, ea.md 4.10).      |
//|                                                                    |
//|   Ausfuehrung ausschliesslich auf geschlossenen Bars.            |
//|   PollNewBars() latcht die Bar-Flags einmal pro Tick, alle       |
//|   Is*Bar()-Aufrufe sind danach nicht-mutierend (Bugfix).        |
//|                                                                    |
//|   LiquiditySweep und LBMA-Fix-Reversal sind verworfene          |
//|   Hypothesen (ea.md 8.1) - hardcodiert deaktiviert (Konstanten  |
//|   statt Inputs, 2026-08-18), nicht mehr ueber Inputs steuerbar. |
//|   Default Asia: InpUseAsiaModule=false (Hazard H14: bestehende  |
//|   .set-Dateien wuerden sonst still zum Mehr-Modul-Lauf).        |
//|                                                                    |
//|   ACHTUNG: Vor Echtgeld zwingend Out-of-Sample + Walk-Forward + |
//|   Forward-Test (ea.md Abschnitt 8, Go-Live-Kette).             |
//+------------------------------------------------------------------+
#property copyright "swingea"
#property version   "2.00"
#property strict

#include "Include/Types.mqh"
#include "Include/MagicNumbers.mqh"
#include "Include/SymbolResolver.mqh"
#include "Include/TimeContext.mqh"
#include "Include/MarketData.mqh"
#include "Include/SignalModuleBase.mqh"
#include "Include/SignalDipBuy.mqh"
#include "Include/SignalOverlapTrend.mqh"
#include "Include/SignalLiquiditySweep.mqh"
#include "Include/SignalLbmaFixReversal.mqh"
#include "Include/SignalAsiaRangeBreakout.mqh"
#include "Include/FilterStack.mqh"
#include "Include/RiskManager.mqh"
#include "Include/ClusterRiskGuard.mqh"
#include "Include/PositionTracker.mqh"
#include "Include/DrawdownGuard.mqh"
#include "Include/TradeExecution.mqh"
#include "Include/TradeManager.mqh"
#include "Include/DecisionLog.mqh"
#include "Include/Notifications.mqh"

//====================== HARDCODED PARAMETER (optimiert 2020-2026) =
// DipBuy
const bool   DIPBUY_ALLOW_SHORT        = false;
const int    DIPBUY_EMA_SLOW           = 200;
const int    DIPBUY_EMA_MID            = 100;
const int    DIPBUY_SWING_LOOKBACK     = 4;
const int    DIPBUY_ATR_PERIOD         = 14;
const double DIPBUY_ATR_STOP_MULT      = 2.25;
const int    DIPBUY_ARMED_EXPIRY_BARS  = 10;
const double DIPBUY_TRAIL_ATR_MULT     = 3.5;
// Overlap
const bool   OVERLAP_ALLOW_SHORT       = false;
const int    OVERLAP_EMA_FAST_H4       = 30;
const int    OVERLAP_EMA_SLOW_H4       = 150;
const int    OVERLAP_PULLBACK_EMA_FAST = 15;
const int    OVERLAP_PULLBACK_EMA_SLOW = 50;
const int    OVERLAP_ATR_PERIOD_M15    = 14;
const int    OVERLAP_SWING_LOOKBACK    = 3;
const int    OVERLAP_ZONE_EXPIRY_BARS  = 12;
const double OVERLAP_TRAIL_ATR_MULT    = 4.0;
const double OVERLAP_ATR_STOP_MULT     = 2.75; // H-Test 6 bestaetigt (Plateau 2.0-3.5, ea.md 8.4)
// AsiaRangeBreakout
const double ASIA_TRAIL_ATR_MULT       = 3.0;
const bool   ASIA_ALLOW_SHORT          = true;  // H-Test 2 Robustheits-Nachtest: Long+Short > Long-only (ea.md 8.4)

//====================== VERWORFENE STRATEGIEN (ea.md 8.1) =========
// LiquiditySweep (Slot 2): kein Edge in allen Eskalationsstufen (Basis, Round-Number-,
// G/S-Ratio-Filter). LBMA-Fix-Reversal (Slot 3): PF<1 im gesamten 96-Passes-Grid.
// Beide dauerhaft deaktiviert - Konstanten statt Inputs, Werte = letzter getesteter Stand.
const bool   SWEEP_MODULE_ENABLED      = false;
const bool   SWEEP_ALLOW_SHORT         = false;
const double SWEEP_ATR_STOP_MULT       = 1.5;
const double SWEEP_MIN_SWEEP_ATR_MULT  = 0.5;
const bool   SWEEP_USE_WEEKLY          = true;
const bool   SWEEP_USE_MONTHLY         = true;
const bool   SWEEP_USE_YEARLY          = true;
const int    SWEEP_RECLAIM_BARS        = 3;
const int    SWEEP_COOLDOWN_BARS       = 2;
const bool   SWEEP_SESSION_RESTRICTED  = false;
const bool   SWEEP_USE_TREND_FILTER    = false;
const double SWEEP_ROUND_STEP          = 0.0;
const double SWEEP_ROUND_TOLERANCE     = 1.0;
const bool   SWEEP_USE_GS_FILTER       = false;
const string SWEEP_GS_SYMBOL           = "XAGUSD";
const int    SWEEP_GS_LOOKBACK         = 20;
const double SWEEP_RISK_PCT            = 1.0;

const bool   LBMAFIX_MODULE_ENABLED    = false;
const bool   LBMAFIX_ALLOW_SHORT       = false;
const double LBMAFIX_ATR_STOP_MULT     = 1.0;
const double LBMAFIX_MIN_MOVE_ATR_MULT = 0.5;
const double LBMAFIX_REVERSAL_ATR_MULT = 0.3;
const int    LBMAFIX_PRE_FIX_BARS      = 2;
const int    LBMAFIX_CONFIRM_BARS      = 3;
const int    LBMAFIX_FIX_AM_HOUR       = 10;
const int    LBMAFIX_FIX_AM_MINUTE     = 30;
const int    LBMAFIX_FIX_PM_HOUR       = 15;
const int    LBMAFIX_FIX_PM_MINUTE     = 0;
const double LBMAFIX_RISK_PCT          = 1.0;
// LbmaFixReversal
const double LBMAFIX_TRAIL_ATR_MULT    = 3.0;

//====================== INPUTS ====================================

input group "=== Module ==="
input bool   InpUseDipBuyModule    = true;   // DipBuy-Strategie (D1/H4) aktiv
input bool   InpUseOverlapModule   = true;   // Overlap-Strategie (H4-Bias/M15) aktiv
// InpUseSweepModule und InpUseLbmaFixModule entfernt (2026-08-18, ea.md 8.1): beide
// Hypothesen verworfen, dauerhaft deaktiviert als SWEEP_MODULE_ENABLED/LBMAFIX_MODULE_ENABLED.
input bool   InpUseAsiaModule      = false;  // Asia-Range-Breakout (M15) - Default false (Hazard H14)

// InpOverlapAtrStopMult entfernt (2026-08-18): H-Test 6 bestaetigt Plateau, Wert wieder
// hardcodiert als OVERLAP_ATR_STOP_MULT (s.o.).

// === Strategie LiquiditySweep === entfernt (2026-08-18, ea.md 8.1: kein Edge, verworfen).
// Alle Parameter jetzt hardcodiert als SWEEP_*-Konstanten (s.o.). Bei Bedarf zur
// Re-Validierung: Inputs wieder einkommentieren und Configure()-Aufruf in OnInit anpassen.
// input bool   InpSwAllowShort      = false; // Short-Sweeps erlaubt
// input double InpSwAtrStopMult     = 1.5;  // Stop-Abstand (ATR-M15-Multiplikator)
// input double InpSwMinSweepAtrMult = 0.5;  // Mindest-Sweep-Tiefe (ATR-M15-Vielfaches)
// input bool   InpSwUseWeekly       = true;  // W1 High/Low als Levels
// input bool   InpSwUseMonthly      = true;  // MN1 High/Low als Levels
// input bool   InpSwUseYearly       = true;  // Jahreshoch/-tief (13 MN1-Bars) als Levels
// input int    InpSwReclaimBars     = 3;    // Max. M15-Bars fuer Reclaim nach Sweep
// input int    InpSwCooldownBars    = 2;    // D1-Bars Pause nach jedem Trade/Veto
// input bool   InpSwSessionRestricted = false; // Sweep nur im Overlap-Fenster (12-16 GMT)
// input bool   InpSwUseTrendFilter    = false; // Sweep nur mit D1-Trend, 'Trends nicht faden'
// input double InpSwRoundStep      = 0.0; // Runde-Zahl-Schrittweite (z.B. 50.0), 0=Filter aus
// input double InpSwRoundTolerance = 1.0; // Max. Abstand Level<->runde Zahl (ATR-M15-Vielfaches)
// input bool   InpSwUseGsFilter    = false; // G/S-Ratio-Bestaetigungsfilter (Silber)
// input string InpSwGsSymbol       = "XAGUSD"; // Silber-Symbol, Broker-Suffix ggf. anpassen
// input int    InpSwGsLookback     = 20;    // D1-Bars fuer G/S-Ratio-/Silber-Momentum-Slope

// === Strategie LBMA-Fix-Reversal === entfernt (2026-08-18, ea.md 8.1: PF<1 im gesamten
// Grid, verworfen). Alle Parameter jetzt hardcodiert als LBMAFIX_*-Konstanten (s.o.).
// input bool   InpLbmaAllowShort     = false; // Short-Reversals erlaubt
// input double InpLbmaAtrStopMult    = 1.0;   // Stop-Abstand (ATR-M15-Multiplikator)
// input double InpLbmaMinMoveAtrMult = 0.5;   // Mindest-Pre-Fix-Lauf (ATR-M15-Vielfaches)
// input double InpLbmaReversalAtrMult= 0.3;   // Mindest-Reversal-Bestaetigung (ATR-M15-Vielfaches)
// input int    InpLbmaPreFixBars     = 2;     // M15-Bars vor dem Fix zur Lauf-Messung (30 Min)
// input int    InpLbmaConfirmBars    = 3;     // Max. M15-Bars fuer Reversal-Bestaetigung
// input int    InpLbmaFixAmHour      = 10;    // AM-Fix Stunde (London-Zeit)
// input int    InpLbmaFixAmMinute    = 30;    // AM-Fix Minute (London-Zeit)
// input int    InpLbmaFixPmHour      = 15;    // PM-Fix Stunde (London-Zeit)
// input int    InpLbmaFixPmMinute    = 0;     // PM-Fix Minute (London-Zeit)

input group "=== Strategie Asia-Range-Breakout ==="
// InpAsiaAllowShort entfernt (2026-08-18): H-Test 2 Robustheits-Nachtest validiert
// Long+Short, hardcodiert als ASIA_ALLOW_SHORT=true (s.o.).
input bool   InpAsiaRequireRetest         = true;  // Retest-Pflicht vs. Sofort-Entry (H-Test 2)
input int    InpAsiaBoxStartHour          = 0;     // Asia-Box Start (GMT-Stunde)
input int    InpAsiaBoxEndHour            = 8;     // Asia-Box Ende (GMT-Stunde)
input double InpAsiaRetestToleranceAtrMult= 0.2;   // Retest-Toleranz (ATR-M15-Vielfaches)
input int    InpAsiaConfirmBars           = 8;     // Max. M15-Bars fuer Retest-Bestaetigung
input double InpAsiaAtrStopMult           = 1.5;   // Stop-Kappung (ATR-M15-Multiplikator)

input group "=== Zeit / Session ==="
input bool   InpUseSessionFilter   = true;   // Overlap-Einstieg nur 12:00-16:00 GMT (validiert IS+OOS, ea.md 8.4)
input bool   InpUseWeekdayFilter   = false;  // Montag/Freitag-Sperre (H-Test)
input int    InpOverlapStartGmtHour = 12;    // Overlap-Fenster Start (GMT-Stunde, inkl.)
input int    InpOverlapEndGmtHour  = 16;     // Overlap-Fenster Ende (GMT-Stunde, exkl.)
input int    InpMondayStartGmtHour = 8;      // Montag: ab dieser GMT-Stunde erlaubt
input int    InpFridayStopGmtHour  = 18;     // Freitag: ab dieser GMT-Stunde gesperrt
input int    InpGmtOffsetWinter    = 2;      // Server-GMT-Offset Winter (ea.md 7.1)
input int    InpGmtOffsetSummer    = 3;      // Server-GMT-Offset Sommer (ea.md 7.1)

input group "=== Filter ==="
input bool   InpUseSpreadFilter    = false;  // H-Test
input int    InpMaxSpreadPoints    = 150;    // Friktionsgrenze (Points)

input group "=== Risiko (uebergreifend) ==="
input double InpRiskPctDipBuy      = 1.0;   // Risiko % je DipBuy-Trade (knowledge.md 4)
input double InpRiskPctOverlap     = 1.0;   // Risiko % je Overlap-Trade
// InpRiskPctSweep/InpRiskPctLbmaFix entfernt (2026-08-18): hardcodiert als SWEEP_RISK_PCT/
// LBMAFIX_RISK_PCT (s.o.), irrelevant solange beide Module deaktiviert bleiben.
input double InpRiskPctAsia        = 1.0;   // Risiko % je Asia-Range-Breakout-Trade
input double InpMaxClusterRiskPct  = 3.0;   // Cluster-Gesamt-Deckel (strategies.md Teil F)
input string InpMetalCluster       = "XAUUSD,XAGUSD,AUDUSD"; // Korrelations-Cluster
input bool   InpClusterCountForeign = true; // Fremd-Magic-Positionen im Cluster mitzaehlen
input bool   InpClusterNoSLBlocks  = true;  // Position ohne SL blockiert neue Trades
input double InpMaxRiskPctPerTrade = 2.0;   // Max. Risiko % pro Trade (Lot-Kappung, kapitalunabhaengig)
input double InpFrictionSLMult     = 15.0;  // Mindest-Stop vs. Friktion
input double InpSlippageBufferPts  = 20.0;  // Slippage-Puffer (Points)
input double InpMaxDailyLossPct    = 3.0;   // Tages-Kill-Switch
input double InpMaxTotalDDPct      = 100.0; // Gesamt-Kill-Switch
input double InpPartialPct         = 50.0;  // Teilgewinn-Anteil

input group "=== Infrastruktur ==="
input int    InpMagicBase          = 770000; // Basis, DipBuy +1, Overlap +2, Sweep +3, LbmaFix +4, Asia +5
input bool   InpLogDecisions       = true;   // Telemetrie (DecisionLog.csv)
input bool   InpEnableEmailNotify  = false;  // E-Mail bei Trade-Open/-Close (Terminal: Tools->Options->Email + "Allow Email" im EA)

//====================== SLOT-KLASSE ===============================
//
// Bündelt alles Modulspezifische. Als class (nie struct), da MQL5
// keinen operator= fuer Klassen generiert und ein bitweises Kopieren
// das eingebettete CTrade in CTradeExecution duplizieren wuerde
// (Hazard H3). Stets per &-Referenz uebergeben, nie kopieren.
//
class CStrategySlot
  {
public:
   bool               enabled;
   int                magic;
   double             riskPct;
   double             trailAtrMult;
   ulong              lastTicket;    // letztes bekanntes Positions-Ticket (fuer History-Lookup nach externem Close)
   CSignalModuleBase *module;     // heap-alloziert, Release() pflicht
   CPositionTracker   tracker;
   CTradeExecution    exec;
   CTradeManager      manager;

                     CStrategySlot(void): enabled(false), magic(0), riskPct(1.0),
                        trailAtrMult(2.5), lastTicket(0), module(NULL) {}

   //--- Gibt den heap-allozierten Modul-Zeiger frei. Fuer ALLE Slots
   //--- in OnDeinit aufrufen (auch bei disabled, ea.md H2).
   void              Release(void)
     {
      if(CheckPointer(module) == POINTER_DYNAMIC)
        {
         delete module;
        }
      module = NULL;
     }
  };

//====================== GLOBALE OBJEKTE ============================
CStrategySlot    g_slots[5];          // 0=DipBuy, 1=Overlap, 2=Sweep, 3=LbmaFix, 4=Asia (feste Reihenfolge, Hazard H10)
CSymbolResolver  g_symbolResolver;
CTimeContext     g_timeContext;
CMarketData      g_marketData;
CFilterStack     g_filterStack;
CRiskManager     g_riskManager;
CClusterRiskGuard g_clusterRiskGuard;
CDrawdownGuard   g_drawdownGuard;
CDecisionLog     g_decisionLog;
CNotifications   g_notifications;

//+------------------------------------------------------------------+
//| Prueft, ob eine eigene Position mit gegebener Magic existiert.   |
//| Wird VOR MarketData.Init() benoetigt, um TF-Flags korrekt zu    |
//| setzen (ein disabled Modul mit offener Position braucht seinen  |
//| ATR-Timeframe, ea.md H8).                                        |
//+------------------------------------------------------------------+
bool PositionExistsForMagic(const int magic)
  {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Synchronisiert einen Slot aus der tatsaechlichen Broker-Position.|
//| Verallgemeinert SwingGoldEA v1 :169-181.                        |
//+------------------------------------------------------------------+
void SyncSlotFromBroker(CStrategySlot &slot)
  {
   ulong ticket;
   if(!slot.tracker.FindOwnPosition(ticket))
      return;

   ENUM_POSITION_TYPE posType;
   if(!slot.tracker.GetType(ticket, posType))
     {
      PrintFormat("SwingGoldEA: Positionsrichtung fuer Slot '%s' nicht lesbar - Sync uebersprungen.",
                  slot.module.Name());
      return;
     }

   ENUM_SIGNAL_DIR dir = (posType == POSITION_TYPE_BUY) ? SIGNAL_LONG : SIGNAL_SHORT;
   slot.module.SyncInPosition(dir);
   PrintFormat("SwingGoldEA: Slot '%s' SyncInPosition dir=%d (Restart-Resilienz, ea.md 5).",
               slot.module.Name(), (int)dir);
  }

//+------------------------------------------------------------------+
//| Fuehrt eine gefeuerte SignalProposal durch FilterStack,          |
//| DrawdownGuard, ClusterRiskGuard, RiskManager und TradeExecution. |
//| Schreibt in jedem Fall eine DecisionLog-Zeile.                  |
//+------------------------------------------------------------------+
void EvaluateAndExecute(CStrategySlot &slot, SignalProposal &proposal)
  {
   string rejectReason  = "";
   double clusterRiskPct = 0.0;
   bool   accepted       = true;

   //--- 1. FilterStack (Spread + Session/Wochentag wenn session-restricted)
   accepted = g_filterStack.Evaluate(proposal,
                                     slot.module.SessionRestricted(),
                                     g_timeContext,
                                     rejectReason);

   //--- 2. DrawdownGuard (kontoweit)
   if(accepted)
     {
      string ddReason;
      if(!g_drawdownGuard.AllowNewTrade(ddReason))
        {
         accepted     = false;
         rejectReason = ddReason;
        }
     }

   //--- 3. Sizing (benoetigt fuer ClusterRiskGuard-Deckel-Pruefung)
   double refPrice  = 0.0;
   double stopPrice = proposal.stopPrice;
   double lots      = 0.0;

   if(accepted)
     {
      refPrice = (proposal.dir == SIGNAL_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      g_riskManager.EnforceMinStopDistance(proposal.dir, refPrice, stopPrice,
                                           g_symbolResolver.StopsLevelPoints());

      double riskScale  = g_drawdownGuard.GetRiskScale();
      double scaledRisk = slot.riskPct * riskScale;
      lots = g_riskManager.ComputeLots(refPrice, stopPrice,
                                       g_symbolResolver.VolumeMin(),
                                       g_symbolResolver.VolumeMax(),
                                       g_symbolResolver.VolumeStep(),
                                       scaledRisk);

      if(lots <= 0.0)
        {
         accepted     = false;
         rejectReason = "Lotgroesse < VOLUME_MIN";
        }
     }

   //--- 4. ClusterRiskGuard (uebgreifendes Risiko, ea.md 4.10)
   if(accepted)
     {
      double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
      double newRiskMoney = 0.0;
      if(equity > 0.0 && stopPrice != 0.0 && refPrice != 0.0)
        {
         double tickValue, tickSize;
         if(GetValidatedTickValue(_Symbol, tickValue, tickSize))
            newRiskMoney = (tickValue / tickSize) * MathAbs(refPrice - stopPrice) * lots;
        }

      string clusterReason;
      if(!g_clusterRiskGuard.AllowNewRisk(newRiskMoney, clusterRiskPct, clusterReason))
        {
         accepted     = false;
         rejectReason = clusterReason;
        }
     }

   //--- Log: Telemetrie (auch abgelehnte Trades, ea.md 4.12)
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(!accepted)
     {
      g_decisionLog.Write(slot.module.Name(), proposal.dir, refPrice, stopPrice,
                          proposal.targetPrice, proposal.atrAtSignal, spread, lots,
                          clusterRiskPct, false, rejectReason);
      slot.module.NotifyFilterVeto();
      return;
     }

   //--- 5. Order senden
   ulong dealTicket = 0;
   bool  sent       = slot.exec.SendMarket(proposal.dir, lots, stopPrice, 0.0, dealTicket);

   g_decisionLog.Write(slot.module.Name(), proposal.dir, refPrice, stopPrice,
                       proposal.targetPrice, proposal.atrAtSignal, spread, lots,
                       clusterRiskPct, sent,
                       sent ? "" : "TradeExecution fehlgeschlagen");

   if(sent)
     {
      slot.module.NotifyFilled();
      g_notifications.TradeOpened(slot.module.Name(), _Symbol, proposal.dir, lots, refPrice, stopPrice, proposal.targetPrice);
     }
   else
      slot.module.NotifyOrderFailed();
  }

//+------------------------------------------------------------------+
//| Ermittelt Netto-Profit und Einstiegs-Volumen einer bereits       |
//| geschlossenen Position ueber die History (slot.lastTicket) und  |
//| verschickt die Close-Mail. MUSS vor module.NotifyPositionClosed()|
//| aufgerufen werden, da GetDir() danach auf SIGNAL_FLAT zurueckfaellt.|
//+------------------------------------------------------------------+
void NotifyTradeClosed(CStrategySlot &slot)
  {
   double profit = 0.0;
   double volume = 0.0;

   if(slot.lastTicket != 0 && HistorySelectByPosition(slot.lastTicket))
     {
      int deals = HistoryDealsTotal();
      for(int d = 0; d < deals; d++)
        {
         ulong dealTicket = HistoryDealGetTicket(d);
         if(dealTicket == 0)
            continue;

         profit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
        }
     }

   g_notifications.TradeClosed(slot.module.Name(), _Symbol, slot.module.GetDir(), volume, profit);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   //--- 1. Symbol-Resolver
   if(!g_symbolResolver.Init(_Symbol))
      return INIT_FAILED;

   //--- 2. TimeContext + Plausibilitaets-Log
   g_timeContext.Configure(InpGmtOffsetWinter, InpGmtOffsetSummer,
                           InpOverlapStartGmtHour, InpOverlapEndGmtHour,
                           InpMondayStartGmtHour, InpFridayStopGmtHour);
   g_timeContext.LogInitPlausibility();

   //--- 3. Pruefen ob ein disabled Modul eine offene Position hat
   //---    (muss VOR MarketData.Init sein, damit TF-Flags korrekt gesetzt werden)
   int  magicDipBuy  = MagicDipBuy(InpMagicBase);
   int  magicOverlap = MagicOverlapTrend(InpMagicBase);
   int  magicSweep   = MagicLiquiditySweep(InpMagicBase);
   int  magicLbmaFix = MagicLbmaFixReversal(InpMagicBase);
   int  magicAsia    = MagicAsiaRangeBreakout(InpMagicBase);
   bool dipBuyHasPos  = PositionExistsForMagic(magicDipBuy);
   bool overlapHasPos = PositionExistsForMagic(magicOverlap);
   bool sweepHasPos   = PositionExistsForMagic(magicSweep);
   bool lbmaHasPos    = PositionExistsForMagic(magicLbmaFix);
   bool asiaHasPos    = PositionExistsForMagic(magicAsia);

   bool needH4Emas = InpUseOverlapModule || overlapHasPos;
   bool needM15    = InpUseOverlapModule || overlapHasPos || SWEEP_MODULE_ENABLED || sweepHasPos ||
                      LBMAFIX_MODULE_ENABLED || lbmaHasPos || InpUseAsiaModule || asiaHasPos;

   //--- 4. MarketData mit TF-Konfiguration
   SMarketDataCfg mdCfg;
   mdCfg.emaSlowPeriod      = DIPBUY_EMA_SLOW;
   mdCfg.emaMidPeriod       = DIPBUY_EMA_MID;
   mdCfg.atrPeriod          = DIPBUY_ATR_PERIOD;
   mdCfg.swingLookback      = DIPBUY_SWING_LOOKBACK;
   mdCfg.useH4Emas          = needH4Emas;
   mdCfg.emaFastH4Period    = OVERLAP_EMA_FAST_H4;
   mdCfg.emaSlowH4Period    = OVERLAP_EMA_SLOW_H4;
   mdCfg.useM15             = needM15;
   mdCfg.emaPullbackFastM15 = OVERLAP_PULLBACK_EMA_FAST;
   mdCfg.emaPullbackSlowM15 = OVERLAP_PULLBACK_EMA_SLOW;
   mdCfg.atrPeriodM15       = OVERLAP_ATR_PERIOD_M15;

   if(!g_marketData.Init(_Symbol, mdCfg))
      return INIT_FAILED;

   //--- 5. PollNewBars als Seed (IsNewD1Bar-Referenz setzen)
   g_marketData.PollNewBars();

   //--- 6a. DipBuy-Slot
   g_slots[0].enabled      = InpUseDipBuyModule;
   g_slots[0].magic        = magicDipBuy;
   g_slots[0].riskPct      = InpRiskPctDipBuy;
   g_slots[0].trailAtrMult = DIPBUY_TRAIL_ATR_MULT;
   g_slots[0].module       = new CSignalDipBuy();

   CSignalDipBuy *dipBuy = (CSignalDipBuy *)g_slots[0].module;
   dipBuy.Configure(DIPBUY_ALLOW_SHORT, DIPBUY_SWING_LOOKBACK, DIPBUY_ATR_STOP_MULT,
                    DIPBUY_ARMED_EXPIRY_BARS, magicDipBuy);

   g_slots[0].tracker.Configure(_Symbol, magicDipBuy);
   g_slots[0].exec.Configure(_Symbol, magicDipBuy,
                              g_symbolResolver.StopsLevelPoints(),
                              g_symbolResolver.FreezeLevelPoints(),
                              (int)MathRound(InpSlippageBufferPts),
                              "SwingGoldDipBuy");
   g_slots[0].manager.Configure(_Symbol, InpPartialPct, g_slots[0].trailAtrMult,
                                 g_symbolResolver.VolumeMin(), g_symbolResolver.VolumeStep(),
                                 g_symbolResolver.StopsLevelPoints(),
                                 PERIOD_D1);  // ATR vom D1 fuer DipBuy

   //--- 6b. Overlap-Slot
   g_slots[1].enabled      = InpUseOverlapModule;
   g_slots[1].magic        = magicOverlap;
   g_slots[1].riskPct      = InpRiskPctOverlap;
   g_slots[1].trailAtrMult = OVERLAP_TRAIL_ATR_MULT;
   g_slots[1].module       = new CSignalOverlapTrend();

   CSignalOverlapTrend *overlap = (CSignalOverlapTrend *)g_slots[1].module;
   overlap.Configure(OVERLAP_ALLOW_SHORT, OVERLAP_SWING_LOOKBACK, OVERLAP_ATR_STOP_MULT,
                     OVERLAP_ZONE_EXPIRY_BARS, magicOverlap);

   g_slots[1].tracker.Configure(_Symbol, magicOverlap);
   g_slots[1].exec.Configure(_Symbol, magicOverlap,
                              g_symbolResolver.StopsLevelPoints(),
                              g_symbolResolver.FreezeLevelPoints(),
                              (int)MathRound(InpSlippageBufferPts),
                              "SwingGoldOverlap");
   g_slots[1].manager.Configure(_Symbol, InpPartialPct, g_slots[1].trailAtrMult,
                                 g_symbolResolver.VolumeMin(), g_symbolResolver.VolumeStep(),
                                 g_symbolResolver.StopsLevelPoints(),
                                 PERIOD_M15); // ATR vom M15 fuer Overlap (strategies.md Teil D)

   //--- 6c. LiquiditySweep-Slot (verworfen, ea.md 8.1 - hardcodiert deaktiviert)
   g_slots[2].enabled      = SWEEP_MODULE_ENABLED;
   g_slots[2].magic        = magicSweep;
   g_slots[2].riskPct      = SWEEP_RISK_PCT;
   g_slots[2].trailAtrMult = OVERLAP_TRAIL_ATR_MULT; // M15-ATR-Trailing wie Overlap
   g_slots[2].module       = new CSignalLiquiditySweep();

   CSignalLiquiditySweep *sweep = (CSignalLiquiditySweep *)g_slots[2].module;
   sweep.Configure(SWEEP_ALLOW_SHORT, SWEEP_ATR_STOP_MULT, SWEEP_MIN_SWEEP_ATR_MULT,
                   SWEEP_USE_WEEKLY, SWEEP_USE_MONTHLY, SWEEP_USE_YEARLY,
                   SWEEP_RECLAIM_BARS, SWEEP_COOLDOWN_BARS,
                   SWEEP_SESSION_RESTRICTED, SWEEP_USE_TREND_FILTER,
                   SWEEP_ROUND_STEP, SWEEP_ROUND_TOLERANCE,
                   SWEEP_USE_GS_FILTER, SWEEP_GS_SYMBOL, SWEEP_GS_LOOKBACK, magicSweep);

   g_slots[2].tracker.Configure(_Symbol, magicSweep);
   g_slots[2].exec.Configure(_Symbol, magicSweep,
                              g_symbolResolver.StopsLevelPoints(),
                              g_symbolResolver.FreezeLevelPoints(),
                              (int)MathRound(InpSlippageBufferPts),
                              "SwingGoldSweep");
   g_slots[2].manager.Configure(_Symbol, InpPartialPct, g_slots[2].trailAtrMult,
                                 g_symbolResolver.VolumeMin(), g_symbolResolver.VolumeStep(),
                                 g_symbolResolver.StopsLevelPoints(),
                                 PERIOD_M15); // ATR vom M15 fuer Sweep

   //--- 6d. LBMA-Fix-Reversal-Slot (verworfen, ea.md 8.1 - hardcodiert deaktiviert)
   g_slots[3].enabled      = LBMAFIX_MODULE_ENABLED;
   g_slots[3].magic        = magicLbmaFix;
   g_slots[3].riskPct      = LBMAFIX_RISK_PCT;
   g_slots[3].trailAtrMult = LBMAFIX_TRAIL_ATR_MULT;
   g_slots[3].module       = new CSignalLbmaFixReversal();

   CSignalLbmaFixReversal *lbmaFix = (CSignalLbmaFixReversal *)g_slots[3].module;
   lbmaFix.Configure(LBMAFIX_ALLOW_SHORT, LBMAFIX_ATR_STOP_MULT,
                      LBMAFIX_MIN_MOVE_ATR_MULT, LBMAFIX_REVERSAL_ATR_MULT,
                      LBMAFIX_PRE_FIX_BARS, LBMAFIX_CONFIRM_BARS,
                      LBMAFIX_FIX_AM_HOUR, LBMAFIX_FIX_AM_MINUTE,
                      LBMAFIX_FIX_PM_HOUR, LBMAFIX_FIX_PM_MINUTE,
                      InpGmtOffsetWinter, InpGmtOffsetSummer, magicLbmaFix);

   g_slots[3].tracker.Configure(_Symbol, magicLbmaFix);
   g_slots[3].exec.Configure(_Symbol, magicLbmaFix,
                              g_symbolResolver.StopsLevelPoints(),
                              g_symbolResolver.FreezeLevelPoints(),
                              (int)MathRound(InpSlippageBufferPts),
                              "SwingGoldLbmaFix");
   g_slots[3].manager.Configure(_Symbol, InpPartialPct, g_slots[3].trailAtrMult,
                                 g_symbolResolver.VolumeMin(), g_symbolResolver.VolumeStep(),
                                 g_symbolResolver.StopsLevelPoints(),
                                 PERIOD_M15);

   //--- 6e. Asia-Range-Breakout-Slot
   g_slots[4].enabled      = InpUseAsiaModule;
   g_slots[4].magic        = magicAsia;
   g_slots[4].riskPct      = InpRiskPctAsia;
   g_slots[4].trailAtrMult = ASIA_TRAIL_ATR_MULT;
   g_slots[4].module       = new CSignalAsiaRangeBreakout();

   CSignalAsiaRangeBreakout *asia = (CSignalAsiaRangeBreakout *)g_slots[4].module;
   asia.Configure(ASIA_ALLOW_SHORT, InpAsiaRequireRetest,
                   InpAsiaBoxStartHour, InpAsiaBoxEndHour,
                   InpAsiaRetestToleranceAtrMult, InpAsiaConfirmBars,
                   InpAsiaAtrStopMult,
                   InpGmtOffsetWinter, InpGmtOffsetSummer, magicAsia);

   g_slots[4].tracker.Configure(_Symbol, magicAsia);
   g_slots[4].exec.Configure(_Symbol, magicAsia,
                              g_symbolResolver.StopsLevelPoints(),
                              g_symbolResolver.FreezeLevelPoints(),
                              (int)MathRound(InpSlippageBufferPts),
                              "SwingGoldAsia");
   g_slots[4].manager.Configure(_Symbol, InpPartialPct, g_slots[4].trailAtrMult,
                                 g_symbolResolver.VolumeMin(), g_symbolResolver.VolumeStep(),
                                 g_symbolResolver.StopsLevelPoints(),
                                 PERIOD_M15);

   //--- 6f. Kontoweite Komponenten
   g_filterStack.Configure(_Symbol,
                            InpUseSpreadFilter, InpMaxSpreadPoints,
                            InpUseSessionFilter, InpUseWeekdayFilter);

   g_riskManager.Configure(_Symbol, InpRiskPctDipBuy, InpMaxRiskPctPerTrade,
                            InpFrictionSLMult, InpSlippageBufferPts);
   // Hinweis: m_riskPercent in RiskManager wird nur als Fallback genutzt;
   // der eigentliche per-Slot-Wert kommt via riskPercentOverride in ComputeLots.

   g_clusterRiskGuard.Configure(InpMetalCluster, InpMaxClusterRiskPct,
                                 InpClusterCountForeign, InpClusterNoSLBlocks);

   g_drawdownGuard.Configure(_Symbol, InpMagicBase, InpMaxDailyLossPct, InpMaxTotalDDPct);
   g_drawdownGuard.Update();

   if(!g_decisionLog.Init(InpLogDecisions, "SwingGoldEA_DecisionLog.csv",
                          g_symbolResolver.Digits()))
      Print("SwingGoldEA: DecisionLog konnte nicht initialisiert werden - Telemetrie deaktiviert.");

   g_notifications.Configure(InpEnableEmailNotify);

   //--- 7. Restart-Resilienz: offene eigene Positionen resynchronisieren
   for(int i = 0; i < 5; i++)
     {
      if(PositionExistsForMagic(g_slots[i].magic))
         SyncSlotFromBroker(g_slots[i]);
     }

   //--- 8. Init-Log (Beweis im Journal welche Konfiguration lief, Hazard H14)
   PrintFormat("SwingGoldEA v2 init OK | Symbol=%s | DipBuy=%s (Magic=%d) | Overlap=%s (Magic=%d) | "
               "Sweep=%s (Magic=%d) | Lbma=%s (Magic=%d) | Asia=%s (Magic=%d) | Equity=%.2f | ClusterDegraded=%s",
               _Symbol,
               InpUseDipBuyModule ? "ON" : "OFF", magicDipBuy,
               InpUseOverlapModule ? "ON" : "OFF", magicOverlap,
               SWEEP_MODULE_ENABLED   ? "ON" : "OFF", magicSweep,
               LBMAFIX_MODULE_ENABLED ? "ON" : "OFF", magicLbmaFix,
               InpUseAsiaModule    ? "ON" : "OFF", magicAsia,
               AccountInfoDouble(ACCOUNT_EQUITY),
               g_clusterRiskGuard.IsDegraded() ? "true" : "false");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Alle Slots freigeben (auch nicht-aktivierte, Hazard H2)
   for(int i = 0; i < 5; i++)
      g_slots[i].Release();

   g_marketData.Deinit();
   g_decisionLog.Deinit();
  }

//+------------------------------------------------------------------+
//| OnTick — handelt nur auf neuen, geschlossenen Bars.              |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   //--- Bar-Flags einmal latchern (Bugfix: consumable-flag, Hazard H5)
   g_marketData.PollNewBars();

   //--- DrawdownGuard kontoweit aktualisieren
   g_drawdownGuard.Update();

   //--- Indikatorcaches VOR dem Slot-Loop einmalig aktualisieren (Bugfix: EnsureD1/H4/M15
   //--- setzt m_*Valid am Anfang auf false — wuerde bei Fehler im 2. Slot-Durchlauf
   //--- den Cache ungueltigen Zustand hinterlassen, obwohl Slot 0 bereits damit arbeitete).
   bool d1ReadOk  = true;
   bool h4ReadOk  = true;
   bool m15ReadOk = true;

   if(g_marketData.IsNewH4Bar() || g_marketData.IsNewD1Bar())
     {
      if(!g_marketData.EnsureD1())
        {
         if(!g_marketData.IsD1Valid())
           {
            Print("SwingGoldEA: EnsureD1 fehlgeschlagen - alle Slots in diesem Tick uebersprungen.");
            d1ReadOk = false;
           }
        }
     }

   if(g_marketData.IsNewH4Bar())
     {
      if(!g_marketData.EnsureH4())
        {
         if(!g_marketData.IsH4Valid())
           {
            Print("SwingGoldEA: EnsureH4 fehlgeschlagen - Overlap-Slot in diesem Tick uebersprungen.");
            h4ReadOk = false;
           }
        }
     }

   if(g_marketData.IsNewM15Bar())
     {
      if(!g_marketData.EnsureM15())
        {
         if(!g_marketData.IsM15Valid())
           {
            Print("SwingGoldEA: EnsureM15 fehlgeschlagen - Overlap-Slot in diesem Tick uebersprungen.");
            m15ReadOk = false;
           }
        }
     }

   //--- Slot-Loop in fester Reihenfolge (0=DipBuy, 1=Overlap, 2=Sweep, 3=LbmaFix, 4=Asia, Hazard H10:
   //--- bei simultanen Bar-Rollover beansprucht DipBuy das Budget zuerst)
   for(int s = 0; s < 5; s++)
     {
      ENUM_TIMEFRAMES trigTf = g_slots[s].module.TriggerTimeframe();
      ENUM_TIMEFRAMES atrTf  = g_slots[s].module.AtrTimeframe();

      //--- Daten-Verfuegbarkeit fuer diesen Slot pruefen
      bool dataOk = true;
      if(!d1ReadOk)
         dataOk = false;
      if(!h4ReadOk  && (trigTf == PERIOD_H4  || atrTf == PERIOD_H4))
         dataOk = false;
      if(!m15ReadOk && (trigTf == PERIOD_M15 || atrTf == PERIOD_M15))
         dataOk = false;

      if(!dataOk)
         continue;

      //--- Position vorhanden? -> Management (AUCH bei disabled Modul, Hazard H2/plan Anforderung)
      ulong ticket;
      bool  hasPosition = g_slots[s].tracker.FindOwnPosition(ticket);

      if(hasPosition)
        {
         //--- State-Machine synchron halten
         if(g_slots[s].module.GetState() != ST_IN_POSITION)
           {
            ENUM_POSITION_TYPE posType;
            if(g_slots[s].tracker.GetType(ticket, posType))
               g_slots[s].module.SyncInPosition(posType == POSITION_TYPE_BUY ? SIGNAL_LONG : SIGNAL_SHORT);
            else
               PrintFormat("SwingGoldEA: Positionsrichtung fuer Slot %d unlesbar - Sync uebersprungen.", s);
           }

         g_slots[s].lastTicket = ticket; // fuer History-Lookup nach externem Close merken

         //--- TradeManager: Teilgewinn, Breakeven, ATR-Trailing
         g_slots[s].manager.Manage(ticket, g_slots[s].module.GetDir(), g_slots[s].module.GetTargetPrice(),
                                   g_marketData, g_slots[s].tracker, g_slots[s].exec);

         continue; // kein neuer Entry solange Position offen
        }

      //--- Position gerade extern geschlossen (SL/TP-Hit oder manuell)?
      if(g_slots[s].module.GetState() == ST_IN_POSITION)
        {
         NotifyTradeClosed(g_slots[s]);
         g_slots[s].module.NotifyPositionClosed();
        }

      //--- Neuer Entry nur wenn Modul enabled UND neue Bar auf dem Trigger-TF
      if(!g_slots[s].enabled)
         continue;

      bool newTriggerBar = (trigTf == PERIOD_H4)  ? g_marketData.IsNewH4Bar()
                         : (trigTf == PERIOD_M15) ? g_marketData.IsNewM15Bar()
                         : false;

      if(!newTriggerBar)
         continue;

      //--- D1 muss fuer beide Module valid sein
      if(!g_marketData.IsD1Valid())
         continue;

      SignalProposal proposal;
      bool triggered = g_slots[s].module.OnBar(g_marketData, proposal);

      if(!triggered || !proposal.valid)
         continue;

      EvaluateAndExecute(g_slots[s], proposal);
     }
  }
//+------------------------------------------------------------------+
