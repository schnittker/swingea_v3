# Portfolio-EA – Konzept-Dokumentation

Stand: 2026-08-03. Greenfield-Neustart, Multi-Strategie-Portfolio fuer ein
IC-Markets-MT5-Hedge-Konto. Ersetzt alle frueheren Konzeptversionen
(insbesondere die reine Intraday-Breakout-Ausrichtung).

## Eckdaten

- Konto: IC Markets MT5, **Hedge-Modus** (`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`).
  Gegenlaeufige Positionen verschiedener Strategien im selben Symbol sind
  ausdruecklich erlaubt, kein Netting-Zwang.
- Kapital: 3.000 EUR Start, +500 EUR/Monat Einzahlung. Risiko wird **dynamisch**
  vom aktuellen Equity berechnet (`AccountInfoDouble(ACCOUNT_EQUITY)`) – keine
  separate Einzahlungs-Tracking-Logik im EA.
- Risiko: **1.0% Equity pro Trade** (`InpRiskPercentPerTrade`).
- Symbole: EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD (5 FX-Majors, niedrige
  Friktion, per CSV-Input konfigurierbar).
- Strategien: Session-Open-Range-Breakout, Donchian-Breakout (+ADX-Trendfilter),
  Mean-Reversion (Bollinger+RSI, +ADX-Range-Filter).
- **Strikt Intraday**: kein Overnight, kein Wochenende, per Force-Close erzwungen.

## Kernzahl: Friktion

Round-Turn-Friktion ≈ 1.0–1.8 Pip (EURUSD-Referenz), bestehend aus Spread +
Kommission + Slippage (v.a. bei Breakout-Entries relevant). Jede Strategie MUSS
`SL-Distanz >= 15 x aktuelle Friktion` einhalten, sonst frisst die Kostenseite
das Risikobudget. Diese Untergrenze wird zur Laufzeit berechnet
(`SymbolUtils::GetFrictionPips()`, Spread live + Kommission-Input + fester
Slippage-Puffer) und ueber `RiskManager::EnforceMinSLDistance()` **vor** jeder
Lotberechnung erzwungen – nie danach, sonst waere das Risiko pro Trade falsch
kalkuliert.

## Magic-Number-Schema

```
MagicNumber = 10000 + StrategyID * 100 + SymbolIndex
```

- StrategyID: 1 = Session-Open-Range-Breakout, 2 = Donchian-Breakout,
  3 = Mean-Reversion.
- SymbolIndex: 0-basierter Index in `InpSymbolsCsv` (Reihenfolge wie im Input).

Encode/Decode in `Include/MagicNumbers.mqh` (`MagicEncode()`, `MagicDecode()`).
Granularitaet pro Strategie+Symbol ist notwendig, weil auf einem Hedge-Konto
mehrere Strategien gegenlaeufige Positionen im selben Symbol halten koennen –
reines Symbol-Filtern reicht nicht aus, um eine Position beim Force-Close,
Trailing oder Risk-Guard zweifelsfrei einer Strategie zuzuordnen. Jede
(Strategie, Symbol)-Kombination haelt maximal 1 offene Position (kein
Pyramiding), durchgesetzt von `PositionTracker::HasOpenPosition()`.

## Brutto-Exposure-Formel (Portfolio-Risikobudget)

```
GrossRiskUsedPercent = Σ (RiskAmount_p / aktuelles Equity) * 100   ueber ALLE offenen Positionen
RiskAmount_p = |OpenPrice_p - AktuellerSL_p| in Pips * PipValuePerLot(Symbol_p) * Volume_p
```

Bewusst **Brutto**, nicht Netto: Zwei gegenlaeufige Positionen im selben Symbol
heben sich im Richtungsrisiko auf, aber nicht im Stop-Loss-Risiko – bei einem
Whipsaw koennen beide unabhaengig ausgestoppt werden. Netting wuerde das Budget
faelschlich als "0% Risiko" ausweisen. `RiskAmount_p` wird live aus dem
**aktuellen** SL berechnet (nicht dem urspruenglichen) – Trailing/Breakeven
reduziert damit automatisch das gebundene Budget. Implementiert in
`Include/PortfolioRiskGuard.mqh` (`CalculateGrossRiskUsedPercent()`,
`CanOpenNewPosition()`). Default-Cap: `InpMaxPortfolioRiskPercent = 4.0`
(Zielkorridor 3-5%).

## Sessions / Force-Close

`Include/SessionManager.mqh` erzwingt "strikt Intraday" unabhaengig vom
jeweiligen Signal-Modul:

- `InpForceCloseHour/Minute`: taegliche Force-Close-Zeit (Server-Zeit, Default
  21:00).
- `InpFridayForceCloseHour/Minute`: fruehere Force-Close-Zeit an Freitagen
  (Default 20:00) als Wochenend-Gap-Schutz.
