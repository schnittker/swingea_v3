//+------------------------------------------------------------------+
//|                                              TrendMomentumEA.mq5 |
//|   Daily Time-Series-Momentum (Trendfolge) mit Vola-Targeting     |
//|   ueber einen diversifizierten Basket (FX-Majors + Gold + Index).|
//|                                                                  |
//|   Umsetzung von plan.md, Abschnitt 5 (Primaerstrategie):         |
//|   - Signal: 100/200-Tage-MA-Cross-Proxy auf GESCHLOSSENEN        |
//|     Daily-Bars (kein Look-Ahead/Repainting).                     |
//|   - Sizing: Volatilitaets-Targeting invers zur ATR, Ziel ~10%    |
//|     Portfolio-Jahresvolatilitaet.                                |
//|   - Frequenz: genau 1x pro Tag rebalancen (Latenz/Spread egal).  |
//|   - Kapital-Start: 3.000 EUR, IC Markets Raw MT5, Hedge-Konto.   |
//|                                                                  |
//|   ACHTUNG: Vor Echtgeld zwingend Out-of-Sample + Walk-Forward +  |
//|   Monte-Carlo + Forward-Test (siehe Go-Live-Checkliste plan.md). |
//+------------------------------------------------------------------+
#property copyright "swingea"
#property version   "1.00"
#property strict

#include "Include/Types.mqh"
#include "Include/SymbolManager.mqh"
#include "Include/SignalEngine.mqh"
#include "Include/RiskManager.mqh"
#include "Include/PositionTracker.mqh"
#include "Include/TradeExecution.mqh"
#include "Include/DrawdownGuard.mqh"

//====================== INPUTS ====================================
input group "=== Universum ==="
input string InpSymbols            = "EURUSD,USDJPY,GBPUSD,AUDUSD,XAUUSD,US500"; // Basket (CSV)

input group "=== Signal (TSMOM MA-Cross) ==="
input int    InpMaFastPeriod       = 100;    // schnelle MA (Tage)
input int    InpMaSlowPeriod       = 200;    // langsame MA (Tage)
input bool   InpAllowShort         = true;   // Short-Signale zulassen (sonst Long/Flat)

input group "=== Risiko / Sizing (Vola-Targeting) ==="
input double InpTargetAnnualVolPct = 10.0;   // Ziel-Portfolio-Jahresvol in %
input int    InpAtrPeriod          = 14;     // ATR-Periode (Daily)
input double InpAtrStopMult        = 3.0;    // SL = Mult * ATR(Daily)
input double InpMaxLotPerTrade      = 1.0;    // harte Lot-Obergrenze pro Trade
input double InpFrictionSLMult     = 15.0;   // Mindest-SL >= Mult * Friktion
input double InpSlippageBufferPts  = 20.0;   // Slippage-Puffer (Points)

input group "=== Schutz ==="
input double InpMaxDrawdownPct     = 20.0;   // DD-Kill-Switch: Entries sperren ab %
input double InpLotRebalanceTol    = 0.02;   // Rebalancing nur ab Lot-Abweichung

input group "=== Sonstiges ==="
input long   InpMagicNumber        = 990001; // Magic Number des EA

//====================== GLOBALE OBJEKTE ===========================
CSymbolManager   g_symbols;
CSignalEngine    g_signal;
CRiskManager     g_risk;
CPositionTracker g_tracker;
CTradeExecution  g_exec;
CDrawdownGuard   g_dd;

datetime         g_lastBarTime=0; // Zeitstempel der zuletzt verarbeiteten Daily-Bar

//+------------------------------------------------------------------+
//| Neuer geschlossener Daily-Bar auf dem Chart-Symbol?              |
//| Dient als globaler 1x/Tag-Trigger fuers Rebalancing.            |
//+------------------------------------------------------------------+
bool IsNewDailyBar(void)
  {
   datetime t=iTime(_Symbol,PERIOD_D1,0);
   if(t==0) return false;
   if(t!=g_lastBarTime)
     {
      g_lastBarTime=t;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(InpMaFastPeriod>=InpMaSlowPeriod)
     {
      Print("OnInit: MaFast muss < MaSlow sein");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_symbols.Configure(InpMaFastPeriod,InpMaSlowPeriod,InpAtrPeriod);
   if(!g_symbols.Init(InpSymbols))
      return INIT_FAILED;

   // Slippage-Puffer ist eine Point-Angabe (ganzzahlig). Einmal runden und
   // an beide Konsumenten (Deviation + Friktions-Berechnung) identisch geben.
   double slippagePts=MathRound(InpSlippageBufferPts);

   g_signal.Configure(InpAllowShort);
   g_risk.Configure(InpTargetAnnualVolPct,InpAtrStopMult,InpMaxLotPerTrade,
                    InpFrictionSLMult,slippagePts);
   g_tracker.Configure(InpMagicNumber);
   g_exec.Configure(InpMagicNumber,(ulong)slippagePts);
   g_exec.SetLotTolerance(InpLotRebalanceTol);
   g_dd.Configure(InpMaxDrawdownPct);
   g_dd.Init(AccountInfoDouble(ACCOUNT_EQUITY));

   // Beim Start sofort einmal rebalancen (nicht auf Tageswechsel warten).
   g_lastBarTime=0;

   PrintFormat("TrendMomentumEA init OK - %d Symbole, Ziel-Vol %.1f%%, Equity %.2f",
               g_symbols.Count(),InpTargetAnnualVolPct,AccountInfoDouble(ACCOUNT_EQUITY));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_symbols.Release();
  }

//+------------------------------------------------------------------+
//| Kern-Rebalancing ueber den gesamten Basket (1x/Tag)             |
//+------------------------------------------------------------------+
void RebalancePortfolio(void)
  {
   bool entriesAllowed = g_dd.Update();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int    n      = g_symbols.Count();

   for(int i=0;i<n;i++)
     {
      SymbolState *st=g_symbols.At(i);
      if(st==NULL || !st.valid) continue;

      //--- Signal + ATR aktualisieren (nur geschlossene Bars)
      if(!g_signal.Evaluate(st))
        {
         PrintFormat("Rebalance: %s Datenluecke - uebersprungen",st.name);
         continue;
        }

      //--- SL-Abstand (mit erzwungener Mindestdistanz)
      st.stopDistance=g_risk.ComputeStopDistance(st.name,st.atr);

      ENUM_SIGNAL_DIR target=st.targetDir;
      double lots=0.0;

      if(target!=SIGNAL_FLAT)
        {
         // Bei DD-Pause keine neuen/erhoehten Positionen -> Ziel FLAT erzwingen.
         if(!entriesAllowed)
            target=SIGNAL_FLAT;
         else
            lots=g_risk.ComputeLots(st.name,equity,n,st.atr);
        }

      g_exec.Rebalance(st.name,target,lots,st.stopDistance,g_tracker);
     }

   PrintFormat("Rebalance fertig - Equity %.2f, DD %.2f%%, offene Pos %d%s",
               equity,g_dd.CurrentDDPct(),g_tracker.OpenCount(),
               entriesAllowed?"":" [DD-PAUSE]");
  }

//+------------------------------------------------------------------+
//| OnTick - handelt nur beim ersten Tick eines neuen Daily-Bars.    |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(!IsNewDailyBar())
      return;
   RebalancePortfolio();
  }
//+------------------------------------------------------------------+
