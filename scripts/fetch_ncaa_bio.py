"""
fetch_ncaa_bio.py  (PRODUCTION)
===============================

Acquire NCAA baseball player HEIGHT (+ Class / Bats / Throws) by SEASON
(2026, 2025, 2024) for the ~9-11k distinct (Player, Team) pairs already held in
the staged 6-4-3 exports, and write one bio CSV per season that joins straight
back onto those exports.

PIPELINE
--------
  1. Read unique Team values per season from the staged exports:
       hitters : data/643_exports/hitters_<season>_overall.csv   (col `Team`)
       pitchers: data/643_exports/pitching/pitchers_<season>.csv  (col `Team`)
     Union the team sets per season. (Pitchers repeat one row per pitch type;
     we de-dup to distinct (Team, Player).)
  2. For each (team, season): resolve team -> school_id, season -> instance id,
     fetch the modern roster, parse Height "6-2" -> inches (+ class/bats/throws).
  3. Match roster players to the export players for that (team, season) by
     normalized name (src.portal.util.normalize_name), with a token-overlap
     fuzzy fallback for accents/suffixes/initials.
  4. Write data/643_exports/bio/ncaa_heights_<season>.csv with columns
       player, team, season, height_in, class_year, bats, throws
     where player/team are the EXPORT's strings (clean join key).

RESILIENCE / POLITENESS
-----------------------
  - Processes 2026 first, then 2025, then 2024 (most-relevant-first).
  - FLUSHES per team (append) to the per-season CSV, so an interrupted run
    keeps everything done so far.
  - Caches resolved school_id (per team name) and instance-id maps (per school)
    to data/ncaa_cache/, so a re-run resumes cheaply and skips teams already
    written for that season.
  - Jittered ~2-3s delay between live page loads; reuses one stealth browser.
  - Hand-curated alias overrides in data/ncaa_cache/team_aliases.json. A null
    alias = a non-NCAA program (JUCO/NAIA/data artifact) -> skipped cleanly.

NCAA rosters carry Height/Bats/Throws/Class/Position/Hometown/HS but NO WEIGHT.
Internal USD evaluation use only.

USAGE
-----
    python scripts/fetch_ncaa_bio.py                 # all seasons, 2026 first
    python scripts/fetch_ncaa_bio.py --season 2026   # one season
    python scripts/fetch_ncaa_bio.py --limit 25      # cap teams/season (debug)
    python scripts/fetch_ncaa_bio.py --no-headless   # watch the browser
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import re
import sys
import time
from pathlib import Path

import pandas as pd
from bs4 import BeautifulSoup

# project import: reuse the canonical name normalizer
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ncaa.portal.util import normalize_name, parse_height_to_inches, parse_hometown  # noqa: E402

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BASE = "https://stats.ncaa.org"
SPORT_CODE = "MBA"

import os

DATA_DIR = ROOT / "data"
EXPORT_DIR = DATA_DIR / "643_exports"
PITCHING_DIR = EXPORT_DIR / "pitching"
CACHE_DIR = DATA_DIR / "ncaa_cache"

# Output dirs can be redirected via env (e.g. to a Temp dir that survives the
# harness's per-turn working-tree restore, when run as a detached background
# process). Inputs (the exports + org directory) always read from DATA_DIR.
BIO_DIR = Path(os.environ.get("NCAA_BIO_OUT_DIR", str(EXPORT_DIR / "bio")))
_CACHE_OUT = Path(os.environ.get("NCAA_CACHE_OUT_DIR", str(CACHE_DIR)))

ORG_DIR_FILE = DATA_DIR / "ncaa_org_directory_MBA.json"
INSTANCE_CACHE_FILE = _CACHE_OUT / "instance_ids.json"     # {school_id: {label: instance}}
SCHOOL_ID_CACHE_FILE = _CACHE_OUT / "school_ids.json"      # {team_name: {"school_id":..,"ncaa_label":..,"how":..}}
# alias overrides are an INPUT — always from the canonical cache dir
ALIAS_FILE = CACHE_DIR / "team_aliases.json"               # {export_team: ncaa_label | null}

# any legacy season-id seed; the team page it lands on still renders the full
# <select name="year_id"> dropdown (every season -> instance id) for the school.
LEGACY_SEED = 16340

# season (spring year) -> stats.ncaa.org dropdown label
SEASON_LABELS = {2024: "2023-24", 2025: "2024-25", 2026: "2025-26"}
SEASON_ORDER = [2026, 2025, 2024]  # most relevant first

MIN_DELAY, MAX_DELAY = 2.0, 3.0

BIO_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)
_CACHE_OUT.mkdir(parents=True, exist_ok=True)

OUT_COLS = ["player", "team", "season", "height_in", "class_year", "bats", "throws",
            "hometown_city", "hometown_state", "high_school"]


# ---------------------------------------------------------------------------
# Browser session
# ---------------------------------------------------------------------------
class NcaaSession:
    def __init__(self, headless: bool = True):
        from cloakbrowser import launch
        self._browser = launch(headless=headless)
        self._page = self._browser.new_page()
        self._page.goto(f"{BASE}/", wait_until="domcontentloaded", timeout=45000)

    def get_html(self, url: str) -> str:
        self._page.goto(url, wait_until="domcontentloaded", timeout=45000)
        return self._page.content()

    def get_json(self, url: str):
        return self._page.request.get(url).json()

    def close(self):
        try:
            self._browser.close()
        except Exception:
            pass


def _polite():
    time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))


# ---------------------------------------------------------------------------
# JSON cache helpers
# ---------------------------------------------------------------------------
def _load_json(path: Path, default):
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default
    return default


def _save_json(path: Path, obj):
    path.write_text(json.dumps(obj, indent=0, ensure_ascii=False), encoding="utf-8")


# ---------------------------------------------------------------------------
# Parsing — parse_height_to_inches now lives in src/portal/util.py (shared with
# the Sidearm bio adapter so heights are read identically everywhere).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Step 1: org directory + team -> school_id resolution
# ---------------------------------------------------------------------------
def build_org_directory(sess: NcaaSession | None, refresh: bool = False) -> list[dict]:
    if ORG_DIR_FILE.exists() and not refresh:
        return _load_json(ORG_DIR_FILE, [])
    if sess is None:
        raise RuntimeError("org directory missing and no session to fetch it")
    data = sess.get_json(f"{BASE}/team/search?sport_code={SPORT_CODE}")
    _save_json(ORG_DIR_FILE, data)
    return data


# NCAA abbreviates state/region words in its directory labels ("Central Mich.",
# "Western Caro.", "Southern Ill."). Map both the abbreviation and the full word
# to one canonical token so an export name and the NCAA label normalize equal.
_ABBR_CANON = {
    # state/region (NCAA abbr . stripped of period by the [^a-z0-9] pass)
    "ala": "alabama", "alas": "alaska", "ariz": "arizona", "ark": "arkansas",
    "caro": "carolina", "colo": "colorado", "conn": "connecticut",
    "fla": "florida", "ga": "georgia", "ill": "illinois", "ind": "indiana",
    "ky": "kentucky", "la": "louisiana", "mass": "massachusetts", "me": "maine",
    "mich": "michigan", "minn": "minnesota", "miss": "mississippi",
    "mo": "missouri", "mont": "montana", "neb": "nebraska", "okla": "oklahoma",
    "ore": "oregon", "tenn": "tennessee", "tex": "texas", "va": "virginia",
    "wash": "washington", "wis": "wisconsin",
    # direction / common words NCAA shortens
    "so": "southern", "east": "eastern",
    "col": "college", "dist": "district", "mt": "mount", "u": "university",
    "univ": "university", "st": "st",  # 'St.' already folded to 'st' below
}


def _norm_team(name: str) -> str:
    """Loose team-name normalizer for matching export strings to NCAA labels.

    Folds 'State'->'st', strips punctuation, then canonicalizes NCAA's standard
    state/region abbreviations (Mich.->michigan, Caro.->carolina, ...) so both
    sides of the match collapse to the same tokens.
    """
    s = name.lower()
    s = re.sub(r"\bstate\b", "st", s)
    s = re.sub(r"\bst\.?\b", "st", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    toks = [_ABBR_CANON.get(t, t) for t in s.split()]
    return " ".join(toks).strip()


def build_label_indexes(directory: list[dict]):
    exact: dict[str, int] = {}
    by_norm: dict[str, list[tuple[str, int]]] = {}
    for d in directory:
        label = d["label"].rsplit(" - ", 1)[0]
        exact[label] = d["value"]
        by_norm.setdefault(_norm_team(label), []).append((label, d["value"]))
    return exact, by_norm


def resolve_school_id(team_name, aliases, exact, by_norm):
    """
    Return (school_id, ncaa_label, how). how in
    {'alias','exact','fuzzy'}. Returns (None, None, 'skip-nonNCAA') when the
    alias map explicitly marks the team as a non-NCAA program (null), or
    (None, None, 'unresolved') when nothing matches.
    """
    if team_name in aliases:
        want = aliases[team_name]
        if want is None:
            return None, None, "skip-nonNCAA"
        if want in exact:
            return exact[want], want, "alias"
        # alias target itself may need a norm match
        nt = _norm_team(want)
        if nt in by_norm:
            lab, sid = by_norm[nt][0]
            return sid, lab, "alias"
        return None, None, "alias-target-missing"

    nt = _norm_team(team_name)
    if nt in by_norm:
        lab, sid = by_norm[nt][0]
        return sid, lab, "exact"

    # SAFE fuzzy fallback (token-subset, not naive prefix). A naive
    # nl.startswith(nt)/nt.startswith(nl) wrongly collapses "Florida Atlantic"
    # -> "Florida", "Eastern Illinois" -> "Eastern", "Arkansas-Pine Bluff" ->
    # "Arkansas", etc. Instead require token-set containment with a guard so a
    # single-token directory label can never absorb a multi-token export name:
    #   - export tokens superset-of label tokens, label has >= 2 tokens, OR
    #   - label tokens superset-of export tokens, export has >= 2 tokens
    # Ambiguous (>1 candidate) or single-token-only overlaps are left for the
    # alias map (intentional 'unresolved' so they surface in the report).
    et = set(nt.split())
    if et:
        cands = []
        for nl, lst in by_norm.items():
            lt = set(nl.split())
            if not lt:
                continue
            if (lt <= et and len(lt) >= 2) or (et <= lt and len(et) >= 2):
                cands.append(lst[0])
        uniq = {sid: lab for lab, sid in cands}  # dedup by school_id
        if len(uniq) == 1:
            sid, lab = next(iter(uniq.items()))
            return sid, lab, "fuzzy"
    return None, None, "unresolved"


# ---------------------------------------------------------------------------
# Step 2: school_id -> per-season instance ids (year_id dropdown, cached)
# ---------------------------------------------------------------------------
def discover_instances(sess: NcaaSession, school_id: int, instance_cache: dict) -> dict:
    key = str(school_id)
    if key in instance_cache:
        return instance_cache[key]
    html = sess.get_html(f"{BASE}/team/{school_id}/roster/{LEGACY_SEED}")
    soup = BeautifulSoup(html, "lxml")
    sel = soup.find("select", attrs={"name": "year_id"})
    mapping = {}
    if sel:
        for opt in sel.find_all("option"):
            val = opt.get("value")
            if val and str(val).isdigit():
                mapping[opt.get_text(strip=True)] = int(val)
    instance_cache[key] = mapping
    _save_json(INSTANCE_CACHE_FILE, instance_cache)
    _polite()
    return mapping


# ---------------------------------------------------------------------------
# Step 3: instance_id -> roster rows
# ---------------------------------------------------------------------------
def fetch_team_roster(sess: NcaaSession, instance_id: int) -> list[dict]:
    html = sess.get_html(f"{BASE}/teams/{instance_id}/roster")
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
    rows: list[dict] = []
    if table is None:
        _polite()
        return rows
    idx = {h: i for i, h in enumerate(header)}
    for tr in table.find("tbody").find_all("tr"):
        cells = [td.get_text(strip=True) for td in tr.find_all("td")]
        if len(cells) < len(header):
            continue
        ht_raw = cells[idx["Height"]]
        # Hometown / High School live on the same roster table (header:
        # [..., Height, Bats, Throws, Hometown, High School]); column is
        # absent for some programs, so guard every lookup.
        home_raw = cells[idx["Hometown"]] if "Hometown" in idx else None
        hs_raw = cells[idx["High School"]] if "High School" in idx else None
        home_city, home_state = parse_hometown(home_raw)
        rows.append({
            "Player": cells[idx["Name"]],
            "height_in": parse_height_to_inches(ht_raw),
            "class_year": cells[idx["Class"]] if "Class" in idx else None,
            "bats": cells[idx["Bats"]] if "Bats" in idx else None,
            "throws": cells[idx["Throws"]] if "Throws" in idx else None,
            "hometown_city": home_city,
            "hometown_state": home_state,
            "high_school": (hs_raw or None),
        })
    _polite()
    return rows


# ---------------------------------------------------------------------------
# Step 4: export players + name matching
# ---------------------------------------------------------------------------
def load_export_players_by_season() -> dict[int, dict[str, list[str]]]:
    """{season: {team: [export player strings...]}} (distinct per team)."""
    out: dict[int, dict[str, list[str]]] = {}
    for season in SEASON_ORDER:
        h = pd.read_csv(EXPORT_DIR / f"hitters_{season}_overall.csv",
                        usecols=["Team", "Player"])
        p = pd.read_csv(PITCHING_DIR / f"pitchers_{season}.csv",
                        usecols=["Team", "Player"])
        both = pd.concat([h, p], ignore_index=True).dropna(subset=["Team", "Player"])
        both = both.drop_duplicates(["Team", "Player"])
        by_team: dict[str, list[str]] = {}
        for team, grp in both.groupby("Team"):
            by_team[str(team)] = list(dict.fromkeys(grp["Player"].astype(str)))
        out[season] = by_team
    return out


def _token_set(name: str) -> set[str]:
    return set(normalize_name(name).split())


def match_roster_to_export(export_players, roster):
    """
    Map each export player -> roster bio via normalized name, with a
    token-overlap fuzzy fallback (handles accents, suffixes, dropped middle
    names/initials). Returns {export_player: bio_dict}.
    """
    # index roster by exact normalized name (first wins) + keep token sets
    norm_index: dict[str, dict] = {}
    roster_tokens: list[tuple[set[str], dict]] = []
    for r in roster:
        nm = normalize_name(r["Player"])
        if nm and nm not in norm_index:
            norm_index[nm] = r
        roster_tokens.append((_token_set(r["Player"]), r))

    matched: dict[str, dict] = {}
    for ep in export_players:
        en = normalize_name(ep)
        if en in norm_index:
            matched[ep] = norm_index[en]
            continue
        et = set(en.split())
        if not et:
            continue
        best, best_score = None, 0.0
        for rt, r in roster_tokens:
            if not rt:
                continue
            inter = len(et & rt)
            if inter == 0:
                continue
            # symmetric overlap; require a strong overlap to avoid false joins
            score = inter / max(len(et), len(rt))
            if score > best_score:
                best, best_score = r, score
        # last-name + first-initial agreement is the practical bar
        if best is not None and best_score >= 0.5:
            matched[ep] = best
    return matched


# ---------------------------------------------------------------------------
# CSV flush helpers (append per team)
# ---------------------------------------------------------------------------
def season_csv(season: int) -> Path:
    return BIO_DIR / f"ncaa_heights_{season}.csv"


def ensure_csv_header(path: Path):
    # If a CSV from an older column set exists (e.g. a height-only run before the
    # Hometown/HS columns were added), rotate it to .bak and start fresh so we
    # don't append wide rows under a narrow header. The school_id/instance caches
    # still make the re-run cheap (only roster pages reload).
    if path.exists():
        try:
            existing = next(csv.reader(path.open(newline="", encoding="utf-8")))
        except StopIteration:
            existing = []
        if existing != OUT_COLS:
            bak = path.with_suffix(path.suffix + ".bak")
            print(f"  ! {path.name}: header changed -> rotating old file to {bak.name}")
            path.replace(bak)
    if not path.exists():
        with path.open("w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(OUT_COLS)


def teams_already_written(path: Path) -> set[str]:
    done: set[str] = set()
    if not path.exists():
        return done
    try:
        df = pd.read_csv(path, usecols=["team"])
        done = set(df["team"].dropna().astype(str).unique())
    except Exception:
        pass
    return done


def append_rows(path: Path, rows: list[list]):
    with path.open("a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def run(seasons, limit, headless):
    aliases_raw = _load_json(ALIAS_FILE, {})
    aliases = {k: v for k, v in aliases_raw.items() if not k.startswith("_")}

    export_by_season = load_export_players_by_season()

    sess = NcaaSession(headless=headless)
    school_cache = _load_json(SCHOOL_ID_CACHE_FILE, {})
    instance_cache = _load_json(INSTANCE_CACHE_FILE, {})
    try:
        directory = build_org_directory(sess)
        exact, by_norm = build_label_indexes(directory)
        print(f"Org directory: {len(directory)} MBA programs\n")

        summary = {}
        failed_teams: dict[int, list[str]] = {}

        for season in seasons:
            label = SEASON_LABELS[season]
            by_team = export_by_season[season]
            teams = sorted(by_team.keys())
            if limit:
                teams = teams[:limit]

            out_path = season_csv(season)
            ensure_csv_header(out_path)
            done = teams_already_written(out_path)

            total_players = sum(len(by_team[t]) for t in by_team)
            print(f"=== SEASON {season} ({label}) : {len(teams)} teams, "
                  f"{total_players} export players ===")

            failed_teams[season] = []
            n_skip_nonncaa = 0

            for i, team in enumerate(teams, 1):
                if team in done:
                    continue
                players = by_team[team]

                # --- resolve school_id (cached) ---
                if team in school_cache:
                    sc = school_cache[team]
                    sid, ncaa_label, how = sc["school_id"], sc["ncaa_label"], sc["how"]
                else:
                    sid, ncaa_label, how = resolve_school_id(team, aliases, exact, by_norm)
                    school_cache[team] = {"school_id": sid, "ncaa_label": ncaa_label, "how": how}
                    _save_json(SCHOOL_ID_CACHE_FILE, school_cache)

                if sid is None:
                    if how == "skip-nonNCAA":
                        n_skip_nonncaa += 1
                    else:
                        failed_teams[season].append(f"{team} [{how}]")
                    # write nothing for these players this season; mark team done
                    # by writing zero rows is not enough (teams_already_written keys
                    # off rows) -> we just skip; re-run will retry resolution cheaply.
                    continue

                # --- resolve instance id for this season (cached) ---
                inst_map = discover_instances(sess, sid, instance_cache)
                instance = inst_map.get(label)
                if instance is None:
                    failed_teams[season].append(f"{team} [no {label} instance, sid={sid}]")
                    continue

                # --- fetch roster + match ---
                try:
                    roster = fetch_team_roster(sess, instance)
                except Exception as e:
                    failed_teams[season].append(f"{team} [roster error: {e!r}]")
                    continue

                matched = match_roster_to_export(players, roster)

                rows = []
                for ep in players:
                    bio = matched.get(ep)
                    if bio is None:
                        continue
                    rows.append([
                        ep, team, season,
                        bio.get("height_in"),
                        bio.get("class_year"),
                        bio.get("bats"),
                        bio.get("throws"),
                        bio.get("hometown_city"),
                        bio.get("hometown_state"),
                        bio.get("high_school"),
                    ])
                # flush per team (only rows that got a bio with any field)
                if rows:
                    append_rows(out_path, rows)

                if i % 25 == 0 or rows:
                    n_ht = sum(1 for r in rows if r[3] is not None)
                    print(f"  [{i}/{len(teams)}] {team} (sid={sid}, {how}): "
                          f"{len(roster)} roster, {len(rows)}/{len(players)} matched, "
                          f"{n_ht} w/height")

            # --- per-season coverage ---
            df = pd.read_csv(out_path) if out_path.exists() else pd.DataFrame(columns=OUT_COLS)
            with_height = df["height_in"].notna().sum() if len(df) else 0
            matched_rows = len(df)
            summary[season] = {
                "export_players": total_players,
                "matched_rows": int(matched_rows),
                "with_height": int(with_height),
                "skip_nonNCAA_teams": n_skip_nonncaa,
                "failed_teams": failed_teams[season],
                "csv": str(out_path),
            }
            print(f"  -> {season}: matched {matched_rows}, with height {with_height} "
                  f"({100*with_height/total_players:.1f}% of {total_players} export players)\n")

        # ------- final report -------
        print("\n================= COVERAGE SUMMARY =================")
        for season in seasons:
            s = summary[season]
            cov = 100 * s["with_height"] / s["export_players"] if s["export_players"] else 0
            print(f"{season}: {s['with_height']}/{s['export_players']} export players "
                  f"have a height ({cov:.1f}%)  | matched rows {s['matched_rows']} "
                  f"| non-NCAA teams skipped {s['skip_nonNCAA_teams']}")
            print(f"        CSV: {s['csv']}")
            if s["failed_teams"]:
                print(f"        FAILED to resolve ({len(s['failed_teams'])}): "
                      f"{', '.join(s['failed_teams'])}")
        print("====================================================")
        return summary
    finally:
        sess.close()


def main():
    # line-buffer stdout so progress survives in a redirected log (python -u also works)
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="NCAA baseball height scraper -> per-season bio CSVs")
    ap.add_argument("--season", type=int, choices=SEASON_ORDER, default=None,
                    help="run a single season (default: all, 2026 first)")
    ap.add_argument("--limit", type=int, default=None,
                    help="cap number of teams per season (debug)")
    ap.add_argument("--no-headless", action="store_true", help="show the browser")
    args = ap.parse_args()

    seasons = [args.season] if args.season else SEASON_ORDER
    run(seasons, args.limit, headless=not args.no_headless)


if __name__ == "__main__":
    main()
