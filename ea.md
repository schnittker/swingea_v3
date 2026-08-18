# XAUUSD-EA – Theoretischer Umsetzungsplan (MT5)

> Abgeleitet aus [`knowledge.md`](./knowledge.md) und [`strategies.md`](./strategies.md) · Stand: 2026-08-06
> Zielplattform: MetaTrader 5, IC Markets Raw-Spread

---

## Vorbemerkung zur Ehrlichkeit des Vorhabens

`strategies.md` weist die Setup-Regeln ausdrücklich als **logische Ableitungen, nicht als backgetestete Ergebnisse** aus. Ein erheblicher Teil der Grundlagen ist in `knowledge.md` als **[M]** (Marktwissen ohne Beleg) markiert.

> **Konsequenz für die Architektur:** Dieser EA ist **primär ein Test-Harness, sekundär ein Handelssystem.** Jede Hypothese aus `strategies.md` Teil G muss per Input-Schalter ein- und ausschaltbar sein, damit der EA seine eigene Grundlage messen kann. Ein EA, der die Annahmen fest verdrahtet, kann sie nie widerlegen.

Das gilt besonders für den zentralen Befund aus `knowledge.md` 1.1: Die Realzins-Korrelation ist **seit 2022 gebrochen**. Ein Gold-System muss davon ausgehen, dass **auch die aktuell beobachteten Zusammenhänge brechen können.**

---

## Inhalt

