#!/usr/bin/env python3
"""Recover bio rows for ENTERED portal players who have NO ``player_bio`` row.

~3,200 ENTERED players carry no ``player_bio`` row, but most are not genuinely
missing data -- they simply failed an EXACT name match against bio rows we have
ALREADY scraped (e.g. DB "JT THOMPSON" vs CSV "JT Thompson", or the mangled DB
name "RAYMOND MT KEANE" vs "Raymond Keane"). This pure-local recovery finds each
no-bio player's team in the on-disk bio CSVs, fuzzy-matches their name against
that team's rows, and emits the matched bio fields to a CSV. A later exact-match
load attaches the values to the DB.

Candidate bio sources (richest first):
  - team_bio_full.csv          : player/team/season + height/WEIGHT/bats/throws/
                                  class/position/hometown(combined)/high_school
  - ncaa_heights_2026/25/24.csv: NCAA rows, height/class/bats/throws/hometown
                                  (city+state split)/high_school -- NO weight
  - ncaa_d23.csv               : newly scraped D2/D3, team_bio_full schema,
                                  no weight in practice

Method (conservative -- false matches are worse than misses):
  1. Normalize team names (lowercase; strip punctuation + noise tokens
     university/college/the/of/at/st/saint). Group candidate rows by that key,
     plus a suffix-stripped fallback key (drop one trailing state/abbrev token).
  2. For each no-bio player, look up their team's candidate rows (full key, then
     suffix-stripped fallback). Skip if the team is absent from all sources.
     Fuzzy-match full_name with rapidfuzz token_sort_ratio; strip the junk middle
     token "MT" from both sides first. Accept the best match only if
     score >= 88 AND it beats the 2nd-best by >= 6.
  3. PREFER a team_bio_full match (carries weight); only fall back to an
     ncaa/ncaa_d23 match when team_bio_full yields no accepted match. Among
     accepted candidate rows for the chosen source, keep the most-recent season.
  4. Emit recovered_er.csv (one row per recovered player). ``player`` = DB
     full_name verbatim so a later exact-match load re-attaches it.

Reads only. Does NOT write to the DB.
"""

from __future__ import annotations

import re
import sqlite3
from collections import Counter
from pathlib import Path

import pandas as pd
from rapidfuzz import fuzz, process

# --- paths -----------------------------------------------------------------
ROOT = Path(r"c:\Users\TrevorWhite\Downloads\Big Projects\baseball")
DB_PATH = ROOT / "db" / "baseball.db"
BIO_DIR = ROOT / "data" / "643_exports" / "bio"
OUT_CSV = BIO_DIR / "recovered_er.csv"

# team_bio_full is the only source with weight -> highest priority.
TEAM_BIO_FILES = ["team_bio_full.csv"]
# ncaa height tables + D2/D3 scrape: height/hometown/class/pos/bats/throws.
NCAA_FILES = [
    "ncaa_heights_2026.csv",
    "ncaa_heights_2025.csv",
    "ncaa_heights_2024.csv",
    "ncaa_d23.csv",
]

# --- acceptance thresholds -------------------------------------------------
MIN_SCORE = 88.0          # best match must score at least this
MIN_MARGIN = 6.0          # ...and beat the 2nd-best by at least this much

_TEAM_NOISE = {"university", "college", "the", "of", "at", "st", "saint"}
# US state names / abbreviations seen as trailing disambiguators in DB school
# names (e.g. "Albany State University (Georgia)" -> "albany state georgia").
# Used only to derive a *fallback* suffix-stripped team key.
_STATE_TOKENS = {
    "alabama", "alaska", "arizona", "arkansas", "california", "colorado",
    "connecticut", "delaware", "florida", "georgia", "hawaii", "idaho",
    "illinois", "indiana", "iowa", "kansas", "kentucky", "louisiana", "maine",
    "maryland", "massachusetts", "michigan", "minnesota", "mississippi",
    "missouri", "montana", "nebraska", "nevada", "ohio", "oklahoma", "oregon",
    "pennsylvania", "tennessee", "texas", "utah", "vermont", "virginia",
    "washington", "wisconsin", "wyoming", "carolina", "dakota", "hampshire",
    "jersey", "mexico", "york", "pa", "ny", "nj", "ca", "tx", "ga", "sc", "nc",
    "sd", "nd", "il", "oh", "pr",
}

