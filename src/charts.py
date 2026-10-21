"""Draw the five charts from sql/ict.db into charts/*.png.   Usage: python3 -I src/charts.py
Every plotted number comes from the views in sql/views.sql (same definitions as sql/queries.sql).
Style: one hue (blue) for the thing being measured, grey for context; thin marks; direct labels; one axis per chart."""
import os, shutil, sqlite3, tempfile
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLUE, GREY, INK, INK2, SURFACE, GRID = "#2a78d6", "#b9b8b2", "#0b0b0b", "#52514e", "#fcfcfb", "#e6e5e0"
EN = {"Binnenlandse Zaken en Koninkrijksrelaties": "Interior & Kingdom Relations", "Defensie": "Defence",
      "Economische Zaken": "Economic Affairs", "Financiën": "Finance", "Infrastructuur en Waterstaat": "Infrastructure & Water Mgmt",
      "Justitie en Veiligheid": "Justice & Security", "Onderwijs, Cultuur en Wetenschap": "Education, Culture & Science",
      "Sociale Zaken en Werkgelegenheid": "Social Affairs & Employment", "Volksgezondheid, Welzijn en Sport": "Health, Welfare & Sport"}
SRC = "Source: Rijks ICT-dashboard open data (CC-0), downloaded 20 Oct 2026. Outside view, public data."

plt.rcParams.update({"figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2, "text.color": INK,
    "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6,
    "axes.axisbelow": True, "font.size": 10, "axes.titlesize": 12, "axes.titleweight": "bold", "axes.titlelocation": "left"})

def load():
    tmp = tempfile.mkdtemp()
    shutil.copyfile(os.path.join(ROOT, "sql", "ict.db"), os.path.join(tmp, "ict.db"))
    con = sqlite3.connect(os.path.join(tmp, "ict.db"))
    return pd.read_sql("SELECT * FROM v_drift", con)

def load_after_year_one():
    tmp = tempfile.mkdtemp()
    shutil.copyfile(os.path.join(ROOT, "sql", "ict.db"), os.path.join(tmp, "ict.db"))
    return pd.read_sql("SELECT * FROM v_after_year_one", sqlite3.connect(os.path.join(tmp, "ict.db")))

def collisions(fig):
    """Layout self-check (the charts cannot be eyeballed in this environment): report overlapping text boxes."""
    fig.canvas.draw(); r = fig.canvas.get_renderer(); items = []
    for ax in fig.axes:
        for t in ax.texts + [ax.title, ax.xaxis.label, ax.yaxis.label] + ax.get_xticklabels() + ax.get_yticklabels():
            if t.get_visible() and t.get_text().strip(): items.append((t.get_text().replace("\n", " ")[:28], t.get_window_extent(r)))
    for t in fig.texts:
        if t.get_text().strip(): items.append((t.get_text()[:28], t.get_window_extent(r)))
    bad = [(a, b) for i, (a, ea) in enumerate(items) for b, eb in items[i + 1:] if ea.overlaps(eb)]
    return bad

def finish(fig, name, note):
    fig.text(0.01, -0.02, note + "  " + SRC, fontsize=7.5, color=INK2, ha="left", va="top", wrap=True)
    for a, b in collisions(fig): print(f"  LAYOUT WARNING in {name}: '{a}' overlaps '{b}'")
    fig.savefig(os.path.join(ROOT, "charts", name), dpi=200, bbox_inches="tight", pad_inches=0.25)
    plt.close(fig); print("wrote charts/" + name)

def pct_over(df, col="cost_growth_pct", thr=25):
    return 100.0 * (df[col] > thr).sum() / len(df)

def share_ci(df, thr=25, z=1.96):
    """Share above the threshold plus its 95% Wilson interval (in %). Small groups get wide intervals - that is the point."""
    n = len(df); k = int((df.cost_growth_pct > thr).sum()); p = k / n
    d = 1 + z * z / n; centre = (p + z * z / (2 * n)) / d
    half = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return pd.Series({"p": 100 * p, "n": n, "lo": 100 * (centre - half), "hi": 100 * (centre + half)})

