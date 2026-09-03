"""
Monte-Carlo: "Master-Frage" -- ab 2031 fuenfzehn Jahre lang 1.000 EUR/Monat in BTC.

Verglichen werden vier Arme mit IDENTISCHER Einzahlsumme (180.000 EUR):

  1) BTC-only,    1.000 EUR/Mon., Jan 2031 - Dez 2045, Exit Dez 2045
  2) BTC-only,    dieselbe Einzahlung, Exit Dez 2046  (zyklisch unguenstig)
  3) BTC-only,    dieselbe Einzahlung, gestaffelter Exit 2044-2045
  4) Variante A,  1.000 EUR/Mon., Jan 2031 - Dez 2045, Glide Path 2040-2045
  5) Variante A,    789 EUR/Mon., Jan 2027 - Dez 2045  <- gleiches Geld, aber ab heute
                    (isoliert die Kosten des 4-jaehrigen Wartens)

Modellkern identisch zu simulation_btconly.py: BTC = Trend * exp(Zyklus-Overlay)
* Rauschen, 4-Jahres-Sinus mit Hoch ~Nov 2045, Phasen-Jitter, opt. Amplitudenzerfall.
Die absolute Zeitachse (Jan 2027 = Monat 1) bleibt erhalten, damit die Zyklusphase
in allen Armen dieselbe ist.

Steuer BTC: Tranchen > 12 Mon. Haltedauer steuerfrei, die letzten 12 Einzahlungen
vor dem Exit werden mit 26,375 % auf den Gewinn belastet.
"""
import math
import random

PATHS = 15000
MONTHS = 240                      # Jan 2027 - Dez 2046
CASH_RATE = 0.02
INFL = 0.02
KEST = 0.26375
TFS = 0.30
TAX_EQ = KEST * (1 - TFS)         # 18,46 % auf Aktien-ETF-Gewinne


def mon(y, m):
    return (y - 2027) * 12 + m


M_START = mon(2031, 1)            # 49  erste Einzahlung
M_EXIT = mon(2045, 12)            # 228 Exit / letzte Einzahlung
M_LATE = mon(2046, 12)            # 240 Vergleichs-Exit
N_PAY = M_EXIT - M_START + 1      # 180
RATE = 1000.0
INVEST = RATE * N_PAY             # 180.000 EUR

# Arm 5: gleiches Geld, aber ab Jan 2027 gestreckt
N_PAY_NOW = M_EXIT                # 228 Monate
RATE_NOW = INVEST / N_PAY_NOW     # 789,47 EUR/Monat

TAXFREE_FROM = M_EXIT - 11        # Einzahlungen ab hier sind < 12 Mon. alt

QUARTERS = [mon(2044, 3), mon(2044, 6), mon(2044, 9), mon(2044, 12),
            mon(2045, 3), mon(2045, 6), mon(2045, 9), mon(2045, 12)]
PEAK_MONTH = mon(2045, 11)

# ---------------------------------------------------------------- Zyklusmodell
CYCLE_LEN = 48.0
AMP0 = 0.65


def cycle_path(amp_halflife, rnd):
    lam = 0.0 if amp_halflife is None else math.log(2) / amp_halflife
    off = rnd.gauss(0, 6.0)
    ov = []
    for m in range(MONTHS + 1):
        if m > 0 and m % 48 == 0:
            off += rnd.gauss(0, 4.0)
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
GLIDE_START_Y, GLIDE_END_Y = 2040, 2045


def chol(c):
    n = len(c)
    L = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            L[i][j] = math.sqrt(max(c[i][i] - s, 1e-12)) if i == j else (c[i][j] - s) / L[j][j]
    return L


LCH = chol(CORR)


def weights(cal_year):
    if cal_year <= GLIDE_START_Y:
        return [s[1] for s in SLEEVES]
    f = min(1.0, (cal_year - GLIDE_START_Y) / (GLIDE_END_Y - GLIDE_START_Y))
    return [s[1] + f * (s[2] - s[1]) for s in SLEEVES]


WT = {y: weights(y) for y in range(2027, 2047)}


def pct(a, p):
    a = sorted(a)
    return a[min(len(a) - 1, int(p / 100 * len(a)))]


def irr(fv, rate, n):
    """IRR p.a. fuer n monatliche Zahlungen (vorschuessig) mit Endwert fv."""
    lo, hi = -0.9, 1.5
    for _ in range(200):
        r = (lo + hi) / 2
        mr = (1 + r) ** (1 / 12) - 1
        v = rate * n if abs(mr) < 1e-12 else rate * (((1 + mr) ** n - 1) / mr) * (1 + mr)
        if v < fv:
            lo = r
        else:
            hi = r
    return (lo + hi) / 2


