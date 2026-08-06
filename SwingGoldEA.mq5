//+------------------------------------------------------------------+
//|                                                    SwingGoldEA.mq5 |
//|   Struktureller Dip-Buy auf XAUUSD (D1-Bias/Setup, H4-Trigger).  |
//|   Umsetzung von ea.md, Phase 0 (Infrastruktur) + Phase 1         |
//|   (Baseline-Strategie, FilterStack nur Spread). Intermarket-      |
//|   Filter, NewsGuard, Session-Logik etc. sind bewusst NICHT Teil  |
//|   dieser Phase (siehe ea.md Abschnitt 9, Abbruchkriterium nach   |
//|   Phase 2).                                                       |
//|                                                                    |
//|   Ausfuehrung ausschliesslich auf geschlossenen Bars (D1-Bias/    |
//|   Setup, H4-Trigger). Long-only per Default (InpAllowShort=false),|
//|   da preisunelastische Zentralbanknachfrage keinen Stop-Loss hat  |
//|   (knowledge.md 5) - Shorts bleiben ueber InpAllowShort messbar.  |
//|                                                                    |
//|   ACHTUNG: Vor Echtgeld zwingend Out-of-Sample + Walk-Forward +   |
//|   Forward-Test (siehe ea.md Abschnitt 8, Go-Live-Kette).          |
//+------------------------------------------------------------------+
#property copyright "swingea"
#property version   "1.00"
#property strict

#include "Include/Types.mqh"
#include "Include/MagicNumbers.mqh"
#include "Include/SymbolResolver.mqh"
#include "Include/MarketData.mqh"
#include "Include/SignalDipBuy.mqh"
#include "Include/FilterStack.mqh"
#include "Include/RiskManager.mqh"
#include "Include/PositionTracker.mqh"
#include "Include/DrawdownGuard.mqh"
#include "Include/TradeExecution.mqh"
#include "Include/TradeManager.mqh"
#include "Include/DecisionLog.mqh"

//====================== INPUTS ====================================
input group "=== Strategie (SignalDipBuy) ==="
input bool   InpAllowShort       = false;   // Asymmetrie-Hypothese testbar machen (ea.md 2.2)
input int    InpEmaSlow          = 200;     // D1-Trendfilter
input int    InpEmaMid           = 150;     // [OPT] Ruecksetzer-Zone
input int    InpSwingLookback    = 3;       // Fraktal-Breite fuer Swing-Erkennung
input int    InpAtrPeriod        = 14;      // ATR-Periode (D1)
input double InpAtrStopMult      = 1.5;     // [OPT] Stop-Abstand (strategies.md: 1.5-2.0)
input int    InpArmedExpiryBars  = 25;      // Verfall eines Setups (D1-Bars)

input group "=== Filter (FilterStack) ==="
input bool   InpUseSpreadFilter  = true;    // H-Test
input int    InpMaxSpreadPoints  = 50;      // Friktionsgrenze (Points)

input group "=== Risiko ==="
input double InpRiskPercent        = 1.0;   // knowledge.md 4: 1-2%
input double InpMaxLotPerTrade     = 1.0;   // Lot-Kappung bei InpBaseEquity
input double InpBaseEquity         = 3000.0; // Referenz-Equity: MaxLot skaliert mit equity/base
input double InpFrictionSLMult     = 15.0;  // Mindest-Stop vs. Friktion
input double InpSlippageBufferPts  = 20.0;  // Slippage-Puffer (Points)
input double InpMaxDailyLossPct    = 3.0;   // Tages-Kill-Switch
input double InpMaxTotalDDPct      = 20.0;  // Gesamt-Kill-Switch
input double InpPartialPct         = 50.0;  // Teilgewinn-Anteil
input double InpTrailAtrMult       = 2.5;   // Trailing-Abstand

input group "=== Infrastruktur ==="
input int    InpMagicBase       = 770000;   // Basis, Module +1/+2/+3 (aktuell nur DipBuy)
input bool   InpLogDecisions    = true;     // Telemetrie (DecisionLog.csv)

