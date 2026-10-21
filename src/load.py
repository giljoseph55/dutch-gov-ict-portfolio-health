"""Load the Rijks ICT-dashboard JSON into a normalised SQLite database and run the integrity checks.

Usage:  python3 -I src/load.py            (from the repo root; stdlib only)
Output: sql/ict.db (rebuilt from scratch every run), integrity report on screen and in results/integrity_report.txt

Design rules
- Only the "(correct)" cost fields are loaded. The source also carries two older field-name generations that are
  only partly filled; the "(correct)" set is complete for every report entry (verified: 3,109 of 3,109).
- Nothing is dropped silently: every Dutch category value must be in the translation tables below, otherwise the load stops.
- Report entries are ordered by report date; ties keep their order in the file (the source list is NOT date-sorted).
"""
import json, os, re, sqlite3, sys, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw", "rijks_ict_opendata.json")
DB = os.path.join(ROOT, "sql", "ict.db")

STATUS_EN = {"Afgerond": "Completed", "In uitvoering": "In progress", "Geannuleerd": "Cancelled",
             "In heroriëntatie": "Under reorientation", "Nog niet gestart": "Not yet started"}
ACTION_EN = {"Initieel": "Initial plan", "Rapportage": "Routine report", "Herijking": "Re-plan (re-baseline)"}
REASON_EN = {
    "Tegenvallers binnen project": "Setbacks within the project",
    "Aanpassing (business)doelen of eisen": "Change of (business) goals or requirements",
    "Implementatie in organisatie": "Implementation in the organisation",
    "Project-endogene scopewijzigingen": "Scope changes originating inside the project",
    "Overnemen aanbeveling extern advies": "Adopting external advice",
    "Prijsontwikkeling": "Price development",
    "Wetswijziging": "Change in law",
    "Wens van de Tweede Kamer/Eerste Kamer": "Wish of the House of Representatives / Senate",
}

def method_class(raw):
    """Classify the free-text 'Ontwikkelwijze' (development method). Keyword rules, documented in the README."""
    s = (raw or "").lower().strip()
    if not s or s == "n.v.t." or "niet van toepassing" in s:
        return "Unknown / n.a."
    agile = bool(re.search(r"agile|scrum|\bsafe\b|devops", s))
    waterfall = "waterval" in s
    standard = "standaard product" in s
    if agile and waterfall: return "Mixed"
    if agile: return "Agile/DevOps"
    if waterfall: return "Waterfall"
    if standard: return "Standard product"
    return "Unknown / n.a."          # free text that names no method (e.g. an architecture remark)

def f(x, ctx):
    try: return float(x)
    except (TypeError, ValueError): sys.exit(f"STOP: non-numeric cost value {x!r} in {ctx}")

