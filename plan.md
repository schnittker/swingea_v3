# Trading-Strategie-Plan für MT5-EA (IC Markets Echtgeldkonto)

## Kurzfazit

Die beste Kombination aus **jahrzehntelang belegtem Edge** und **robuster EA-Umsetzbarkeit**:

**→ Volatilitäts-getargetetes Time-Series-Momentum (Trendfolge) auf dem Tages-Chart über einen kleinen diversifizierten Basket.**

Optional als zweites, experimentelles Modul: **London Opening-Range-Breakout** auf EURUSD/GBPUSD.

Ausdrücklich **nicht**: Martingale/Grid-EAs, Tick-Scalping, Stat-Arb (Edge weitgehend erodiert).

---

## 1. Strategien mit belegtem Langzeit-Edge (nach Evidenzstärke)

| Strategie | Edge & Beleg | Realistischer Sharpe (einzeln) |
|---|---|---|
| **Time-Series-Momentum (Trendfolge)** | Moskowitz/Ooi/Pedersen (JFE 2012): 58 Futures über ~25 Jahre, 12-Monats-Signal auf *jedem* Instrument profitabel. AQR "Century of Evidence" bis ~1880. Beste Evidenz. | 0,3–0,6 (Basket höher) |
| **Carry Trade** | Menkhoff et al. (JF 2012), Brunnermeier et al. UIP-Bruch. Aber: **starkes negatives Skew** → "Nickel vor der Dampfwalze", Crash-Risiko (2008, CHF 2015). | 0,6–0,9 (Basket) |
| **Volatility-Breakout / ORB** | Crabel (1990), London-Session-Breakout. Positives Skew (kleine Verluste, gelegentlich große Gewinne). Kostenempfindlich. | modest |
| **Mean Reversion** | Lehmann/Lo&MacKinlay. Auf FX-Majors schwach, negatives Skew (Tail-Risk). | schwach |
| **Stat-Arb / Pairs** | Gatev et al. (2006). Edge **weitgehend erodiert** seit ~2002, Multi-Symbol-Komplexität. | vermeiden |

---

## 2. EA-Umsetzbarkeit in MT5 (Ranking)

MT5-Realität: kein echtes HFT für Retail, `OnTick()` pro Symbol, Multi-Symbol möglich aber komplexer, guter Strategy-Tester mit Walk-Forward + Real-Tick.

1. **London-/ATR-Breakout** – Single-Symbol, session-gated, saubere Stops ✅
2. **Time-Series-Momentum (Daily)** – niedrige Frequenz → Latenz/Spread egal, minimale Overfitting-Fläche ✅✅
3. **Carry (Swap-Harvesting)** – mechanisch trivial, aber braucht Basket + Makro-Risiko-Overlay
4. Mean Reversion – einfach zu coden, Tail-Risk schwer beherrschbar
5. Cross-Sectional-Momentum / 6. Stat-Arb – Multi-Symbol, komplex

---

## 3. IC Markets spezifisch (Werte 2026 auf der Website verifizieren!)

- **Konto:** Raw-Spread MT5 (nicht Standard – dort ist Kommission im breiteren Spread versteckt)
- **Kommission:** ~$3,50/Lot/Seite → **$7 Round-Turn** pro Standard-Lot
- **Spreads (Majors):** EURUSD oft 0,0–0,3 Pips raw → effektiv ~0,7–1,0 Pip all-in
- **Ausführung:** ECN/STP, kein Dealing Desk, gut für Breakout/Momentum
- **Swaps:** täglich, Mittwoch dreifach (Carry-Mechanik)
- **Min. Lot:** 0,01 (Micro-Lots)
- **VPS:** bei Daily-Strategie unkritisch; bei Intraday VPS nahe Equinix NY4/LD5 sinnvoll

---

## 4. Ehrliche Warnung zu Erwartungen

- **Overfitting ist der #1-Killer** → max. 2–3 freie Parameter, Performance muss auf einem *Parameter-Plateau* stabil sein
- **Kosten fressen den Edge:** ~1 Pip Round-Turn all-in – jede Intraday-/Scalping-Idee stirbt hier oft
- **Live ist deutlich schlechter als Backtest** (Backtest-Sharpe 1,5 → live evtl. 0,5)
- **Pflicht-Validierung:** Out-of-Sample + Walk-Forward + Monte-Carlo + mehrere Regimes (2008/2015/2020/2022)
- Auf **geschlossenen Bars** handeln (kein Look-Ahead/Repainting)

---

## 5. Konkrete Empfehlung

### Primär: Daily Time-Series-Momentum, diversifizierter Basket
- **Signal:** täglicher Close, 252-Tage-Return-Vorzeichen (oder 100/200-MA-Cross als robuster Proxy)
- **Universum:** EURUSD, USDJPY, GBPUSD, AUDUSD, XAUUSD (+ evtl. Index-CFD)
- **Sizing:** Volatilitäts-Targeting (invers zur ATR), Ziel ~10–15 % p.a. Vol
- **Frequenz:** 1×/Tag → Latenz/Spread irrelevant
- **Erwartung:** Sharpe ~0,4–0,7, Drawdowns 20–30 %, lange Seitwärtsphasen – Wert = *Crisis-Alpha*

### Sekundär (optional): London-ORB auf EURUSD/GBPUSD
- Asian-Range (00:00–07:00 Server-Zeit) definieren
- bei London-Open Stop-Entry
- Stop 1×ATR(14), Ziel 1,5–2×ATR
- 1 Trade/Session, News-Filter

### Go-Live-Checkliste
1. EA auf geschlossenen Daily-Bars, Kosten modelliert
2. In-Sample ~2005–2018, Out-of-Sample 2019–2026 unangetastet, dann Walk-Forward + Monte-Carlo
3. Edge über mehrere Instrumente stabil?
4. 1–3 Monate Demo/Forward-Test bei IC Markets
5. Live klein starten (0,01–0,05 Lots, ≤0,5–1 % Risiko/Position, Drawdown-Kill-Switch)

---

## Quellen

- [AQR — "Time Series Momentum" (Moskowitz, Ooi, Pedersen, 2012)](https://www.aqr.com/Insights/Research/Journal-Article/Time-Series-Momentum)
- Asness/Moskowitz/Pedersen, "Value and Momentum Everywhere" (JF 2013)
- Hurst/Ooi/Pedersen, "A Century of Evidence on Trend-Following" (AQR)
- Menkhoff/Sarno/Schmeling/Schrimpf, "Carry Trades and Global FX Volatility" (JF 2012)
- Brunnermeier/Nagel/Pedersen, "Carry Trades and Currency Crashes" (NBER 2008)
- Jegadeesh & Titman (1993); Gatev/Goetzmann/Rouwenhorst (2006); Gao/Han/Li/Zhou (JFE 2018); Crabel (1990)

---

## Wichtiger Hinweis

Live-Websuche war bei der Erstellung eingeschränkt. Die akademischen Edges sind real, aber gegenüber ihren ursprünglichen Stichproben **erodiert** – alle Sharpe-Zahlen als optimistische Obergrenze behandeln. IC-Markets-Zahlen (Spreads/Kommission/Swaps) unbedingt auf der aktuellen Website prüfen, bevor echtes Geld eingesetzt wird.
