#!/usr/bin/env python
"""Portal pipeline CLI.

    python run.py init                        # create the database
    python run.py import-excel [path.xlsx]    # seed from the 2025 workbook
    python run.py ingest --source csv --path data/events.csv
    python run.py ingest --source d1baseball --path tracker.txt  # parse a saved paste (no cookie)
    python run.py ingest --source d1baseball  # live fetch; needs cookie
    python run.py enrich-643 --dir data/643_exports     # import 6-4-3 CSVs
    python run.py enrich-trackman [--csv path/url]      # score TrackMan w/ Stuff+/xSLG models
    python run.py evaluate                    # compute fit scores
    python run.py board --limit 100           # export hot board (CSV + Sheet)
    python run.py run-all                      # ingest+enrich+evaluate+board
"""
from __future__ import annotations

import argparse
import logging
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.alerts import send_alerts  # noqa: E402
from ncaa.portal.bio import load_player_bio  # noqa: E402
from ncaa.portal.board import export_board  # noqa: E402
from ncaa.portal.config import load_config  # noqa: E402
from ncaa.portal.d3dashboard import enrich_from_d3dashboard  # noqa: E402
from ncaa.portal.db import connect, reconcile_status_from_ledger  # noqa: E402
from ncaa.portal.enrich import import_643_csv  # noqa: E402
from ncaa.portal.evaluate import evaluate  # noqa: E402
from ncaa.portal.geo import export_california_board, score_geo_ties  # noqa: E402
from ncaa.portal.overlay import backend_of, push_overlay_to_sheet, sync_overlay_to_db  # noqa: E402
from ncaa.portal.rollup import rollup_arsenal  # noqa: E402
from ncaa.portal.trackman import enrich_from_trackman  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")


def _adapter(source: str, cfg: dict, path: str | None):
    sc = (cfg.get("sources") or {}).get(source, {}) or {}
    sc = {**sc, "enabled": True}  # explicit ingest implies enabled
    if source == "csv":
        from ncaa.portal.sources.csv_feed import CsvFeedAdapter
        if not path:
            sys.exit("--path required for csv source")
        return CsvFeedAdapter(path, sc)
    if source == "d1baseball":
        from ncaa.portal.sources.d1baseball import D1BaseballAdapter
        if path:                       # --path => parse a saved tracker paste (no cookie)
            sc = {**sc, "paste_path": path}
        return D1BaseballAdapter(sc)
    if source == "verbalcommits":
        from ncaa.portal.sources.verbalcommits import VerbalCommitsAdapter
        return VerbalCommitsAdapter(sc)
    if source == "twitter":
        from ncaa.portal.sources.twitter import TwitterAdapter
        return TwitterAdapter(sc)
    sys.exit(f"unknown source: {source}")


def cmd_init(args, cfg):
    import subprocess
    subprocess.run([sys.executable, str(ROOT / "scripts" / "init_db.py")]
                   + (["--force"] if args.force else []), check=True)


def cmd_import_excel(args, cfg):
    import subprocess
    a = [sys.executable, str(ROOT / "scripts" / "import_excel.py")]
    if args.path:
        a.append(args.path)
    subprocess.run(a, check=True)


def cmd_ingest(args, cfg):
    con = connect()
    print(_adapter(args.source, cfg, args.path).ingest(con))
    con.close()


def _infer_643_tags(name: str, default_season: str = "2025") -> tuple[str, str]:
    """Season + source from a filename like 'hitters_2026_vlhp.csv'.

    A 4-digit year → season; '_vlhp'/'_vrhp' → a split-tagged source so platoon
    splits don't collide with the overall line on UNIQUE(player_id, season, source).
    """
    m = re.search(r"20\d\d", name)
    season = m.group(0) if m else default_season
    low = name.lower()
    source = "643-vlhp" if "vlhp" in low else "643-vrhp" if "vrhp" in low else "643"
    return season, source


def _is_ingestable_csv(path: Path) -> bool:
    low = path.name.lower()
    return path.suffix.lower() == ".csv" and not low.startswith(("sample_", "demo_", "test_"))


def cmd_enrich_643(args, cfg):
    con = connect()
    files = []
    if args.path:
        files = [Path(args.path)]
    elif args.dir:
        files = [f for f in sorted(Path(args.dir).glob("*.csv")) if _is_ingestable_csv(f)]
    else:
        d = (cfg.get("enrichment", {}).get("six_four_three", {}) or {}).get("inbox_dir")
        files = [f for f in sorted(Path(d).glob("*.csv")) if _is_ingestable_csv(f)] if d and Path(d).exists() else []
    if not files:
        print("no 6-4-3 CSVs found")
    for f in files:
        season, source = _infer_643_tags(f.name)
        if args.season:
            season = args.season
        if args.source:
            source = args.source
        print(f.name, f"[{season}/{source}]", "->",
              import_643_csv(con, f, season=season, source=source, fuzzy=False))
    con.close()