- `InpNoNewEntryBeforeCloseMin`: sperrt neue Entries X Minuten vor der
  Force-Close-Zeit (Default 60), damit eine frische Position nicht sofort
  wieder zwangsweise geschlossen werden muss.
- `EnforceForceClose()` laeuft als erster Schritt in `OnTick()`, hat Vorrang vor
  allen neuen Entries, und schliesst jede als offen getrackte Position per
  Ticket (`TradeExecution::ClosePositionByTicket()`).

## Tagesverlust-Regler (Soft-Pause)

`Include/DrawdownGuard.mqh` ist bewusst **kein Kill-Switch**: Bei Erreichen von
`InpDailySoftPauseLossPercent` (Default 3.0%) werden nur neue Entries fuer den
Rest des Handelstags gesperrt (`IsSoftPauseActive()`), bestehende Positionen
laufen unangetastet bis SL/TP oder Force-Close weiter. Daily/Total-DD sind laut
Vorgabe nur sekundaerer Regler.

## Strategie-Skizzen

Alle drei Strategien nutzen `SymbolUtils::GetFrictionPips()` →
`MinSLDistancePips = InpMinSLFrictionMultiple x FrictionPips` (Default-Multiple
15), angewendet in `RiskManager::EnforceMinSLDistance()` vor der Lotberechnung.
Jede Strategie hat eine eigene Tages-Frequenzsperre (max. 1 Trade/Tag pro
Symbol) gegen Overtrading.

### Strategie 1: Session-Open-Range-Breakout (M15)

`Include/SessionBreakoutSignal.mqh`. Bildet die Tagesrange (High/Low) im
konfigurierbaren Zeitfenster `InpSB_RangeStart.../InpSB_RangeEnd...` (Default
00:00-06:00 Server-Zeit, z.B. Asia-Session). Ausbruch wird NUR auf Bar-Close
der letzten abgeschlossenen M15-Bar getriggert (kein Intra-Bar-Trigger, vermeidet
False-Breakouts durch kurze Spikes), mit Puffer `InpSB_BufferPips` ueber/unter der
Range. SL = Gegenrange minus Puffer, mit Floor `MinSLDistancePips`. TP per
festem RR `InpSB_RRRatio` (Default 1.8, Zielkorridor 1.5-2.0).

### Strategie 2: Donchian-Breakout (H1)

`Include/DonchianBreakoutSignal.mqh`. Donchian-Kanal ueber `InpDC_Period`
abgeschlossene H1-Bars (Default 20) + ADX(`InpDC_ADXPeriod`)-Trendfilter:
Breakout wird nur gehandelt, wenn ADX >= `InpDC_ADXMinLevel` (Default 23,
Zielkorridor 22-25) – adressiert das historische Ergebnis PF 0.44 im
Range-Markt (Donchian ohne Trendfilter). SL = max(Gegenband-Distanz,
`InpDC_ATRMult` x ATR14), mit Floor `MinSLDistancePips`. TP per festem RR
`InpDC_RRRatio` (Default 2.5, Zielkorridor 2.5-3.0). Trailing ist eine spaetere
Ausbaustufe, aktuell fester RR.

### Strategie 3: Mean-Reversion (M15)

`Include/MeanReversionSignal.mqh`. ADX(`InpMR_ADXPeriod`) < `InpMR_ADXMaxLevel`
(Default 20) als Range-Filter (Gegenstueck zum Donchian-Trendfilter). Bollinger
(`InpMR_BBPeriod`/`InpMR_BBDeviation`, Default 20/2.0) + RSI(`InpMR_RSIPeriod`,
Default 14) im Extrembereich (> `InpMR_RSIUpperLevel`/< `InpMR_RSILowerLevel`,
Default 70/30) GEGEN die Extremrichtung. SL bewusst breit:
`InpMR_ATRMult` x ATR14 (Default 2.75, Zielkorridor 2.5-3.0) – der Floor
`MinSLDistancePips` wird davon i.d.R. ohnehin uebertroffen. TP = mittleres
Band (SMA `InpMR_BBPeriod`). Historisch am fehleranfaelligsten (Vorprojekt: nur
6 Trades, DD 8.06%, zu restriktive Filter) – deshalb zuletzt integriert und mit
gelockerten Schwellen versehen.

## Architektur-Uebersicht