def main():
    os.makedirs(os.path.join(ROOT, "charts"), exist_ok=True)
    d = load(); c = d[d.cost_ok == 1].copy(); s = d[(d.cost_ok == 1) & (d.sched_ok == 1)].copy()

    # 1. distribution of cost growth
    fig, ax = plt.subplots(figsize=(8, 4.6))
    lo, hi, w = -50, 200, 10
    clipped_hi = (c.cost_growth_pct > hi).sum(); clipped_lo = (c.cost_growth_pct < lo).sum()
    vals = c.cost_growth_pct.clip(lo, hi - 0.001)
    ax.hist(vals, bins=np.arange(lo, hi + w, w), color=BLUE, edgecolor=SURFACE, linewidth=1.2)
    for x, lab in ((0, "0%"), (25, "+25%")):
        ax.axvline(x, color=INK2, lw=1, ls="--"); ax.text(x, 1.01, lab, transform=ax.get_xaxis_transform(), color=INK2, fontsize=8.5, ha="center", va="bottom")
    ax.set_xlabel("Latest cost estimate vs first estimate (%)"); ax.set_ylabel("Projects")
    ax.set_title("Cost growth of Dutch central-government ICT projects", pad=24)
    ax.text(0.99, 0.93, f"n = {len(c)} projects\n{pct_over(c,thr=0):.0f}% above their first estimate\n{pct_over(c):.0f}% more than +25%\nmedian {c.cost_growth_pct.median():+.0f}%",
            transform=ax.transAxes, ha="right", va="top", fontsize=9.5, color=INK, linespacing=1.5)
    finish(fig, "01_cost_growth_distribution.png", f"Bars cap at -50% / +200%: {clipped_hi} projects above +200% and {clipped_lo} below -50% sit in the end bars. Cost sample: not cancelled, first estimate >= EUR 1m.")

    # 2. share above +25% by size band
    order = ["EUR 1-5m", "EUR 5-20m", "EUR 20-100m", "EUR 100m+"]
    g = c.groupby("size_band").apply(share_ci, include_groups=False).reindex(order)
    fig, ax = plt.subplots(figsize=(8, 3.8))
    y = np.arange(len(order))[::-1]
    ax.barh(y, g.p, color=BLUE, height=0.5)
    ax.errorbar(g.p, y, xerr=[g.p - g.lo, g.hi - g.p], fmt="none", ecolor=INK2, elinewidth=1, capsize=3)
    for yi, (p, n, hi) in zip(y, zip(g.p, g.n, g.hi)): ax.text(hi + 1.2, yi, f"{p:.0f}%   (n = {int(n)})", va="center", fontsize=9.5, color=INK)
    ax.set_yticks(y, order); ax.set_xlim(0, 115); ax.set_xticks(range(0, 101, 20)); ax.set_xlabel("Share of projects more than +25% above their first cost estimate (%)")
    ax.grid(axis="y", visible=False); ax.set_title("Cost growth by size of the first estimate", pad=12)
    finish(fig, "02_cost_growth_by_size.png", "Whiskers: 95% interval (Wilson). EUR 1-5m projects start from a small base, so the same euro increase is a bigger %; small first estimates may also be selected (see README).")

    # 3. is a first-year re-plan an early warning? growth AFTER month 12, by first-year re-plans (view v_after_year_one, query Q11)
    a1 = load_after_year_one(); a1["cost_growth_pct"] = a1["later_growth_pct"]
    order3 = ["0", "1", "2+"]
    gg = a1.groupby("replans_y1_group").apply(share_ci, include_groups=False).reindex(order3)
    fig, ax = plt.subplots(figsize=(7, 4.2)); x = np.arange(len(order3))
    ax.bar(x, gg.p, color=BLUE, width=0.55)
    ax.errorbar(x, gg.p, yerr=[gg.p - gg.lo, gg.hi - gg.p], fmt="none", ecolor=INK2, elinewidth=1, capsize=3)
    for xi, (p, n, hi) in zip(x, zip(gg.p, gg.n, gg.hi)): ax.text(xi + 0.08, hi + 1.5, f"{p:.0f}%\nn={int(n)}", ha="left", va="bottom", fontsize=9, color=INK)
    ax.set_xticks(x, order3); ax.set_xlabel("Re-plans in the first 12 months after the first plan"); ax.grid(axis="x", visible=False)
    ax.set_ylim(0, 100); ax.set_yticks(range(0, 101, 20)); ax.set_ylabel("Share growing more than +25% AFTER month 12 (%)")
    ax.set_title("After the first year, projects keep growing at the same rate\nwhether or not they re-planned early", pad=12)
    finish(fig, "03_growth_after_year_one.png", f"n = {len(a1)} projects observed for more than a year. Growth measured from each project's estimate at month 12, so the early re-plan's own increase is excluded. Whiskers: 95% interval (Wilson).")

    # 4. by ministry (n >= 15)
    m = c.groupby("ministry").apply(share_ci, include_groups=False)
    small = m[m.n < 15]; m = m[m.n >= 15].sort_values("p")
    fig, ax = plt.subplots(figsize=(8, 4.6)); y = np.arange(len(m))
    ax.barh(y, m.p, color=BLUE, height=0.55)
    ax.errorbar(m.p, y, xerr=[m.p - m.lo, m.hi - m.p], fmt="none", ecolor=INK2, elinewidth=1, capsize=3)
    for yi, (p, n, hi) in zip(y, zip(m.p, m.n, m.hi)): ax.text(hi + 1, yi, f"{p:.0f}%  (n = {int(n)})", va="center", fontsize=9, color=INK)
    ax.set_yticks(y, [EN[i] for i in m.index]); ax.set_xlim(0, 105); ax.set_xticks(range(0, 101, 20)); ax.grid(axis="y", visible=False)
    ax.set_xlabel("Share of projects more than +25% above their first cost estimate (%)")
    ax.set_title("Cost growth by ministry", pad=12)
    finish(fig, "04_cost_growth_by_ministry.png", f"Only ministries with 15+ projects in the cost sample; {len(small)} smaller ministries ({int(small.n.sum())} projects) left out. Whiskers: 95% interval (Wilson) - where two ministries' whiskers overlap, the difference between them may be chance.")

    # 5. cost vs schedule
    fig, ax = plt.subplots(figsize=(8, 5))
    xx = s.cost_growth_pct.clip(-60, 300); yy = (s.slip_days / 365.25).clip(-4, 10)
    ax.scatter(xx, yy, s=22, color=BLUE, alpha=0.55, edgecolor=SURFACE, linewidth=0.5)
    ax.axvline(25, color=INK2, lw=1, ls="--"); ax.axhline(1, color=INK2, lw=1, ls="--"); ax.set_ylim(-5.2, 11.4); ax.set_yticks(range(-4, 11, 2)); ax.set_xticks(range(-50, 301, 50))   # headroom so corner labels sit clear of the points
    q = {"tl": ((s.cost_growth_pct <= 25) & (s.slip_days > 365)).sum(), "tr": ((s.cost_growth_pct > 25) & (s.slip_days > 365)).sum(),
         "bl": ((s.cost_growth_pct <= 25) & (s.slip_days <= 365)).sum(), "br": ((s.cost_growth_pct > 25) & (s.slip_days <= 365)).sum()}
    ax.text(0.015, 0.97, f"late, cost within +25%: {q['tl']}", transform=ax.transAxes, va="top", fontsize=9, color=INK)
    ax.text(0.985, 0.97, f"late and over budget: {q['tr']}", transform=ax.transAxes, va="top", ha="right", fontsize=9, color=INK)
    ax.text(0.015, 0.03, f"neither: {q['bl']}", transform=ax.transAxes, va="bottom", fontsize=9, color=INK)
    ax.text(0.985, 0.03, f"over budget, end date within 12 months: {q['br']}", transform=ax.transAxes, va="bottom", ha="right", fontsize=9, color=INK)
    ax.set_xlabel("Cost growth vs first estimate (%, capped at -60 / +300)"); ax.set_ylabel("End-date slip vs first estimate (years, capped at -4 / +10)")
    ax.set_title("Cost growth and schedule slip tend to come together", pad=12)
    finish(fig, "05_cost_vs_schedule.png", f"n = {len(s)} projects in both samples. Dashed lines: +25% cost and 12 months slip (the Red thresholds).")