//====================== GLOBALE OBJEKTE ============================
CSymbolResolver  g_symbolResolver;
CMarketData      g_marketData;
CSignalDipBuy    g_signalDipBuy;
CFilterStack     g_filterStack;
CRiskManager     g_riskManager;
CPositionTracker g_positionTracker;
CDrawdownGuard   g_drawdownGuard;
CTradeExecution  g_tradeExecution;
CTradeManager    g_tradeManager;
CDecisionLog     g_decisionLog;

int              g_magicDipBuy = 0;

//+------------------------------------------------------------------+
//| Fuehrt eine gefeuerte SignalProposal durch FilterStack,          |
//| DrawdownGuard, RiskManager und TradeExecution. Schreibt in jedem |
//| Fall (angenommen oder abgelehnt) eine DecisionLog-Zeile.         |
//+------------------------------------------------------------------+
void EvaluateAndExecute(SignalProposal &proposal)
  {
   string rejectReason = "";
   bool   accepted     = g_filterStack.Evaluate(proposal, rejectReason);

   if(accepted)
     {
      string ddReason;
      if(!g_drawdownGuard.AllowNewTrade(ddReason))
        {
         accepted     = false;
         rejectReason = ddReason;
        }
     }

   double refPrice  = 0.0;
   double stopPrice = proposal.stopPrice;
   double lots      = 0.0;

   if(accepted)
     {
      refPrice = (proposal.dir == SIGNAL_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      g_riskManager.EnforceMinStopDistance(proposal.dir, refPrice, stopPrice, g_symbolResolver.StopsLevelPoints());
      lots = g_riskManager.ComputeLots(refPrice, stopPrice, g_symbolResolver.VolumeMin(),
                                       g_symbolResolver.VolumeMax(), g_symbolResolver.VolumeStep());

      if(lots <= 0.0)
        {
         accepted     = false;
         rejectReason = "Lotgroesse < VOLUME_MIN";
        }
     }

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(!accepted)
     {
      g_decisionLog.Write("SignalDipBuy", proposal.dir, refPrice, stopPrice, proposal.targetPrice,
                          proposal.atrAtSignal, spread, lots, false, rejectReason);
      g_signalDipBuy.NotifyFilterVeto();
      return;
     }

   ulong dealTicket = 0;
   bool  sent        = g_tradeExecution.SendMarket(proposal.dir, lots, stopPrice, 0.0, dealTicket);

   g_decisionLog.Write("SignalDipBuy", proposal.dir, refPrice, stopPrice, proposal.targetPrice,
                       proposal.atrAtSignal, spread, lots, sent, sent ? "" : "TradeExecution fehlgeschlagen");

   if(sent)
      g_signalDipBuy.NotifyFilled();
   else
      g_signalDipBuy.NotifyOrderFailed();
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(!g_symbolResolver.Init(_Symbol))
      return INIT_FAILED;

   if(!g_marketData.Init(_Symbol, InpEmaSlow, InpEmaMid, InpAtrPeriod, InpSwingLookback))
      return INIT_FAILED;

   g_marketData.IsNewD1Bar(); // D1-Referenz seeden, damit InpArmedExpiryBars nicht sofort dekrementiert

   g_magicDipBuy = MagicDipBuy(InpMagicBase);

   g_signalDipBuy.Configure(InpAllowShort, InpSwingLookback, InpAtrStopMult, InpArmedExpiryBars, g_magicDipBuy);
   g_filterStack.Configure(_Symbol, InpUseSpreadFilter, InpMaxSpreadPoints);
   g_riskManager.Configure(_Symbol, InpRiskPercent, InpMaxLotPerTrade, InpBaseEquity, InpFrictionSLMult, InpSlippageBufferPts);
   g_positionTracker.Configure(_Symbol, g_magicDipBuy);
   g_drawdownGuard.Configure(_Symbol, InpMagicBase, InpMaxDailyLossPct, InpMaxTotalDDPct);
   g_tradeExecution.Configure(_Symbol, g_magicDipBuy, g_symbolResolver.StopsLevelPoints(),
                              g_symbolResolver.FreezeLevelPoints(), (int)MathRound(InpSlippageBufferPts));
   g_tradeManager.Configure(_Symbol, InpPartialPct, InpTrailAtrMult, g_symbolResolver.VolumeMin(),
                            g_symbolResolver.VolumeStep(), g_symbolResolver.StopsLevelPoints());

   if(!g_decisionLog.Init(InpLogDecisions, "SwingGoldEA_DecisionLog.csv", g_symbolResolver.Digits()))
      Print("SwingGoldEA: DecisionLog konnte nicht initialisiert werden - Telemetrie deaktiviert.");

   g_drawdownGuard.Update(); // Tagesstart-/Peak-Equity beim Start seeden

   //--- Restart-Resilienz: bereits offene eigene Position erkennen (ea.md 5, Persistenz).
   //--- Hinweis: Zone-/Zielpreise fuer Teilgewinn koennen nach einem Neustart nicht
   //--- rekonstruiert werden (nicht persistiert) - TradeManager faellt dann auf reines
   //--- Breakeven+Trailing zurueck, bis die Position regulaer schliesst.
   ulong ticket;
   if(g_positionTracker.FindOwnPosition(ticket))
     {
      ENUM_POSITION_TYPE posType;
      if(g_positionTracker.GetType(ticket, posType))
         g_signalDipBuy.SyncInPosition(posType == POSITION_TYPE_BUY ? SIGNAL_LONG : SIGNAL_SHORT);
      else
         Print("SwingGoldEA: Positionsrichtung konnte nicht gelesen werden - Sync uebersprungen.");
     }

   PrintFormat("SwingGoldEA init OK - Symbol=%s MagicDipBuy=%d Equity=%.2f",
               _Symbol, g_magicDipBuy, AccountInfoDouble(ACCOUNT_EQUITY));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_marketData.Deinit();
   g_decisionLog.Deinit();
  }

//+------------------------------------------------------------------+
//| OnTick - handelt nur auf neuen, geschlossenen H4-Bars.           |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(!g_marketData.IsNewH4Bar())
      return;

   if(!g_marketData.Update())
     {
      Print("SwingGoldEA: MarketData.Update() fehlgeschlagen - Bar uebersprungen.");
      return;
     }

   g_drawdownGuard.Update();

   ulong ticket;
   bool  hasPosition = g_positionTracker.FindOwnPosition(ticket);

   if(hasPosition)
     {
      if(g_signalDipBuy.GetState() != ST_IN_POSITION)
        {
         ENUM_POSITION_TYPE posType;
         if(g_positionTracker.GetType(ticket, posType))
            g_signalDipBuy.SyncInPosition(posType == POSITION_TYPE_BUY ? SIGNAL_LONG : SIGNAL_SHORT);
         else
            Print("SwingGoldEA: Positionsrichtung konnte nicht gelesen werden - Sync uebersprungen.");
        }

      g_tradeManager.Manage(ticket, g_signalDipBuy.GetDir(), g_signalDipBuy.GetTargetPrice(),
                            g_marketData, g_positionTracker, g_tradeExecution);
      return;
     }

   if(g_signalDipBuy.GetState() == ST_IN_POSITION)
      g_signalDipBuy.NotifyPositionClosed(); // extern geschlossen (SL/TP-Hit, manuell)

   SignalProposal proposal;
   bool triggered = g_signalDipBuy.OnBar(g_marketData, proposal);

   if(!triggered || !proposal.valid)
      return; // reine Beobachtung ohne Trigger wird nicht geloggt (kein Log-Spam)

   EvaluateAndExecute(proposal);
  }
//+------------------------------------------------------------------+