# Junk middle token seen in DB full_name ingestion (e.g. "NOLAN MT FOSTER") and
# in ncaa_d23 rows ("MARTIN MT SANCHEZ"). Not part of the real name; inflates
# the token set under token_sort_ratio. Dropping it from BOTH sides is strictly
# more conservative (right matches go up, wrong matches do not).
_NAME_NOISE = {"mt"}


def norm_team(s: object) -> str:
    """Normalize a team/school name for grouping & matching."""
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return ""
    s = str(s).lower()
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    toks = [t for t in s.split() if t not in _TEAM_NOISE]
    return " ".join(toks)


def norm_team_suffix_stripped(nt: str) -> str:
    """Fallback key: drop a single trailing state/abbrev disambiguator token.

    "albany state georgia" -> "albany state"; "anderson sc" -> "anderson".
    Returns "" if nothing was stripped (so callers can tell it apart).
    """
    toks = nt.split()
    if len(toks) >= 2 and toks[-1] in _STATE_TOKENS:
        return " ".join(toks[:-1])
    return ""


def norm_name(s: object) -> str:
    """Normalize a player name for fuzzy comparison (drop punctuation/case/MT)."""
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return ""
    s = str(s).lower()
    s = re.sub(r"[^a-z0-9 ]", " ", s)  # "J.T." -> "j t", strips periods/commas
    toks = [t for t in s.split() if t not in _NAME_NOISE]
    return " ".join(toks)


def _clean(v: object) -> object:
    """Return None for NaN/empty cells, else the value."""
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    if isinstance(v, str) and v.strip() == "":
        return None
    return v


def _season_int(v: object) -> int:
    try:
        return int(float(str(v)))
    except (ValueError, TypeError):
        return -1


def _split_hometown(combined: object) -> tuple[object, object]:
    """Split a combined "City, ST" hometown into (city, state); else (combined, None)."""
    s = _clean(combined)
    if s is None:
        return None, None
    parts = str(s).rsplit(",", 1)
    if len(parts) == 2:
        return parts[0].strip() or None, parts[1].strip() or None
    return str(s).strip() or None, None


def load_source(fname: str, has_weight_schema: bool) -> dict[str, list[dict]]:
    """Load a bio CSV into {normalized_team: [normalized row dicts]}.

    Each row dict carries the unified output fields plus a normalized name and
    integer season for matching/ranking. ``has_weight_schema`` files use a
    combined ``hometown``; ncaa-height files use split ``hometown_city/state``.
    """
    path = BIO_DIR / fname
    df = pd.read_csv(path, dtype=str, keep_default_na=True)
    out: dict[str, list[dict]] = {}
    for rec in df.to_dict("records"):
        nt = norm_team(rec.get("team"))
        if not nt:
            continue
        name = _clean(rec.get("player"))
        if name is None:
            continue

        if "hometown_city" in rec or "hometown_state" in rec:
            city = _clean(rec.get("hometown_city"))
            state = _clean(rec.get("hometown_state"))
            hometown = None
            if city and state:
                hometown = f"{city}, {state}"
            elif city:
                hometown = city
            elif state:
                hometown = state
        else:
            hometown, _ = (str(_clean(rec.get("hometown"))), None) \
                if _clean(rec.get("hometown")) is not None else (None, None)

        row = {
            "_name_norm": norm_name(name),
            "_season_int": _season_int(rec.get("season")),
            "player_src": name,
            "team": _clean(rec.get("team")),
            "season": _clean(rec.get("season")),
            "height_in": _clean(rec.get("height_in")),
            "weight_lb": _clean(rec.get("weight_lb")) if has_weight_schema else None,
            "bats": _clean(rec.get("bats")),
            "throws": _clean(rec.get("throws")),
            "class_year": _clean(rec.get("class_year")),
            "position": _clean(rec.get("position")),
            "hometown": hometown,
            "high_school": _clean(rec.get("high_school")),
        }
        out.setdefault(nt, []).append(row)
    return out