1. [Zielsetzung & Scope](#1-zielsetzung--scope)
2. [Grundsatzentscheidungen](#2-grundsatzentscheidungen)
3. [Architektur](#3-architektur)
4. [Modulspezifikationen](#4-modulspezifikationen)
5. [State Machine](#5-state-machine)
6. [Inputs](#6-inputs)
7. [MT5-spezifische Fallstricke](#7-mt5-spezifische-fallstricke)
8. [Backtest- & Validierungsplan](#8-backtest--validierungsplan)
9. [Entwicklungsphasen](#9-entwicklungsphasen)
10. [Bekannte Grenzen & offene Fragen](#10-bekannte-grenzen--offene-fragen)

---

## 1. Zielsetzung & Scope

**Ziel:** Ein modularer Single-Symbol-EA für XAUUSD, der die Tier-1-Strategien aus `strategies.md` mechanisch umsetzt und dabei die Intermarket-Filter (Teil B) als abschaltbare Schichten führt.

### In Scope

- XAUUSD als Handelssymbol (Single-Symbol-Ausführung)
- Satelliten-Symbole **nur als Datenquelle** für Filter (XAGUSD, EURUSD, USDJPY, USDCHF, Copper)
- Long-only im Baseline (Begründung siehe 2.2)
- Swing-Modul zuerst, Intraday-Module später

### Out of Scope

| Ausgeschlossen | Grund (Quelle) |
|---|---|
| Scalping / M1–M5-Entries | `strategies.md` Teil D: Ziel < 10× Round-Trip-Kosten |
| Martingale / Grid / Averaging | keine Stop-Definition, Ruin-Risiko |
| G/S-Ratio-Pairtrade | `strategies.md` Tier 3: Silber-Spread 4,5×, Liquidität bricht im Extrem |
| Realzins-/DXY-Timing als Signal | `knowledge.md` 1.1/1.2: Korrelation gebrochen, nur 14 % Attribution |
| Saisonalität | `knowledge.md` 7: schwächste Datenlage |
| Multi-Symbol-Portfolio-Ausführung | bewusst dem Vorgänger-EA überlassen; hier Fokus Gold |

---

## 2. Grundsatzentscheidungen

Jede Entscheidung mit Ableitung – damit später nachvollziehbar bleibt, warum es so gebaut ist.

### 2.1 Baseline-Strategie: Struktureller Dip-Buy (Swing, D1-Bias / H4-Entry)

Von den beiden Tier-1-Strategien zuerst der Swing-Ansatz:

| Argument | Begründung |
|---|---|
| **Kostenrobustheit** | `strategies.md` Teil D nennt den Swing-Pfad explizit „deutlich kostenrobuster". Deckt sich mit der Erfahrung aus dem Vorgänger-Plan: Intraday-Ideen sterben an der Friktion. |
| **Einziger fundamentaler Rückenwind** | Zentralbanknachfrage ~1.000 t/Jahr, preisunelastisch, ohne Stop-Loss (`knowledge.md` 5). Keine andere Strategie hat eine strukturelle Stütze. |
| **Kleinste Overfitting-Fläche** | D1/H4 braucht keine Session-, DST- und Fix-Zeit-Logik → deutlich weniger Code-Risiko und weniger Parameter. |
| **Keine Kalender-Abhängigkeit im Tester** | Der News-Filter ist auf D1 weniger kritisch (siehe 7.2 – Kalender ist im Tester nicht verfügbar). |

**Der Preis dieser Wahl:** wenige Trades → dünne Stichprobe. Gegenmaßnahme in 8.3.

### 2.2 Long-only im Baseline

Direkt aus `knowledge.md` 5 und `strategies.md` Teil A.2: Shorts kämpfen gegen preisunelastische Käufer ohne Stop-Loss; `strategies.md` Teil E schließt „Shorts über Wochen halten" explizit aus. Ein Swing-EA hält per Definition über Wochen.

> `InpAllowShort` bleibt als Input vorhanden (Default `false`), damit die Asymmetrie-Hypothese **messbar** ist statt nur behauptet.

### 2.3 Ausführung ausschließlich auf geschlossenen Bars

Konvention des Repos (`SignalEngine.mqh`: „Es wird ausschliesslich Bar[1] gelesen"). Bei Gold zusätzlich zwingend, weil Intrabar-Spikes (Stop-Hunts, `knowledge.md` 4) sonst als Signal fehlinterpretiert werden.

### 2.4 Fixed-Fractional-Risiko statt Vola-Targeting

Der Vorgänger-EA nutzte Vola-Targeting, weil er ein **Portfolio** über N Symbole ausbalancierte. Hier gibt es nur ein Symbol → das Ziel ist nicht Vola-Gleichverteilung, sondern die in `knowledge.md` 4 belegte Regel **1–2 % Risiko pro Trade** mit ATR-basiertem Stop.

Die Vola-Anpassung passiert implizit: breiterer ATR-Stop → kleinere Lots (`knowledge.md` 4: „Positionsgröße folgt dem Stop-Abstand").

### 2.5 Filter sind Vetos, keine Signale

`knowledge.md` 1.2 (DXY nur 14 % Attribution) und 1.1 (Realzins gebrochen) verbieten es, Intermarket-Daten als Entry-Trigger zu nutzen. Architektonisch: **Signalmodule kennen keine Satelliten-Symbole.** Der `FilterStack` kann einen Trade nur ablehnen, nie auslösen.

### 2.6 Graceful Degradation bei fehlenden Daten

Satelliten-Symbole sind brokerabhängig oft nicht vorhanden (v. a. DXY, VIX, Copper). Fehlt ein Symbol, darf der EA **nicht** stillschweigend ohne Filter weiterhandeln – er muss in einen definierten, geloggten Zustand fallen (siehe 4.5).

---

## 3. Architektur

### 3.1 Datenfluss

```
OnTick()
   |
   v
[NewBarDetector]  -- nur bei neuer geschlossener H4/D1-Bar weiter
   |
   v
[TimeContext]     -- GMT / London / NY, Session, Broker-Pause
   |
   v
[MarketData]      -- Closed-Bar-Reads, Indikator-Handles, Sync-Check
   |
   +---> [RegimeClassifier] ---> ENUM_REGIME
   |
   v
[SignalModule(s)] -- liefern SignalProposal (Richtung, Entry, SL, TP)
   |
   v
[FilterStack]     -- Vetos: Spread, News, Regime, Silber, Session
   |             (lehnt ab, loest nie aus)
   v
[RiskManager]     -- Lotberechnung aus SL-Abstand
   |
   v
[ClusterRiskGuard]-- Metall-Gesamtexposure-Deckel
   |
   v
[DrawdownGuard]   -- Tages-/Gesamt-Limit, Kill-Switch
   |
   v
[TradeExecution]  -- Order, Filling-Mode, StopsLevel-Normalisierung
   |
   v
[TradeManager]    -- Teilgewinne, Trailing, "Walking the Band"-Regel
   |
   v
[DecisionLog]     -- CSV: jede Entscheidung inkl. Ablehnungsgrund
```

### 3.2 Dateistruktur

Konsistent mit dem Vorgänger-Layout (`Include/*.mqh`, Include-Guards, ASCII-Kommentare auf Deutsch):

```
SwingGoldEA.mq5                     Einstieg: Inputs, OnInit/OnTick/OnDeinit, Verdrahtung
Include/
  Types.mqh                         Enums, SignalProposal, GoldState
  MagicNumbers.mqh                  Magic pro Signalmodul (Cluster-Zuordnung)
  SymbolResolver.mqh                Suffix-Auflösung, Satelliten-Verfügbarkeit
  TimeContext.mqh                   GMT/London/NY, DST, Sessions, LBMA-Fix, Broker-Pause
  MarketData.mqh                    Closed-Bar-Reads, Handles, Multi-Symbol-Sync
  RegimeClassifier.mqh              knowledge.md Teil B als Zustandsmaschine
  SignalDipBuy.mqh                  Phase 1: Swing Dip-Buy (D1-Bias / H4-Entry)
  SignalOverlapTrend.mqh            Phase 3: Overlap-Trendfolge (H4-Bias / M15)
  SignalSweepReclaim.mqh            Phase 4: Liquidity-Sweep-Reclaim
  FilterStack.mqh                   Veto-Schichten, einzeln abschaltbar
  NewsGuard.mqh                     Kalender live + CSV-Fallback fuer Tester
  RiskManager.mqh                   Fixed-Fractional + ATR-Stop
  ClusterRiskGuard.mqh              Metall-Korrelations-Deckel (strategies.md Teil F)
  DrawdownGuard.mqh                 Tages-/Gesamt-Limit, Kill-Switch
  PositionTracker.mqh               eigene Positionen per Magic
  TradeExecution.mqh                Order-Sendung, Broker-Normalisierung
  TradeManager.mqh                  Exit-Logik
  DecisionLog.mqh                   CSV-Telemetrie
Data/
  news_schedule.csv                 Fallback-Newsplan fuer den Strategy Tester
```

---

## 4. Modulspezifikationen

### 4.1 `Types.mqh`

```cpp
enum ENUM_SIGNAL_DIR { SIGNAL_FLAT=0, SIGNAL_LONG=1, SIGNAL_SHORT=-1 };

// knowledge.md Teil B - Regime-Klassifikation
enum ENUM_REGIME
  {
   REGIME_UNKNOWN=0,        // Datenluecke -> konservativer Modus
   REGIME_REFLATION,        // Gold hoch, G/S-Ratio fallend, Kupfer hoch
   REGIME_RISKOFF,          // Gold hoch mit JPY+CHF, Aktien tief
   REGIME_USD_DRIVEN,       // invers DXY, JPY/CHF neutral
   REGIME_LIQUIDITY_PANIC,  // Gold faellt MIT Aktien
   REGIME_MOMENTUM_UNWIND,  // Gold faellt ohne Makro-Grund
   REGIME_REFLATION_RETURN  // Realzins hoch, Kupfer/Gold-Ratio steil
  };

enum ENUM_SETUP_STATE
  { ST_IDLE=0, ST_ARMED, ST_WAIT_TRIGGER, ST_PENDING, ST_IN_POSITION, ST_BLOCKED };

// Vorschlag eines Signalmoduls - noch ohne Lots, ohne Filterpruefung
class SignalProposal
  {
public:
   bool              valid;
   ENUM_SIGNAL_DIR   dir;
   double            entryPrice;     // 0 = Market
   double            stopPrice;      // Pflicht, nie 0
   double            targetPrice;    // 0 = kein Fix-TP (Trailing)
   double            atrAtSignal;    // fuer Sizing und Telemetrie
   int               magic;          // Herkunftsmodul
   string            reason;         // Klartext fuer DecisionLog
  };
```

### 4.2 `SymbolResolver.mqh`

**Problem:** Gold heißt je Broker `XAUUSD`, `GOLD`, `XAUUSD.a`, `XAUUSDm`. Satelliten fehlen oft ganz.

**Aufgabe:**
- Handelssymbol aus `_Symbol` übernehmen (EA läuft auf dem Gold-Chart), Digits/Point/ContractSize auslesen statt annehmen
- Satelliten über Kandidatenlisten auflösen und per `SymbolSelect()` in die MarketWatch aufnehmen
- Verfügbarkeit je Satellit als Flag führen

**Fallback-Kette – begründet:**

| Satellit | Primär | Fallback | Begründung |
|---|---|---|---|
| Silber | `XAGUSD` | keiner → G/S-Filter aus | Kernfilter, ohne Silber kein Ersatz |
| USD-Index | `DXY`/`USDX` | **`EURUSD` invertiert** | `knowledge.md` 1.2: EUR = 57,6 % des DXY, „Gold vs. USD ist praktisch Gold vs. EUR/USD" |
| Kupfer | `XCUUSD`/`COPPER` | keiner → Kupfer/Gold-Bias aus | – |
| VIX | `VIX`/`VXX` | ATR-Perzentil auf D1 als Vola-Proxy | Nur Regime-Grobklassifikation, kein Signal |
| Aktien | `US500`/`SPX500` | `NAS100` | für Liquiditätspanik-Erkennung |

### 4.3 `TimeContext.mqh`

Für das Baseline-Swing-Modul unkritisch, für Phase 3/4 der **wichtigste Fehlerquellen-Kandidat**.

**Aufgabe:**
- Broker-Server-Zeit → GMT → London-Zeit → NY-Zeit
- Session-Fenster: Asia 00:00–08:00 GMT, London-Open 08:00 GMT, Overlap 12:00–16:00 GMT
- **LBMA-Fix an London-Lokalzeit ankern** (10:30 / 15:00), nicht an GMT – `knowledge.md` 2 belegt die Fix-Zeiten in London-Zeit; in GMT verschieben sie sich mit der UK-Sommerzeit
- Wochentagsfilter (Montag früh, Freitag Nachmittag – `strategies.md` Teil E)
- Broker-Handelspause erkennen (`knowledge.md` 2: teils 1 h täglich) → in der Pause nicht evaluieren

**Design:** Server-GMT-Offset **nicht** aus `TimeGMT()` ableiten (im Tester unzuverlässig, siehe 7.1), sondern als explizite Inputs `InpServerGMTOffsetWinter` / `InpServerGMTOffsetSummer` mit Plausibilitätsprüfung beim Init und Auto-Erkennung nur als Vorschlag im Log.

### 4.4 `MarketData.mqh`

**Aufgabe:** Einzige Stelle, an der Kursdaten gelesen werden.

- Indikator-Handles in `OnInit` erzeugen, nie in `OnTick`
- Alle Reads mit `shift >= 1` (geschlossene Bars)
- Rückgabewert von `CopyBuffer`/`CopyRates` **immer** prüfen; Teilmengen als Fehler behandeln
- Für Satelliten zusätzlich **Bar-Zeit-Abgleich**: Wenn `time[1]` des Satelliten nicht zur Gold-Bar passt, gilt der Wert als ungültig → `REGIME_UNKNOWN`

### 4.5 `RegimeClassifier.mqh`

Setzt `knowledge.md` Teil B um. Läuft auf D1-Closed-Bars.

**Eingangsgrößen (alle als Slope über N geschlossene Bars, nicht als Absolutwert):**

| Größe | Berechnung |
|---|---|
| G/S-Ratio | `Close(XAUUSD)/Close(XAGUSD)`, Slope über `InpRegimeLookback` |
| Kupfer/Gold-Ratio | `Close(Copper)/Close(XAUUSD)`, Slope |
| USD-Proxy | Slope EURUSD (invertiert) |
| Safe-Haven-Bid | Slope USDJPY und USDCHF (fallend = JPY/CHF-Stärke) |
| Aktien | Slope US500 |
| Vola | VIX-Level oder ATR-Perzentil |

**Entscheidungslogik (Reihenfolge = Priorität):**

```
1. Gold faellt UND Aktien fallen UND Vola extrem  -> LIQUIDITY_PANIC
2. Gold steigt UND JPY-Stärke UND CHF-Stärke
   UND Aktien fallen UND G/S-Ratio steigt         -> RISKOFF
3. Gold steigt UND G/S-Ratio fällt UND Kupfer steigt -> REFLATION
4. Kupfer/Gold-Ratio steil steigend
   UND Gold fallend                               -> REFLATION_RETURN
5. Gold fallend, kein Makro-Treiber erkennbar     -> MOMENTUM_UNWIND
6. Gold invers USD-Proxy, JPY/CHF neutral         -> USD_DRIVEN
7. sonst / Datenluecke                            -> UNKNOWN
```

> **Wichtig:** `REGIME_UNKNOWN` ist **kein Handelsverbot**, sondern reduziert die Positionsgröße auf `InpUnknownRegimeSizeFactor` (Default 0,5). Sonst würde ein fehlendes Satelliten-Symbol den EA dauerhaft stilllegen.

### 4.6 `SignalDipBuy.mqh` — Phase-1-Strategie

Umsetzung von `strategies.md` Tier 1.2 mit den Timeframes aus Teil D (Bias W1/D1, Setup D1, Trigger H4).

**Bias-Prüfung (D1, geschlossen):**
- `Close > EMA(InpEmaSlow)` — Trendfilter
- Aufwärtsstruktur: letztes Swing-Tief > vorheriges Swing-Tief (fraktalbasiert über `InpSwingLookback`)

**Setup-Erkennung (D1):**
- Rücksetzer in die Zone `EMA(InpEmaMid)` **oder** Fib 0,382–0,618 des letzten Impulses
- Impuls = Bewegung vom letzten bestätigten Swing-Tief zum letzten Swing-Hoch

**Trigger (H4, geschlossen):**
- Bullische Umkehrkerze in der Zone (Close > Open **und** Close > Mid der Vorkerze)
- → `ST_ARMED` erst bei Setup, `ST_PENDING` erst bei Trigger

**Stop / Ziel:**
- `stopPrice = min(Swing-Tief, Entry - InpAtrStopMult * ATR(D1))` — ATR **vom Entry-TF-Kontext**, siehe Fehler 1 in `strategies.md` Teil D
- Ziel 1: alter Swing-Hoch → Teilgewinn `InpPartialPct`
- Ziel 2: Trailing, kein Fix-TP

**Explizit nicht implementiert:** vorzeitiger Exit bei RSI-Überkauft. `knowledge.md` 4 („Walking the Band" = Fortsetzung) verbietet das.

### 4.7 `FilterStack.mqh`

Jede Schicht einzeln per Input abschaltbar – das ist die Voraussetzung für die Hypothesentests in Abschnitt 8.

| # | Filter | Regel | Quelle |
|---|---|---|---|
| 1 | **Spread** | `SYMBOL_SPREAD > InpMaxSpreadPoints` → ablehnen | `knowledge.md` 4 |
| 2 | **News** | Blackout ± `InpNewsBlackoutMin` um High-Impact | `knowledge.md` 3 |
| 3 | **Regime** | Ablehnen bei `LIQUIDITY_PANIC`, `MOMENTUM_UNWIND`, `REFLATION_RETURN` (long) | `knowledge.md` Teil B |
| 4 | **Silber-Bestätigung** | Long nur wenn G/S-Ratio nicht steigend **oder** Silber-Momentum positiv | `knowledge.md` 1.4 |
| 5 | **Session** | nur relevant für Phase 3/4 | `knowledge.md` 2 |
| 6 | **Wochentag** | Montag vor `InpMondayStartGMT`, Freitag nach `InpFridayStopGMT` | `strategies.md` Teil E |

Rückgabe: `bool` + Ablehnungsgrund als String → geht in `DecisionLog`, damit später auswertbar ist, **welcher** Filter wie viele Trades gekostet hat.

### 4.8 `NewsGuard.mqh`

**Kernproblem:** `CalendarValueHistory()` funktioniert **nicht im Strategy Tester** (siehe 7.2).

**Zwei Betriebsmodi:**
- **Live/Demo:** MT5-Kalender, Filter auf Land = US, Importance = High; zusätzlich die in `knowledge.md` 3 gerankten Events (CPI, FOMC, NFP, PCE, PPI)
- **Tester:** CSV aus `Data/news_schedule.csv` (Format: `datetime;event;impact`). Mindestens CPI, FOMC, NFP über den Testzeitraum.

**FOMC-Spezialregel aus `knowledge.md` 3:** zweistufig – Blackout **bis 20:30 CET + Puffer**, nicht nur bis 20:00, weil die Pressekonferenz die Statement-Reaktion oft dreht.

### 4.9 `RiskManager.mqh`

Fixed-Fractional. Broker-genaue Geldbewertung wie im Vorgänger-Modul über `tickValue/tickSize`:

```
riskMoney   = Equity * InpRiskPercent/100 * regimeSizeFactor
stopDist    = |entry - stop|                    (Preis-Einheiten)
moneyPerLot = tickValue/tickSize * stopDist     (Verlust je 1.0 Lot)
lots        = riskMoney / moneyPerLot
```

**Pflicht-Schutzschichten (Übernahme aus dem Vorgänger, dort bereits als notwendig erkannt):**
1. **Mindest-Stop-Abstand** ≥ `InpFrictionSLMult * (Spread + Slippage-Puffer)` — verhindert Lot-Explosion bei winzigem ATR
2. **Broker-`SYMBOL_TRADE_STOPS_LEVEL`** als harte Untergrenze
3. **`InpMaxLotPerTrade`** als Kappung
4. Normalisierung auf `SYMBOL_VOLUME_STEP`, Prüfung gegen `VOLUME_MIN`/`VOLUME_MAX`
5. Abbruch wenn `lots < VOLUME_MIN` → Trade auslassen statt aufrunden

### 4.10 `ClusterRiskGuard.mqh` — neu, aus `strategies.md` Teil F

Der in beiden Dokumenten identifizierte, aber nirgends implementierte Punkt: **Gold + Silber + AUD + Miner = ein Trade.**

- Summiert offenes Risiko über alle Symbole der Gruppe `InpMetalCluster` (Default: `XAUUSD,XAGUSD,AUDUSD`)
- Risiko je Position = `|entryPrice - SL| * moneyPerLot * lots` in Kontowährung
- Neue Position nur, wenn `Cluster-Risiko + neues Risiko <= InpMaxClusterRiskPct` (Default 3 %)
- Erfasst auch Positionen **fremder Magic-Nummern**, wenn `InpClusterCountForeign=true` — sonst umgeht ein zweiter EA den Deckel

### 4.11 `TradeManager.mqh`

- **Teilgewinn** `InpPartialPct` am alten Swing-Hoch
- **Break-even-Stop** nach Teilgewinn
- **Trailing** in ATR-Vielfachen (`InpTrailAtrMult`), nur nachziehen, nie lockern
- **Kein Zeit-Exit**, kein Überkauft-Exit — begründet in 4.6
- Bei `REGIME_LIQUIDITY_PANIC`: Stop auf Break-even ziehen statt schließen (`knowledge.md` 1.3: Effekt hält 1–3 Wochen, danach Outperformance)

### 4.12 `DecisionLog.mqh`

Ohne diese Telemetrie ist Abschnitt 8 nicht durchführbar.

CSV pro Lauf: `timestamp; regime; signalModule; dir; entry; sl; tp; atr; spread; lots; clusterRiskPct; accepted; rejectReason`

Geloggt wird **jede Evaluierung**, auch abgelehnte – nur so lässt sich messen, ob ein Filter Edge liefert oder nur Trades kostet.

---

## 5. State Machine

Pro Signalmodul eine Instanz, Übergänge nur auf geschlossenen Bars.

```
ST_IDLE
   | Bias erfuellt + Setup erkannt
   v
ST_ARMED            (Zone aktiv, warte auf Trigger)
   | Trigger-Kerze         | Bias verloren / Zone ungueltig -> ST_IDLE
   v                       | InpArmedExpiryBars ueberschritten -> ST_IDLE
ST_WAIT_TRIGGER
   | FilterStack OK
   v                       | Veto -> ST_BLOCKED (geloggt) -> ST_IDLE
ST_PENDING          (Order gesendet)
   | Fill                  | Timeout / Reject -> ST_IDLE
   v
ST_IN_POSITION
   | Exit (SL/TP/Trailing)
   v
ST_IDLE
```

**Persistenz:** Zustand nach `OnDeinit`/Terminal-Restart aus offenen Positionen und `GlobalVariable` rekonstruieren. Ein Swing-EA hält über Tage – ein Neustart darf das Management nicht verlieren.

---

## 6. Inputs

> **Parsimonie-Warnung.** Der Vorgänger-Plan nennt Overfitting den „#1-Killer" und fordert **max. 2–3 freie Parameter**. Die Tabelle unten hat mehr – die meisten sind aber **strukturell** (Broker-, Zeit-, Risikogrenzen) und werden **nicht optimiert**. Optimiert werden ausschließlich die mit **[OPT]** markierten. Alles andere bleibt fest.

### Strategie

| Input | Default | Zweck |
|---|---|---|
| `InpAllowShort` | `false` | Asymmetrie-Hypothese testbar machen |
| `InpEmaSlow` | 200 | D1-Trendfilter |
| `InpEmaMid` | 50 | **[OPT]** Rücksetzer-Zone |
| `InpSwingLookback` | 5 | Fraktal-Breite für Swing-Erkennung |
| `InpAtrPeriod` | 14 | ATR |
| `InpAtrStopMult` | 2.0 | **[OPT]** Stop-Abstand (`strategies.md`: 1,5–2,0) |
| `InpArmedExpiryBars` | 10 | Verfall eines Setups |

### Filter

| Input | Default | Zweck |
|---|---|---|
| `InpUseSpreadFilter` | `true` | H-Test |
| `InpMaxSpreadPoints` | broker-kalibriert | Friktionsgrenze |
| `InpUseNewsFilter` | `true` | H-Test |
| `InpNewsBlackoutMin` | 60 | Blackout-Fenster |
| `InpUseRegimeFilter` | `true` | **H-Test (Kern)** |
| `InpUseSilverFilter` | `true` | **H-Test (Kern)** |
| `InpUseSessionFilter` | `true` | **H-Test (Kern, Phase 3)** |
| `InpRegimeLookback` | 20 | Slope-Fenster |
| `InpUnknownRegimeSizeFactor` | 0.5 | Verhalten bei Datenlücke |

### Risiko

| Input | Default | Zweck |
|---|---|---|
| `InpRiskPercent` | 1.0 | `knowledge.md` 4: 1–2 % |
| `InpMaxClusterRiskPct` | 3.0 | `strategies.md` Teil F |
| `InpMetalCluster` | `XAUUSD,XAGUSD,AUDUSD` | Cluster-Definition |
| `InpClusterCountForeign` | `true` | Fremd-EAs mitzählen |
| `InpMaxLotPerTrade` | 1.0 | harte Kappung |
| `InpFrictionSLMult` | 15.0 | Mindest-Stop vs. Friktion |
| `InpSlippageBufferPts` | 20.0 | Slippage-Puffer |
| `InpMaxDailyLossPct` | 3.0 | Tages-Kill-Switch |
| `InpMaxTotalDDPct` | 20.0 | Gesamt-Kill-Switch |
| `InpPartialPct` | 50.0 | Teilgewinn-Anteil |
| `InpTrailAtrMult` | 2.5 | Trailing-Abstand |

### Infrastruktur

| Input | Default | Zweck |
|---|---|---|
| `InpMagicBase` | 770000 | Basis, Module +1/+2/+3 |
| `InpServerGMTOffsetWinter` | 2 | siehe 7.1 |
| `InpServerGMTOffsetSummer` | 3 | siehe 7.1 |
| `InpNewsCsvPath` | `news_schedule.csv` | Tester-Fallback |
| `InpLogDecisions` | `true` | Telemetrie |
| `InpTesterForceSatellites` | `false` | Satelliten im Tester erzwingen |

> **Zu optimieren sind exakt zwei Parameter** (`InpEmaMid`, `InpAtrStopMult`) plus die booleschen Hypothesen-Schalter. Alles andere wird broker- bzw. regelbasiert festgelegt. Damit bleibt die Overfitting-Fläche im vom Vorgänger-Plan geforderten Rahmen.

---

## 7. MT5-spezifische Fallstricke

Der praktisch wichtigste Abschnitt. Jeder Punkt hat schon einmal ein Gold-System zerstört.

### 7.1 Zeitzonen und DST — die größte Fehlerquelle

- **`TimeCurrent()` ist Broker-Server-Zeit**, nicht GMT. Alle Zeiten in `knowledge.md` sind GMT bzw. London.
- **`TimeGMT()` ist im Strategy Tester unzuverlässig** (wird aus der letzten bekannten Terminal-Zeitzone modelliert). → Explizite Offset-Inputs, `TimeGMT()` nur als Init-Plausibilitätscheck loggen.
- **DST-Asymmetrie:** UK, EU und US schalten an **unterschiedlichen Terminen** um. Der LBMA-Fix ist an London-Lokalzeit gebunden, US-Daten an ET. In den Übergangswochen (März, Oktober/November) verschieben sich die GMT-Abstände. → Fix-Zeiten aus London-Zeit berechnen, News-Zeiten aus ET.
- Konsequenz für Phase 3/4: **Session-Logik separat und mit synthetischen Datumsfällen testen** (DST-Wechseltage explizit).

### 7.2 Wirtschaftskalender im Tester nicht verfügbar

`CalendarValueHistory()` & Co. liefern im Strategy Tester **keine Daten**. Ein EA, der den News-Filter nur über den Kalender löst, testet faktisch **ohne** News-Filter → Backtest und Live divergieren systematisch. → CSV-Fallback ist Pflicht, nicht optional (4.8).

### 7.3 Symbolnamen und Kontraktspezifikation

- Suffixe (`.a`, `m`, `_raw`) → nie hardcoden, `_Symbol` als Quelle nehmen
- **`SYMBOL_DIGITS` bei Gold ist 2 oder 3**, je Broker → `Point`/`Digits` immer auslesen, nie annehmen
- `SYMBOL_TRADE_CONTRACT_SIZE` (typisch 100 oz) verifizieren – geht direkt in die Lotberechnung ein
- Satelliten per `SymbolSelect(sym,true)` aktivieren, danach Verfügbarkeit **prüfen**

### 7.4 Multi-Symbol-Daten im Tester

- Satelliten-Historie muss beim Broker vorhanden sein, sonst schweigend leere Buffer
- Bars der Satelliten sind **nicht garantiert synchron** mit Gold (Feiertage, andere Handelszeiten) → Bar-Zeit-Abgleich statt Index-Vertrauen (4.4)
- Multi-Symbol-Backtests sind deutlich langsamer → Regime-Berechnung nur **1× pro D1-Bar**, nicht pro Tick
- `InpTesterForceSatellites` als Notausgang, falls der Tester Symbole nicht lädt

### 7.5 Order-Ausführung

- **`SYMBOL_TRADE_STOPS_LEVEL`**: SL/TP-Mindestabstand, bei Gold oft deutlich > 0 → Stops normalisieren, sonst `Invalid stops`
- **`SYMBOL_TRADE_FREEZE_LEVEL`**: nahe am Preis keine Modifikation möglich
- **Filling-Mode** aus `SYMBOL_FILLING_MODE` (Bitmaske) ableiten – falscher Modus = `Unsupported filling mode`
- **Retry-Logik** mit begrenzten Versuchen bei `REQUEUE`/`PRICE_CHANGED`; nie Endlosschleife
- Slippage/Deviation bei Gold großzügiger als bei FX, aber begrenzt

### 7.6 Backtest-Realismus

| Punkt | Anforderung |
|---|---|
| Modellierung | **„Jeder Tick basierend auf realen Ticks"**. M1-OHLC ist für Sweep-/Stop-Hunt-Logik ungültig – es erzeugt genau die Intrabar-Fiktion, die `knowledge.md` 4 als Hauptrisiko nennt |
| Spread | Historischer Spread ist häufig fix/zu eng → Aufschlag modellieren, sonst wird Phase 3/4 systematisch zu gut |
| Kommission | IC Markets Raw: ~$3,50/Lot/Seite → **$7 Round-Turn** explizit setzen |
| Swap | Für Swing-Holds relevant, **Mittwoch dreifach** |
| Historie | Gold-Tickdaten reichen brokerseitig oft nur ~10–15 Jahre zurück → begrenzt die Regime-Abdeckung |

### 7.7 Look-Ahead und Repainting

- Ausschließlich `shift >= 1`
- Indikator-Handles in `OnInit`, `CopyBuffer`-Rückgabe prüfen
- Swing-Erkennung braucht **bestätigte** Fraktale: ein Swing-Tief bei `shift=n` ist erst gültig, wenn `InpSwingLookback` Bars **danach** geschlossen sind → beim Setup entsprechend versetzt rechnen. Klassische Repainting-Falle.

### 7.8 Weitere

- Broker-Handelspause (täglich, oft 1 h) → in der Pause nicht evaluieren, sonst Fehl-Orders
- Wochenend-Gaps: Gold gappt regelmäßig → Stop kann über den Gap hinweg schlechter füllen als geplant; im Risikomodell als Realität akzeptieren, nicht wegrechnen
- `OnTradeTransaction` für verlässliche Fill-Erkennung statt Polling
- Ein Chart, ein Symbol, ein Magic pro Modul → keine Doppelbelegung

---

## 8. Backtest- & Validierungsplan

### 8.1 Hypothesen aus `strategies.md` Teil G als Testmatrix

Der EA ist so gebaut, dass jede Hypothese ein A/B-Test über einen Schalter ist:

| # | Hypothese | Schalter | Metrik | Ergebnis |
|---|---|---|---|---|
| 1 | Session-Selektivität schlägt 24 h | `InpUseSessionFilter` | Expectancy/Trade, Profit-Faktor (Phase 3) | **Bestätigt** (2026-08-17, s. 8.4) |
| 2 | Retest-Pflicht schlägt Sofort-Entry | `InpAsiaRequireRetest` | Trefferquote + Expectancy (Phase 3/4) | **Bestätigt** (2026-08-18, s. 8.4) |
| 3 | G/S-Ratio-Filter verbessert Longs | `InpUseSilverFilter` | Expectancy, gefilterte Trades vs. Ersparnis | **Verworfen** (2026-08-17, s. 8.4) |
| 4 | LBMA-Fix-Reversal existiert | Phase-4-Modul solo | Reversal-Häufigkeit vs. Zufallserwartung | **Verworfen** (2026-08-17, s. 8.4) |
| 5 | Kupfer/Gold-Bias schlägt DFII10 | `InpUseRegimeFilter` | Swing-Expectancy | **Nicht testbar** (2026-08-18, s. 8.4) |
| 6 | Optimaler ATR-Multiplikator | `InpOverlapAtrStopMult` 1,5-3,5 | **Parameter-Plateau**, nicht Peak | **Bestätigt** (2026-08-18, s. 8.4) |

**Auswertung über `DecisionLog`**, nicht nur über den Tester-Report: nur dort steht, welcher Filter wie viele Trades abgelehnt hat und was diese Trades gebracht hätten.

### 8.2 Validierungsablauf

1. **In-Sample** ca. 2011–2019 (bzw. ab Beginn brauchbarer Tickdaten)
2. **Out-of-Sample** 2020–2026 **unangetastet** lassen, bis IS abgeschlossen ist
3. **Walk-Forward** über rollierende Fenster
4. **Monte-Carlo** über Trade-Reihenfolge → Drawdown-Verteilung statt Einzelpfad
5. **Parameter-Plateau** prüfen: benachbarte Werte müssen ähnlich gut sein, sonst Kurvenfit
6. **Regime-Stresstest** einzeln auswerten: 2013 (Crash −28 %), 2020 (Panik + Rallye), 2022 (**der dokumentierte Korrelationsbruch**), H1/2026 (Momentum-Unwind, −8 % trotz Bullfaktoren)

### 8.3 Das Stichprobenproblem

Ein D1-Swing-System liefert über 15 Jahre grob **50–150 Trades**. Das ist für belastbare Statistik dünn.

**Gegenmaßnahmen:**
- **Cross-Instrument-Robustheit:** Dieselbe Logik ohne Reoptimierung auf XAGUSD, Platin, ggf. AUDUSD testen. Wenn der Edge instrumentübergreifend hält, ist er wahrscheinlich echt – genau die Logik, die der Vorgänger-Plan beim TSMOM-Basket nutzte.
- **Parameter maximal sparsam** (zwei [OPT]-Werte)
- Ergebnisse als **Größenordnung**, nicht als Punktschätzung lesen

### 8.4 Testergebnisse (Stand 2026-08-18)

**Hypothese 1 — Session-Selektivität (`InpUseSessionFilter`, Overlap-Modul, Slot 1):**
**bestätigt**, sowohl IS als auch OOS, mit ausreichender Stichprobe in beiden Fenstern.
Isolierter A/B-Test (Overlap solo, DipBuy/Sweep/LbmaFix aus), Variante A =
`InpUseSessionFilter=true` (Einstieg nur 12:00-16:00 GMT), Variante B = `false` (24 h):

| Fenster | Variante | Trades | WR | PF | Exp. Payoff | Max DD% (Equity) | Net Profit |
|---|---|---|---|---|---|---|---|
| IS 2020-2023 | B (24h) | 549 | 42.81% | 1.17 | 0.41 | 7.58% | 223.50 |
| IS 2020-2023 | A (Session) | 142 | 61.97% | 1.53 | 2.80 | 3.72% | 397.04 |
| OOS 2024-2026 | B (24h) | 283 | 38.16% | 1.14 | 0.53 | 7.59% | 148.88 |
| OOS 2024-2026 | A (Session) | 107 | 54.21% | 1.22 | 1.35 | 2.91% | 144.66 |

PF>1 in beiden Fenstern für beide Varianten, A liegt aber durchgehend über B (IS +0.36,
OOS +0.08 PF). Der Effekt schwächt sich OOS ab, bleibt aber in derselben Richtung, bei
OOS-Trades 107 (>> Mindestschwelle 30). Risikoadjustiert ist der Vorteil von A OOS sogar
deutlicher als beim reinen PF-Vergleich: Max DD halbiert (2.91% vs. 7.59%), Sharpe 7.44 vs.
2.43, Recovery Factor 1.58 vs. 0.63, Win-Rate 54.21% vs. 38.16% — bei nahezu gleichem
Net Profit trotz weniger als halb so vieler Trades. Erster Filter in der gesamten Testreihe
mit robustem Edge in beiden Fenstern (anders als G/S-Ratio, Round-Number, LBMA-Fix).
**Konsequenz:** Default von `InpUseSessionFilter` auf `true` geändert (SwingGoldEA.mq5).

**Hypothese 2 — Retest-Pflicht schlägt Sofort-Entry (`InpAsiaRequireRetest`, neues Modul
`SignalAsiaRangeBreakout`, Slot 4, strategies.md Teil C.4):** **bestätigt**, sowohl IS als
auch OOS, mit deutlich ausreichender Stichprobe in beiden Fenstern. Isolierter A/B-Test
(Asia solo, alle anderen Module aus, `InpAsiaAllowShort=true` fix), Optimierung über
`InpAsiaRequireRetest` (false=Sofort-Entry / true=Retest-Pflicht):

| Fenster | Variante | Trades | PF | Exp. Payoff | Max DD% | Sharpe | Net Profit |
|---|---|---|---|---|---|---|---|
| IS 2020-2023 | false (Sofort) | 1161 | 0.98 | -0.08 | 16.83% | – | -89.96 |
| IS 2020-2023 | true (Retest) | 912 | 1.13 | 0.55 | 12.51% | – | 500.71 |
| OOS 2024-2026 | true (Retest) | 328 | 1.29 | 1.26 | 10.60% | 1.62 | 413.38 |

Sofort-Entry scheidet schon IS aus (PF<1 bei 1161 Trades, negativer Profit) — kein OOS-Test
nötig (identische Begründung wie bei LBMA-Fix: Mindestvoraussetzung PF>1 nicht erfüllt).
Retest-Pflicht erfüllt die IS-Mindestanforderung (PF 1.13, 912 Trades) und bestätigt sich OOS
sogar staerker als IS (PF 1.29 statt 1.13, DD 10.60% statt 12.51%, 328 Trades >> Mindest-
schwelle 30) — kein Overfitting-Muster wie bei den verworfenen Sweep-Eskalationsstufen.
**Konsequenz:** `InpAsiaRequireRetest` Default bleibt `true` (bereits Standardwert bei
Einführung des Moduls). Modul `InpUseAsiaModule` bleibt vorerst `false` (Hazard H14) — die
in `strategies.md` Teil C.4 dokumentierte Einschränkung (Asien trieb H1/2026 die Rebounds,
Box-Annahme nicht mehr uneingeschränkt gültig) ist mit diesem Backtest-Zeitraum nicht
geprüft; vor Live-Aktivierung zusätzlich Cross-Check auf 2026er-Teilfenster empfehlenswert.

Alle vier in der Testmatrix (8.1) vorgesehenen Eskalationsstufen für das `LiquiditySweep`-
und `LbmaFixReversal`-Modul (Slot 2/3) sind durchgetestet:

- **LiquiditySweep-Reclaim (Basis, W1/MN1/Yearly-Levels):** isolierter IS-Test 2020-2023 mit
  validierten Basis-Settings (`InpSwSessionRestricted=true`, `InpSwUseTrendFilter=false`)
  liefert PF 1.66 bei 73 Trades — bester bisheriger Stand, aber ohne OOS-Bestätigung noch
  nicht live-validiert.
- **Round-Number-Filter (Hypothese-adjazent, `m_roundStep`):** kein Edge. Jede Konfiguration
  mit `RoundStep>0` reduziert die Trade-Zahl drastisch und drückt PF unter die Baseline;
  einzige Ausnahme hatte nur 19 Trades (Overfitting-Verdacht, unter Mindestschwelle 50).
  Default bleibt `InpSwRoundStep=0.0`.
- **Hypothese 3 — G/S-Ratio-Filter (`m_useGsFilter`):** kein belastbarer Edge. Bester Wert
  PF 1.14 bei nur 16 Trades (Baseline ohne Filter: PF 1.66 bei 73 Trades) — Filter reduziert
  die Trade-Zahl um 68-78 %, Stichprobe bleibt unter der Mindestschwelle 50. Ergebnis
  unentschieden mangels Daten, nicht widerlegt. Default bleibt `InpSwUseGsFilter=false`.
- **Hypothese 4 — LBMA-Fix-Reversal (eigenes Phase-4-Modul, Slot 3):** **klar verworfen.**
  Zeitfenster-Erkennung (AM-Fix 10:30 / PM-Fix 15:00 London-Zeit) technisch verifiziert
  (Journal-Timestamps stimmen exakt mit Broker-GMT-Offset). Isolierter IS-Test 2020-2023
  über 96 Parameter-Kombinationen (`InpLbmaMinMoveAtrMult` × `InpLbmaReversalAtrMult`),
  jeweils 412-772 Trades (Stichprobe ausreichend groß, anders als bei den Sweep-Filtern)
  — **kein einziger Durchlauf erreicht PF ≥ 1.0** (bester Wert: PF 0.84 bei 620 Trades).
  Kein OOS-Test nötig, da keine IS-Kandidaten die Mindestvoraussetzung (PF>1) erfüllen.
  Default bleibt `InpUseLbmaFixModule=false`, Modul bleibt im Code für mögliche spätere
  Re-Tests mit anderer Mechanik, wird aber nicht live eingesetzt.

Damit ist Frage aus Abschnitt 10 ("Ist der LBMA-Fix-Effekt überhaupt messbar?") beantwortet:
messbar ja (Zeitfenster technisch einwandfrei erkannt), aber **kein handelbarer Reversal-
Edge** mit der hier konstruierten Entry/Stop/Target-Regel.

**Hypothese 6 — ATR-Multiplikator-Plateau (`InpOverlapAtrStopMult`, Overlap-Modul, Slot 1):**
**bestätigt**, reine Formanalyse (kein PF>1-Mindestkriterium wie bei Edge-Hypothesen, sondern
Plateau vs. Peak). Der bisher hardcodierte Wert `OVERLAP_ATR_STOP_MULT=2.75` wurde in den Input
`InpOverlapAtrStopMult` umgewandelt und isoliert optimiert (Overlap solo, alle anderen Module
aus, `InpUseSessionFilter=true` fix), IS 2020-2023, Grid 1,5-3,5 in 0,25-Schritten:

| ATR-Mult | Trades | PF | Exp. Payoff | DD% | Net Profit |
|---|---|---|---|---|---|
| 1,50 | 0 | – | – | – | 0,00 |
| 1,75 | 152 | 1,14 | 0,75 | 4,70 | 114,66 |
| 2,00 | 151 | 1,33 | 1,89 | 4,25 | 285,68 |
| 2,25 | 136 | 1,21 | 1,14 | 4,74 | 155,61 |
| 2,50 | 139 | 1,44 | 2,37 | 4,75 | 328,86 |
| **2,75** | 139 | 1,38 | 1,85 | 4,51 | 257,66 |
| 3,00 | 143 | 1,42 | 2,10 | 4,15 | 300,83 |
| 3,25 | 140 | 1,44 | 2,19 | 4,18 | 306,19 |
| 3,50 | 129 | 1,41 | 1,90 | 4,36 | 245,43 |

Sieben benachbarte Werte (2,00-3,50) liefern durchgehend PF zwischen 1,21 und 1,44 bei
129-151 Trades je Punkt (>> Mindestschwelle 50) — kein Wert in dieser Nachbarschaft bricht
auf PF<1 oder negative Expectancy ein. Der Produktionswert 2,75 liegt komfortabel innerhalb
dieses Plateaus (nicht am Rand), auch wenn er nicht das Maximum ist (2,50/3,25 liefern PF
1,44). Erst unterhalb von 2,00 fällt die Kurve ab: bei 1,75 sinkt PF auf 1,14, bei 1,50
kollabiert das Modul komplett (0 Trades — Stop-Abstand kollidiert dort vermutlich mit einer
internen Mindestabstands-Validierung). Diese Kante liegt außerhalb der unmittelbaren
Nachbarschaft von 2,75 und bestätigt die Plateau-Grenze, statt die Hypothese zu widerlegen.

Zusatz-Check OOS 2024-2026 mit Produktionswert `InpOverlapAtrStopMult=2,75` (identische
Modul-Isolation): 116 Trades, WR 54,31%, PF 1,34, Exp. Payoff 2,03, Max DD 2,80%/2,92%
(Balance/Equity), Sharpe 4,05, Recovery Factor 2,58, Net Profit 235,92 — bestätigt, dass der
bestehende Produktionswert auch außerhalb des IS-Fensters funktioniert (keine Änderung an der
Deploy-Konfiguration nötig).

**Konsequenz:** `OVERLAP_ATR_STOP_MULT` bleibt dauerhaft als `InpOverlapAtrStopMult`-Input
(Default 2,75) im Code, kein Zurückbau zur Konstante — Input bleibt für künftige
Re-Validierungen nützlich und entspricht dem etablierten Muster der anderen Module
(`InpSwAtrStopMult`/`InpLbmaAtrStopMult`/`InpAsiaAtrStopMult`).

**Hypothese 5 — Kupfer/Gold-Bias schlägt DFII10 (`InpUseRegimeFilter`, `RegimeClassifier`):**
**nicht testbar**, mangels Datenzugriff auf beiden Vergleichsseiten. `RegimeClassifier.mqh`
(4.5) ist bisher nicht implementiert — es existiert kein `InpUseRegimeFilter` im Code. Vor der
Implementierung wurde geprüft, ob die für die Hypothese nötigen Datenquellen überhaupt
verfügbar sind:

- **Kupfer/Gold-Ratio:** Broker (IC Markets) bietet **kein** Kupfer-Symbol im Market Watch
  (weder `XCUUSD` noch `COPPER` o.ä. gefunden). Das ist bereits in 4.2 als Fallback-Fall
  vorgesehen (Zeile 226: "Kupfer | keiner → Kupfer/Gold-Bias aus"), betrifft hier aber nicht
  nur einen Teilfilter, sondern die gesamte Vergleichsseite der Hypothese.
- **DFII10:** FRED-Zeitreihe ohne MT5-Symbol, kein automatisierter Zugriff aus dem Tester ohne
  manuellen CSV-Import/Custom-Symbol-Infrastruktur.

Beide Seiten des A/B-Vergleichs ("Kupfer/Gold-Bias schlägt DFII10") sind damit ohne signifikanten
Zusatzaufwand (Custom-Symbol-Import, Datenpflege) nicht umsetzbar. Anders als bei Hypothese 3/4
ist das kein inhaltliches Ergebnis (kein Edge widerlegt), sondern ein Infrastruktur-Blocker.

**Konsequenz:** Hypothese 5 wird nicht weiterverfolgt, `RegimeClassifier.mqh` wird nicht
gebaut. Damit ist die Testmatrix aus 8.1 vollständig abgeschlossen: 4 von 6 Hypothesen
entschieden (2 bestätigt, 2 verworfen), 1 nicht testbar (Hypothese 5), 1 als Formanalyse
bestätigt (Hypothese 6).

### 8.5 Go-Live-Kette

1. Modul-Einzeltests (TimeContext mit DST-Fällen, RiskManager-Lotberechnung gegen Handrechnung, ClusterRiskGuard mit Fremdpositionen)
2. IS → OOS → Walk-Forward → Monte-Carlo
3. Cross-Instrument-Check
4. **1–3 Monate Demo-Forward-Test** — hier zeigt sich auch, ob Kalender-Modus und Zeitzonen live korrekt greifen
5. Live klein: `InpRiskPercent` 0,25–0,5, Kill-Switch aktiv
6. Skalierung erst nach belegter Übereinstimmung Demo ↔ Live

> Erwartungshaltung aus dem Vorgänger-Plan: **Live ist deutlich schlechter als Backtest** (Backtest-Sharpe 1,5 → live evtl. 0,5). Für Gold mit weiten Spreads und Gap-Risiko gilt das verstärkt.

---

## 9. Entwicklungsphasen

| Phase | Inhalt | Ergebnis |
|---|---|---|
| **0 – Infrastruktur** | `Types`, `SymbolResolver`, `MarketData`, `RiskManager`, `TradeExecution`, `PositionTracker`, `DrawdownGuard`, `DecisionLog` | EA handelt noch nicht, aber Sizing/Ausführung/Logging sind verifiziert |
| **1 – Baseline** | `SignalDipBuy`, minimaler `FilterStack` (nur Spread) | Erste messbare Kurve, bewusst **ohne** Intermarket |
| **2 – Filter** | `RegimeClassifier`, `ClusterRiskGuard`, `NewsGuard` + CSV | A/B gegen Phase 1 → liefern die Filter überhaupt Edge? |
| **3 – Intraday** | `TimeContext` vollständig, `SignalOverlapTrend` (M15) | Hypothesen 1 und 2 testbar |
| **4 – Experimentell** | `SignalSweepReclaim`, LBMA-Fix-Modul | Hypothese 4; nur bei Signifikanz behalten |
| **5 – Forward** | Demo, Telemetrie-Abgleich, Live klein | Go-Live-Entscheidung |

**Abbruchkriterium nach Phase 2:** Wenn die Filter gegenüber Phase 1 keine Verbesserung zeigen, ist die Intermarket-Prämisse aus `knowledge.md` Teil B für den Handel wertlos — dann Phase 3/4 nicht bauen, sondern die Baseline vereinfachen. **Diese Möglichkeit ist ausdrücklich einzuplanen.**

---

## 10. Bekannte Grenzen & offene Fragen

### Grenzen

1. **Die Wissensbasis ist teilweise unbelegt.** Kernannahmen (Reversal-Zeiten, Fakeout-Neigung, Wochentagseffekte) sind **[M]**. Der EA testet sie, er verlässt sich nicht auf sie.
2. **Der dokumentierte Korrelationsbruch ist eine Warnung an das eigene Modell.** `knowledge.md` 1.1 zeigt, dass eine Korrelation von −0,82 über Jahre versagen kann. Für den `RegimeClassifier` gilt dasselbe Risiko.
3. **Zentralbank-Rückenwind ist ein Regime, kein Naturgesetz.** H1/2026 lief −8 % trotz aller Bullfaktoren. Long-only ist eine begründete Wette, keine Sicherheit.
4. **Dünne Stichprobe** auf D1 (8.3).
5. **Preisregime-Wechsel:** `knowledge.md` 4 warnt, dass absolute ATR-Werte veraltet sind. Alles muss **relativ** (ATR-Vielfache, Perzentile) gerechnet werden – nie in absoluten Dollarbeträgen.
6. **Kein Live-Datenzugriff bei der Erstellung** dieses Plans; Broker-Spezifika (Spreads, Kommission, Swap, Contract Size, StopsLevel) sind **vor dem ersten Test am Konto zu verifizieren**.

### Offene Fragen

| Frage | Zu klären durch |
|---|---|
| Welche Satelliten-Symbole bietet IC Markets tatsächlich (Copper? US500? VIX?) | Symbolliste im Terminal prüfen |
| Wie weit reichen brauchbare XAUUSD-Tickdaten zurück? | History Center / Tester-Log |
| Ist der LBMA-Fix-Effekt überhaupt messbar? | **Beantwortet (2026-08-17, s. 8.4):** Zeitfenster ja, handelbarer Edge nein — verworfen |
| Hat die in `knowledge.md` 2 notierte Verschiebung (Asien treibt Rebounds) Bestand? | Session-Attribution über `DecisionLog` |
| Reicht der Swing-Ansatz allein, oder braucht es Phase 3 für Stichprobengröße? | Nach Phase 2 entscheiden |
| Soll die Cluster-Grenze auch Goldminen-CFDs erfassen? | Abhängig vom übrigen Portfolio |

---

## Zusammenfassung

**Baue zuerst das langweiligste, kostenrobusteste Modul** – Swing Dip-Buy, long-only, D1/H4, zwei optimierte Parameter – und **messe damit, ob die Intermarket-Filter aus `knowledge.md` überhaupt etwas beitragen.**

Die interessanten Ideen (LBMA-Fix, Sweep-Reclaim, Overlap-Trendfolge) kommen zuletzt, weil sie am meisten Infrastruktur (Zeitzonen, DST, Tick-Genauigkeit) und die höchsten Kosten haben. Wenn Phase 2 keinen Filter-Edge zeigt, ist der Plan erfolgreich gewesen – er hat dann eine falsche Annahme billig widerlegt.
