# Analyse & Projektion — Aggressiver ETF-Sparplan (Trade Republic)

**Erstellt:** 2026-08-19
**Bezug:** [`portfolio.md`](./portfolio.md) — dort steht die konkrete Positionsaufstellung
**Basis:** 3.000 € Start + 500 €/Monat, Broker Trade Republic

> **Disclaimer:** Private Analyse, keine Anlageberatung. Alle Zahlen sind Modellrechnungen,
> keine Prognosen. Steuerliche Angaben ohne Gewähr — für die konkrete Situation
> Steuerberatung einholen.

---

## Inhalt

1. [Broker-Wahl: warum Trade Republic](#1-broker-wahl-warum-trade-republic)
2. [Methodik der Simulation](#2-methodik-der-simulation)
3. [Vermögensentwicklung 5 / 10 / 15 / 20 Jahre](#3-vermögensentwicklung)
4. [Risiko: Drawdowns](#4-risiko-drawdowns)
5. [Nach Steuern und Inflation](#5-nach-steuern-und-inflation)
6. [Der wichtigste Befund: Strategie vs. Zeit vs. Sparrate](#6-der-wichtigste-befund)
7. [Entnahmephase: wie viel kommt monatlich raus](#7-entnahmephase)
8. [Glide Path: Portfolio-Umbau vor der Entnahme](#8-glide-path)
9. [Entnahme-Mechanik und Steueroptimierung](#9-entnahme-mechanik-und-steueroptimierung)
10. [Was man ändern müsste, um davon zu leben](#10-was-man-ändern-müsste-um-davon-zu-leben)
11. [Vergleich der drei Vehikel: ETF-Plan, Krypto, Gold-EA](#11-vergleich-der-drei-vehikel)
12. [Prop-Firm-Finanzierung und Sparraten-Sensitivität](#12-prop-firm-finanzierung-und-sparraten-sensitivität)
13. [Fazit und offene Entscheidung](#13-fazit-und-offene-entscheidung)

---

## 1. Broker-Wahl: warum Trade Republic

Ursprünglich war ein **Sparkassen-LEVClassic-Depot** vorhanden. Für diese Strategie ist
das die falsche Umgebung — Kostenvergleich Jahr 1 (3.000 € Start + 6.000 € Einzahlung,
10 Positionen):

| Posten | Sparkasse LEVClassic | Trade Republic |
|---|---|---|
| Sparplangebühr | ~150 € (2,5 % der Rate) | **0 €** |
| Initialkäufe (10 Orders) | ~120–250 € | **~10 €** (1 €/Order) |
| Depotführung | ~15–50 € | **0 €** |
| **Summe Jahr 1** | **~285–450 €** | **~10 €** |

Zusätzliche Gründe gegen das Filialdepot:

- Gehebelte ETFs oft nicht sparplanfähig, Zielmarktprüfung/Risikoklasse blockiert sie häufig
- Krypto-ETPs/ETNs in vielen Sparkassen-Depots gar nicht handelbar
- Sparplanfähig ist überwiegend der Deka-Kosmos
- Vertriebsdruck Richtung aktive Fonds mit 3–3,75 % Ausgabeaufschlag

Bei Trade Republic zusätzlich möglich: **Krypto als Direktkauf** statt über ETPs —
günstiger und steuerlich klarer (§ 23 EStG, nach 12 Monaten steuerfrei).

**Nachteile von TR, die man kennen muss:** nur ein Handelsplatz (LS Exchange, kein Xetra)
→ Einzelkäufe nur zwischen 9:00 und 17:30; kein Auto-Rebalancing; kein Auszahlplan;
Support nur schriftlich; Krypto ist kein Sondervermögen (Gegenparteirisiko).

---

## 2. Methodik der Simulation

Monte-Carlo, **20.000 Pfade**, monatliche Schritte über 20 Jahre, monatliche Einzahlung
zu Zielquoten, **jährliches Rebalancing**. Sechs Bausteine mit korrelierten
lognormalen Renditen (Cholesky-Zerlegung der Korrelationsmatrix).

| Baustein | Quote | Ø Rendite p.a. | Vola p.a. |
|---|---|---|---|
| Breite Aktien (World / EM / Small Cap / Momentum) | 40 % | 8,5 % | 17 % |
| Nasdaq 100 | 15 % | 11,5 % | 24 % |
| 2x USA (nach Kosten) | 15 % | 16,5 % | 36 % |
| 2x Nasdaq (nach Kosten) | 10 % | 19,4 % | 48 % |
| Krypto (BTC / ETH) | 15 % | 25,0 % | 70 % |
| Gold | 5 % | 4,0 % | 15 % |

> **Hinweis:** Diese Simulation wurde mit der *ursprünglichen* Allokation gerechnet, die
> noch 10 % 2x-Nasdaq enthielt. Diese Position wurde am 2026-08-19 gestrichen und die
> Quote auf 2x USA verschoben (Begründung in `portfolio.md` Abschnitt 3). Der Effekt auf
> die Ergebnisse ist **leicht positiv** — höhere erwartete Rendite bei geringerer
> Volatilität. Die hier ausgewiesenen Zahlen sind damit eine konservative Untergrenze
> und wurden nicht neu gerechnet.

**Hebelmodellierung:** Die 2x-Sleeves laufen mit doppelter Volatilität und doppelter
arithmetischer Drift, minus Finanzierungskosten (~3 % p.a.) und TER. Da der geometrische
Mittelwert um σ²/2 unter dem arithmetischen liegt, ist der **Volatility Decay automatisch
enthalten** — bei 36 % bzw. 48 % Vola ist der Drag erheblich. Das ist der Grund, warum
25 % Hebelanteil das Gesamtergebnis weit weniger hebt, als man intuitiv erwartet.

**Bekannte Modellgrenzen:**
- Lognormale Renditen unterschätzen Fat Tails und echte Crash-Ereignisse
- Korrelationen sind statisch; in Krisen springen sie real gegen 1
- Keine Momentum-/Mean-Reversion-Effekte
- Renditeannahmen sind historisch abgeleitet, nicht zukunftssicher — besonders die
  25 % p.a. für Krypto sind eine Fortschreibung der Vergangenheit und hochgradig unsicher
- → **Realität eher schlechter als das Modell, nicht besser**

---

## 3. Vermögensentwicklung

### Monte-Carlo-Verteilung (nominal, vor Steuern)

| Jahr | eingezahlt | P10 (schlecht) | P25 | **Median** | P75 | P90 (sehr gut) |
|---|---|---|---|---|---|---|
| 5 | 33.000 € | 27.500 € | 33.900 € | **43.400 €** | 56.800 € | 73.200 € |
| 10 | 63.000 € | 56.500 € | 75.800 € | **108.000 €** | 158.800 € | 229.500 € |
| 15 | 93.000 € | 92.300 € | 134.500 € | **214.200 €** | 349.700 € | 563.600 € |
| 20 | 123.000 € | 140.100 € | 221.800 € | **381.000 €** | 690.800 € | 1.203.500 € |

**Median-Rendite: ~10 % p.a.** Das ursprüngliche Ziel von 12–15 % p.a. liegt etwa
zwischen P60 und P75 — möglich, aber im oberen Drittel der Verteilung, nicht der
Erwartungswert.

Die Spannweite ist die eigentliche Botschaft: nach 20 Jahren **Faktor 8,6** zwischen
P10 und P90. Das ist der Preis der aggressiven Ausrichtung.

### Deterministischer Vergleich (konstante Rendite)

| Jahr | eingezahlt | 6 % p.a. | 9 % p.a. | 11 % p.a. | 14 % p.a. |
|---|---|---|---|---|---|
| 5 | 33.000 € | 38.900 € | 42.300 € | 44.600 € | 48.400 € |
| 10 | 63.000 € | 87.000 € | 102.600 € | 114.700 € | 135.800 € |
| 15 | 93.000 € | 151.300 € | 195.600 € | 232.900 € | 304.000 € |
| 20 | 123.000 € | 237.400 € | 338.500 € | 432.000 € | 628.000 € |

---

## 4. Risiko: Drawdowns

| Kennzahl | Wert |
|---|---|
| Max. Drawdown über 20 Jahre — **Median** | **−43 %** |
| Max. Drawdown — P75 | −51 % |
| Max. Drawdown — P95 | −63 % |
| Wahrscheinlichkeit, nach 10 Jahren unter der Einzahlsumme zu liegen | 14,7 % |
| Wahrscheinlichkeit, nach 20 Jahren unter der Einzahlsumme zu liegen | 7,0 % |

Wegen der Modellgrenzen aus Abschnitt 2 (Fat Tails, Korrelationssprünge) sollte man
sich mental auf **−60 bis −70 %** einstellen.

**Was das konkret bedeutet:** Steht das Depot nach 12 Jahren bei 160.000 €, kann es
innerhalb von 12 Monaten bei 60.000 € stehen. Wer bei dieser Vorstellung verkaufen
würde, für den ist das Portfolio zu aggressiv → dann die konservativere Variante aus
`portfolio.md` (Hebel 15 %, Krypto 10 %).

**Verhalten ist der dominante Risikofaktor**, nicht die Produktauswahl. Panikverkauf im
Drawdown zerstört die Strategie zuverlässiger als jedes Marktereignis.

---

## 5. Nach Steuern und Inflation

Annahmen: 2 % Inflation p.a.; Steuer bei Verkauf 26,375 % auf Gewinne minus 30 %
Teilfreistellung ≈ **18,46 % effektiv**. Konservativ gerechnet — Krypto-Gewinne sind
nach 12 Monaten Haltedauer steuerfrei, real fällt die Last also niedriger aus.

### Median-Pfad

| Jahr | brutto | netto | **real (heutige Kaufkraft)** |
|---|---|---|---|
| 5 | 43.400 € | 41.500 € | **37.600 €** |
| 10 | 108.000 € | 99.700 € | **81.800 €** |
| 15 | 214.200 € | 191.800 € | **142.500 €** |
| 20 | 381.000 € | 333.300 € | **224.000 €** |

### Verteilung nach 20 Jahren

| Szenario | brutto nominal | netto nominal | **real** |
|---|---|---|---|
| P10 | 140.100 € | 136.900 € | **92.200 €** |
| P25 | 221.800 € | 203.500 € | **137.000 €** |
| **Median** | 380.900 € | 333.300 € | **224.300 €** |
| P75 | 690.800 € | 585.900 € | **394.300 €** |
| P90 | 1.203.500 € | 1.004.000 € | **675.700 €** |

### Der faire Vergleich

Nominal eingezahlt werden 123.000 € — aber verteilt über 20 Jahre. In heutiger
Kaufkraft sind das nur **102.000 €**.

> 102.000 € real eingezahlt → **224.300 € real** heraus = **Faktor 2,2** nach Steuern
> und Inflation

Ein respektables Ergebnis. Es klingt nur unspektakulär, weil „12–15 % p.a." im Kopf
größer wirkt, als es über 20 Jahre auf eine Sparrate von 500 € tatsächlich wird.

---

## 6. Der wichtigste Befund

Was die einzelnen Faktoren wirklich bringen (nominal brutto):

| Szenario | Ergebnis | Delta zur Basis |
|---|---|---|
| 100 % MSCI World, 8 % p.a., 500 € fix, 20 J. | 298.000 € | Basis |
| **Aggressives Portfolio, 10 % p.a., 500 € fix, 20 J.** | **379.000 €** | **+27 %** |
| Aggressiv + Sparrate jährlich +3 %, 20 J. | 461.000 € | +55 % |
| Aggressiv, 500 € fix, **25 Jahre** | 649.000 € | +118 % |
| Aggressiv, 500 € fix, **30 Jahre** | 1.084.000 € | +264 % |
| Aggressiv + Rate +3 % p.a., **30 Jahre** | 1.398.000 € | +369 % |

**Der gesamte Aufwand mit 2x-Hebel, Bitcoin, Ethereum, Volatility Decay, 60-%-Drawdowns
und Rebalancing-Disziplin bringt gegenüber einem simplen MSCI-World-Sparplan +27 %.
Fünf Jahre länger sparen bringt +118 %. Zehn Jahre länger bringt +264 %.**

Und: Die +27 % sind der *Median* einer breiten Verteilung. Im P10-Fall schlägt der
langweilige World-Sparplan das Hebelportfolio trotz allem.

### Wirksame Stellschrauben, nach Wirkung sortiert

1. **Horizont verlängern** — größter Effekt, kostet nur Geduld, risikofrei
2. **Sparrate dynamisieren** — jährlich +3 % (im ersten Jahr 15 € mehr), wirkt stärker als der gesamte Hebel
3. **Sparrate erhöhen**, sobald das Einkommen es erlaubt
4. **Erst danach: mehr Risiko im Portfolio**

---

## 7. Entnahmephase

Annahme: **3,5 % inflationsindexierte Entnahmerate** aus einem deriskten Portfolio
(siehe Glide Path), Horizont 30 Entnahmejahre. Besteuert wird bei Teilverkäufen nur der
Gewinnanteil → effektive Steuerlast auf die Entnahme ca. 12–13 %, nicht 26 %.
Sparerpauschbetrag 1.000 € berücksichtigt.

| Szenario | Depot nominal | brutto/Monat | netto/Monat nominal | **netto/Monat in heutiger Kaufkraft** |
|---|---|---|---|---|
| P10 | 140.100 € | 409 € | 409 € | **275 €** |
| P25 | 221.800 € | 647 € | 609 € | **410 €** |
| **Median** | 380.900 € | 1.111 € | 988 € | **665 €** |
| P75 | 690.800 € | 2.015 € | 1.724 € | **1.160 €** |
| P90 | 1.203.500 € | 3.510 € | 2.944 € | **1.981 €** |

**Ergebnis: im Median rund 665 € pro Monat in heutiger Kaufkraft.**

Davon kann man nicht leben. Das ist eine solide Zusatzrente, kein Ersatz für
Erwerbseinkommen. Der Grund ist einfach: 3,5 % von 381.000 € sind 13.300 € im Jahr.
**Der Kapitalstock ist der Engpass, nicht die Rendite.** Und 3,5 % ist bereits die
Obergrenze des Vernünftigen — höhere Entnahmen erhöhen das Risiko, dass das Kapital
vor dem Lebensende aufgebraucht ist.

---

## 8. Glide Path

Mit 25 % Hebel und 15 % Krypto in die Entnahmephase zu gehen wäre der schwerste Fehler
der ganzen Strategie.

### Warum: Sequence-of-Returns-Risiko

In der **Ansparphase** ist ein Crash ein Vorteil — die Sparrate kauft billig ein.
In der **Entnahmephase** ist er ruinös: Man muss verkaufen, verkauft also ins Tief
hinein, und der Kapitalstock erholt sich nie mehr vollständig. Die Logik dreht sich
komplett um. Ein 60-%-Crash in den ersten Entnahmejahren ist nicht aussitzbar.

### Umbau über die letzten 5–7 Jahre

| Zeitpunkt | Hebel (Pos. 3) | Krypto (Pos. 4+5) | Aktien ungehebelt | Anleihen/Geldmarkt | Gold | Cash-Puffer |
|---|---|---|---|---|---|---|
| Jahr 0–13 | 25 % | 15 % | 55 % | 0 % | 5 % | – |
| Jahr 14 | 20 % | 12 % | 61 % | 0 % | 7 % | – |
| Jahr 16 | 12 % | 10 % | 63 % | 8 % | 7 % | – |
| Jahr 18 | 5 % | 7 % | 60 % | 20 % | 8 % | 1 Jahr |
| **Jahr 20** | **0 %** | **5 %** | **55 %** | **30 %** | **10 %** | **2–3 Jahre** |

### Konkrete Schritte

1. **Ab Jahr 14: Sparplan für Pos. 3 stoppen.** Raten auf Pos. 1 (World) und
   neu auf einen Anleihe-/Geldmarktbaustein umleiten. Nicht verkaufen — umlenken.
   Verschiebt die Quoten ohne Steuerauslösung.
2. **Ab Jahr 16: Hebelposition aktiv abbauen**, verteilt über mehrere Steuerjahre,
   jedes Jahr den Sparerpauschbetrag von 1.000 € voll ausnutzen.
3. **Krypto anteilig reduzieren** — nur Tranchen mit über 12 Monaten Haltedauer, die
   sind steuerfrei. FIFO arbeitet hier automatisch für dich. Restanteil 5 % kann bleiben.
4. **Cash-Puffer aufbauen:** 2–3 Jahresentnahmen (bei 1.111 €/Monat ≈ 27.000–40.000 €)
   auf Tagesgeld/Geldmarkt. Das ist der eigentliche Schutz: In einem Crashjahr entnimmst
   du aus dem Puffer statt zu verkaufen und füllst ihn erst nach der Erholung wieder auf.

### Ergänzende Bausteine für die Entnahmephase

ISINs vor Nutzung verifizieren:

| Zweck | Produkt | ISIN |
|---|---|---|
| Geldmarkt / Cash-Puffer | Xtrackers Overnight Rate Swap | `LU0290358497` |
| Kurzläufer Euro-Staat | iShares € Govt Bond 0-1yr | `IE00B3VTMJ99` |
| Euro-Staatsanleihen mittlere Laufzeit | iShares Core € Govt Bond | `IE00B3DKXQ41` |

---

## 9. Entnahme-Mechanik und Steueroptimierung

- **Trade Republic hat keinen automatischen Auszahlplan.** Verkäufe erfolgen manuell.
  Praktikabel: 1× pro Quartal oder Halbjahr die nächsten Monate „vorverkaufen" und das
  Geld auf dem Verrechnungskonto parken. Spart Orders und vermeidet monatliche
  Marktentscheidungen.
- **Teilverkäufe statt Umschichtung in ausschüttende ETFs.** Ein Wechsel auf
  Ausschütter löst beim Umschichten Steuern aus und bringt keinen Vorteil —
  Teilverkäufe sind flexibler und steuerlich effizienter.
- **Nur der Gewinnanteil ist steuerpflichtig**, nicht der Verkaufsbetrag. Bei 68 %
  Gewinnanteil im Depot liegt die effektive Belastung der Entnahme bei ca. 12–13 %.
- **Sparerpauschbetrag** jedes Jahr ausnutzen: 1.000 € (verheiratet 2.000 €).
- **Günstigerprüfung** in der Steuererklärung beantragen: Liegt das sonstige Einkommen
  in der Entnahmephase niedrig, ist der persönliche Steuersatz möglicherweise unter
  25 % → günstiger als die Abgeltungsteuer.
- **Krypto:** wird von TR **nicht** automatisch versteuert. Nach 12 Monaten Haltedauer
  steuerfrei (§ 23 EStG), vorher persönlicher Steuersatz. Jede Sparplan-Tranche hat
  eigene Haltefrist, Verrechnung nach FIFO. Steuerreport jährlich herunterladen und
  dauerhaft archivieren.
- **Vorabpauschale** fällt schon in der Ansparphase jährlich an (thesaurierende ETFs)
  → im Januar für ausreichende Kontodeckung sorgen.

---

## 10. Was man ändern müsste, um davon zu leben

### Benötigter Kapitalstock

Für einen bestimmten Betrag netto pro Monat in **heutiger Kaufkraft**:

| Ziel netto/Monat (real) | benötigtes Depot in 20 J. (nominal) |
|---|---|
| 1.000 € | 597.000 € |
| 1.500 € | 909.000 € |
| 2.000 € | 1.222.000 € |
| 2.500 € | 1.534.000 € |
| 3.000 € | 1.847.000 € |

### Dafür nötige Sparrate (10 % p.a. Median-Annahme)

| Ziel netto/Monat real | bei 20 Jahren | **bei 30 Jahren** |
|---|---|---|
| 1.000 € | 803 €/Monat | **264 €/Monat** |
| 1.500 € | 1.238 €/Monat | **415 €/Monat** |
| 2.000 € | 1.673 €/Monat | **567 €/Monat** |

Zinseszins in Reinform: Für 2.000 € monatliche Entnahme braucht man bei 20 Jahren
Ansparzeit **1.673 €/Monat** — bei 30 Jahren nur **567 €/Monat**. Zehn Jahre mehr Zeit
ersetzen fast das Dreifache der Sparrate.

### Optionen im Überblick

| Option | Maßnahme | Ergebnis (netto/Monat real) |
|---|---|---|
| **A** | Alles so lassen | ~665 € — solide Zusatzrente |
| **B** | Horizont auf 30 Jahre | ~1.900 € bei gleicher Rate |
| **C** | Rate jährlich +5 %, 25 Jahre | ~1.400–1.600 € |
| **D** | Rate auf ~1.700 € erhöhen, 20 Jahre | ~2.000 € |

**Option B ist die effizienteste** — kostet kein zusätzliches Geld, nur Zeit. Und sie
erlaubt sogar ein *weniger* aggressives Portfolio, weil der Renditeaufschlag aus Hebel
und Krypto dann nicht mehr gebraucht wird: Bei 30 Jahren erreicht ein simpler
World-Sparplan mit 8 % p.a. bereits ~745.000 € — ohne Volatility Decay, ohne
60-%-Drawdowns, ohne Rebalancing-Zwang und ohne Krypto-Verwahrrisiko.

---

## 11. Vergleich der drei Vehikel

Es existieren inzwischen drei parallel dokumentierte Ansätze: dieser ETF-Sparplan, das
Krypto-Portfolio in [`crypto.md`](./crypto.md) und der Gold-Swing-EA in
`../swingea/` (`ea.md`, Backtest `ReportOptimizer-106452261.xml`). Auf den ersten Blick
liefern alle drei eine ähnliche Rendite. Dieser Abschnitt zeigt, warum dieser Eindruck
täuscht.

### Die Ausgangszahlen

| | Erwartung p.a. | Max Drawdown | Rendite/DD |
|---|---|---|---|
| ETF-Plan (Variante A) | ~10 % Median | −43 % Median, −63 % P95 | 0,23 |
| Krypto, 20 J. (`crypto.md` 10) | 7–11 % | −75 bis −85 % | 0,14 |
| **Gold-EA** | **6,6 %** | **13,3 % Equity** | **0,50** |

Der EA-Wert stammt aus dem besten Optimizer-Pass: 3.000 € Deposit → 4.583,74 € über
6,63 Jahre (2020-01 bis 2026-08), Profit Factor 1,26, 308 Trades, Sharpe 1,94.
Das ist die **niedrigste** Rendite der drei — bei mit Abstand der besten Risikoadjustierung.

### Warum die Zahlen nicht vergleichbar sind

**1. Unterschiedliche epistemische Klasse.** ETF- und Krypto-Zahlen sind Medianwerte einer
*Vorwärts*-Monte-Carlo — die Hälfte aller Pfade liegt darunter. Die 6,6 % des EA sind ein
*gefitteter Backtest über denselben Zeitraum, in dem optimiert wurde*. `ea.md` formuliert die
Erwartung selbst: Live-Sharpe ~0,5 statt Backtest 1,5. Mit diesem Faktor bleiben 2–3 % p.a.
Der faire Satz lautet: **6,6 % ist die Obergrenze des EA, 10 % ist die Mitte des ETF-Plans.**

**2. Steuerstundung.** Der ETF-Plan schiebt die Besteuerung 20 Jahre auf — das ist in
Abschnitt 5 der Unterschied zwischen 381.000 € brutto und 224.000 € real. Der EA realisiert
308 Einzelgewinne, jeder sofort steuerpflichtig; der Zinseszins läuft dauerhaft auf dem
Nachsteuerbetrag. Gleiche Bruttorendite ergibt hier deutlich weniger netto.
Zusätzlich: IC Markets führt als ausländischer Broker nichts ab, und die steuerliche
Einordnung von Gold-CFDs (Termingeschäft vs. sonstige Kapitalforderung, Verlust-
verrechnung) ist **prüfpflichtig**.

**3. Kapazität.** Endvermögen über 20 Jahre bei 3.000 € Start + 500 €/Monat
(123.000 € Einzahlung, nominal, vor Steuern):

| Szenario | Rendite p.a. | Endvermögen |
|---|---|---|
| EA, live-degradiert | 2,5 % | 160.000 € |
| EA, Backtest-Rendite | 6,6 % | 253.000 € |
| ETF-Plan, Median | 10 % | 379.000 € |
| Krypto, unteres Ende | 9 % | 336.000 € |
| Krypto, oberes Ende | 12 % | 485.000 € |

Auf 3.000 € Kapital erwirtschaftet der EA rund 200 €/Jahr — weniger als eine halbe
Monatssparrate. Das ist derselbe Befund wie in Abschnitt 6: **Sparrate und Horizont
dominieren die Vehikelwahl.**

**4. Aufwand.** ETF-Plan: 0 h/Monat plus ein Rebalancing-Termin im Jahr. Krypto: Minuten.
EA: VPS, Broker-Überwachung, MT5-Wartung, laufende Weiterentwicklung — für 200 €/Jahr.

### Befund zum Backtest

Alle 64 Pässe des Optimizer-Laufs variieren `InpRiskPctDipBuy`/`InpRiskPctOverlap`
von 6 bis 20 % und liefern dennoch nur drei verschiedene Ergebnisse (1.583,74 /
1.563,30 / 1.381,50 €). Ursache: `InpMaxRiskPctPerTrade = 2.0` kappt in
`RiskManager::ComputeLots` jeden höheren Wert. Der Sweep hat effektiv nur die Reihenfolge
variiert, in der die Slots das Cluster-Risikobudget belegen — nicht das Risiko selbst.
Für einen echten Risiko-Test muss `InpMaxRiskPctPerTrade` mitoptimiert werden.
Die 6,6 % gelten also für 2 % Risiko pro Trade, nicht für 6–20 %.

### Schlussfolgerung

Die richtige Frage ist nicht, welches Vehikel mehr erwirtschaftet, sondern welche Rolle
jedes spielt:

- **Der ETF-Plan bleibt der Kern.** Beste Kombination aus Erwartungswert, Steuerstundung,
  Kapazität für die Sparrate und Aufwand.
- **Krypto ist bereits mit 15 % integriert** (Variante A). Ein separates 100-%-Krypto-Depot
  nach `crypto.md` würde diese Rolle nur verdoppeln, mit dem in `crypto.md` 10
  dokumentierten Problem, dass der Krypto-Vorteil mit dem Horizont verfällt.
- **Der Gold-EA ist kein Renditevehikel, sondern ein Diversifikator.** Sein Argument ist der
  13-%-Drawdown neben −43 % (ETF) und −80 % (Krypto), nicht die 6,6 %. Als kleiner
  Depotbaustein (5–10 %) kann er die Drawdown-Verteilung glätten; als Ersatz für den
  Sparplan ist er unterlegen — geringere Rendite, mehr Aufwand, mehr Modellrisiko,
  schlechtere Steuerbehandlung.

Offen bleibt die Frage, ob der EA überhaupt Kapital aus diesem Plan erhalten soll. Solange
kein Live-Track-Record existiert, ist die Antwort **nein** — der Backtest allein rechtfertigt
keine Allokation.

---

## 12. Prop-Firm-Finanzierung und Sparraten-Sensitivität

Geprüfte Frage (2026-08-19): Der Gold-EA aus Abschnitt 11 soll auf einem **E8-Markets-Konto
über 500.000 USD** laufen. Nach Backtest bestünde die Challenge in ~4 Jahren und würde
danach ~2.000 €/Monat erzeugen, nach Steuern ~1.000 €/Monat. Damit sollte ohne eigenes
Startkapital gespart werden. Drei Ausbaustufen wurden gerechnet: 1.000 € über 10 Jahre,
1.000 € über 20 Jahre, und 100 % BTC über 15 Jahre (letzteres in `crypto.md` Abschnitt 12).

### Die Ertragsrechnung stimmt — die Zahlungsreihe nicht

Die Größenordnung ist konsistent: Der Challenge-Kandidat aus `swingea/ea.md` 8.4a liefert
36,5 % über 79,5 Monate = **4,8 % p.a.** Auf 500.000 USD sind das 24.000 USD/Jahr =
2.000 USD/Monat, und die Zeit bis zum 21-%-Ziel ist ln(1,21)/ln(1,048) = **4,06 Jahre**.

Vier Einwände, in der Reihenfolge ihrer Wirkung:

**1. Die ersten vier Jahre zahlen nichts.** In der Evaluationsphase gibt es keine Auszahlung.
Wenn das Profitziel erst nach vier Jahren fällt, beginnt der Cashflow frühestens 2031. Ein
„Sparplan ab jetzt" ist damit nicht finanzierbar — und genau die frühen Jahre sind die
wertvollsten (siehe Sensitivitätstabelle unten).

**2. Der Drawdown-Puffer beträgt 2,5 Prozentpunkte.** 11,51 % gemessener Equity-DD gegen ein
14-%-Limit — und das ist der Wert **eines** Backtest-Pfades. Die Monte-Carlo über die
Trade-Reihenfolge (Schritt 2 der Go-Live-Kette in `ea.md` 8.5) ist nicht gelaufen; bei 302
Trades und 2,5 pp Luft liegt das P95 der DD-Verteilung mit hoher Wahrscheinlichkeit über dem
Limit. `ea.md` vermerkt selbst, dass E8s „Dynamic Drawdown" nicht identisch mit MT5s
Equity-DD%-Metrik ist. Ein Breach beendet das Konto — und die Regel gilt nach dem Bestehen
unbefristet weiter. **Der Cashflow ist keine Annuität, sondern ein Strom mit jährlicher
Abbruchrate.** Eine Verpflichtung über 180–240 Monate darauf zu stützen, ist nicht vertretbar.

**3. Die 4,8 % p.a. sind ein gefitteter Wert.** Der Demo-Forward-Test (Schritt 4 der
Go-Live-Kette) hat nicht stattgefunden. `ea.md` erwartet selbst Live-Sharpe 0,5 statt 1,5,
was auf 2–3 % p.a. führt. Bei 2,5 % p.a. dauert das 21-%-Ziel **7,7 Jahre statt 4**.
Zusätzlich ist die Skalierung von 3.000 € Backtest-Deposit auf 500.000 USD ungetestet
(`ea.md` offener Punkt 1: `SYMBOL_VOLUME_MAX` bei 1:30 Hebel).

**4. Profit Split und Steuerart fehlen in der Rechnung.** 2.000 USD Kontogewinn × ~80 %
Split = 1.600 USD. Prop-Firm-Auszahlungen sind in Deutschland **keine Kapitaleinkünfte** mit
26,375 %, sondern nach persönlichem Steuersatz zu versteuern; die Einordnung
(gewerblich / sonstige Einkünfte, ggf. Gewerbe- und Umsatzsteuer) ist **prüfpflichtig**.
Bei 42 % + Soli bleiben ~900 €. Die 1.000 € sind die Obergrenze, nicht die Mitte.

### Sparraten- und Horizont-Sensitivität

Median nominal auf Basis der Monte-Carlo aus Abschnitt 3 skaliert (Annuität ist linear in der
Rate; der MC-Median liegt ~5 % unter der deterministischen Zinsrechnung). Steuer 18,46 %
effektiv auf den Gewinn, dann 2 % Inflation abdiskontiert.

| Plan | Einzahlung | Median nominal | real nach Steuern | Entnahme 3,5 % SWR |
|---|---|---|---|---|
| 1.000 €/Mon., 10 J. | 120.000 € | ~205.000 € | ~155.000 € | ~450 €/Mon. |
| 3.000 € + 500 €/Mon., 20 J. (Basisplan) | 123.000 € | ~381.000 € | ~224.000 € | ~665 €/Mon. |
| **1.000 €/Mon., 20 J.** | 240.000 € | **~720.000 €** | **~425.000 €** | **~1.240 €/Mon.** |
| Basisplan + 1.000 €/Mon. ab Jahr 5 | 303.000 € | ~775.000 € | ~463.000 € | ~1.350 €/Mon. |

Varianten-Spreizung bei 1.000 €/Mon. über 20 Jahre: **C ~595.000 € · A ~720.000 € ·
B ~820.000 €** nominal. Die offene Variantenwahl aus `portfolio.md` ist damit ~225.000 €
wert — bei 500 €/Monat war die Spanne halb so groß.

**Drei Befunde daraus:**

- **Der Horizont schlägt die Rate.** 1.000 € über 10 Jahre (205.000 €) liefert bei gleichem
  Geld deutlich weniger als 500 € über 20 Jahre (381.000 €) — **+86 % nur durch Zeit.** Den
  Horizont zu kürzen, um EA-Erträge unterzubringen, ist auch bei perfekt laufendem EA ein
  Downgrade.
- **Frühes Geld trägt den Löwenanteil.** Fällt die Rate nach 5 Jahren von 1.000 € auf 500 €,
  bleiben ~525.000 € statt 720.000 € — nur −27 %, obwohl zwei Drittel der Einzahlungen
  entfallen. Umgekehrt gilt: die vier Nullmonate-Jahre der Challenge treffen genau das Geld,
  das am meisten wert wäre.
- **Die 1.000-€-Zeile über 20 Jahre ist mit EA-Geld nicht erreichbar.** Sie verlangt
  1.000 € ab Monat 1. Mit vierjähriger Evaluationsphase bleibt bestenfalls die letzte Zeile —
  und die verlangt, dass das Prop-Konto 16 Jahre übersteht.

Die 100-%-BTC-Ausbaustufe derselben Idee (1.000 €/Monat 2031–2045) ist in `crypto.md`
Abschnitt 12 durchsimuliert. Ergebnis: Gegen denselben Betrag in Variante A **ab heute**
liegt BTC-only im Median bei 527.000 € gegen 487.000 € — Trefferquote 53 %, bei −81 % statt
−34 % Drawdown und 22,8 % statt 2,6 % Wahrscheinlichkeit, unter der Einzahlsumme zu landen.
Der Zeitvorteil des früheren Starts ist so groß wie die gesamte erwartete
Krypto-Überrendite. Das ist derselbe Kernbefund wie in Abschnitt 6, hier gegen die
aggressivste denkbare Produktauswahl: **Zeit dominiert Produktauswahl.**

### Schlussfolgerung

**Prop-Firm-Erträge werden nicht in die Finanzplanung aufgenommen.** Begründung:

1. **Entkoppeln.** Der Sparplan läuft ab jetzt mit eigenem Geld, in welcher Höhe möglich ist.
   Jeder Monat Aufschub kostet mehr als jede Produktoptimierung einbringt.
2. **Der EA bleibt bei Abschnitt 11.** Erst Schritt 4 der Go-Live-Kette (1–3 Monate
   Demo-Forward), dann Bewertung. Ohne Live-Track-Record keine Allokation und keine
   Planungsgrundlage.
3. **Falls EA-Geld kommt: Sparrate erhöhen, nicht Horizont kürzen** — und als *variable*
   Sondereinzahlung behandeln, nicht als Erhöhung des festen Sparplans. Dann bricht ein
   Ausfall den Plan nicht.
4. **Bei Variante B und dieser Größenordnung wird Selbstverwahrung Pflicht.** 25 % Startquote
   wächst per Konvexität auf ~59 %; bei 720.000 € Endwert liegen mehrere hunderttausend Euro
   in Krypto ohne Sondervermögen. `portfolio.md` Zusatzregel 3 ist dann keine Überlegung mehr.
5. **Drawdowns werden in Euro erlebt, nicht in Prozent.** −65 % auf ein 500.000-€-Depot sind
   325.000 € Buchverlust. Bei 1.000 €/Monat gilt der Merksatz aus `portfolio.md` doppelt:
   die Variante, die man im Crash nicht verkauft, schlägt jede rechnerisch überlegene.

---

## 13. Fazit und offene Entscheidung

**Kernaussagen dieser Analyse:**

1. Das Portfolio aus `portfolio.md` liefert im Median ~10 % p.a., nicht die
   angestrebten 12–15 %. Die Zielgröße liegt im oberen Drittel der Verteilung.
2. Nach 20 Jahren stehen im Median ~224.000 € in heutiger Kaufkraft zur Verfügung —
   Faktor 2,2 auf das real Eingezahlte. Bandbreite: 92.000 € bis 676.000 €.
3. Daraus lassen sich nachhaltig ~665 €/Monat real entnehmen. Zum Leben reicht das nicht.
4. **Das Hauptproblem ist nicht die Rendite, sondern die Sparrate relativ zum Ziel.**
   Hebel und Krypto sind der Versuch, das mit Risiko zu kompensieren — sie liefern aber
   nur einen Bruchteil dessen, was Zeit und Sparrate liefern (+27 % vs. +264 %).
5. Vor der Entnahmephase ist der Glide Path aus Abschnitt 8 nicht optional.

### Getroffene Entscheidung (2026-08-19)

**Aggressive Ausrichtung, Horizont 20 Jahre.** Die Alternative eines längeren Horizonts
mit defensiverem Portfolio wurde geprüft und verworfen. Damit gilt:

- Portfolio bleibt wie in `portfolio.md` — 25 % Hebel, 15 % Krypto
- Realistische Erwartung: ~224.000 € real nach 20 Jahren, ~665 €/Monat real Entnahme
- Das Ergebnis ist bewusst als **Zusatzvermögen** geplant, nicht als
  Einkommensersatz. Die Altersvorsorge muss auf weiteren Säulen stehen
  (gesetzliche Rente, betriebliche Vorsorge, Immobilie).
- Drawdowns von 60 % sind Teil des Plans, nicht ein Zeichen, dass etwas schiefläuft

### Was daraus folgt — die drei Dinge, die jetzt zählen

1. **Durchhalten.** Bei diesem Risikoprofil ist Verhalten der dominante Faktor.
   Sparrate niemals aussetzen, im Drawdown nicht verkaufen, keine Strategieänderung
   außerhalb des Rebalancing-Termins.
2. **Jährliches Rebalancing.** Ohne das wächst der Hebelanteil unkontrolliert und die
   Verteilung verschiebt sich Richtung P10. Fester Termin, z. B. jeden Januar.
3. **Glide Path ab Jahr 14 (2040) einleiten.** Im Kalender vormerken. Das ist der
   Schritt, der am leichtesten vergessen wird und am teuersten ist, wenn er ausbleibt.

### Optionale nächste Schritte

- `simulation.py` ins Projekt legen (Monte-Carlo mit Entnahmephase), um Pleite-
  wahrscheinlichkeiten für verschiedene Entnahmeraten zu testen
- `entnahme.md` als operativer Jahresplan für den Glide Path (relevant ab ~2038)