class Aport:
    """Variante-A-Portfolio mit Einstandswerten, Rebalancing-Steuer, Glide Path."""

    __slots__ = ("v", "b", "peak", "dd")

    def __init__(self):
        self.v = [0.0] * N
        self.b = [0.0] * N
        self.peak = 0.0
        self.dd = 0.0

    def step(self, cal_year, pay, mu, sd, sd_btc, dov, x):
        v, b = self.v, self.b
        wt = WT[cal_year]
        if pay:
            for i in range(N):
                v[i] += pay * wt[i]
                b[i] += pay * wt[i]
        for i in range(N):
            r = (mu[i] + dov + sd_btc * x[i]) if i == 2 else (mu[i] + sd[i] * x[i])
            v[i] *= math.exp(r)
        tot = sum(v)
        if tot > self.peak:
            self.peak = tot
        elif self.peak > 0:
            d = 1 - tot / self.peak
            if d > self.dd:
                self.dd = d
        return tot

    def rebalance(self, cal_year):
        v, b = self.v, self.b
        tot = sum(v)
        if tot <= 0:
            return
        wt_next = WT[min(cal_year + 1, GLIDE_END_Y)]
        tgt = [tot * w for w in wt_next]
        tax_due = 0.0
        for i in range(N):
            if v[i] > tgt[i]:
                sell = v[i] - tgt[i]
                gain = sell * max(0.0, 1 - b[i] / v[i]) if v[i] > 0 else 0.0
                tax_due += gain * TAX[i]
                b[i] -= sell * min(1.0, b[i] / v[i] if v[i] > 0 else 1.0)
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

    def net(self):
        return sum(self.v[i] - max(0.0, self.v[i] - self.b[i]) * TAX[i] for i in range(N))


# ---------------------------------------------------------------- Simulation
def run(btc_trend, halflife, seed=7):
    rnd = random.Random(seed)
    mu = []
    for s in SLEEVES:
        if s[3] is None:
            mu.append(math.log(1 + btc_trend) / 12)
        else:
            mu.append((math.log(1 + s[3]) - s[4] ** 2 / 2) / 12)
    sd = [s[4] / math.sqrt(12) for s in SLEEVES]
    sd_btc = sd[2]
    no_cycle = (halflife == 0)

    out = {k: [] for k in ("btc45", "btc46", "staffel", "A", "Anow")}
    dd = {"A": [], "Anow": [], "btc": []}

    for _ in range(PATHS):
        ov = [0.0] * (MONTHS + 1) if no_cycle else cycle_path(halflife, rnd)

        A = Aport()
        Anow = Aport()

        price = 1.0
        units = 0.0                 # Buy & Hold
        units_recent = 0.0          # Tranchen < 12 Mon. vor Exit
        cost_recent = 0.0
        peakB, ddB = 0.0, 0.0
        units_st = 0.0
        cash_st = 0.0
        px45 = px46 = 1.0

        for m in range(1, MONTHS + 1):
            cal_year = 2027 + (m - 1) // 12
            dov = ov[m] - ov[m - 1]
            z = [rnd.gauss(0, 1) for _ in range(N)]
            x = [sum(LCH[i][k] * z[k] for k in range(i + 1)) for i in range(N)]

            pay = RATE if M_START <= m <= M_EXIT else 0.0
            pay_now = RATE_NOW if m <= N_PAY_NOW else 0.0

            # --- BTC Preis
            price *= math.exp(mu[2] + dov + sd_btc * x[2])

            # --- Variante A (spaet) und Variante A (ab heute)
            A.step(cal_year, pay, mu, sd, sd_btc, dov, x)
            Anow.step(cal_year, pay_now, mu, sd, sd_btc, dov, x)

            # --- BTC-only Buy & Hold
            if pay:
                u = pay / price
                units += u
                if m >= TAXFREE_FROM:
                    units_recent += u
                    cost_recent += pay
            valB = units * price
            if valB > peakB:
                peakB = valB
            elif peakB > 0:
                d = 1 - valB / peakB
                if d > ddB:
                    ddB = d

            # --- BTC-only Staffel-Exit
            if m in QUARTERS:
                k = QUARTERS.index(m) + 1
                sell = units_st * (1.0 / (9 - k))
                units_st -= sell
                cash_st += sell * price
            if pay:
                if m < QUARTERS[0]:
                    units_st += pay / price
                else:
                    cash_st += pay
            if cash_st:
                cash_st *= (1 + CASH_RATE) ** (1 / 12)

            if m % 12 == 0:
                A.rebalance(cal_year)
                Anow.rebalance(cal_year)

            if m == M_EXIT:
                px45 = price
                # Exit Dez 2045: alte Tranchen steuerfrei, junge versteuern
                gross = units * price
                gain_recent = max(0.0, units_recent * price - cost_recent)
                out["btc45"].append(gross - gain_recent * KEST)
                out["A"].append(A.net())
                dd["A"].append(A.dd)
                dd["btc"].append(ddB)
                out["Anow"].append(Anow.net())
                dd["Anow"].append(Anow.dd)
                out["staffel"].append(cash_st + units_st * price)
            if m == M_LATE:
                px46 = price

        # Exit Dez 2046: alle Tranchen > 12 Mon. -> voll steuerfrei
        out["btc46"].append(units * px46)

    return out, dd