```
PortfolioEA.mq5              Inputs, OnInit/OnTick, Orchestrierung
Include/
  Types.mqh                  Structs/Enums (SSignal, SStrategyPosition, ENUM_STRATEGY_ID)
  MagicNumbers.mqh           Encode/Decode Magic <-> (StrategyID, SymbolIndex)
  SymbolUtils.mqh            Pip/Point-Konvertierung (JPY-Fall), Friktionsschaetzung
  RiskManager.mqh            Equity-% -> Lotgroesse, Min-SL-Enforcement, Max-Lot-Cap
  TradeExecution.mqh         Order Open/Modify/Close, hedge-sicher (immer per Ticket)
  PositionTracker.mqh        State pro (Strategie, Symbol), Re-Sync ueber Magic-Filter
  SessionManager.mqh         Handelsfenster, Force-Close (Tag + Wochenende)
  PortfolioRiskGuard.mqh     Brutto-Exposure-Budget ueber alle offenen Positionen
  DrawdownGuard.mqh          Tagesverlust-Regler (Soft-Pause, kein Hard-Kill)
  SessionBreakoutSignal.mqh  Strategie 1
  DonchianBreakoutSignal.mqh Strategie 2
  MeanReversionSignal.mqh    Strategie 3
```

Abhaengigkeitsrichtung: Signal-Module duerfen `RiskManager`/`SymbolUtils`
nutzen, aber nicht umgekehrt (keine Zyklen). Alle `input`-Parameter leben in
`PortfolioEA.mq5`, gruppiert per `input group` (Symbole / Risk / Session /
Strategie 1-3).

## Orchestrierung (`OnTick()`)

1. Equity lesen, `DrawdownGuard` aktualisieren, `PositionTracker` re-syncen.
2. `SessionManager::EnforceForceClose()` – hat Vorrang vor allem anderen.
3. Entry-Fenster offen? (`IsNewEntryWindowOpen()`) UND keine Soft-Pause?
   (`IsSoftPauseActive()`) – sonst keine neuen Entries, bestehende Positionen
   laufen weiter.
4. Pro Symbol, pro aktivierter Strategie (`InpEnableSessionBreakout/Donchian/
   MeanReversion`): bereits offene Position dieser Strategie+Symbol? →
   uebersprungen. Sonst Signal pruefen → `RiskManager::CalculateLotSize()` →
   `CapLotSize()` → `PortfolioRiskGuard::CanOpenNewPosition()` →
   `TradeExecution::OpenPosition()`.

## Verifikation (durch den User in MetaTrader)

- Jede Strategie isoliert testen (andere zwei per Input deaktivieren:
  `InpEnableDonchian`/`InpEnableMeanReversion` sind standardmaessig `false`),
  Tester-Modus "Jeder Tick basierend auf echten Kursen".
- Referenzwerte aus Vorprojekt (nur Vergleich, kein Zielwert): Donchian vorher
  PF 0.44 (22 Trades, kein Trendfilter) – mit ADX-Filter Ziel PF > 1.0.
  Asia-Breakout-Analogon PF 1.21/74 Trades/DD 3.62% als plausibler Korridor
  fuer Session-Breakout. Mean-Reversion vorher nur 6 Trades/DD 8.06% (zu
  restriktiv) – mit gelockerten Schwellen Richtwert >30-50 Trades.
- Haltedauer-Check: keine Position darf ueber die Force-Close-Zeit hinaus
  offen sein (Log-Zeile "EnforceForceClose: Position ... zwangsweise
  geschlossen" pruefen).
- Risk-Audit-Log pro Trade (FrictionPips, MinSLPips, ActualSLPips wird bei
  jedem Entry geloggt) zur Verifikation der 15x-Friktion-Untergrenze.
- Kombinierter Portfolio-Test: Log-Zeilen "PortfolioRiskGuard: ... Signal ...
  uebersprungen (Budget voll)" zaehlen, um `InpMaxPortfolioRiskPercent` zu
  kalibrieren.
- Realistische Spread/Kommission-Werte im Tester setzen (Standard-Tester-Spread
  ist oft optimistischer als reale Breakout-Slippage). `InpCommissionPerLotRoundTurn`
  auf den tatsaechlichen IC-Markets-Raw-Tarif setzen.
- Monatliche 500-EUR-Einzahlungen werden im Backtest nicht automatisch
  simuliert – ggf. fuer Forward-/Demo-Test vormerken.

## Bekannte Grenzen / offene Ausbaustufen

- Kein Trailing-Stop implementiert (Donchian-Strategie nutzt aktuell festen
  RR statt Trailing – siehe Strategie-Skizze oben).
- `TradeExecution::OpenPosition()` gibt `result.order` als Ticket zurueck; bei
  `TRADE_ACTION_DEAL` entspricht dies i.d.R. dem Positions-Ticket, wird aber
  im naechsten `PositionTracker`-Sync ohnehin ueber die Magic-Number erneut
  verifiziert.
- Session-Range-Fenster (`InpSB_RangeStart/End`) wird als Minuten-des-Tages
  behandelt und unterstuetzt keinen Wrap ueber Mitternacht – fuer die
  Asia-Session (00:00-06:00 Server-Zeit typischerweise) ausreichend, bei
  abweichenden Broker-Zeitzonen ggf. anpassen.
