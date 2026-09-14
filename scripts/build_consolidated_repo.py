#!/usr/bin/env python3
"""Build the consolidated `baseball-analytics` tree from the three places the work lives.

Additive and re-runnable: it only ever writes into DEST, never touches a source. Run it again
after fixing something upstream and it rebuilds the same tree.

Sources (measured 2026-09-12, see docs/consolidation-plan.md):
  A  Big Projects/baseball/                           the pipeline, apps, warehouse, tests
  B  OneDrive .../Python Scripts/Baseball/            22 research notebooks + battles/
  C  the two public GitHub app repos                  already cloned into A as hitter-app/pitcher-app

The MLB/NCAA notebook split is by data source, not by filename, which is why it is a table here
rather than a glob: several notebooks pull Statcast AND TrackMan.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # Big Projects/baseball
DEST = ROOT.parent / "baseball-analytics"
ONEDRIVE = Path.home() / "OneDrive - GOOD360" / "Documents" / "Python Scripts" / "Baseball"

# Regenerable or oversized; never copied.
SKIP_DIRS = {
    ".git", ".venv", "venv", "__pycache__", ".pytest_cache", ".netlify",
    "node_modules", "target", "logs", "dbt_packages", ".ipynb_checkpoints",
}
SKIP_SUFFIX = {".pyc", ".duckdb", ".db"}

# research/notebooks/<bucket>/ — bucketed by which league's data the notebook pulls.
NOTEBOOK_BUCKET = {
    "app_trumedia_integration.ipynb": "mlb",
    "Trumediadev.ipynb": "mlb",
    "Post_Game_Report_Generator.ipynb": "mlb",
    "baseballmodels.ipynb": "mlb",
    "armangle.ipynb": "mlb",
    "Pitcher_scouting_report.ipynb": "mlb",
    "3d_wOBA.ipynb": "mlb",
    "predicting_shoulder_coord.ipynb": "mlb",
    "NCAA_Stuffplus.ipynb": "ncaa",
    "Bunt_outcome_research.ipynb": "ncaa",
    "effectiveveloandotherpitchtopitchchanges.ipynb": "ncaa",
    "hitterapp.ipynb": "ncaa",
    "ideallocations.ipynb": "ncaa",
    "NCAA_WHIFF.ipynb": "ncaa",
    "pitchusage.ipynb": "ncaa",
    "transfer_portal_analysis.ipynb": "ncaa",
    "pitch_mix_effectiveness.ipynb": "ncaa",
    "TRANSFERSTATS.ipynb": "ncaa",
    "Umpire_Accuracy.ipynb": "ncaa",
    "USD_baseball_app.ipynb": "ncaa",
    "TRANSFERDEBUG.IPYNB": "ncaa",
}
# Named in the cleanup table: a 1-cell duplicate and a 0-cell checkpoint.
NOTEBOOK_DROP = {"Post_Game_Report_Generator (1).ipynb", "NCAA_WHIFF-checkpoint.ipynb"}


def copytree(src: Path, dst: Path, *, extra_skip_dirs=frozenset()) -> int:
    """Copy a directory, pruning regenerable dirs. Returns files written."""
    if not src.exists():
        print(f"  MISSING {src}")
        return 0
    n = 0
    skip = SKIP_DIRS | set(extra_skip_dirs)
    for p in src.rglob("*"):
        if any(part in skip for part in p.relative_to(src).parts):
            continue
        rel = p.relative_to(src)
        if p.is_dir():
            (dst / rel).mkdir(parents=True, exist_ok=True)
        elif p.suffix.lower() not in SKIP_SUFFIX:
            (dst / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dst / rel)
            n += 1
    return n


def copyfile(src: Path, dst: Path) -> int:
    if not src.exists():
        print(f"  MISSING {src}")
        return 0
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return 1


def strip_outputs(nb_path: Path) -> None:
    """Clear cell outputs in place. The 22 notebooks are ~27MB, nearly all embedded images."""
    try:
        doc = json.loads(nb_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"  UNPARSEABLE {nb_path.name}: {e}")
        return
    for cell in doc.get("cells", []):
        if cell.get("cell_type") == "code":
            cell["outputs"] = []
            cell["execution_count"] = None
    nb_path.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")


def main() -> int:
    DEST.mkdir(exist_ok=True)
    total = 0

    print("phase 2: NCAA pipeline, warehouse, tests, docs")
    total += copytree(ROOT / "src" / "portal", DEST / "src" / "ncaa" / "portal")
    total += copyfile(ROOT / "run.py", DEST / "src" / "ncaa" / "cli.py")
    total += copytree(ROOT / "scripts", DEST / "scripts")
    total += copytree(ROOT / "tests", DEST / "tests")
    # warehouse keeps models/macros/tests/sample_data; target, logs, dbt_packages regenerate
    total += copytree(ROOT / "warehouse", DEST / "warehouse")
    total += copyfile(ROOT / "db" / "schema.sql", DEST / "db" / "schema.sql")
    total += copytree(ROOT / "supabase", DEST / "supabase")
    total += copytree(ROOT / "docs", DEST / "docs")
    # data/cache is 85MB of regenerable HTTP cache; the exports and boards ship
    total += copytree(ROOT / "data", DEST / "data", extra_skip_dirs={"cache", "ncaa_cache"})

    print("phase 3: the two Streamlit apps, with their models")
    total += copytree(ROOT / "hitter-app", DEST / "apps" / "hitter")
    total += copytree(ROOT / "pitcher-app", DEST / "apps" / "pitcher")

    print("phase 4: NCAA play-by-play (battles) as a package")
    total += copytree(ONEDRIVE / "battles", DEST / "src" / "ncaa" / "pbp")

    print("phase 6: research notebooks, outputs stripped, split by league")
    seen = set()
    for nb in sorted(ONEDRIVE.glob("*.ipynb")) + sorted(ONEDRIVE.glob("*.IPYNB")):
        if nb.name in NOTEBOOK_DROP or nb.name in seen:
            continue
        seen.add(nb.name)
        bucket = NOTEBOOK_BUCKET.get(nb.name)
        if bucket is None:
            print(f"  UNBUCKETED {nb.name} -> research/notebooks/unsorted/")
            bucket = "unsorted"
        out = DEST / "research" / "notebooks" / bucket / nb.name
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(nb, out)
        strip_outputs(out)
        total += 1
    total += copyfile(ROOT / "scripts" / "ncaa_baseballr_export.R", DEST / "research" / "r" / "ncaa_baseballr_export.R")

    print(f"\n{total} files written to {DEST}")
    return 0


def demo() -> int:
    """Self-check: the notebook bucketer and the prune predicate, offline, no copying."""
    assert set(NOTEBOOK_BUCKET.values()) <= {"mlb", "ncaa"}
    assert NOTEBOOK_DROP.isdisjoint(NOTEBOOK_BUCKET), "a dropped notebook must not also be bucketed"
    # every source notebook on disk is either bucketed or explicitly dropped
    if ONEDRIVE.exists():
        on_disk = {p.name for p in ONEDRIVE.glob("*.ipynb")} | {p.name for p in ONEDRIVE.glob("*.IPYNB")}
        unknown = on_disk - set(NOTEBOOK_BUCKET) - NOTEBOOK_DROP
        assert not unknown, f"unbucketed notebooks would land in unsorted/: {sorted(unknown)}"
    # the prune predicate must reject a .venv path and accept a real source path
    def pruned(rel_parts):
        return any(part in SKIP_DIRS for part in rel_parts)
    assert pruned(("warehouse", ".venv", "lib", "x.py"))
    assert pruned(("target", "compiled", "m.sql"))
    assert not pruned(("models", "marts", "fct_portal.sql"))
    assert ".pyc" in SKIP_SUFFIX and ".sql" not in SKIP_SUFFIX
    print("demo ok")
    return 0


if __name__ == "__main__":
    sys.exit(demo() if "--demo" in sys.argv else main())
