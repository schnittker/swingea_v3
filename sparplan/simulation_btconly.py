"""
Monte-Carlo: BTC-only mit gestaffeltem Exit 2044-2045  vs.  Variante A (Glide Path)

Modellkern: BTC-Preis = Trend * exp(Zyklus-Overlay) * Rauschen.
Das Overlay ist eine 4-Jahres-Sinuswelle (Hoch ~Nov 2045, Halving 2044),
mit Phasen-Jitter und optionalem Amplituden-Zerfall. Ohne dieses Overlay
waere die Frage "wann verkaufen" definitionsgemaess irrelevant.

Zeitachse: Monat 1 = Jan 2027 ... Monat 240 = Dez 2046.
Alle Betraege nominal in EUR, Steuern beruecksichtigt.
"""
import math
import random

PATHS = 15000
INIT = 3000.0
RATE = 500.0
MONTHS = 240                      # Jan 2027 - Dez 2046
CASH_RATE = 0.02                  # Verzinsung nach Exit
INFL = 0.02
KEST = 0.26375                    # inkl. Soli
TFS = 0.30                        # Teilfreistellung Aktienfonds
TAX_EQ = KEST * (1 - TFS)         # 18.46 % auf Aktien-ETF-Gewinne


def mon(y, m):
    return (y - 2027) * 12 + m


M_DEZ45 = mon(2045, 12)
M_DEZ46 = mon(2046, 12)
QUARTERS = [mon(2044, 3), mon(2044, 6), mon(2044, 9), mon(2044, 12),
            mon(2045, 3), mon(2045, 6), mon(2045, 9), mon(2045, 12)]
PEAK_MONTH = mon(2045, 11)        # zyklisches Zielhoch
FORESIGHT_WIN = range(mon(2044, 1), M_DEZ46 + 1)

# ---------------------------------------------------------------- Zyklusmodell
CYCLE_LEN = 48.0
AMP0 = 0.65                       # exp(+-0.65) => Hoch 1.92x / Tief 0.52x Trend


def cycle_path(amp_halflife, rnd):
    """Liefert Liste overlay[0..MONTHS] der log-Bewertungsabweichung."""
    lam = 0.0 if amp_halflife is None else math.log(2) / amp_halflife
    off = rnd.gauss(0, 6.0)                    # Phasenunsicherheit heute
    ov = []
    for m in range(MONTHS + 1):
        if m > 0 and m % 48 == 0:
            off += rnd.gauss(0, 4.0)           # Drift der Zyklusphase
        amp = AMP0 * math.exp(-lam * m / 12.0)
        ov.append(amp * math.cos(2 * math.pi * (m - PEAK_MONTH - off) / CYCLE_LEN))
    return ov


# ---------------------------------------------------------------- Variante A
#            Name                 w_start w_ziel  arith  vol
SLEEVES = [("Breite Aktien",        0.55,  0.45,  0.085, 0.17),
           ("2x MSCI USA",          0.25,  0.00,  0.154, 0.36),
           ("Krypto (BTC)",         0.15,  0.05,  None,  0.60),
           ("Gold",                 0.05,  0.05,  0.040, 0.15),
           ("Anleihen/Cash",        0.00,  0.45,  0.030, 0.05)]
TAX = [TAX_EQ, TAX_EQ, 0.0, 0.0, KEST]
CORR = [[1.00, 0.93, 0.35, 0.10, 0.05],
        [0.93, 1.00, 0.35, 0.08, 0.00],
        [0.35, 0.35, 1.00, 0.15, 0.00],
        [0.10, 0.08, 0.15, 1.00, 0.25],
        [0.05, 0.00, 0.00, 0.25, 1.00]]
N = len(SLEEVES)
GLIDE_START, GLIDE_END = 14, 20    # Jahr 14 = 2040


def chol(c):
    n = len(c)
    L = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            L[i][j] = math.sqrt(max(c[i][i] - s, 1e-12)) if i == j else (c[i][j] - s) / L[j][j]
    return L


LCH = chol(CORR)


def weights(year):
    if year <= GLIDE_START:
        return [s[1] for s in SLEEVES]
    f = min(1.0, (year - GLIDE_START) / (GLIDE_END - GLIDE_START))
    return [s[1] + f * (s[2] - s[1]) for s in SLEEVES]


def pct(a, p):
    a = sorted(a)
    return a[min(len(a) - 1, int(p / 100 * len(a)))]