def cmd_enrich_643_pitching(args, cfg):
    """Load 6-4-3 per-pitch-type pitcher exports into pitch_arsenal (per pitcher, per pitch)."""
    from ncaa.portal.arsenal import import_643_arsenal
    con = connect()
    if args.path:
        files = [Path(args.path)]
    elif args.dir:
        files = sorted(Path(args.dir).glob("*.csv"))
    else:
        files = []
    if not files:
        print("no pitcher CSVs found (use --path or --dir)")
    for f in files:
        season, _ = _infer_643_tags(f.name)
        if args.season:
            season = args.season
        print(f.name, f"[{season}]", "->", import_643_arsenal(con, f, season=season, fuzzy=False))
    con.close()


def cmd_rollup(args, cfg):
    """Derive the per-pitcher stats_pitching line from pitch_arsenal (per-pitch source of truth)."""
    con = connect()
    print(rollup_arsenal(con, season=args.season))
    con.close()


def cmd_enrich_bio(args, cfg):
    """Load player height/weight (by season) into player_bio from a bio CSV (or a --dir of them)."""
    con = connect()
    files = [Path(args.path)] if args.path else (sorted(Path(args.dir).glob("*.csv")) if args.dir else [])
    if not files:
        print("no bio CSVs found (use --path or --dir)")
    for f in files:
        print(f.name, "->", load_player_bio(con, f, source=args.source))
    con.close()


def cmd_geo_tie(args, cfg):
    """Roll canonical hometown onto players + flag CA / San Diego ties, then
    export data/california_board.csv (San Diego ties first)."""
    con = connect()
    print("geo-tie ->", score_geo_ties(con))
    print("california-board ->", export_california_board(con, csv_path=args.csv))
    con.close()


def cmd_reconcile_status(args, cfg):
    """Recompute current_status from the portal-events ledger (Excel seed ignored)."""
    con = connect()
    print("reconcile-status ->", reconcile_status_from_ledger(con))
    con.close()


def cmd_split_collisions(args, cfg):
    """Split same-name players the resolver merged into one identity (tracker = truth)."""
    from ncaa.portal.dedupe import split_name_collisions
    con = connect()
    print("split-collisions ->", split_name_collisions(con, tracker_path=args.path or "sampl.txt"))
    con.close()


def cmd_evaluate(args, cfg):
    con = connect()
    print(evaluate(con, cfg))
    con.close()


def cmd_board(args, cfg):
    con = connect()
    print(export_board(con, cfg, csv_path=args.csv, limit=args.limit,
                       per=args.per, top=args.top))
    con.close()


def cmd_enrich_d3(args, cfg):
    con = connect()
    print(enrich_from_d3dashboard(con, cfg))
    con.close()


def cmd_enrich_trackman(args, cfg):
    cfg = dict(cfg)
    tm = {**(cfg.get("enrichment", {}).get("trackman", {}) or {}), "enabled": True}
    if args.csv:
        tm["csv"] = args.csv
    cfg["enrichment"] = {**cfg.get("enrichment", {}), "trackman": tm}
    con = connect()
    print(enrich_from_trackman(con, cfg))
    con.close()


def cmd_enrich_d1b_stats(args, cfg):
    from ncaa.portal.d1b_stats import enrich_from_d1b_stats
    con = connect()
    print(enrich_from_d1b_stats(con, args.path, season=args.season or "2026",
                                kind=args.kind, portal_only=not args.all))
    con.close()


def cmd_alert(args, cfg):
    con = connect()
    print(send_alerts(con, cfg, min_fit=args.min_fit))
    con.close()


def cmd_sync_overlay(args, cfg):
    """Pull coach edits (lead temp / favorites / notes) from the active overlay backend
    (supabase | sheet) back into call_assignments, keyed by player_id."""
    con = connect()
    print("sync-overlay ->", sync_overlay_to_db(con, cfg))
    con.close()


def cmd_push_overlay_sheet(args, cfg):
    """Sheet backend only: (re)build the coach-editable tab with the current ENTERED
    player list, preserving any lead/favorite/notes already entered."""
    con = connect()
    print("push-overlay-sheet ->", push_overlay_to_sheet(con, cfg))
    con.close()


