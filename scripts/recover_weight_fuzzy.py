#!/usr/bin/env python3
"""Recover missing player weight via fuzzy name matching within the same team.

Many ENTERED portal players are missing ``weight_lb`` only because their DB
``full_name`` did not EXACTLY match a row in an already-scraped team roster
(e.g. "JT Thompson" vs "J.T. Thompson", "Mike" vs "Michael"). This pure-local
recovery groups roster rows by a normalized team name, finds each missing-weight
player's team, fuzzy-matches their name against that team's roster, and emits the
matched bio fields (height, weight, position, bats, throws, class year, hometown,
high school) to a CSV. A later exact-match load attaches the values to the DB.

Conservative by design: false matches are worse than misses.
  - rapidfuzz token_sort_ratio (case/word-order insensitive)
  - accept only if best score >= 88 AND best beats 2nd-best by >= 6 points
  - only emit rows where the matched roster row actually has a weight

Reads only. Does NOT write to the DB.
"""

from __future__ import annotations

import json
import re
import sqlite3
from collections import Counter
from pathlib import Path

import pandas as pd
from rapidfuzz import fuzz, process

# --- paths -----------------------------------------------------------------
ROOT = Path(r"c:\Users\TrevorWhite\Downloads\Big Projects\baseball")
ROSTER_JSON = ROOT / "data" / "cache" / "team_bio_rosters.json"
DB_PATH = ROOT / "db" / "baseball.db"
OUT_CSV = ROOT / "data" / "643_exports" / "bio" / "recovered_fuzzy.csv"

# --- acceptance thresholds -------------------------------------------------
MIN_SCORE = 88.0          # best match must score at least this
MIN_MARGIN = 6.0          # ...and beat the 2nd-best by at least this much

_TEAM_NOISE = {"university", "college", "the", "of", "st", "saint"}


def norm_team(s: str | None) -> str:
    """Normalize a team/school name for grouping & matching."""
    if not s:
        return ""
    s = s.lower()
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    toks = [t for t in s.split() if t not in _TEAM_NOISE]
    return " ".join(toks)


# Junk middle tokens seen in DB full_name ingestion (e.g. "NOLAN MT FOSTER").
# These are not part of the real name and inflate the token set under
# token_sort_ratio, capping otherwise-perfect matches near ~90. Dropping them
# from BOTH sides makes the score reflect true first+last agreement -- which is
# strictly more conservative (right matches go up, wrong matches don't).
_NAME_NOISE = {"mt"}


def norm_name(s: str | None) -> str:
    """Normalize a player name for fuzzy comparison (drop punctuation/case)."""
    if not s:
        return ""
    s = s.lower()
    s = re.sub(r"[^a-z0-9 ]", " ", s)  # "J.T." -> "j t", strips periods/commas
    toks = [t for t in s.split() if t not in _NAME_NOISE]
    return " ".join(toks)


def main() -> None:
    # 1) roster rows grouped by normalized team -----------------------------
    with open(ROSTER_JSON, "r", encoding="utf-8") as f:
        rosters = json.load(f)

    # normalized team -> list of (raw_team, season, row)
    team_rows: dict[str, list[tuple[str, object, dict]]] = {}
    for entry in rosters.values():
        raw_team = entry.get("team")
        season = entry.get("season")
        nt = norm_team(raw_team)
        if not nt:
            continue
        bucket = team_rows.setdefault(nt, [])
        for row in entry.get("rows", []):
            bucket.append((raw_team, season, row))

    # 2) missing-weight ENTERED players -------------------------------------
    con = sqlite3.connect(str(DB_PATH))
    con.row_factory = sqlite3.Row
    players = con.execute(
        "SELECT player_id, full_name, from_school FROM players "
        "WHERE current_status='ENTERED' AND (weight_lb IS NULL)"
    ).fetchall()
    con.close()

    total_missing = len(players)

    out_rows: list[dict] = []
    accepted_scores: list[float] = []
    examples: list[str] = []
    no_team = 0
    no_candidate = 0

    for p in players:
        db_name = p["full_name"]
        team_key = norm_team(p["from_school"])
        candidates = team_rows.get(team_key)
        if not candidates:
            no_team += 1
            continue

        # candidate names (normalized) -> keep index back to the row
        cand_norm = [norm_name(c[2].get("player")) for c in candidates]
        query = norm_name(db_name)
        if not query:
            continue

        # score every candidate, then inspect top-2 for margin test
        results = process.extract(
            query,
            cand_norm,
            scorer=fuzz.token_sort_ratio,
            limit=2,
        )
        if not results:
            no_candidate += 1
            continue

        best_name, best_score, best_idx = results[0]
        second_score = results[1][1] if len(results) > 1 else 0.0

        if best_score < MIN_SCORE:
            continue
        if (best_score - second_score) < MIN_MARGIN:
            continue  # ambiguous -- two roster rows match nearly as well

        raw_team, season, row = candidates[best_idx]
        weight = row.get("weight_lb")
        if weight is None or weight == "":
            continue  # no weight to recover -> skip (spec: only emit w/ weight)

        out_rows.append(
            {
                "player": db_name,  # DB full_name so exact-match load attaches it
                "team": raw_team,
                "season": season,
                "height_in": row.get("height_in"),
                "weight_lb": weight,
                "bats": row.get("bats"),
                "throws": row.get("throws"),
                "class_year": row.get("class_year"),
                "position": row.get("position"),
                "hometown": row.get("hometown"),
                "high_school": row.get("high_school"),
            }
        )
        accepted_scores.append(float(best_score))
        if len(examples) < 8:
            examples.append(
                f'  {db_name!r} -> {row.get("player")!r} @{best_score:.1f}  weight={weight}'
            )

    # 3) write CSV ----------------------------------------------------------
    cols = [
        "player", "team", "season", "height_in", "weight_lb",
        "bats", "throws", "class_year", "position", "hometown", "high_school",
    ]
    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame(out_rows, columns=cols)
    df.to_csv(OUT_CSV, index=False, encoding="utf-8")

    # 4) report -------------------------------------------------------------
    print("=" * 60)
    print("Fuzzy weight recovery")
    print("=" * 60)
    print(f"Missing-weight ENTERED players : {total_missing}")
    print(f"  skipped (no roster for team) : {no_team}")
    print(f"  skipped (no candidates)      : {no_candidate}")
    print(f"Recovered (got a weight)       : {len(out_rows)}")
    print(f"Output CSV                     : {OUT_CSV}")

    if accepted_scores:
        # score distribution of accepted matches (bucketed)
        buckets = Counter()
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
              f"mean={sum(accepted_scores)/n:.1f}  "
              f"max={max(accepted_scores):.1f}")

    print("\nExample matches (db_name -> roster_name @score, weight):")
    for line in examples:
        print(line)


if __name__ == "__main__":
    main()
