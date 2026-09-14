"""
fetch_ncaa_bio_portal.py  (companion to fetch_ncaa_bio.py)
==========================================================

Recover HOMETOWN / HS / height / class / bats / throws for portal-entered players
who are MISSING a hometown but sit on an NCAA roster we can already locate.

WHY THIS EXISTS
---------------
fetch_ncaa_bio.py is keyed to the 6-4-3 export player universe: it fetches a
team's NCAA roster but only KEEPS the players who appear in the 6-4-3 stats
export. Many transfer-portal entrants have no 6-4-3 line (walk-ons, low-PA arms,
mid-season entrants), so their hometown is on the roster page but gets filtered
out. This script closes that gap without a 6-4-3 dependency:

  1. Pull the target players straight from the DB:
        current_status='ENTERED' AND hometown_state IS NULL AND from_school set.
  2. Group by from_school; resolve each school -> NCAA school_id via the SAME
     org-directory machinery fetch_ncaa_bio uses (alias > exact > safe fuzzy).
  3. Fetch the FULL 2026 roster (fall back to 2025 for players cut from the
     current roster after entering the portal) and match ONLY our target names
     against it (exact normalized name, then a last-name-guarded token overlap).
  4. Upsert the matched bio straight into player_bio keyed by the KNOWN
     player_id (source='ncaa') — no name re-resolution, so a hard-won match
     can't be lost. Also writes an audit CSV.

Reuses fetch_ncaa_bio's session, caches, roster parser and resolver verbatim.
Internal USD evaluation use only — polite (2-3s jittered), resumes via caches.

    python scripts/fetch_ncaa_bio_portal.py            # all missing ENTERED players
    python scripts/fetch_ncaa_bio_portal.py --limit 10 # cap schools (debug)
    python scripts/fetch_ncaa_bio_portal.py --no-headless
"""
from __future__ import annotations

import argparse
import csv
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

import fetch_ncaa_bio as nb  # noqa: E402  (reuse session/caches/parser/resolver)
from ncaa.portal.db import connect  # noqa: E402
from ncaa.portal.util import normalize_name  # noqa: E402

SEASONS = [2026, 2025]  # prefer current roster; fall back to last season
AUDIT_CSV = nb.BIO_DIR / "ncaa_portal_recovered.csv"
AUDIT_COLS = ["player_id", "player", "team", "season", "height_in", "class_year",
              "bats", "throws", "hometown_city", "hometown_state", "high_school"]


def targets(con: sqlite3.Connection) -> dict[str, list[tuple[int, str]]]:
    """{from_school: [(player_id, full_name), ...]} for ENTERED players w/o hometown."""
    by_school: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for r in con.execute(
        "SELECT player_id, full_name, from_school FROM players "
        "WHERE current_status='ENTERED' AND hometown_state IS NULL "
        "AND from_school IS NOT NULL AND TRIM(from_school) <> ''"
    ):
        by_school[r["from_school"]].append((r["player_id"], r["full_name"]))
    return by_school


def _surname(name: str) -> str:
    toks = normalize_name(name).split()
    return toks[-1] if toks else ""


def match_one(target_name: str, roster: list[dict]) -> dict | None:
    """Find the roster row for ONE known target. Exact normalized name first;
    else best token-overlap that AGREES on surname + first initial (guards
    against assigning a teammate's hometown to the wrong portal player)."""
    tn = normalize_name(target_name)
    if not tn:
        return None
    tt = set(tn.split())
    t_sur, t_init = _surname(target_name), tn[0]
    best, best_score = None, 0.0
    for r in roster:
        rn = normalize_name(r["Player"])
        if not rn:
            continue
        if rn == tn:
            return r  # exact
        rt = set(rn.split())
        inter = len(tt & rt)
        if inter == 0:
            continue
        score = inter / max(len(tt), len(rt))
        if score > best_score and _surname(r["Player"]) == t_sur and rn[0] == t_init:
            best, best_score = r, score
    return best if best_score >= 0.5 else None


UPSERT = """
INSERT INTO player_bio (player_id, season, source, team, height_in, class_year,
                        bats, throws, hometown_city, hometown_state, high_school)
VALUES (:player_id, :season, 'ncaa', :team, :height_in, :class_year,
        :bats, :throws, :hometown_city, :hometown_state, :high_school)
ON CONFLICT(player_id, season, source) DO UPDATE SET
    team           = COALESCE(excluded.team, player_bio.team),
    height_in      = COALESCE(excluded.height_in, player_bio.height_in),
    class_year     = COALESCE(excluded.class_year, player_bio.class_year),
    bats           = COALESCE(excluded.bats, player_bio.bats),
    throws         = COALESCE(excluded.throws, player_bio.throws),
    hometown_city  = COALESCE(excluded.hometown_city, player_bio.hometown_city),
    hometown_state = COALESCE(excluded.hometown_state, player_bio.hometown_state),
    high_school    = COALESCE(excluded.high_school, player_bio.high_school)
"""