LABEL = {"btc45": "BTC-only  1.000 EUR/M ab 2031, Exit Dez 2045",
         "btc46": "BTC-only  dito, Exit Dez 2046 (Zyklustief)",
         "staffel": "BTC-only  dito, Staffel-Exit 2044-2045",
         "A": "Variante A  1.000 EUR/M ab 2031 (n. Steuer)",
         "Anow": "Variante A    789 EUR/M ab 2027 (n. Steuer)"}
ORDER = ["btc45", "btc46", "staffel", "A", "Anow"]
DEFL45 = (1 + INFL) ** 19          # 2027 -> Ende 2045
NPAY = {"btc45": (RATE, N_PAY), "btc46": (RATE, N_PAY), "staffel": (RATE, N_PAY),
        "A": (RATE, N_PAY), "Anow": (RATE_NOW, N_PAY_NOW)}


def report(title, out, dd):
    print("=" * 104)
    print(title)
    print("=" * 104)
    print(f"{'':44} {'P10':>11} {'P25':>11} {'Median':>11} {'P75':>11} {'P90':>11} {'IRR med':>8}")
    for k in ORDER:
        a = out[k]
        row = " ".join(f"{pct(a, p):>11,.0f}" for p in (10, 25, 50, 75, 90))
        r, n = NPAY[k]
        print(f"{LABEL[k]:44} {row} {irr(pct(a, 50), r, n) * 100:>7.1f}%")
    print(f"\n  real (2 % Infl., Basis 2026):  BTC Exit 2045 Median {pct(out['btc45'], 50) / DEFL45:>9,.0f} EUR"
          f"   |  Variante A ab 2031 {pct(out['A'], 50) / DEFL45:>9,.0f} EUR"
          f"   |  Variante A ab 2027 {pct(out['Anow'], 50) / DEFL45:>9,.0f} EUR")
    print(f"  Max. Drawdown:  BTC-only Median {pct(dd['btc'], 50) * 100:.0f} % / P95 {pct(dd['btc'], 95) * 100:.0f} %"
          f"   |  A ab 2031 Median {pct(dd['A'], 50) * 100:.0f} % / P95 {pct(dd['A'], 95) * 100:.0f} %"
          f"   |  A ab 2027 Median {pct(dd['Anow'], 50) * 100:.0f} % / P95 {pct(dd['Anow'], 95) * 100:.0f} %")
    n = len(out["btc45"])
    beat = sum(1 for i in range(n) if out["btc45"][i] > out["A"][i]) / n
    beat_now = sum(1 for i in range(n) if out["btc45"][i] > out["Anow"][i]) / n
    print(f"  P(BTC > A ab 2031): {beat * 100:.0f} %    P(BTC > A ab 2027): {beat_now * 100:.0f} %")
    for k in ("btc45", "A", "Anow"):
        loss = sum(1 for x in out[k] if x < INVEST) / n
        print(f"  P(unter Einzahlsumme {INVEST:,.0f} EUR) {LABEL[k]:44} {loss * 100:>5.1f} %")
    print()


if __name__ == "__main__":
    print(f"{PATHS:,} Pfade | Einzahlsumme in allen Armen {INVEST:,.0f} EUR")
    print(f"BTC/A spaet: {RATE:,.0f} EUR x {N_PAY} Mon. (Jan 2031 - Dez 2045)")
    print(f"A ab heute:  {RATE_NOW:,.0f} EUR x {N_PAY_NOW} Mon. (Jan 2027 - Dez 2045)\n")
    for trend, hl, name in [
        (0.09, None, "SZENARIO 1  BTC-Trend 9 % p.a., Zyklus bleibt bis 2045 intakt"),
        (0.09, 10.0, "SZENARIO 2  BTC-Trend 9 % p.a., Zyklus zerfaellt (Halbwertszeit 10 J.)"),
        (0.09, 0, "SZENARIO 3  BTC-Trend 9 % p.a., kein Zyklus mehr (Random Walk)"),
        (0.12, None, "SZENARIO 4  BTC-Trend 12 % p.a., Zyklus intakt (Bull Case)"),
        (0.07, 10.0, "SZENARIO 5  BTC-Trend 7 % p.a., Zyklus zerfaellt (Bear Case)"),
    ]:
        o, d = run(trend, hl)
        report(name, o, d)