def irr(fv, years):
    lo, hi = -0.9, 1.5
    for _ in range(120):
        r = (lo + hi) / 2
        mr = (1 + r) ** (1 / 12) - 1
        if abs(mr) < 1e-12:
            v = INIT + RATE * years * 12
        else:
            v = INIT * (1 + mr) ** (years * 12) + RATE * (((1 + mr) ** (years * 12) - 1) / mr)
        if v < fv:
            lo = r
        else:
            hi = r
    return (lo + hi) / 2


# ---------------------------------------------------------------- Simulation
def run(btc_trend, halflife, seed=7):
    """btc_trend: geometrische Trendrendite BTC p.a.  halflife: Amplituden-
    Halbwertszeit in Jahren oder None (Zyklus bleibt) oder 0 (kein Zyklus)."""
    rnd = random.Random(seed)
    mu = []
    for k, s in enumerate(SLEEVES):
        if s[3] is None:
            mu.append(math.log(1 + btc_trend) / 12)          # Trend, geometrisch
        else:
            mu.append((math.log(1 + s[3]) - s[4] ** 2 / 2) / 12)
    sd = [s[4] / math.sqrt(12) for s in SLEEVES]
    sd_btc_base = math.sqrt(max(sd[2] ** 2 - 0.0, 1e-9))
    no_cycle = (halflife == 0)

    out = {k: [] for k in ("A", "staffel", "dez45", "dez46", "perfect")}
    dd = {"A": [], "btc": []}

    for _ in range(PATHS):
        ov = [0.0] * (MONTHS + 1) if no_cycle else cycle_path(halflife, rnd)

        # ---- Variante A: Sleeve-Werte + Einstandswerte (Durchschnittskosten)
        w0 = weights(0)
        v = [INIT * w for w in w0]
        b = list(v)
        peakA, ddA = INIT, 0.0

        # ---- BTC-only: Units + Preisindex
        price = 1.0
        units = INIT / price
        cash = 0.0
        sold_frac = 0.0
        px_hist = [1.0]
        peakB, ddB = INIT, 0.0
        val_staffel = None
        cash_staffel = 0.0
        units_staffel = INIT / price

        for m in range(1, MONTHS + 1):
            year = (m + 11) // 12
            dov = ov[m] - ov[m - 1]
            z = [rnd.gauss(0, 1) for _ in range(N)]
            x = [sum(LCH[i][k] * z[k] for k in range(i + 1)) for i in range(N)]

            # --- BTC Preisentwicklung (gleicher Schock wie Sleeve 2 in A)
            r_btc = mu[2] + dov + sd_btc_base * x[2]
            price *= math.exp(r_btc)
            px_hist.append(price)

            # --- Variante A: Einzahlung nach Zielgewichten, dann Rendite
            wt = weights(year)
            for i in range(N):
                v[i] += RATE * wt[i]
                b[i] += RATE * wt[i]
            for i in range(N):
                r = (mu[i] + dov + sd_btc_base * x[i]) if i == 2 else (mu[i] + sd[i] * x[i])
                v[i] *= math.exp(r)
            tot = sum(v)
            peakA = max(peakA, tot)
            ddA = max(ddA, 1 - tot / peakA)

            # --- BTC-only Buy&Hold-Zweig (fuer dez45/dez46/perfect)
            units += RATE / price
            valB = units * price
            peakB = max(peakB, valB)
            ddB = max(ddB, 1 - valB / peakB)

            # --- BTC-only Staffel-Zweig
            if m in QUARTERS:
                k = QUARTERS.index(m) + 1
                sell = units_staffel * (1.0 / (9 - k))       # 1/8, 1/7, ... 1/1
                units_staffel -= sell
                cash_staffel += sell * price
            if m < QUARTERS[0]:
                units_staffel += RATE / price
            else:
                cash_staffel += RATE
            cash_staffel *= (1 + CASH_RATE) ** (1 / 12)

            # --- jaehrliches Rebalancing in A (mit Steuer auf realisierte Gewinne)
            if m % 12 == 0:
                wt_next = weights(min(year + 1, GLIDE_END))
                tgt = [tot * w for w in wt_next]
                tax_due = 0.0
                for i in range(N):
                    if v[i] > tgt[i]:
                        sell = v[i] - tgt[i]
                        gain = sell * max(0.0, 1 - b[i] / v[i])
                        tax_due += gain * TAX[i]
                        b[i] -= sell * min(1.0, b[i] / v[i])
                        v[i] = tgt[i]
                for i in range(N):
                    if v[i] < tgt[i]:
                        add = tgt[i] - v[i]
                        v[i] += add
                        b[i] += add
                if tax_due > 0:
                    sc = max(0.0, 1 - tax_due / sum(v))
                    for i in range(N):
                        v[i] *= sc
                        b[i] *= sc

        # ---- Endwerte
        # Variante A: Restgewinne versteuern
        endA = sum(max(0.0, v[i] - max(0.0, v[i] - b[i]) * TAX[i]) for i in range(N))
        out["A"].append(endA)
        dd["A"].append(ddA)
        dd["btc"].append(ddB)

        # BTC-only: alle Tranchen > 12 Mon. -> steuerfrei
        out["staffel"].append(cash_staffel + units_staffel * px_hist[M_DEZ46])
        c45 = units * px_hist[M_DEZ45] * (1 + CASH_RATE) ** (12 / 12)
        out["dez45"].append(c45)
        out["dez46"].append(units * px_hist[M_DEZ46])
        best = max(px_hist[i] for i in FORESIGHT_WIN)
        out["perfect"].append(units * best)

    return out, dd


