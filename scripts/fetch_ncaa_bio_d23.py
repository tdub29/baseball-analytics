"""
fetch_ncaa_bio_d23.py  (D2/D3 source-gap recovery)
==================================================

Close the **D2/D3 bio coverage gap**: ~1,874 ENTERED players at division II / III
have no `player_bio` row. Some are *matching gaps* (their team WAS scraped, the
player just didn't match -> the entity-resolution subagent handles those); the
rest are *source gaps* (their D2/D3 team was never scraped at all). This script
scrapes the NCAA rosters for the **source-gap teams only** and emits a join-ready
bio CSV. It does NOT write to the DB.

It REUSES the production D1 scraper's machinery wholesale
(`scripts/fetch_ncaa_bio.py`): the CloakBrowser session, the org directory
(`team/search?sport_code=MBA`, which already lists D2/D3 programs), the
team->school_id resolver, the per-school instance dropdown, and the roster-page
parser + name matcher. The only thing that changes for D2/D3 is the *source of
the team list and the players to match*: instead of the 6-4-3 D1 exports, it
comes from the DB (ENTERED, division in II/III, no `player_bio` row, and team
absent from `player_bio` under any source).

DIVISIONS / SEASONS
-------------------
The NCAA `team/search` directory and the roster endpoints are division-agnostic
-- a school's instance dropdown lists every season it played regardless of
division -- so divisions II and III need no special params. Seasons are tried
**2026 first, then 2025** (most-relevant-first); a player is written once, from
the first season whose roster matches them.

RESUMABLE / POLITE
------------------
  - Resume list: data/cache/ncaa_d23_done.json -- a list of scraped team
    identifiers (the DB `from_school` string). A re-run skips finished teams.
  - Raw roster HTML cached under data/cache/ncaa_d23_raw/<school_id>_<instance>.html
    so re-runs (and audits) don't re-hit the site.
  - Separate school_id / instance caches (data/cache/ncaa_d23_school_ids.json,
    ...instance_ids.json) so we never collide with the D1 production caches.
  - Writes incrementally (append per team) to the output CSV.
  - ~1 req/sec polite delay, descriptive UA inherited from the shared session.

OUTPUT
------
  data/643_exports/bio/ncaa_d23.csv with columns:
    player, team, season, height_in, weight_lb (blank), bats, throws,
    class_year, position, hometown, high_school
  `player`/`team` are the DB strings (clean join key back onto `players`).

USAGE
-----
    python scripts/fetch_ncaa_bio_d23.py                 # all source-gap teams
    python scripts/fetch_ncaa_bio_d23.py --limit 10      # cap teams (debug)
    python scripts/fetch_ncaa_bio_d23.py --no-headless   # watch the browser
    python scripts/fetch_ncaa_bio_d23.py --diagnose-only # print the gap split, no scrape

Internal USD evaluation only -- respect source ToS, rate-limit, cache.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
import time
from pathlib import Path

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# reuse the production D1 scraper's machinery (module has no import side effects)
import importlib.util as _ilu

_spec = _ilu.spec_from_file_location("fetch_ncaa_bio", str(ROOT / "scripts" / "fetch_ncaa_bio.py"))
_fnb = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_fnb)  # type: ignore

from ncaa.portal.util import (  # noqa: E402
    normalize_name, parse_hometown, parse_height_to_inches,
)

NcaaSession = _fnb.NcaaSession
build_org_directory = _fnb.build_org_directory
build_label_indexes = _fnb.build_label_indexes
resolve_school_id = _fnb.resolve_school_id
discover_instances = _fnb.discover_instances
match_roster_to_export = _fnb.match_roster_to_export
_load_json = _fnb._load_json
_save_json = _fnb._save_json
_polite = _fnb._polite
BASE = _fnb.BASE
SEASON_LABELS = _fnb.SEASON_LABELS

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DB_PATH = ROOT / "db" / "baseball.db"
DATA_DIR = ROOT / "data"
EXPORT_DIR = DATA_DIR / "643_exports"
BIO_DIR = EXPORT_DIR / "bio"
CACHE_DIR = DATA_DIR / "cache"
RAW_DIR = CACHE_DIR / "ncaa_d23_raw"

OUT_CSV = BIO_DIR / "ncaa_d23.csv"
DONE_FILE = CACHE_DIR / "ncaa_d23_done.json"          # [from_school, ...] already scraped
SCHOOL_ID_CACHE = CACHE_DIR / "ncaa_d23_school_ids.json"   # {from_school: {school_id,ncaa_label,how}}
INSTANCE_CACHE = CACHE_DIR / "ncaa_d23_instance_ids.json"  # {school_id: {label: instance}}
# Alias inputs: the canonical map shared with the D1 scraper, plus a
# D2/D3-specific map (curated NCAA labels for formal D2/D3 names that diverge too
# far for token-fuzzy; null = program not in the NCAA MBA directory).
ALIAS_FILE = DATA_DIR / "ncaa_cache" / "team_aliases.json"
ALIAS_FILE_D23 = CACHE_DIR / "ncaa_d23_aliases.json"

# D2/D3 schools play in spring of 2026/2025; try most-relevant first.
SEASON_ORDER = [2026, 2025]

OUT_COLS = ["player", "team", "season", "height_in", "weight_lb", "bats",
            "throws", "class_year", "position", "hometown", "high_school"]

BIO_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)
RAW_DIR.mkdir(parents=True, exist_ok=True)

# Words stripped so DB `from_school` ('Limestone University') matches
# player_bio.team ('Limestone'). Mirrors fetch_ncaa_bio._norm_team + suffix folds.
_STRIP = {"university", "college", "the", "of", "at"}


def _norm_school(name: str | None) -> str:
    if name is None:
        return ""
    base = _fnb._norm_team(str(name))   # reuse the production normalizer (state abbrs etc.)
    toks = [t for t in base.split() if t not in _STRIP]
    return " ".join(toks).strip()


def _strip_suffix_name(name: str) -> str:
    """A loose-but-legible team string with 'University'/'College'/etc removed,
    so DB formal names ('Barry University') feed the resolver as the NCAA's short
    label ('Barry'). Also drops a trailing parenthetical state disambiguator and
    flips 'X, Campus' to 'X Campus' (NCAA writes 'Cal St. San Marcos')."""
    s = str(name)
    s = re.sub(r"\s*\([^)]*\)\s*$", "", s)          # 'Crown College (Minnesota)' -> 'Crown College'
    s = s.replace(",", " ")                           # 'Cal State University, San Marcos'
    toks = [t for t in re.split(r"\s+", s) if t]
    keep = [t for t in toks if t.lower().strip(".") not in _STRIP]
    return " ".join(keep).strip() or s


def resolve_d23(team, aliases, exact, by_norm):
    """resolve_school_id, but retry on a suffix-stripped name when the formal DB
    string ('Barry University') misses the NCAA short label ('Barry'). Returns
    the same (school_id, ncaa_label, how) tuple; `how` gains a '-sfx' suffix when
    the stripped retry is what hit."""
    sid, label, how = resolve_school_id(team, aliases, exact, by_norm)
    if sid is not None:
        return sid, label, how
    stripped = _strip_suffix_name(team)
    if stripped and stripped.lower() != str(team).lower():
        sid2, label2, how2 = resolve_school_id(stripped, aliases, exact, by_norm)
        if sid2 is not None:
            return sid2, label2, f"{how2}-sfx"
    return sid, label, how


# ---------------------------------------------------------------------------
# Diagnosis: which source-gap teams + their players need scraping
# ---------------------------------------------------------------------------
def diagnose():
    """Return (source_gap, matching_gap) where each is a list of
    {from_school, division, players:[full_name...]}. source_gap = teams NOT in
    player_bio (need a scrape); matching_gap = teams already in player_bio
    (handled by the ER subagent, skipped here)."""
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    bio_norms: set[str] = set()
    for (t,) in cur.execute("select distinct team from player_bio where team is not null"):
        bio_norms.add(_norm_school(t))

    rows = cur.execute("""
        select p.from_school, p.division, p.full_name
        from players p
        where p.current_status='ENTERED' and p.division in ('II','III')
          and not exists (select 1 from player_bio b where b.player_id=p.player_id)
        order by p.from_school
    """).fetchall()
    con.close()

    by_team: dict[str, dict] = {}
    for fs, dv, name in rows:
        key = fs or ""
        d = by_team.setdefault(key, {"from_school": fs, "division": dv, "players": []})
        if name:
            d["players"].append(name)

    source_gap, matching_gap = [], []
    for key, d in by_team.items():
        n = _norm_school(d["from_school"])
        (matching_gap if (n and n in bio_norms) else source_gap).append(d)

    source_gap.sort(key=lambda d: -len(d["players"]))
    matching_gap.sort(key=lambda d: -len(d["players"]))
    return source_gap, matching_gap


# ---------------------------------------------------------------------------
# Roster fetch (cached raw HTML) + parse incl. Position
# ---------------------------------------------------------------------------
def fetch_roster_html(sess: NcaaSession, instance_id: int, school_id: int) -> str:
    raw_path = RAW_DIR / f"{school_id}_{instance_id}.html"
    if raw_path.exists():
        return raw_path.read_text(encoding="utf-8")
    html = sess.get_html(f"{BASE}/teams/{instance_id}/roster")
    raw_path.write_text(html, encoding="utf-8")
    _polite()
    return html


def parse_roster(html: str) -> list[dict]:
    """Like fetch_ncaa_bio.fetch_team_roster's parser, plus a Position column."""
    soup = BeautifulSoup(html, "lxml")
    table = header = None
    for t in soup.find_all("table"):
        body = t.find("tbody")
        if not (body and body.find_all("tr")):
            continue
        heads = [th.get_text(strip=True) for th in t.find_all("th")]
        if "Height" in heads and "Name" in heads:
            table, header = t, heads
            break
    if table is None:
        return []
    idx = {h: i for i, h in enumerate(header)}
    pos_key = next((k for k in ("Position", "Pos", "Pos.") if k in idx), None)
    rows: list[dict] = []
    for tr in table.find("tbody").find_all("tr"):
        cells = [td.get_text(strip=True) for td in tr.find_all("td")]
        if len(cells) < len(header):
            continue
        home_raw = cells[idx["Hometown"]] if "Hometown" in idx else None
        hs_raw = cells[idx["High School"]] if "High School" in idx else None
        home_city, home_state = parse_hometown(home_raw)
        hometown = None
        if home_city or home_state:
            hometown = ", ".join([x for x in (home_city, home_state) if x])
        rows.append({
            "Player": cells[idx["Name"]],
            "height_in": parse_height_to_inches(cells[idx["Height"]]),
            "class_year": cells[idx["Class"]] if "Class" in idx else None,
            "bats": cells[idx["Bats"]] if "Bats" in idx else None,
            "throws": cells[idx["Throws"]] if "Throws" in idx else None,
            "position": cells[idx[pos_key]] if pos_key else None,
            "hometown": hometown,
            "high_school": (hs_raw or None),
        })
    return rows