def build_index(files: list[str], has_weight_schema: bool) -> dict[str, list[dict]]:
    """Merge multiple CSVs into one {team: [rows]} index."""
    merged: dict[str, list[dict]] = {}
    for f in files:
        if not (BIO_DIR / f).exists():
            print(f"  WARN: missing source {f}")
            continue
        src = load_source(f, has_weight_schema)
        for nt, rows in src.items():
            merged.setdefault(nt, []).extend(rows)
    return merged


def lookup_team(index: dict[str, list[dict]], full_key: str) -> list[dict]:
    """Return candidate rows for a team: try the full key, then suffix-stripped."""
    rows = index.get(full_key)
    if rows:
        return rows
    alt = norm_team_suffix_stripped(full_key)
    if alt:
        return index.get(alt, []) or []
    return []


def best_match(query: str, candidates: list[dict]) -> tuple[dict, float] | None:
    """Fuzzy-match ``query`` against candidate rows; return (row, score) or None.

    Accepts the best candidate only if score >= MIN_SCORE and it beats the
    2nd-best by >= MIN_MARGIN.
    """
    if not query or not candidates:
        return None
    cand_norm = [c["_name_norm"] for c in candidates]
    results = process.extract(
        query, cand_norm, scorer=fuzz.token_sort_ratio, limit=2
    )
    if not results:
        return None
    _, best_score, best_idx = results[0]
    second_score = results[1][1] if len(results) > 1 else 0.0
    if best_score < MIN_SCORE:
        return None
    if (best_score - second_score) < MIN_MARGIN:
        return None  # ambiguous -- two rows match nearly as well
    return candidates[best_idx], float(best_score)


def pick_recent(rows: list[dict]) -> dict:
    """Among rows that tied for the same matched player, keep most-recent season."""
    return max(rows, key=lambda r: r["_season_int"])