LABEL = {"A": "Variante A (Glide Path, nach Steuer)",
         "staffel": "BTC-only, Staffel-Exit 2044-2045",
         "dez45": "BTC-only, alles Dez 2045",
         "dez46": "BTC-only, alles Dez 2046",
         "perfect": "BTC-only, perfektes Timing (Obergrenze)"}
ORDER = ["A", "staffel", "dez45", "dez46", "perfect"]
INVEST = INIT + RATE * MONTHS
DEFL = (1 + INFL) ** 20


def report(title, out, dd):
    print("=" * 96)
    print(title)
    print("=" * 96)
    print(f"{'':46} {'P10':>10} {'P25':>10} {'Median':>10} {'P75':>10} {'P90':>10} {'IRR med':>8}")
    for k in ORDER:
        a = out[k]
        row = " ".join(f"{pct(a, p):>10,.0f}" for p in (10, 25, 50, 75, 90))
        print(f"{LABEL[k]:46} {row} {irr(pct(a, 50), 20) * 100:>7.1f}%")
    print(f"\n  real (2 % Infl.): Variante A Median {pct(out['A'], 50) / DEFL:>9,.0f} EUR   "
          f"BTC-Staffel Median {pct(out['staffel'], 50) / DEFL:>9,.0f} EUR")
    print(f"  Max. Drawdown:    Variante A  Median {pct(dd['A'], 50) * 100:.0f} %  P95 {pct(dd['A'], 95) * 100:.0f} %"
          f"   |  BTC-only  Median {pct(dd['btc'], 50) * 100:.0f} %  P95 {pct(dd['btc'], 95) * 100:.0f} %")
    n = len(out["A"])
    beat = sum(1 for i in range(n) if out["staffel"][i] > out["A"][i]) / n
    loss = sum(1 for x in out["staffel"] if x < INVEST) / n
    lossA = sum(1 for x in out["A"] if x < INVEST) / n
    print(f"  P(BTC-Staffel > Variante A): {beat * 100:.0f} %   "
          f"P(unter Einzahlsumme {INVEST:,.0f} EUR): BTC {loss * 100:.0f} %  A {lossA * 100:.0f} %")
    print()


if __name__ == "__main__":
    print(f"{PATHS:,} Pfade | {INIT:,.0f} EUR Start + {RATE:,.0f} EUR/Monat | "
          f"Jan 2027 - Dez 2046 | Einzahlsumme {INVEST:,.0f} EUR\n")
    for trend, hl, name in [
        (0.09, None, "SZENARIO 1  BTC-Trend 9 % p.a., Zyklus bleibt bis 2045 voll intakt"),
        (0.09, 10.0, "SZENARIO 2  BTC-Trend 9 % p.a., Zyklus zerfaellt (Halbwertszeit 10 J.)"),
        (0.09, 0, "SZENARIO 3  BTC-Trend 9 % p.a., kein Zyklus mehr (reiner Random Walk)"),
        (0.12, None, "SZENARIO 4  BTC-Trend 12 % p.a., Zyklus intakt (Bull Case)"),
        (0.07, 10.0, "SZENARIO 5  BTC-Trend 7 % p.a., Zyklus zerfaellt (Bear Case)"),
    ]:
        o, d = run(trend, hl)
        report(name, o, d)
