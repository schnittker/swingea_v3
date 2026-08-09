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
//|   Default: InpUseOverlapModule=false, InpUseSweepModule=false   |
//|   (Hazard H14: bestehende .set-Dateien wuerden sonst still      |
//|   zum Mehr-Modul-Lauf).                                         |
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
#include "Include/FilterStack.mqh"
#include "Include/RiskManager.mqh"
#include "Include/ClusterRiskGuard.mqh"
#include "Include/PositionTracker.mqh"
#include "Include/DrawdownGuard.mqh"
#include "Include/TradeExecution.mqh"
#include "Include/TradeManager.mqh"
#include "Include/DecisionLog.mqh"

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
const double OVERLAP_ATR_STOP_MULT     = 2.75;
const int    OVERLAP_SWING_LOOKBACK    = 3;
const int    OVERLAP_ZONE_EXPIRY_BARS  = 12;
const double OVERLAP_TRAIL_ATR_MULT    = 4.0;

//====================== INPUTS ====================================

input group "=== Module ==="
input bool   InpUseDipBuyModule    = true;   // DipBuy-Strategie (D1/H4) aktiv
input bool   InpUseOverlapModule   = true;   // Overlap-Strategie (H4-Bias/M15) aktiv
input bool   InpUseSweepModule     = false;  // LiquiditySweep-Reclaim (M15) - Default false (Hazard H14)

input group "=== Strategie LiquiditySweep ==="
input bool   InpSwAllowShort      = false; // Short-Sweeps erlaubt
input double InpSwAtrStopMult     = 1.5;  // Stop-Abstand (ATR-M15-Multiplikator)
input double InpSwMinSweepAtrMult = 0.5;  // Mindest-Sweep-Tiefe (ATR-M15-Vielfaches)
input bool   InpSwUseWeekly       = true;  // W1 High/Low als Levels
input bool   InpSwUseMonthly      = true;  // MN1 High/Low als Levels
input bool   InpSwUseYearly       = true;  // Jahreshoch/-tief (13 MN1-Bars) als Levels
input int    InpSwReclaimBars     = 3;    // Max. M15-Bars fuer Reclaim nach Sweep
input int    InpSwCooldownBars    = 2;    // D1-Bars Pause nach jedem Trade/Veto

input group "=== Zeit / Session ==="
input bool   InpUseSessionFilter   = false;  // Overlap-Einstieg nur 12:00-16:00 GMT (H-Test)
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
input double InpRiskPctSweep       = 1.0;   // Risiko % je LiquiditySweep-Trade
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
input int    InpMagicBase          = 770000; // Basis, DipBuy +1, Overlap +2, Sweep +3
input bool   InpLogDecisions       = true;   // Telemetrie (DecisionLog.csv)

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
   CSignalModuleBase *module;     // heap-alloziert, Release() pflicht
   CPositionTracker   tracker;
   CTradeExecution    exec;
   CTradeManager      manager;

                     CStrategySlot(void): enabled(false), magic(0), riskPct(1.0),
                        trailAtrMult(2.5), module(NULL) {}

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
CStrategySlot    g_slots[3];          // 0=DipBuy, 1=Overlap, 2=Sweep (feste Reihenfolge, Hazard H10)
CSymbolResolver  g_symbolResolver;
CTimeContext     g_timeContext;
CMarketData      g_marketData;
CFilterStack     g_filterStack;
CRiskManager     g_riskManager;
CClusterRiskGuard g_clusterRiskGuard;
CDrawdownGuard   g_drawdownGuard;
CDecisionLog     g_decisionLog;

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

      lots = g_riskManager.ComputeLots(refPrice, stopPrice,
                                       g_symbolResolver.VolumeMin(),
                                       g_symbolResolver.VolumeMax(),
                                       g_symbolResolver.VolumeStep(),
                                       slot.riskPct);

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
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize > 0.0)
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
      slot.module.NotifyFilled();
   else
      slot.module.NotifyOrderFailed();
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
   bool dipBuyHasPos  = PositionExistsForMagic(magicDipBuy);
   bool overlapHasPos = PositionExistsForMagic(magicOverlap);
   bool sweepHasPos   = PositionExistsForMagic(magicSweep);

   bool needH4Emas = InpUseOverlapModule || overlapHasPos;
   bool needM15    = InpUseOverlapModule || overlapHasPos || InpUseSweepModule || sweepHasPos;

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

   //--- 6c. LiquiditySweep-Slot
   g_slots[2].enabled      = InpUseSweepModule;
   g_slots[2].magic        = magicSweep;
   g_slots[2].riskPct      = InpRiskPctSweep;
   g_slots[2].trailAtrMult = OVERLAP_TRAIL_ATR_MULT; // M15-ATR-Trailing wie Overlap
   g_slots[2].module       = new CSignalLiquiditySweep();

   CSignalLiquiditySweep *sweep = (CSignalLiquiditySweep *)g_slots[2].module;
   sweep.Configure(InpSwAllowShort, InpSwAtrStopMult, InpSwMinSweepAtrMult,
                   InpSwUseWeekly, InpSwUseMonthly, InpSwUseYearly,
                   InpSwReclaimBars, InpSwCooldownBars, magicSweep);

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

   //--- 6d. Kontoweite Komponenten
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

   //--- 7. Restart-Resilienz: offene eigene Positionen resynchronisieren
   for(int i = 0; i < 3; i++)
     {
      if(PositionExistsForMagic(g_slots[i].magic))
         SyncSlotFromBroker(g_slots[i]);
     }

   //--- 8. Init-Log (Beweis im Journal welche Konfiguration lief, Hazard H14)
   PrintFormat("SwingGoldEA v2 init OK | Symbol=%s | DipBuy=%s (Magic=%d) | Overlap=%s (Magic=%d) | "
               "Sweep=%s (Magic=%d) | Equity=%.2f | ClusterDegraded=%s",
               _Symbol,
               InpUseDipBuyModule ? "ON" : "OFF", magicDipBuy,
               InpUseOverlapModule ? "ON" : "OFF", magicOverlap,
               InpUseSweepModule   ? "ON" : "OFF", magicSweep,
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
   for(int i = 0; i < 3; i++)
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

   //--- Slot-Loop in fester Reihenfolge (0=DipBuy, 1=Overlap, 2=Sweep, Hazard H10:
   //--- bei simultanen Bar-Rollover beansprucht DipBuy das Budget zuerst)
   for(int s = 0; s < 3; s++)
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

         //--- TradeManager: Teilgewinn, Breakeven, ATR-Trailing
         g_slots[s].manager.Manage(ticket, g_slots[s].module.GetDir(), g_slots[s].module.GetTargetPrice(),
                                   g_marketData, g_slots[s].tracker, g_slots[s].exec);

         continue; // kein neuer Entry solange Position offen
        }

      //--- Position gerade extern geschlossen?
      if(g_slots[s].module.GetState() == ST_IN_POSITION)
         g_slots[s].module.NotifyPositionClosed();

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