def main() -> None:
    print("Loading candidate bio sources ...")
    team_bio_idx = build_index(TEAM_BIO_FILES, has_weight_schema=True)
    ncaa_idx = build_index(NCAA_FILES, has_weight_schema=False)
    print(f"  team_bio_full teams : {len(team_bio_idx)}")
    print(f"  ncaa/ncaa_d23 teams : {len(ncaa_idx)}")

    # no-bio ENTERED players ------------------------------------------------
    con = sqlite3.connect(str(DB_PATH))
    con.row_factory = sqlite3.Row
    players = con.execute(
        "SELECT player_id, full_name, from_school, division FROM players p "
        "WHERE p.current_status='ENTERED' "
        "AND NOT EXISTS (SELECT 1 FROM player_bio b WHERE b.player_id=p.player_id)"
    ).fetchall()
    con.close()

    total = len(players)

    out_rows: list[dict] = []
    accepted_scores: list[float] = []
    examples: list[str] = []
    no_team = 0
    no_match = 0
    div_recovered: Counter = Counter()
    div_total: Counter = Counter()
    src_counts: Counter = Counter()

    for p in players:
        db_name = p["full_name"]
        division = p["division"]
        div_total[division] += 1
        team_key = norm_team(p["from_school"])
        query = norm_name(db_name)

        tb_cand = lookup_team(team_bio_idx, team_key)
        ncaa_cand = lookup_team(ncaa_idx, team_key)
        if not tb_cand and not ncaa_cand:
            no_team += 1
            continue

        # Prefer team_bio_full (has weight); fall back to ncaa/ncaa_d23.
        chosen_row = None
        chosen_score = None
        chosen_src = None
        chosen_name = None

        tb = best_match(query, tb_cand)
        if tb is not None:
            row, score = tb
            # collapse multi-season rows for this exact matched player
            same = [c for c in tb_cand if c["_name_norm"] == row["_name_norm"]]
            chosen_row = pick_recent(same)
            chosen_score = score
            chosen_src = "team_bio_full"
            chosen_name = row["player_src"]
        else:
            nc = best_match(query, ncaa_cand)
            if nc is not None:
                row, score = nc
                same = [c for c in ncaa_cand if c["_name_norm"] == row["_name_norm"]]
                chosen_row = pick_recent(same)
                chosen_score = score
                chosen_src = "ncaa"
                chosen_name = row["player_src"]

        if chosen_row is None:
            no_match += 1
            continue

        out_rows.append(
            {
                "player": db_name,  # DB full_name verbatim for later exact-match load
                "team": chosen_row.get("team"),
                "season": chosen_row.get("season"),
                "height_in": chosen_row.get("height_in"),
                "weight_lb": chosen_row.get("weight_lb"),
                "bats": chosen_row.get("bats"),
                "throws": chosen_row.get("throws"),
                "class_year": chosen_row.get("class_year"),
                "position": chosen_row.get("position"),
                "hometown": chosen_row.get("hometown"),
                "high_school": chosen_row.get("high_school"),
            }
        )
        accepted_scores.append(chosen_score)
        div_recovered[division] += 1
        src_counts[chosen_src] += 1
        if len(examples) < 8:
            w = chosen_row.get("weight_lb")
            examples.append(
                f'  {db_name!r} ({division}) -> {chosen_name!r} @{chosen_score:.1f} '
                f'[{chosen_src}] wt={w} ht={chosen_row.get("height_in")}'
            )

    # write CSV -------------------------------------------------------------
    cols = [
        "player", "team", "season", "height_in", "weight_lb",
        "bats", "throws", "class_year", "position", "hometown", "high_school",
    ]
    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame(out_rows, columns=cols)
    df.to_csv(OUT_CSV, index=False, encoding="utf-8")

    with_weight = sum(1 for r in out_rows if r["weight_lb"] not in (None, ""))
    height_only = len(out_rows) - with_weight

    # report ----------------------------------------------------------------
    print("=" * 64)
    print("ENTERED no-bio recovery")
    print("=" * 64)
    print(f"Targets (ENTERED, no player_bio) : {total}")
    print(f"  skipped (team in no source)    : {no_team}")
    print(f"  skipped (no accepted match)    : {no_match}")
    print(f"Recovered                        : {len(out_rows)}")
    print(f"  with weight (team_bio_full)    : {with_weight}")
    print(f"  height-only (ncaa/ncaa_d23)    : {height_only}")
    print(f"Output CSV                       : {OUT_CSV}")

    print("\nRecovered by division (recovered / targets):")
    for d in sorted(div_total, key=lambda x: (x is None, str(x))):
        label = d if d is not None else "(null)"
        print(f"  {label:>7} : {div_recovered.get(d, 0):>5} / {div_total[d]:>5}")

    print("\nRecovered by source:")
    for s, c in src_counts.most_common():
        print(f"  {s:>14} : {c}")

    if accepted_scores:
        buckets: Counter = Counter()
        for s in accepted_scores:
            if s >= 100:
                buckets["100"] += 1
            elif s >= 98:
                buckets["98-99.9"] += 1
            elif s >= 95:
                buckets["95-97.9"] += 1
            elif s >= 92:
                buckets["92-94.9"] += 1
            else:
                buckets["88-91.9"] += 1
        print("\nAccepted-match score distribution:")
        for label in ["100", "98-99.9", "95-97.9", "92-94.9", "88-91.9"]:
            if buckets.get(label):
                print(f"  {label:>9} : {buckets[label]}")
        n = len(accepted_scores)
        print(f"  min={min(accepted_scores):.1f}  "
              f"mean={sum(accepted_scores) / n:.1f}  "
              f"max={max(accepted_scores):.1f}")

    print("\nExample matches (db_name (div) -> src_name @score [source]):")
    for line in examples:
        print(line)


if __name__ == "__main__":
    main()