# ---------------------------------------------------------------------------
# CSV / resume helpers
# ---------------------------------------------------------------------------
def ensure_header(path: Path):
    if path.exists():
        try:
            existing = next(csv.reader(path.open(newline="", encoding="utf-8")))
        except StopIteration:
            existing = []
        if existing != OUT_COLS:
            bak = path.with_suffix(path.suffix + ".bak")
            print(f"  ! {path.name}: header changed -> rotating to {bak.name}")
            path.replace(bak)
    if not path.exists():
        with path.open("w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(OUT_COLS)


def append_rows(path: Path, rows: list[list]):
    with path.open("a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def run(limit, headless, diagnose_only):
    source_gap, matching_gap = diagnose()
    sg_players = sum(len(d["players"]) for d in source_gap)
    mg_players = sum(len(d["players"]) for d in matching_gap)
    print("================= D2/D3 NO-BIO DIAGNOSIS =================")
    print(f"MATCHING-GAP teams (already in player_bio, ER handles): "
          f"{len(matching_gap)} teams / {mg_players} players  -> SKIP")
    print(f"SOURCE-GAP teams (absent from player_bio, scrape):      "
          f"{len(source_gap)} teams / {sg_players} players  -> SCRAPE")
    print("=========================================================\n")
    if diagnose_only:
        for d in source_gap:
            print(f"  [{d['division']}] {len(d['players']):3d}  {d['from_school']!r}")
        return

    aliases_raw = _load_json(ALIAS_FILE, {})
    aliases = {k: v for k, v in aliases_raw.items() if not k.startswith("_")}
    # D2/D3-specific aliases take precedence over the shared canonical map
    d23_raw = _load_json(ALIAS_FILE_D23, {})
    aliases.update({k: v for k, v in d23_raw.items() if not k.startswith("_")})

    teams = source_gap[:limit] if limit else source_gap

    sess = NcaaSession(headless=headless)
    school_cache = _load_json(SCHOOL_ID_CACHE, {})
    instance_cache = _load_json(INSTANCE_CACHE, {})
    done = set(_load_json(DONE_FILE, []))

    ensure_header(OUT_CSV)

    stat = {"scraped": 0, "skip_done": 0, "rows": 0, "with_height": 0,
            "with_hometown": 0, "unresolved": [], "no_instance": [], "no_match": []}
    # patch the production discover_instances to use OUR instance cache file
    _fnb.INSTANCE_CACHE_FILE = INSTANCE_CACHE

    try:
        directory = build_org_directory(sess)
        exact, by_norm = build_label_indexes(directory)
        print(f"Org directory: {len(directory)} MBA programs (all divisions)\n")

        for i, d in enumerate(teams, 1):
            team = d["from_school"]
            players = d["players"]
            if team in done:
                stat["skip_done"] += 1
                continue

            # resolve school_id (cached)
            if team in school_cache:
                sc = school_cache[team]
                sid, label, how = sc["school_id"], sc["ncaa_label"], sc["how"]
            else:
                sid, label, how = resolve_d23(team, aliases, exact, by_norm)
                school_cache[team] = {"school_id": sid, "ncaa_label": label, "how": how}
                _save_json(SCHOOL_ID_CACHE, school_cache)

            if sid is None:
                stat["unresolved"].append(f"{team} [{how}]")
                # don't mark done -> a future alias add can recover it cheaply
                continue

            inst_map = discover_instances(sess, sid, instance_cache)

            # Collect each player's bio across BOTH seasons (2026 first, then
            # 2025). Portal-ENTERED players have usually left the program, so they
            # often live on the PRIOR (2025) roster rather than the current (2026)
            # one -- never stop at the first season with a match. Each player is
            # written once, preferring the most recent season they appear in.
            best: dict[str, tuple[int, dict]] = {}   # player -> (season, bio)
            for season in SEASON_ORDER:
                instance = inst_map.get(SEASON_LABELS[season])
                if instance is None:
                    continue
                try:
                    html = fetch_roster_html(sess, instance, sid)
                    roster = parse_roster(html)
                except Exception as e:
                    stat["no_instance"].append(f"{team} [{season} roster error: {e!r}]")
                    continue
                if not roster:
                    continue
                matched = match_roster_to_export(players, roster)
                for ep, bio in matched.items():
                    if ep not in best:        # SEASON_ORDER is newest-first
                        best[ep] = (season, bio)

            rows = []
            for ep in players:
                if ep not in best:
                    continue
                season, bio = best[ep]
                hometown = bio.get("hometown")
                rows.append([
                    ep, team, season,
                    bio.get("height_in"),
                    "",                       # weight_lb: NCAA has none
                    bio.get("bats"),
                    bio.get("throws"),
                    bio.get("class_year"),
                    bio.get("position"),
                    hometown,
                    bio.get("high_school"),
                ])
                stat["rows"] += 1
                if bio.get("height_in") is not None:
                    stat["with_height"] += 1
                if hometown:
                    stat["with_hometown"] += 1
            wrote_for_team = len(rows)
            if rows:
                append_rows(OUT_CSV, rows)

            stat["scraped"] += 1
            done.add(team)
            _save_json(DONE_FILE, sorted(done))

            if wrote_for_team == 0:
                stat["no_match"].append(team)
            if i % 10 == 0 or wrote_for_team:
                print(f"  [{i}/{len(teams)}] {team} (sid={sid}, {how}): "
                      f"{wrote_for_team}/{len(players)} players matched")

        # ---- report ----
        print("\n================= D2/D3 SCRAPE SUMMARY =================")
        print(f"teams considered (source-gap): {len(teams)}")
        print(f"  scraped this run:            {stat['scraped']}")
        print(f"  skipped (already done):      {stat['skip_done']}")
        print(f"rows written:                  {stat['rows']}")
        print(f"  with height:                 {stat['with_height']}")
        print(f"  with hometown:               {stat['with_hometown']}")
        print(f"teams w/ roster but 0 matches: {len(stat['no_match'])}")
        print(f"teams unresolved (no school):  {len(stat['unresolved'])}")
        if stat["unresolved"]:
            print("    " + "; ".join(stat["unresolved"][:40]))
        print(f"output CSV: {OUT_CSV}")
        print("========================================================")
    finally:
        sess.close()


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="NCAA D2/D3 source-gap bio recovery")
    ap.add_argument("--limit", type=int, default=None, help="cap teams (debug)")
    ap.add_argument("--no-headless", action="store_true", help="show the browser")
    ap.add_argument("--diagnose-only", action="store_true",
                    help="print the matching-gap vs source-gap split and exit (no scrape)")
    args = ap.parse_args()
    run(args.limit, headless=not args.no_headless, diagnose_only=args.diagnose_only)


if __name__ == "__main__":
    main()