def cmd_run_all(args, cfg):
    con = connect()
    for name, sc in (cfg.get("sources") or {}).items():
        if sc and sc.get("enabled") and name != "ncaa_official":
            try:
                print(_adapter(name, cfg, None).ingest(con))
            except SystemExit:
                pass
    # status is a rollup of the ledger, not the Excel seed — refresh it before scoring
    print("reconcile-status ->", reconcile_status_from_ledger(con))
    d = (cfg.get("enrichment", {}).get("six_four_three", {}) or {}).get("inbox_dir")
    if d and Path(d).exists():
        for f in sorted(Path(d).glob("*.csv")):
            if not _is_ingestable_csv(f):
                continue
            print(f.name, "->", import_643_csv(con, f))
    if (cfg.get("enrichment", {}).get("d3dashboard", {}) or {}).get("enabled"):
        try:
            print("d3dashboard ->", enrich_from_d3dashboard(con, cfg))
        except Exception as e:
            print("d3dashboard error:", e)
    if (cfg.get("enrichment", {}).get("trackman", {}) or {}).get("enabled"):
        try:
            print("trackman ->", enrich_from_trackman(con, cfg))
        except Exception as e:
            print("trackman error:", e)
    try:
        print("rollup-pitching ->", rollup_arsenal(con))   # per-pitch arsenal -> per-pitcher line
    except Exception as e:
        print("rollup error:", e)
    print(evaluate(con, cfg))
    try:
        print("geo-tie ->", score_geo_ties(con))
        print("california-board ->", export_california_board(con))
    except Exception as e:
        print("geo-tie error:", e)
    # Coach overlay: for the sheet backend, refresh the coach-editable tab so new portal
    # entries appear (preserving edits); then pull edits (lead temp / favorites / notes)
    # back into the DB before exporting, so the board CSV/Sheet + dashboard reflect them.
    if backend_of(cfg) != "none":
        try:
            if backend_of(cfg) == "sheet":
                print("push-overlay-sheet ->", push_overlay_to_sheet(con, cfg))
            print("sync-overlay ->", sync_overlay_to_db(con, cfg))
        except Exception as e:
            print("overlay error:", e)
    print(export_board(con, cfg, limit=args.limit))
    con.close()


def main():
    ap = argparse.ArgumentParser(description="NCAA baseball transfer portal pipeline")
    ap.add_argument("--config", default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init"); p.add_argument("--force", action="store_true"); p.set_defaults(fn=cmd_init)
    p = sub.add_parser("import-excel"); p.add_argument("path", nargs="?"); p.set_defaults(fn=cmd_import_excel)
    p = sub.add_parser("ingest"); p.add_argument("--source", required=True); p.add_argument("--path"); p.set_defaults(fn=cmd_ingest)
    p = sub.add_parser("enrich-643"); p.add_argument("--path"); p.add_argument("--dir")
    p.add_argument("--season"); p.add_argument("--source"); p.set_defaults(fn=cmd_enrich_643)
    p = sub.add_parser("enrich-643-pitching"); p.add_argument("--path"); p.add_argument("--dir")
    p.add_argument("--season"); p.set_defaults(fn=cmd_enrich_643_pitching)
    p = sub.add_parser("rollup-pitching"); p.add_argument("--season"); p.set_defaults(fn=cmd_rollup)
    p = sub.add_parser("enrich-bio"); p.add_argument("--path"); p.add_argument("--dir")
    p.add_argument("--source", default="ncaa"); p.set_defaults(fn=cmd_enrich_bio)
    p = sub.add_parser("geo-tie"); p.add_argument("--csv"); p.set_defaults(fn=cmd_geo_tie)
    p = sub.add_parser("reconcile-status"); p.set_defaults(fn=cmd_reconcile_status)
    p = sub.add_parser("split-collisions"); p.add_argument("--path"); p.set_defaults(fn=cmd_split_collisions)
    p = sub.add_parser("evaluate"); p.set_defaults(fn=cmd_evaluate)
    p = sub.add_parser("board"); p.add_argument("--limit", type=int); p.add_argument("--csv")
    p.add_argument("--per", choices=["role", "need", "position", "division"], help="top-N per bucket")
    p.add_argument("--top", type=int, default=15); p.set_defaults(fn=cmd_board)
    p = sub.add_parser("enrich-d3"); p.set_defaults(fn=cmd_enrich_d3)
    p = sub.add_parser("enrich-trackman"); p.add_argument("--csv"); p.set_defaults(fn=cmd_enrich_trackman)
    p = sub.add_parser("enrich-d1b-stats"); p.add_argument("--path", default="sampl copy.txt")
    p.add_argument("--kind", choices=["hitting", "pitching", "batted_ball", "adv_batting"], default="hitting")
    p.add_argument("--season"); p.add_argument("--all", action="store_true", help="ingest non-portal players too")
    p.set_defaults(fn=cmd_enrich_d1b_stats)
    p = sub.add_parser("alert"); p.add_argument("--min-fit", type=float, default=85.0, dest="min_fit"); p.set_defaults(fn=cmd_alert)
    p = sub.add_parser("sync-overlay"); p.set_defaults(fn=cmd_sync_overlay)
    p = sub.add_parser("push-overlay-sheet"); p.set_defaults(fn=cmd_push_overlay_sheet)
    p = sub.add_parser("run-all"); p.add_argument("--limit", type=int, default=200); p.set_defaults(fn=cmd_run_all)

    args = ap.parse_args()
    cfg = load_config(args.config)
    args.fn(args, cfg)


if __name__ == "__main__":
    main()