def run(limit: int | None, headless: bool = True) -> None:
    con = connect()
    by_school = targets(con)
    n_players = sum(len(v) for v in by_school.values())
    schools = sorted(by_school, key=lambda s: -len(by_school[s]))
    if limit:
        schools = schools[:limit]
    print(f"targets: {n_players} ENTERED players missing hometown across "
          f"{len(by_school)} schools (processing {len(schools)})")

    directory = nb.build_org_directory(None)
    exact, by_norm = nb.build_label_indexes(directory)
    aliases = nb._load_json(nb.ALIAS_FILE, {})
    instance_cache = nb._load_json(nb.INSTANCE_CACHE_FILE, {})

    sess = nb.NcaaSession(headless=headless)
    nb.AUDIT_ROWS = []  # collected for the CSV

    recovered = 0
    with_home = 0
    unresolved: list[str] = []
    no_roster: list[str] = []
    still_missing = 0
    audit: list[dict] = []

    try:
        for si, school in enumerate(schools, 1):
            tgts = by_school[school]
            sid, label, how = nb.resolve_school_id(school, aliases, exact, by_norm)
            if not sid:
                unresolved.append(f"{school} [{how}]")
                still_missing += len(tgts)
                continue
            try:
                instances = nb.discover_instances(sess, sid, instance_cache)
            except Exception as e:
                no_roster.append(f"{school} (instances: {e})")
                still_missing += len(tgts)
                continue

            remaining = {pid: nm for pid, nm in tgts}
            hit_here = 0
            for season in SEASONS:
                if not remaining:
                    break
                inst = instances.get(nb.SEASON_LABELS[season])
                if not inst:
                    continue
                try:
                    roster = nb.fetch_team_roster(sess, inst)
                except Exception as e:
                    no_roster.append(f"{school} {season} ({e})")
                    continue
                if not roster:
                    continue
                for pid, nm in list(remaining.items()):
                    m = match_one(nm, roster)
                    if not m:
                        continue
                    row = {
                        "player_id": pid, "season": str(season), "team": school,
                        "height_in": m.get("height_in"),
                        "class_year": m.get("class_year"),
                        "bats": m.get("bats"), "throws": m.get("throws"),
                        "hometown_city": m.get("hometown_city"),
                        "hometown_state": m.get("hometown_state"),
                        "high_school": m.get("high_school"),
                    }
                    con.execute(UPSERT, row)
                    audit.append({**row, "player": nm})
                    recovered += 1
                    if m.get("hometown_state"):
                        with_home += 1
                    hit_here += 1
                    del remaining[pid]
            still_missing += len(remaining)
            con.commit()
            print(f"  [{si}/{len(schools)}] {school} -> sid={sid} ({how}); "
                  f"{hit_here}/{len(tgts)} recovered")
    finally:
        sess.close()
        con.commit()

    # audit CSV
    AUDIT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with AUDIT_CSV.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=AUDIT_COLS)
        w.writeheader()
        for a in audit:
            w.writerow({k: a.get(k) for k in AUDIT_COLS})
    con.close()

    print("\n================ RECOVERY SUMMARY ================")
    print(f"  players recovered (any bio field): {recovered}")
    print(f"  of those, WITH a hometown_state:   {with_home}")
    print(f"  still missing:                     {still_missing}")
    print(f"  schools unresolved ({len(unresolved)}): {', '.join(unresolved[:20])}"
          + (" ..." if len(unresolved) > 20 else ""))
    if no_roster:
        print(f"  roster fetch issues ({len(no_roster)}): {', '.join(no_roster[:10])}")
    print(f"  audit CSV: {AUDIT_CSV}")
    print("=================================================")


def main() -> None:
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Recover NCAA hometowns for portal players missing them")
    ap.add_argument("--limit", type=int, default=None, help="cap number of schools (debug)")
    ap.add_argument("--no-headless", action="store_true", help="show the browser")
    args = ap.parse_args()
    run(args.limit, headless=not args.no_headless)


if __name__ == "__main__":
    main()