def main():
    data = json.load(open(RAW, encoding="utf-8"))
    sha = hashlib.sha256(open(RAW, "rb").read()).hexdigest()
    print(f"source file sha256 {sha[:16]}…  projects in file: {len(data)}")
    con = sqlite3.connect(":memory:")
    con.executescript(open(os.path.join(ROOT, "sql", "schema.sql"), encoding="utf-8").read())

    con.executemany("INSERT INTO status_ref VALUES (?,?)", STATUS_EN.items())
    con.executemany("INSERT INTO action_ref VALUES (?,?)", ACTION_EN.items())
    con.executemany("INSERT INTO reason_ref VALUES (?,?)", REASON_EN.items())
    ministries = {}
    n_reports = 0; src_est_sum = 0.0; src_replan_links = 0
    for pid, p in enumerate(data, start=1):
        m = p["Ministerie"]
        if m not in ministries:
            ministries[m] = len(ministries) + 1
            con.execute("INSERT INTO ministry VALUES (?,?)", (ministries[m], m))
        a = p["Algemeen"][0]; st = p["Peildatum en Status"][0]
        if st["Status"] not in STATUS_EN: sys.exit(f"STOP: unknown status {st['Status']!r}")
        con.execute("INSERT INTO project VALUES (?,?,?,?,?,?,?,?,?,?)", (
            pid, p["Naam"], ministries[m], st["Status"], st["Peildatum"], a["Startdatum"],
            a.get("Ontwikkelwijze") or None, method_class(a.get("Ontwikkelwijze")),
            a.get("Maatwerk") or None, a.get("Soort ICT-activiteit") or None))
        entries = sorted(enumerate(p["Doorlooptijd en Kosten"]), key=lambda t: (t[1]["Datum"], t[0]))
        for seq, (_, e) in enumerate(entries, start=1):
            if e["Soort actie"] not in ACTION_EN: sys.exit(f"STOP: unknown action {e['Soort actie']!r}")
            ctx = f"project {pid} {p['Naam']!r} seq {seq}"
            vals = [f(e[k], ctx) for k in (
                "Actueel totaal projectkosten (correct)", "Actueel intern personeel (correct)",
                "Actueel extern personeel (correct)", "Actueel overig materieel (correct)",
                "Daadwerkelijk totale projectenkosten (correct)", "Daadwerkelijk intern personeel (correct)",
                "Daadwerkelijk extern personeel (correct)", "Daadwerkelijk overig materieel (correct)")]
            raw_reason = e.get("Reden herijking") or None
            cur = con.execute("INSERT INTO cost_report (project_id,seq,report_date,action_nl,est_total_m,est_internal_m,"
                              "est_external_m,est_other_m,act_total_m,act_internal_m,act_external_m,act_other_m,"
                              "est_end_date,replan_reason_raw) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                              (pid, seq, e["Datum"], e["Soort actie"], *vals, e["Actueel geschatte einddatum"] or None, raw_reason))
            n_reports += 1; src_est_sum += vals[0]
            if raw_reason and e["Soort actie"] == "Herijking":
                for r in {x.strip() for x in re.split(r"[;,]", raw_reason) if x.strip()}:
                    if r not in REASON_EN: sys.exit(f"STOP: unknown re-plan reason {r!r}")
                    con.execute("INSERT INTO replan_reason VALUES (?,?)", (cur.lastrowid, r)); src_replan_links += 1
    con.commit()

    # reconciliation against the source file
    db_proj = con.execute("SELECT COUNT(*) FROM project").fetchone()[0]
    db_rep = con.execute("SELECT COUNT(*) FROM cost_report").fetchone()[0]
    db_sum = con.execute("SELECT SUM(est_total_m) FROM cost_report").fetchone()[0]
    assert db_proj == len(data), "project count mismatch"
    assert db_rep == n_reports == sum(len(p["Doorlooptijd en Kosten"]) for p in data), "report count mismatch"
    assert abs(db_sum - src_est_sum) < 1e-6, "estimate sum mismatch"
    lines = [f"RECONCILIATION  projects {db_proj}/{len(data)}  reports {db_rep}/{n_reports}  "
             f"sum(est_total_m) db {db_sum:.3f} vs source {src_est_sum:.3f}  OK", ""]

    # analysis views live in the DB too (created before the checks: one info check uses v_baseline)
    con.executescript(open(os.path.join(ROOT, "sql", "views.sql"), encoding="utf-8").read())
    rows = con.execute(open(os.path.join(ROOT, "sql", "integrity.sql"), encoding="utf-8").read()).fetchall()
    lines += [f"{v:6d}  {name}" for name, v in rows]
    hard_fail = [(n, v) for n, v in rows if n.startswith("hard") and v != 0]
    lines += ["", "RESULT: " + ("ALL HARD CHECKS PASSED" if not hard_fail else f"FAILED {hard_fail}")]
    report = "\n".join(lines); print(report)
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    open(os.path.join(ROOT, "results", "integrity_report.txt"), "w", encoding="utf-8").write(report + "\n")
    if hard_fail: sys.exit(1)

    # write the database (backup onto the target path so a re-run overwrites in place)
    # SQLite cannot create its journal on some synced/mounted folders ("disk I/O error"), so build in a temp dir and copy.
    import tempfile, shutil
    with tempfile.TemporaryDirectory() as tmp:
        tmp_db = os.path.join(tmp, "ict.db"); out = sqlite3.connect(tmp_db); con.backup(out); out.close()
        shutil.copyfile(tmp_db, DB)
    print(f"\nwrote {DB} ({os.path.getsize(DB)/1e6:.1f} MB)")

if __name__ == "__main__":
    main()
