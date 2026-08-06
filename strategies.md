# XAUUSD – Strategie-Analyse

> Abgeleitet aus [`knowledge.md`](./knowledge.md) · Stand: 2026-08-06
>
> **Wichtige Einordnung:** Ein erheblicher Teil der zugrundeliegenden Aussagen ist in `knowledge.md` als **[M]** markiert (etabliertes Marktwissen ohne Quellenbeleg). Belegt **[Q]** sind vor allem die Korrelationszahlen, die WGC-Attribution, die Zentralbankdaten und die LBMA-Fix-Zeiten. Die konkreten Setup-Regeln in diesem Dokument sind **logische Ableitungen**, keine backgetesteten Ergebnisse. Abschnittsverweise in Klammern beziehen sich auf `knowledge.md`.

---

## Inhalt

1. [Was die Wissensbasis erzwingt](#teil-a--was-die-wissensbasis-über-die-strategiewahl-erzwingt)
2. [Regime-Filter (Intermarket)](#teil-b--der-regime-filter--hier-liegt-der-intermarket-nutzen)
3. [Die Strategien, priorisiert](#teil-c--die-strategien-priorisiert)
4. [Timeframe-Empfehlung](#teil-d--timeframe-empfehlung)
5. [Was ausgeschlossen ist](#teil-e--was-die-wissensbasis-ausschließt)
6. [Korrelations-Cluster-Risiko](#teil-f--das-unterschätzte-risiko--korrelations-cluster)
7. [Empfehlung & Backtest-Hypothesen](#teil-g--konkrete-empfehlung)

---

## Teil A – Was die Wissensbasis über die Strategiewahl erzwingt

Fünf Befunde schränken den sinnvollen Strategieraum stark ein:

### 1. Makro-Modelle sind aktuell wertlos als Timing-Signal

Momentum erklärte in H1/2026 **24 %** der Bewegung, Zinsen nur **3 %** (Abschnitt 6). Die Realzins-Korrelation von −0,82 ist **seit März 2022 gebrochen** (1.1).

> **Konsequenz:** Preis- und Momentum-basierte Strategien haben Priorität. Makro liefert nur Kontext-Bias und Vetos. Wer Gold über DFII10 oder DXY timen will, handelt ein Modell, das die eigene Wissensbasis als defekt ausweist.

### 2. Es gibt eine strukturelle Long-Asymmetrie

Zentralbanken kaufen ~1.000 t/Jahr, preisunelastisch, **ohne Stop-Loss** – „steigender Boden, aber keine Rallye-Spitzen" (Abschnitt 5). ETF-Zuflüsse liegen bei „less than half" früherer Bullzyklen = Nachfragereserve.

> **Konsequenz:** Longs haben Rückenwind, Shorts kämpfen gegen die Struktur. Shorts sind taktisch (Tage), nicht strategisch (Wochen).

### 3. Gold jagt Stops – das ist ausnutzbar, nicht nur zu vermeiden

Fakeouts an offensichtlichen Levels und runden Zahlen sind dokumentiert (4). Die naive Lehre daraus ist „Retest abwarten". Die stärkere Lehre: **den Sweep als Setup handeln**, nicht als Störung.

### 4. Trends nicht faden

„Walking the Band" = Fortsetzung, nicht Umkehr (4). Gold ist trendstark. Counter-Trend-Mean-Reversion ist bei Gold der teuerste Fehler.

### 5. Die Zeitfenster sind hart begrenzt

Overlap 12:00–16:00 GMT = engste Spreads, sauberste Trends (2). Außerhalb zahlt man Spread und handelt Noise.

> **Konsequenz:** Bei einem Instrument mit weiten Spreads und hoher Slippage ist **Selektivität die größte Einzelstellschraube**.

---

## Teil B – Der Regime-Filter – hier liegt der Intermarket-Nutzen

Die Korrelationen sind als *Signal* zu schwach und instabil (DXY nur 14 % Attribution, dokumentierte Bruchphasen). Als **Regime-Klassifikator** sind sie dagegen sehr wertvoll: sie sagen, *welche Art* von Bewegung läuft – und daraus folgt, welche Strategie greifen darf.

| Regime | Signatur (Intermarket) | Gold-Verhalten | Erlaubte Strategie |
|---|---|---|---|
| **Reflation / Metall-Risk-on** | Gold ↑, **G/S-Ratio fällt** (Silber führt), Kupfer ↑, VIX tief | gesunder Trend, Rücksetzer werden gekauft | Trendfolge, Pullback-Longs, volle Größe |
| **Echtes Risk-off** | Gold ↑ **mit** JPY+CHF ↑, VIX-Spike, Aktien ↓, **G/S-Ratio steigt** | impulsiv, nachhaltig (1.4) | Momentum-Longs, weite Stops, **keine** Gegentrades |
| **Rein USD-getrieben** | Gold invers DXY, JPY/CHF **neutral**, Silber folgt nur | mean-revertierend, weniger nachhaltig | Intraday/Range, kleinere Ziele, Teilgewinne früh |
| **Liquiditätspanik** | Gold ↓ **mit** Aktien ↓, VIX > 50 | Gold wird als Margin-Quelle verkauft, 1–3 Wochen (1.3) | **Flat.** Danach Reversal-Longs |
| **Momentum-Auflösung** | Gold ↓ ohne Makro-Grund, ETF-Abflüsse, nach Parabolik | scharf und tief – H1/2026 war −8 % YTD *trotz* aller Bullfaktoren | Keine Longs im freien Fall, Basisbildung abwarten |
| **Reflation Return** (WGC-Bearcase) | Realzins ↑↑, Wachstum ↑, **Kupfer/Gold-Ratio ↑↑** | −5 bis −20 % | Struktureller Bias neutral, Shorts erlaubt |

### Die drei nützlichsten Wechselwirkungen konkret

**Gold/Silber-Ratio = Qualitätsfilter für jeden Long.**
Korrelation 0,80–0,90, Silber-Beta 1,3, Vola 2× (1.4). Regel: Gold macht neues Hoch, **Silber bestätigt nicht** → schwache Bewegung, Ziele reduzieren, Teilgewinne mitnehmen. Silber führt → Trendfolge mit voller Größe. Billiger, sofort umsetzbarer Filter.

**Kupfer/Gold-Ratio = Vorlaufindikator für den strukturellen Bias.**
Sie „korreliert stark mit der 10J-Rendite und läuft ihr oft voraus" (1.5). Damit bekommt man die Zinsrichtung *früher* als über DFII10 – und ohne dessen Lag. Fallende Ratio = Wachstumsangst = gold-bullisch. Sinnvollerer Makro-Proxy als der Realzins selbst.

**JPY/CHF = Echtheitsprüfung für Safe-Haven-Moves.**
Gold ↑ **mit** JPY/CHF-Stärke = echtes Risk-off, tragfähig. Gold ↑ **ohne** = USD-/inflationsgetrieben, eher mean-revertierend (1.6). Entscheidet direkt über Haltedauer und Zielsetzung.

**DXY: nur als Veto, nie als Signal.** „Gold vs. USD" ist praktisch „Gold vs. EUR/USD" (EUR = 57,6 % des DXY, 1.2). Ein JPY-Schock bewegt den DXY, ohne dass Gold reagiert – wer DXY blind spiegelt, handelt Rauschen.

---

## Teil C – Die Strategien, priorisiert

### Tier 1 – Kernstrategien

#### 1. Overlap-Trendfolge mit Pullback-Einstieg

**Warum:** Kombiniert die beiden robustesten Befunde – Gold ist trendstark, und 12:00–16:00 GMT liefert die sauberste Ausführung.

| Element | Regel |
|---|---|
| Bias | H4/D1 EMA 50/200 |
| Fenster | ausschließlich 12:00–16:00 GMT |
| Entry | M15-Pullback an EMA20/50 oder VWAP, in Trendrichtung, mit Kerzenbestätigung |
| Stop | 1,5–2× ATR (M15), jenseits des Swing-Punkts |
| Ziel | vorheriges Swing-Extrem, dann Trailing – bei „Walking the Band" **nicht** vorzeitig schließen |
| Intermarket-Filter | Silber bestätigt Richtung? DXY nicht gegenläufig ausbrechend? |
| Veto | CPI/FOMC-Tag vor dem Release |

#### 2. Struktureller Dip-Buy (Swing)

**Warum:** Nutzt die dokumentierte Long-Asymmetrie aus Zentralbanknachfrage direkt aus – die einzige Strategie mit echtem fundamentalen Rückenwind.

| Element | Regel |
|---|---|
| Bias | D1-Aufwärtsstruktur (höhere Tiefs) |
| Entry | Rücksetzer auf D1-EMA50 oder Fib 0,382–0,618 des letzten Impulses |
| Stop | unter dem letzten höheren Tief, ATR-gepuffert |
| Ziel | Impulsprojektion / Fib-Extension, Teilgewinne am alten Hoch |
| Intermarket-Filter | Realzins nicht im Spike, Kupfer/Gold-Ratio nicht steil steigend, kein Liquiditätspanik-Regime |
| Veto | Regime „Momentum-Auflösung" |

> Die −8 % in H1/2026 zeigen: „Zentralbanken kaufen" ist **kein** Schutz gegen mehrmonatige Positionsabbauten.

---

### Tier 2 – Ergänzend

#### 3. Liquidity-Sweep-Reclaim an runden Zahlen

**Warum:** Dreht Golds dokumentierte Fakeout-Neigung von einem Risiko in ein Setup um. Der „Retest abwarten"-Rat ist die defensive Version davon – das hier die offensive.

| Element | Regel |
|---|---|
| Setup | Kurs durchsticht ein offensichtliches Level (runde Zahl, Vortageshoch/-tief, Asia-Extrem) und **erobert es innerhalb weniger Kerzen zurück** |
| Entry | beim Reclaim |
| Stop | jenseits des Sweep-Extrems – dort liegt der Stop *hinter* der Liquidität statt davor |
| Ziel | gegenüberliegende Range-Seite |

**Vorteil:** bestes Chance-Risiko-Profil aller genannten Setups, weil der Stop-Abstand definiert und die Liquidität schon abgeräumt ist.

#### 4. Asia-Range-Breakout mit Pflicht-Retest

| Element | Regel |
|---|---|
| Box | Asia-Hoch/-Tief 00:00–08:00 GMT |
| Entry | Bruch, dann **Retest der Box-Kante** – nie der erste Bruch |
| Stop | gegenüberliegende Boxseite oder 1,5× ATR |
| Ziel | 1× Boxhöhe |

> **Wichtige Einschränkung:** In H1/2026 trieb **Asien die Rebounds** (2). Die Annahme „Asien = tote Range" gilt nicht mehr uneingeschränkt. Boxen werden breiter, Fehlsignale häufiger – **größter Validierungsbedarf in Tier 2.**

#### 5. Post-News-Continuation (nie in die News hinein)

CPI und FOMC sind die größten Mover, aber dort sind Slippage und Spread-Ausweitung am schlimmsten (3, 4).

- **Regel:** keine Position in den Release
- **CPI (14:30 CET):** 15–30 Min. Whipsaw abwarten, dann Fortsetzung der etablierten Richtung mit Retest
- **FOMC:** zweistufig – 20:00 Statement, ab 20:30 dreht Powell die Bewegung oft → **nichts vor 20:30 CET** committen
- Spread-Check vor Entry ist Pflicht

---

### Tier 3 – Erst nach Backtest

#### 6. LBMA-Fix-Reversal (10:30 / 15:00 London)

Der einzige Ansatz mit einem **strukturellen, goldspezifischen Mechanismus**: eine echte Auktion mit 15 Direktteilnehmern, um die sich Orderfluss konzentriert (2, **[Q]**). Der PM-Fix liegt zusätzlich im Overlap.

> Potenziell die interessanteste Kante der Wissensbasis – aber der Reversal-Effekt selbst ist **nicht belegt**, nur die Auktionszeiten sind es. Ohne Backtest nicht handelbar.

#### 7. Gold/Silber-Ratio-Pairtrade

Bei Ratio-Extremen (>100 oder <40) Mean Reversion.

**Für Retail meist unattraktiv:** zwei Positionen, Silber-Spread 9 bp vs. Gold 2 bp = **4,5× teurer**, und Silber-Liquidität „bricht bei Stress weg" (1.4). Genau im Extrem, wo das Setup entsteht, ist die Ausführung am schlechtesten.

> **Die Ratio ist als Filter (Tier 1) wertvoller als als Trade.**

---

## Teil D – Timeframe-Empfehlung

Die Timeframe-Wahl folgt bei Gold zwingend aus zwei Zwängen: **Kosten** (weite Spreads, hohe Slippage) und **Stop-Breite** (ATR-Stops 1,5–2×).

### Die entscheidende Logik

**Kostenargument gegen niedrige TFs.** Gold braucht ATR-basiert weite Stops. Auf M1/M5 ist die Kerzen-Range nur ein kleines Vielfaches von Spread + Slippage – das Chance-Risiko-Verhältnis wird mathematisch negativ, bevor die Strategie überhaupt greift.

> Faustregel: **das Ziel muss ≥ 10× die Round-Trip-Kosten betragen.** Bei Gold fällt damit alles unter M15 praktisch weg.

**Fensterargument für M15.** Das Kernfenster ist nur 12:00–16:00 GMT, also 4 Stunden. Auf H1 ergibt das **4 Kerzen** – zu wenig für Setup + Trigger. Auf M15 sind es **16 Kerzen** – genug für Struktur, aber grob genug, um über dem Rauschen zu bleiben. Sweet Spot für den sessionbasierten Ansatz.

**Rauschargument.** Fakeouts und Stop-Hunts (Teil A.3) sind genau das, was auf niedrigen TFs als „Signal" erscheint. Der höhere TF ist der Filter, der sie als Rauschen entlarvt.

### Drei-Ebenen-Struktur (MTF)

| Ebene | Zweck | Timeframe |
|---|---|---|
| **Kontext / Bias** | Trendrichtung, Regime, Hauptlevel | **D1** (+ W1 für runde Zahlen / Major-Level) |
| **Setup / Signal** | das eigentliche Muster | **H4** (Swing) bzw. **M15** (Intraday) |
| **Trigger / Entry** | Feinjustierung des Einstiegs | **H1** (Swing) bzw. **M5** (Intraday, optional) |

### Zuordnung pro Strategie

| Strategie | Bias | Setup | Trigger |
|---|---|---|---|
| **Overlap-Trendfolge** (Tier 1) | H4/D1 | **M15** | M5 optional |
| **Struktureller Dip-Buy** (Tier 1) | W1/D1 | **D1** | H4 |
| **Liquidity-Sweep-Reclaim** (Tier 2) | D1/H4 (Level) | M15 | **M5** – hier legitim, weil der Stop durch das Sweep-Extrem definiert ist, nicht durch ATR |
| **Asia-Range-Breakout** (Tier 2) | H1 (Box) | **M15** (Retest) | – |
| **Post-News** (Tier 2) | – | **M15** – die erste M15-Kerze nach Release *ist* der Whipsaw, gehandelt wird die zweite/dritte | M5 |
| **LBMA-Fix-Reversal** (Tier 3) | – | M15 | M5 |

### Wenn nur eine Kombination gewählt wird

- **Aktives Intraday-Trading:** **H4 (Bias) + M15 (Ausführung)**
- **Begrenzte Screen-Zeit / Swing:** **D1 (Bias) + H4 (Ausführung)** – braucht nur einen Check pro Tag

Beide sind valide. Der Swing-Pfad hat bei Gold den strukturellen Vorteil, dass er die Zentralbank-Asymmetrie (steigender Boden, Teil A.2) über Wochen ausnutzt statt sie zu ignorieren – und er ist deutlich kostenrobuster.

### Drei häufige Fehler bei der TF-Wahl

1. **ATR vom falschen TF lesen.** Der ATR muss auf dem **Entry-TF** gemessen werden, auf dem auch der Stop sitzt. ATR vom H4 nehmen und auf M15 einsteigen ergibt absurd weite Stops.
2. **EMA 50/200 auf dem Entry-TF als Bias nutzen.** Die gehören auf den **Bias-TF**. Auf M15 sind sie ein Momentum-Indikator, kein Trendfilter.
3. **TF-Drift im Verlust.** Position auf M15 eröffnen und dann auf H4 „umdeuten", um den Stop nicht zu nehmen. Bei Golds Volatilität der schnellste Weg zum großen Verlust.

---

## Teil E – Was die Wissensbasis ausschließt

| Ansatz | Warum nicht |
|---|---|
| **DXY-Inverse als Primärsignal** | nur 14 % Attribution, dokumentierte Bruchphasen, faktisch EUR/USD-Proxy |
| **Realzins-Timing** | Korrelation seit 2022 gebrochen; Gold auf Hochs bei +2,40 % Realzins |
| **Counter-Trend-Mean-Reversion** | „Walking the Band" = Fortsetzung; Gold trendet persistent |
| **Scalping** | Spread + Slippage fressen die Kante; nur im Overlap mit Raw-Spread-Broker vertretbar |
| **Saisonalität als Signal** | schwächste Datenlage; Basis (Schmucknachfrage) 2025 um 18 % eingebrochen |
| **Shorts über Wochen halten** | kämpft gegen preisunelastische Zentralbanknachfrage |
| **Enge Stops** | garantierter Stop-Hunt |
| **Forex-Positionsgrößen** | explizit als häufigster Gold-Fehler markiert |
| **Montag früh / Freitag Nachmittag** | dünne Liquidität, Positionsglattstellung |

---

## Teil F – Das unterschätzte Risiko – Korrelations-Cluster

Folgt zwingend aus der Korrelation von 0,80–0,90 zu Silber, wird in `knowledge.md` aber nicht als Risikothema geführt:

> **Long XAUUSD + Long XAGUSD + Long AUD/USD + Goldminen = ein einziger Trade, nicht vier.**

Bei je 2 % Risiko sind das faktisch 8 % auf eine Idee. Konsequenzen:

- **Gesamtes Metall-/Gold-Proxy-Exposure auf 2–3 % deckeln**, nicht pro Position
- Silber statt Gold nur, wenn bewusst mehr Beta gewollt ist (1,3× Beta, 2× Vola) – dann mit **entsprechend kleinerer** Position, nicht gleicher
- In Liquiditätspaniken korreliert *alles* gegen dich, inklusive Gold selbst (1.3)

**Basis aus Abschnitt 4:** 1–2 % pro Trade · ATR-Stops 1,5–2× · Positionsgröße folgt dem Stop-Abstand · ATR live ablesen statt Faustwerte nutzen.

---

## Teil G – Konkrete Empfehlung

| Gewichtung | Strategien | Begründung |
|---|---|---|
| **Kern – 80 % des Risikobudgets** | Overlap-Trendfolge mit Pullback + struktureller Dip-Buy (Swing) | belastbarste Grundlage: Trendstärke, Overlap-Liquidität, Zentralbank-Asymmetrie |
| **Ergänzung – 20 %** | Liquidity-Sweep-Reclaim | bestes Chance-Risiko-Profil, nutzt Golds charakteristischste Eigenschaft |
| **Nicht handeln bis validiert** | LBMA-Fix, G/S-Pairtrade, Asia-Box in aktueller Marktstruktur | Effekt unbelegt bzw. Marktstruktur verschoben |

**Über allem drei Filter:** Regime-Klassifikation (Teil B) → G/S-Ratio-Bestätigung → News-Veto.

### Sinnvolle Backtest-Hypothesen

Nach erwartetem Hebel sortiert:

1. **Session-Selektivität** – Liefert die Beschränkung auf 12:00–16:00 GMT bei identischem Setup eine bessere Expectancy als 24h? Größter erwarteter Effekt, am einfachsten zu testen.
2. **Retest-Pflicht** – Break-and-Retest vs. sofortiger Breakout-Entry: Trefferquote und Expectancy.
3. **G/S-Ratio als Filter** – Verbessert „nur long, wenn Silber bestätigt" die Ergebnisse messbar?
4. **LBMA-Fix** – Gibt es um 10:30/15:00 London eine statistisch signifikante Reversal-Häufung?
5. **Kupfer/Gold-Ratio als Bias-Filter** – Verbessert sie die Swing-Ergebnisse mehr als DFII10?
6. **ATR-Multiplikator** – optimaler Stop-Abstand: 1,0 / 1,5 / 2,0 / 2,5× ATR.
