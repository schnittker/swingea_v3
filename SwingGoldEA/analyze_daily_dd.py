#!/usr/bin/env python3
"""
Analysiert die maximale Tages-Drawdown (%) und Gesamt-Balance-DD (%) aus einem
MT5 Strategy-Tester "Deals"-Export (ReportTester-*.xlsx, Einzeltest, kein
Optimizer-Report).

Naeherung wie ea.md 8.4b: nur Balance-Spruenge bei Trade-Exit (Deal-Zeilen),
keine Floating-Equity offener Positionen -> Untergrenze fuer die reale
Tages-DD, keine exakte Prop-Firm-"Dynamic-Drawdown"-Berechnung.

Nutzung:
    python3 analyze_daily_dd.py ReportTester-XXXXX.xlsx [weitere.xlsx ...]

Findet den "Deals"-Abschnitt im Sheet (Time, Deal, Symbol, Type, Direction,
Volume, Price, Order, Commission, Swap, Profit, Balance, Comment), gruppiert
Balance-Werte pro Kalendertag (Tester-Zeitzone, i.d.R. Broker/GMT) und
berechnet je Tag die DD vom Tagesstart-Balance zum Tagestief.
"""
import sys
from datetime import datetime

import openpyxl


def find_deals_rows(ws):
    rows = list(ws.iter_rows(values_only=True))
    header_idx = None
    for i, row in enumerate(rows):
        if row and row[0] == "Deals":
            header_idx = i + 1  # naechste Zeile ist die Spaltenueberschrift
            break
    if header_idx is None:
        raise ValueError("Kein 'Deals'-Abschnitt gefunden - ist das ein Einzeltest-Export?")

    header = rows[header_idx]
    col = {name: idx for idx, name in enumerate(header) if name}

    deals = []
    for row in rows[header_idx + 1:]:
        if row[0] is None:
            break
        time_raw = row[col["Time"]]
        balance = row[col["Balance"]]
        if balance is None:
            continue
        if isinstance(time_raw, datetime):
            ts = time_raw
        else:
            ts = datetime.strptime(str(time_raw), "%Y.%m.%d %H:%M:%S")
        deals.append((ts, float(balance)))
    return deals


def analyze(deals):
    if not deals:
        raise ValueError("Keine Deals gefunden.")

    # Gesamt-Balance-DD (Peak-to-Trough über alle Deals)
    peak = deals[0][1]
    max_total_dd_pct = 0.0
    for _, bal in deals:
        if bal > peak:
            peak = bal
        dd = (peak - bal) / peak * 100.0 if peak > 0 else 0.0
        if dd > max_total_dd_pct:
            max_total_dd_pct = dd

    # Tages-DD: pro Kalendertag Start-Balance (= Balance am Vortagesende bzw.
    # erster Deal-Wert des Tages vor der ersten Aenderung) vs. Tagestief.
    by_day = {}
    for ts, bal in deals:
        day = ts.date()
        by_day.setdefault(day, []).append(bal)

    day_start_balance = deals[0][1]
    max_daily_dd_pct = 0.0
    worst_day = None
    for day in sorted(by_day.keys()):
        balances_today = by_day[day]
        day_low = min(day_start_balance, min(balances_today))
        dd = (day_start_balance - day_low) / day_start_balance * 100.0 if day_start_balance > 0 else 0.0
        if dd > max_daily_dd_pct:
            max_daily_dd_pct = dd
            worst_day = day
        day_start_balance = balances_today[-1]

    start_balance = deals[0][1]
    end_balance = deals[-1][1]
    total_profit_pct = (end_balance - start_balance) / start_balance * 100.0 if start_balance > 0 else 0.0

    return {
        "start_balance": start_balance,
        "end_balance": end_balance,
        "total_profit_pct": total_profit_pct,
        "max_total_balance_dd_pct": max_total_dd_pct,
        "max_daily_dd_pct": max_daily_dd_pct,
        "worst_day": worst_day,
        "n_deals": len(deals),
        "n_days": len(by_day),
    }


def main(paths):
    for path in paths:
        wb = openpyxl.load_workbook(path, data_only=True)
        ws = wb.active
        deals = find_deals_rows(ws)
        stats = analyze(deals)

        print(f"=== {path} ===")
        print(f"  Deals:               {stats['n_deals']} über {stats['n_days']} Tage")
        print(f"  Start-Balance:       {stats['start_balance']:,.2f}")
        print(f"  End-Balance:         {stats['end_balance']:,.2f}")
        print(f"  Gesamt-Profit:       {stats['total_profit_pct']:.2f}%")
        print(f"  Max. Balance-DD ges.:{stats['max_total_balance_dd_pct']:.2f}%")
        print(f"  Max. Tages-DD (approx.): {stats['max_daily_dd_pct']:.2f}%  (schlechtester Tag: {stats['worst_day']})")
        daily_ok = stats["max_daily_dd_pct"] <= 4.0
        total_ok = stats["max_total_balance_dd_pct"] <= 9.0
        print(f"  Tages-DD<=4%:        {'OK' if daily_ok else 'VERLETZT'}")
        print(f"  Gesamt-DD<=9%:       {'OK' if total_ok else 'VERLETZT'}")
        print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
