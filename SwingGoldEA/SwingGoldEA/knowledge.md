# XAUUSD (Gold) – Trading Knowledge Base

> Recherche-Stand: 2026-08-06
>
> **Quellenlage:** Viele Broker-/Bildungsseiten (babypips, DailyFX, Investopedia, IG, OANDA, Admiral Markets) blockieren automatisierte Abrufe mit HTTP 403. Belastbar belegt sind vor allem **LBMA/ICE**, **World Gold Council (gold.org)**, **FRED**, **federalreserve.gov**, **BEA** und **longtermtrends.com**.
>
> **Kennzeichnung:**
> - **[Q]** = quellenbelegt
> - **[M]** = etabliertes Marktwissen (plausibel, aber in dieser Recherche nicht direkt belegt)

---

## Inhalt

1. [Wechselwirkungen / Korrelationen](#1-wechselwirkungen--was-steigt-wenn-gold-fällt)
2. [Uhrzeiten, Sessions und Trendwechsel](#2-uhrzeiten-sessions-und-trendwechsel)
3. [News-Events mit Uhrzeiten](#3-news-events-mit-uhrzeiten)
4. [Kursverhalten und Strategien](#4-typisches-kursverhalten-und-strategien)
5. [Struktureller Treiber: Zentralbanken](#5-struktureller-treiber-zentralbanken)
6. [WGC-Attributionsmodell (GRAM)](#6-das-wgc-attributionsmodell-gram--die-beste-checkliste)
7. [Saisonalität](#7-saisonalität--schwächste-datenlage)
8. [Kernerkenntnisse](#8-die-8-wichtigsten-erkenntnisse)
9. [Offene Lücken](#9-offene-lücken)
10. [Quellen](#10-quellen)

---

## 1. Wechselwirkungen – was steigt, wenn Gold fällt?

### 1.0 Korrelationsmatrix (Überblick)

| Asset | Beziehung | Stärke | Bricht wann? |
|---|---|---|---|
| **US-Realzins (10J TIPS)** | invers | **−0,82 [Q]** – stärkster struktureller Treiber | **gebrochen seit März 2022 [Q]** |
| **DXY / USD** | invers | −0,3 bis −0,6 [M]; 14 % Erklärungsanteil H1/2026 [Q] | globale Panik → beide ↑ |
| **10J-Nominalrendite** | ambivalent | schwach | wenn Anstieg von Inflationserwartung getrieben → Gold ↑ |
| **S&P 500 / Nasdaq** | regimeabhängig | langfristig ≈ 0 [M]; **in Drawdowns −0,24 [Q]** | Liquiditätsrallye → beide ↑ |
| **Silber (XAGUSD)** | positiv, verstärkt | **0,80–0,90 [Q]**, Beta ≈ 1,3, Vola 2× [Q] | Rezessionsangst → Silber fällt stärker |
| **Kupfer** | invers über den Zyklus [Q] | mittel | gemeinsame Hard-Asset-Phasen |
| **Öl** | schwach positiv | unzuverlässig [M] | nachfragegetriebener Ölanstieg = Risk-on = Gold ↓ |
| **Bitcoin** | instabil, wechselt Vorzeichen [M] | – | Risk-off: BTC ↓, Gold ↑ |
| **VIX** | positiv bei Spikes, nichtlinear | fallende implizite Vola = Gold-Gegenwind [Q] | VIX > 50: Gold fällt mit |
| **JPY / CHF** | positiv (invers zu USD/JPY) | mittel [M] | BoJ/SNB-Interventionen |

### 1.1 Realzinsen – der eigentliche Haupttreiber

Wichtiger als der Dollar. Korrelation **−0,82** (Studie Erb & Harvey) **[Q]**. Logik: Gold zahlt keine Zinsen, also sind die Opportunitätskosten hoch, wenn Realzinsen hoch sind.

**Der entscheidende Trading-Punkt:** „10J-Rendite steigt" ist **allein kein Gold-Verkaufssignal**. Es kommt darauf an, *warum*:

- Nominalrendite ↑, Inflationserwartung gleich → Realzins ↑ → **Gold ↓**
- Nominalrendite ↑ *weil* Inflationserwartung stärker steigt → Realzins ↓ → **Gold ↑**

Deshalb: nicht DGS10 anschauen, sondern **DFII10** (TIPS-Realrendite auf FRED). Der **2-jährige** reagiert am stärksten auf CPI/FOMC und ist der bessere kurzfristige Trigger **[M]**.

> **Achtung – die Beziehung ist derzeit gebrochen [Q]:** Seit März 2022 steigt Gold trotz steigender Realzinsen. Gold notiert nahe historischer Hochs bei einer Realrendite von **+2,40 %**. Der WGC nennt Zentralbankkäufe und asiatische Nachfrage als „crucial drivers **independent of US conditions**". Rein makrobasierte Goldmodelle funktionieren seit 2022 schlecht.

### 1.2 Gold vs. Dollar – schwächer als der Ruf

WGC-Attribution: FX trug im H1/2026 **14 %** zur Preisbewegung bei **[Q]**. Aber:

- **Praktisch ist „Gold vs. USD" = „Gold vs. EUR/USD"**, weil EUR 57,6 % des DXY ausmacht **[Q]**. Ein reiner JPY-Schock drückt den DXY, ohne dass Gold reagiert.
- **Bruchphasen [M]:**
  - Systemkrise → USD *und* Gold steigen gemeinsam (März 2020)
  - US-Fiskal-/Vertrauenskrise → USD ↓ und Gold überproportional ↑
  - De-Dollarisierung → Gold ↑ bei stabilem USD (dominierendes Muster seit 2022)
- Die beiden Treiber können sich neutralisieren – WGC Juli 2026: „Rising yields were somewhat cancelled out by a falling US dollar" **[Q]**.
- Struktureller USD-Gegenwind: **74 %** der Zentralbanken erwarten in 5 Jahren einen niedrigeren USD-Reserveanteil **[Q]**.

### 1.3 Gold vs. Aktien – asymmetrisch, nicht antikorreliert

Die Korrelation ist langfristig ≈ 0, wird aber **negativ genau dann, wenn man es braucht**. WGC: *„gold's negative correlation to equities increases as these assets sell off"* **[Q]**. In Drawdowns **−0,24** (Silber dagegen +0,09) **[Q]**. Gold machte **+21 %** von Dez 2007 bis Feb 2009 **[Q]**.

**Aber [M]:** In Liquiditätspaniken (März 2020, Okt 2008) fällt Gold **mit** Aktien, weil es zur Margin-Deckung verkauft wird – typisch 1–3 Wochen, danach Outperformance. Und in Liquiditätsrallyes (Fed-Cuts, schwacher USD) steigen Gold und Nasdaq gemeinsam.

### 1.4 Silber und die Gold/Silber-Ratio

Korrelation 0,80–0,90, Silber-Vola doppelt so hoch, Beta 1,3 **[Q]**. Silber ist zu **~55 % Industrienachfrage** → prozyklisch **[Q]**. Liquidität: Spread Gold **2 bp** vs. Silber **9 bp** **[Q]**. WGC-Rollenverteilung: Gold = „defensive anchor", Silber = „tactical satellite" **[Q]**.

**Als Bestätigungsindikator nutzen [M]:**

- Gold ↑ **und Ratio fällt** (Silber führt) → gesunder, reflationärer Metall-Bullmarkt
- Gold ↑ **und Ratio steigt** (Silber schwächer) → angstgetriebener Safe-Haven-Move, oft nachhaltiger
- Ratio-Spike = Rezessions-/Deflationsangst

Bandbreite: ~30 (Extremtief 1980/2011) bis ~125 (März 2020), Normalbereich 60–90 **[M]**.

### 1.5 Kupfer/Gold-Ratio – der Zins-Frühindikator

Kupfer ist laut Quelle „the exact opposite" von Gold im Zyklus. Die **Kupfer/Gold-Ratio korreliert stark mit der 10J-Treasury-Rendite** und läuft ihr oft voraus **[Q]**. Fallende Ratio = Wachstumsangst = gold-bullisch.

Ebenso: die **Gold/Öl-Ratio korreliert stark mit dem VIX** und spiket in Krisen (1998, 2008, 2020) **[Q]**.

### 1.6 Konkurrierende Safe Havens: JPY, CHF, VIX

Sie konkurrieren – aber als **Bestätigung** nutzbar **[M]**:

- Gold ↑ **mit** JPY/CHF-Stärke → echtes Risk-off
- Gold ↑ **ohne** JPY/CHF-Stärke → inflations-/USD-getrieben
- **VIX:** Gold reagiert auf *Spikes* (>25–30), aber die statische Korrelation ist niedrig (0,1–0,2) und nichtlinear. Kein Dauertrade. Umgekehrt zählt fallende implizite Vola im WGC-Modell explizit als Gold-**Gegenwind** **[Q]**.
- Gold-Liquidität bricht selbst im Stress nicht weg: ~163 Mrd. USD Tagesumsatz, vergleichbar mit T-Bills **[Q]**.

---

## 2. Uhrzeiten, Sessions und Trendwechsel

### Session-Übersicht

| Session | GMT | CET (Winter) | CEST (Sommer) | Charakter |
|---|---|---|---|---|
| Asien/Tokyo | 00:00–09:00 | 01:00–10:00 | 02:00–11:00 | ruhig, Range-bound |
| London | 08:00–17:00 | 09:00–18:00 | 10:00–19:00 | hohe Aktivität |
| New York | 13:00–22:00 | 14:00–23:00 | 15:00–00:00 | hohe Aktivität |

### Das Kernfenster: London-NY-Overlap

**ca. 12:00–16:00 GMT** = 13:00–17:00 CET / 14:00–18:00 CEST **[Q]**. Höchste Liquidität, engste Spreads, ausgeprägtere Trends, weniger Noise – gilt als beste Handelszeit für Gold.

### Typische Reversal-Zeitpunkte

- **London Open** ~08:00 GMT (09:00 CET / 10:00 CEST): Volatilitätsschub, setzt oft die erste Tagesrichtung **[M]**
- **NY Open** ~13:00–13:30 GMT (14:00–14:30 CET / 15:00–15:30 CEST): häufig Reversals oder Trendbeschleunigung **[M]**
- **LBMA-Fixes** – offiziell bestätigt **[Q]**: **10:30 und 15:00 London-Zeit**. In CET/CEST praktisch konstant **~11:30 und ~16:00**. Elektronische, handelbare Auktion (ICE Benchmark Administration, 15 Direktteilnehmer). Um diese Zeitpunkte konzentriert sich Orderfluss → kurzfristige Volatilität und Umkehrungen. Der PM-Fix liegt zusätzlich im NY-Overlap.

### Wochentage [M]

- **Montag:** träge, dünne Liquidität
- **Dienstag–Donnerstag:** am aktivsten
- **Freitag:** stark bis zum US-Vormittag (NFP am ersten Freitag), danach Liquiditätsabbau und Positionsglattstellung

### Interessante Verschiebung [Q]

WGC-Intraday-Analyse H1/2026: **Asien trieb die Rebounds, US-Handelszeiten brachten die Rücksetzer.** Die Nachfragegeografie verschiebt sich – die alte Regel „Asien ist bedeutungslos" gilt nicht mehr uneingeschränkt.

### Handelszeiten

Sonntag ~22:00–23:00 GMT bis Freitag ~21:00–22:00 GMT, brokerabhängig **[Q]**.

---

## 3. News-Events mit Uhrzeiten

> Faustregel: **CET/CEST = ET + 6 Stunden**, ganzjährig konstant.

| Event | ET | CET/CEST |
|---|---|---|
| **CPI, PPI, NFP, Core PCE, GDP, Retail Sales, Jobless Claims** | 08:30 | **14:30** |
| ISM, JOLTS, UMich | 10:00 | **16:00** |
| **FOMC-Statement** | **14:00** [Q] | **20:00** |
| **FOMC-Pressekonferenz** | 14:30 | **20:30** |
| FOMC-Minutes | 14:00 | 20:00 |

FOMC 14:00 ET und die 08:30-ET-Konvention sind über federalreserve.gov bzw. bea.gov belegt **[Q]**.

### Ranking der Gold-Wirkung [M], gestützt auf WGC-Treiberlogik [Q]

1. **US-CPI** – trifft Inflationserwartung *und* Realzinserwartung gleichzeitig, also beide Gold-Kanäle. Größter Intraday-Mover.
2. **FOMC + Dot Plot + Powell** – zweistufig: 14:00 Statement/Dots, dann oft Gegenbewegung ab 14:30 durch die PK.
3. **NFP** – regimeabhängig! In „Cut-Hoffnung"-Regimen ist schwacher NFP gold-positiv; in Rezessionsangst doppelt positiv.
4. **Core PCE** – weniger Überraschung, da CPI/PPI vorher
5. **PPI**
6. **Fed-Reden** – können den ganzen CPI-Move revidieren
7. **Treasury-Auktionen / Fiskal-/Rating-News** – neuer, zunehmend wichtiger Kanal **[Q]**
8. **Geopolitik** – 12–17 % Erklärungsanteil **[Q]**

---

## 4. Typisches Kursverhalten und Strategien

### Verhalten

- **Trendstark und ausbruchsfreudig** – lange, impulsive Trends, gut für Trendfolge **[M]**
- **Fakeouts / Stop-Hunts an offensichtlichen Levels** – deshalb betonen alle Quellen den **Retest vor dem Einstieg**: *„Waiting for the retest helps confirm the breakout's validity"* **[Q]**
- **Runde Zahlen** wirken stark als psychologische Level **[M]**
- **Deutlich volatiler als Major-Forex-Paare** **[M]**

### Bewährte Strategien

- **Break-and-Retest** – Level identifizieren, Ausbruch abwarten, **Retest** handeln, Bestätigung durch Candlestick-Muster **[Q]**
- **London-Open-Breakout** – Asien-Range als Box, Ausbruch beim London-Open **[M]**
- **Trendfolge** – Kernansatz für Gold **[Q]**
- **Range/Mean-Reversion** in Seitwärtsphasen, via Bollinger **[Q]**
- **Fibonacci** für Level und Extension-Ziele **[Q]**

### Indikatoren

- **EMA 50/200** als Trendfilter **[Q/M]**
- **Bollinger Bänder** – besonders wertvoll bei Gold: **Squeeze** (schmale Bänder) kündigt Ausbrüche an; **„Walking the Band"** = Trendfortsetzung, **nicht** Umkehr. Wichtig, um bei Gold-Trends nicht vorzeitig gegenzuhandeln **[Q]**
- **ATR** für volatilitätsbasierte Stops **[Q/M]**
- **RSI** (>70/<30), **MACD**, **VWAP** für Intraday **[Q/M]**

### Risikomanagement – die Gold-Spezifika

- **1–2 % Risiko pro Trade** **[Q]**
- **Weitere Stops als bei Forex** – ATR-basiert, z. B. 1,5–2× ATR, knapp jenseits des relevanten Levels, um Stop-Hunts zu entgehen **[M]**
- **Folge daraus: Lot-Größe kleiner.** Breiterer Stop bei gleichem Prozentrisiko = kleinere Position. Das ist der häufigste Fehler bei Gold.
- **Spreads** weiter und variabler als EUR/USD, weiten sich bei News und in der Asien-Session deutlich aus. Für Scalping entscheidend **[Q]**
- **Slippage** hoch bei FOMC/CPI/NFP **[Q]**
- **Hebel** brokerabhängig extrem unterschiedlich – CMC bis 1:200, Tickmill Europe (reguliert) nur 1:20 für Metalle **[Q]**. Bei Golds Vola ist hoher Hebel besonders gefährlich.
- **Wichtig:** Nicht auf publizierte ATR-Faustwerte (z. B. „$15–30/Tag") verlassen – die stammen aus früheren Preisregimen und sind bei heutigen Niveaus veraltet. **ATR live am Chart ablesen.**

---

## 5. Struktureller Treiber: Zentralbanken

Der bestbelegte Teil – und der Grund, warum die klassischen Korrelationen seit 2022 versagen **[Q]**:

- Netto-Zentralbankkäufe **~1.000 t p. a. seit 2022** vs. historisch 500–600 t
- 2025: **863 t**
- H1/2026 Käufer: Polen 82 t, Usbekistan 41 t, China 40 t; Verkäufer: Türkei −83 t
- **Rekord 45 %** der Zentralbanken erwarten steigende eigene Goldreserven
- EM-Goldreserven weiterhin deutlich unter Industrieland-Niveau → Aufholpotenzial
- **Schmucknachfrage 2025: −18 % Volumen**, aber Rekordwert 172 Mrd. USD → Schmuck ist **Preisfolger, nicht Preistreiber**
- ETF-Zuflüsse seit Mai 2024 nur „**less than half**" früherer Bullzyklen → strukturelle Nachfragereserve

> **Praktische Konsequenz [M]:** Zentralbanken sind preisunelastische Käufer ohne Stop-Loss. Sie erzeugen einen **steigenden Boden**, aber keine Rallye-Spitzen – und sie entkoppeln Gold über Quartale von DXY und Realzinsen.

---

## 6. Das WGC-Attributionsmodell (GRAM) – die beste Checkliste

Der praktischste analytische Rahmen: „Was treibt Gold gerade?" **[Q]**

| Faktor | H1/2025 (Gold +26 %) | H1/2026 |
|---|---|---|
| Economic expansion | – | 12 % |
| **Risk & uncertainty** (Geopolitik, Vola, Breakeven) | 4 % | **17 %** |
| Opportunity cost IR (Zinsen) | 7 % | **3 %** |
| Opportunity cost FX (USD) | 6 % | 14 % |
| **Momentum** (Positionierung, ETF-Flows) | 5 % | **24 %** |

Bemerkenswert: In H1/2026 war **Momentum der größte Einzeltreiber (24 %)**, Zinsen erklärten nur 3 %. Quantitativer Beleg dafür, dass in Extremphasen **Positionierung die Fundamentaldaten dominiert**.

---

## 7. Saisonalität – schwächste Datenlage

> Mit Vorsicht behandeln. Es konnte **keine** Quelle mit monatlichen Gold-Durchschnittsrenditen erreicht werden (bls.gov, macrotrends, goldprice.org = 403; gold.org-Seasonality-Pfade = 404).

Belegt ist nur ein Proxy: Goldminen-Saisonalität (Newmont) stark **27. Nov – 11. April** (+24 % ⌀, 10/10 Trefferquote), schwach 11. April – 27. Nov (−13 % ⌀) **[Q]**.

**Klassisches Muster [M], ausdrücklich unbelegt:**

- **Stark:** Januar, Februar (chin. Neujahr), August/September (ind. Festival-Saison + Rückkehr der Institutionellen), Nov/Dez
- **Schwach:** März (Quartalsende), April/Mai, Juni–Juli (Sommerloch); Oktober volatil

**Große Einschränkung:** Das Muster beruht auf physischer Schmucknachfrage – und die brach 2025 um 18 % ein **[Q]**. In investment-getriebenen Märkten ist die Saisonalität stark abgeschwächt. Optionsverfall (COMEX) und Monatsende-Rebalancing haben oft mehr Intraday-Einfluss als der Kalendermonat **[M]**.

---

## 8. Die 8 wichtigsten Erkenntnisse

1. **Realzinsen (DFII10), nicht der Dollar**, sind der eigentliche strukturelle Treiber (−0,82) – aber die Beziehung ist seit März 2022 gebrochen.
2. **Steigende Nominalrenditen sind kein Verkaufssignal** – entscheidend ist, ob der Realzins oder die Inflationserwartung treibt.
3. **Kernhandelsfenster 12:00–16:00 GMT**; kritische Zeitpunkte: London Open 08:00 GMT, NY Open 13:00 GMT, LBMA-Fixes 10:30/15:00 London.
4. **CPI 14:30 CET und FOMC 20:00/20:30 CET** sind die beiden größten Mover.
5. **Retest handeln, nicht den Ausbruch** – Gold ist notorisch für Fakeouts an offensichtlichen Levels.
6. **Weitere Stops = kleinere Positionen.** Der häufigste Gold-Fehler ist Forex-Positionsgröße bei Gold-Volatilität.
7. **Gold/Silber-Ratio und Kupfer/Gold-Ratio als Bestätigungsfilter** nutzen – sie sagen, *welche Art* von Move gerade läuft.
8. **Zentralbankkäufe (~1.000 t/Jahr) entkoppeln Gold von den Makro-Korrelationen** – rein makrobasierte Modelle versagen aktuell.

---

## 9. Offene Lücken

1. **Vollständige Korrelationsmatrix** – WGC stellt numerische Koeffizienten nur hinter Login/in Excel bereit. Belegt sind nur Einzelwerte (−0,82 Realzinsen / −0,24 Aktien in Drawdowns / 0,80–0,90 Silber).
2. **Saisonalität** und **aktuelle ATR/Spread-Werte** – Referenzquellen blockiert bzw. veraltet. Live am Chart bzw. beim Broker verifizieren.

---

## 10. Quellen

### LBMA / ICE
- [ICE / LBMA Gold Price – Fix-Zeiten](https://www.ice.com/iba/lbma-gold-price)
- [LBMA Gold Price – Governance](https://www.lbma.org.uk/prices-and-data/lbma-gold-price)

### World Gold Council
- [Gold Mid-Year Outlook 2026](https://www.gold.org/goldhub/research/gold-mid-year-outlook-2026)
- [Gold Outlook 2026](https://www.gold.org/goldhub/research/gold-outlook-2026)
- [Gold Market Commentary July 2026](https://www.gold.org/goldhub/research/gold-market-commentary-july-2026)
- [Gold Demand Trends Full Year 2025](https://www.gold.org/goldhub/research/gold-demand-trends/gold-demand-trends-full-year-2025)
- [Central Bank Gold Reserves Survey 2026](https://www.gold.org/goldhub/research/central-bank-gold-reserves-survey-2026)
- [Gold the safe haven versus silver the wildcard](https://www.gold.org/goldhub/research/gold-safe-haven-versus-silver-wildcard)
- [What's a bear case for gold](https://www.gold.org/goldhub/research/whats-a-bear-case-for-gold)
- [Diversification](https://www.gold.org/goldhub/research/relevance-of-gold-as-a-strategic-asset/diversification)
- [Liquidity](https://www.gold.org/goldhub/research/relevance-of-gold-as-a-strategic-asset-2025/liquidity)
- [Central bank gold statistics June 2026](https://www.gold.org/goldhub/gold-focus/2026/08/central-bank-gold-statistics-june-2026)

### Korrelationen / Ratios
- [Longtermtrends – Gold vs Real Yields](https://www.longtermtrends.com/gold-vs-real-yields/)
- [Longtermtrends – Gold/Silber-Ratio](https://www.longtermtrends.com/gold-silver-ratio/)
- [Longtermtrends – Kupfer/Gold-Ratio](https://www.longtermtrends.com/copper-gold-ratio/)
- [Longtermtrends – Gold/Öl-Ratio](https://www.longtermtrends.com/gold-to-oil-ratio/)

### Offizielle Daten
- [FRED – DFII10 (10J TIPS Realrendite)](https://fred.stlouisfed.org/series/DFII10)
- [Federal Reserve – FOMC-Kalender](https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm)
- [BEA – Release Schedule](https://www.bea.gov/news/schedule)

### Strategien / Sessions
- [forex.in.rs – Best Time to Trade Gold](https://www.forex.in.rs/best-time-to-trade-gold/)
- [howtotrade.com – Break and Retest](https://howtotrade.com/trading-strategies/break-and-retest/)
- [howtotrade.com – Bollinger Bands](https://howtotrade.com/trading-strategies/bollinger-bands/)
- [TradingView – XAUUSD](https://www.tradingview.com/symbols/XAUUSD/)