def write_intervals(d, a1):
    """95% Wilson intervals behind the README's confidence statements -> results/intervals.txt"""
    c = d[d.cost_ok == 1]; out = ["Share of projects more than +25% above first estimate, with 95% Wilson interval (%)", ""]
    for col in ("ministry", "method_class", "size_band", "replans_y1_group"):
        g = c.groupby(col).apply(share_ci, include_groups=False)
        out += [f"[{col}]"] + [f"  {str(k):45s} {r.p:5.1f}  n={int(r.n):3d}  ({r.lo:4.1f} - {r.hi:4.1f})" for k, r in g.iterrows()] + [""]
    a = a1.copy(); a["cost_growth_pct"] = a["later_growth_pct"]
    g = a.groupby("replans_y1_group").apply(share_ci, include_groups=False)
    out += ["[growth AFTER month 12 > +25%, by replans_y1_group]  (Q11)"] + [f"  {str(k):45s} {r.p:5.1f}  n={int(r.n):3d}  ({r.lo:4.1f} - {r.hi:4.1f})" for k, r in g.iterrows()]
    open(os.path.join(ROOT, "results", "intervals.txt"), "w", encoding="utf-8").write("\n".join(out) + "\n"); print("wrote results/intervals.txt")

if __name__ == "__main__":
    main()
    write_intervals(load(), load_after_year_one())
