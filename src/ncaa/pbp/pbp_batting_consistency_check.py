"""
Flag PBP rows where the primary batter in `description` likely belongs to the other team
vs `batting`, by learning surname/plate affinity from the same game (majority vote).

Skips non-PA lines (is_non_pa), pinch/sub lines without a leadoff batter action, and names
with fewer than 2 seen plate events (ambiguous).

Usage (from battles/):
  python pbp_batting_consistency_check.py contest_6507272_pbp.csv
  python pbp_batting_consistency_check.py contest_6544452_pbp.csv
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pandas as pd

# Same USD rule as baseballr_battle_calc
from ncaa.pbp.baseballr_battle_calc import _normalize_to_usd
from ncaa.pbp.baseballr_description_mappings import is_non_pa

# Match name at start of a plate-appearance description (name ends before the action verb)
_BATTER_RE = re.compile(
    r"^(.+?)\s+"
    r"(walked|struck out(?: swinging| looking)?|singled|doubled|tripled|homered|"
    r"flied out to|flied out|fouled out|grounded out|lined out|popped out to|popped out|popped up to|popped up|"
    r"infield fly|reached|hit by pitch|sacrifice bunt|sacrifice fly|sac bunt|sac fly|sac,|sac  |"
    r"flied|fouled|grounded|lined|popped|homered to)\b",
    re.I | re.DOTALL,
)

CHALLENGE_OR_REVIEW = re.compile(
    r"\bchallenge\b|official review|review of the play|mound visit", re.I
)


def _batting_is_usd(batting: str) -> bool:
    return _normalize_to_usd(str(batting or "").strip()) == "USD"


def _roster_key(name: str) -> str:
    """Group by last name / first token before comma (handles 'GonzalezD', 'Griffith, Ta')."""
    s = (name or "").strip().rstrip(",")
    if not s:
        return ""
    if "," in s:
        return s.split(",")[0].strip().lower()
    if re.match(r"^[A-Za-z]+\d$", s):  # GonzalezD
        return s.lower()
    parts = s.split()
    if len(parts) >= 1:
        return parts[-1].lower()
    return s.lower()


def primary_batter_from_description(desc: str) -> str | None:
    d = (desc or "").strip()
    if not d or CHALLENGE_OR_REVIEW.search(d):
        return None
    d = d.strip().strip('"')
    m = _BATTER_RE.match(d)
    if not m:
        return None
    return m.group(1).strip().rstrip(",")


def check_pbp_csv(csv_path: Path) -> list[dict]:
    df = pd.read_csv(csv_path, low_memory=False)
    rows: list[dict] = []
    for i, r in df.iterrows():
        desc = str(r.get("description", "") or "")
        if is_non_pa(desc):
            continue
        pbat = primary_batter_from_description(desc)
        if not pbat:
            continue
        key = _roster_key(pbat)
        if not key:
            continue
        bat = str(r.get("batting", "") or "")
        usd = _batting_is_usd(bat)
        rows.append(
            {
                "row_1idx": int(i) + 2,  # 1=header, +1 for 1-based = file line
                "inning": r.get("inning"),
                "inning_top_bot": r.get("inning_top_bot"),
                "batting": bat,
                "primary_batter": pbat,
                "key": key,
                "usd_bat": usd,
            }
        )
    if not rows:
        return []

    from collections import defaultdict

    usd_c: dict[str, int] = defaultdict(int)
    opp_c: dict[str, int] = defaultdict(int)
    for row in rows:
        if row["usd_bat"]:
            usd_c[row["key"]] += 1
        else:
            opp_c[row["key"]] += 1

    def predicted_team_for_key(k: str) -> str | None:
        u, o = usd_c[k], opp_c[k]
        t = u + o
        if t < 2:
            return None
        if u / t >= 0.75 and o <= 1:
            return "USD"
        if o / t >= 0.75 and u <= 1:
            return "OPP"
        return None

    out: list[dict] = []
    for row in rows:
        pred = predicted_team_for_key(row["key"])
        if pred is None:
            continue
        is_usd_bat = row["usd_bat"]
        if pred == "USD" and is_usd_bat:
            continue
        if pred == "OPP" and not is_usd_bat:
            continue
        out.append(
            {
                **row,
                "team_from_name_votes": f"USD{usd_c[row['key']]}/OPP{opp_c[row['key']]}",
                "predicted_for_name": pred,
            }
        )
    return out


def main() -> None:
    paths = [Path(a) for a in sys.argv[1:] if a.strip()]
    if not paths:
        print("Usage: python pbp_batting_consistency_check.py <pbp.csv> [...]", file=sys.stderr)
        sys.exit(1)
    for p in paths:
        p = p.resolve()
        if not p.is_file():
            print(f"Not found: {p}", file=sys.stderr)
            continue
        hits = check_pbp_csv(p)
        print(f"\n== {p.name} ==")
        if not hits:
            print("No clear batter-vs-batting mismatches (or not enough name repetition to call).")
            continue
        print(f"First misleading row (by CSV line#): {hits[0]['row_1idx']}\n")
        for h in hits:
            print(
                f"  line {h['row_1idx']}  inn {h.get('inning')}-{h.get('inning_top_bot')}\n"
                f"    batting: {h['batting']}\n"
                f"    name in desc: {h['primary_batter']}  (key={h['key']!r} votes {h['team_from_name_votes']})\n"
                f"    inferred: batter should be on {h['predicted_for_name']}, column says different.\n"
            )


if __name__ == "__main__":
    main()
