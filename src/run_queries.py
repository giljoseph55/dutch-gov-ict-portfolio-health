"""Run sql/queries.sql against sql/ict.db and write results/query_results.txt (also printed).
Usage: python3 -I src/run_queries.py        (stdlib only)"""
import os, re, shutil, sqlite3, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def table(cols, rows):
    cells = [[("" if v is None else (f"{v:,.1f}" if isinstance(v, float) and not float(v).is_integer() else f"{int(v):,}" if isinstance(v, float) else str(v))) for v in r] for r in rows]
    w = [max(len(c), *(len(r[i]) for r in cells)) if cells else len(c) for i, c in enumerate(cols)]
    line = lambda r: "  ".join(x.ljust(w[i]) if i == 0 else x.rjust(w[i]) for i, x in enumerate(r))
    return "\n".join([line(cols), "  ".join("-" * x for x in w)] + [line(r) for r in cells])

def main():
    sql = open(os.path.join(ROOT, "sql", "queries.sql"), encoding="utf-8").read()
    blocks = re.split(r"(?m)^(?=-- Q\d+:)", sql)[1:]
    out = []
    with tempfile.TemporaryDirectory() as tmp:          # copy: SQLite cannot open its journal on some mounted folders
        shutil.copyfile(os.path.join(ROOT, "sql", "ict.db"), os.path.join(tmp, "ict.db"))
        con = sqlite3.connect(os.path.join(tmp, "ict.db"))
        for b in blocks:
            head = "\n".join(l for l in b.splitlines() if l.startswith("--") and not l.startswith("-- PARAMS"))
            stmt = "\n".join(l for l in b.splitlines() if not l.startswith("--")).strip().rstrip(";")
            m = re.search(r"-- PARAMS: (\w+) = (.+)", b)
            runs = [{m.group(1): v.strip()} for v in m.group(2).split("|")] if m else [{}]
            out.append(head)
            for params in runs:
                cur = con.execute(stmt, params)
                cols = [c[0] for c in cur.description]
                out.append((f"[{list(params)[0]} = {list(params.values())[0]}]\n" if params else "") + table(cols, cur.fetchall()) + "\n")
            out.append("")
        con.close()
    text = "\n".join(out)
    open(os.path.join(ROOT, "results", "query_results.txt"), "w", encoding="utf-8").write(text)
    print(text)

if __name__ == "__main__":
    main()
