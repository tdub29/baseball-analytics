"""
Merge contest_id and game_url into usd_2026_schedule.csv from either:
  1) R baseballr output: usd_2026_schedule_baseballr.csv (from ncaa_schedule_info)
  2) Or re-run ncaa_schedule_playwright.py (only has contest_id for played games)

Usage:
  python merge_schedule_contest_ids.py
  python merge_schedule_contest_ids.py --schedule usd_2026_schedule.csv --from-r usd_2026_schedule_baseballr.csv -o usd_2026_schedule.csv

Reads our schedule CSV and the R CSV (if present), matches by date + opponent,
fills contest_id and game_url, writes back to the schedule file.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import pandas as pd

OUT_DIR = Path(__file__).resolve().parent
DEFAULT_SCHEDULE = OUT_DIR / "usd_2026_schedule.csv"
DEFAULT_R_CSV = OUT_DIR / "usd_2026_schedule_baseballr.csv"


def normalize_date(s: str) -> str:
    """Normalize to MM/DD/YYYY for matching. Handles '02/13/2026', '02/14/2026(1)', '02/20/2026 08:00 PM', '2026-02-13'."""
    if not s or not isinstance(s, str):
        return ""
    s = str(s).strip()
    # First 10 chars if MM/DD/YYYY
    if re.match(r"\d{1,2}/\d{1,2}/\d{4}", s):
        return s[:10]
    # ISO 2026-02-13 -> 02/13/2026
    m = re.match(r"(\d{4})-(\d{1,2})-(\d{1,2})", s)
    if m:
        y, mo, d = m.group(1), m.group(2), m.group(3)
        return f"{mo.zfill(2)}/{d.zfill(2)}/{y}"
    return s[:10] if len(s) >= 10 else s


def normalize_opponent(s: str) -> str:
    """Lowercase, strip @ and extra spaces, for fuzzy match."""
    if not s or not isinstance(s, str):
        return ""
    return str(s).strip().lstrip("@").lower().strip()


def build_r_lookup(r_df: pd.DataFrame) -> list[tuple[str, str, str, str]]:
    """Return list of (date_norm, opp_norm, contest_id, game_url) from R CSV."""
    rows = []
    date_col = next((c for c in ["date", "Date"] if c in r_df.columns), None)
    opp_col = next((c for c in ["opponent", "Opponent", "opponent_name", "OpponentName"] if c in r_df.columns), None)
    cid_col = next((c for c in ["contest_id", "contest_id"] if c in r_df.columns), None)
    url_col = next((c for c in ["game_info_url", "game_info_url"] if c in r_df.columns), None)
    if not date_col or not opp_col:
        return rows
    for _, r in r_df.iterrows():
        d = normalize_date(r.get(date_col, ""))
        o = normalize_opponent(r.get(opp_col, ""))
        cid = r.get(cid_col) if cid_col else ""
        url = r.get(url_col) if url_col else ""
        if pd.isna(cid):
            cid = ""
        if pd.isna(url):
            url = ""
        cid = str(int(cid)) if cid and str(cid).isdigit() else str(cid).strip()
        url = str(url).strip()
        rows.append((d, o, cid, url))
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge contest_id from R baseballr schedule into our schedule CSV")
    parser.add_argument("--schedule", type=Path, default=DEFAULT_SCHEDULE, help="Our schedule CSV")
    parser.add_argument("--from-r", type=Path, default=DEFAULT_R_CSV, help="R ncaa_schedule_info output CSV")
    parser.add_argument("-o", "--output", type=Path, help="Output CSV (default: overwrite --schedule)")
    args = parser.parse_args()
    out_path = args.output or args.schedule

    if not args.schedule.exists():
        print(f"Schedule not found: {args.schedule}")
        return

    df = pd.read_csv(args.schedule)
    if "contest_id" not in df.columns:
        df["contest_id"] = ""
    if "game_url" not in df.columns:
        df["game_url"] = ""

    if not args.from_r.exists():
        print(f"R schedule not found: {args.from_r}. Run R script first:")
        print("  Rscript r_fetch_usd_schedule_2026.R")
        print("Then run this script again.")
        return

    r_df = pd.read_csv(args.from_r)
    r_lookup = build_r_lookup(r_df)
    if not r_lookup:
        print("No rows parsed from R CSV. Check column names (date, opponent, contest_id, game_info_url).")
        return

    # Group R rows by (date_norm, opp_norm) so doubleheaders match in order
    from collections import defaultdict
    r_by_key = defaultdict(list)
    for (d, o, cid, url) in r_lookup:
        r_by_key[(d, o)].append((cid, url))

    def try_match(d: str, o: str) -> tuple[str, str] | None:
        key = (d, o)
        if r_by_key[key]:
            return r_by_key[key].pop(0)
        for (rd, ro_list) in list(r_by_key.items()):
            if rd != d:
                continue
            if ro_list and (o in ro_list[0][0] or (normalize_opponent(ro_list[0][0]) in o or o in normalize_opponent(ro_list[0][0]))):
                return ro_list.pop(0)
        return None

    filled = 0
    for i, row in df.iterrows():
        if pd.notna(row.get("contest_id")) and str(row.get("contest_id", "")).strip():
            continue
        d = normalize_date(row.get("game_date", ""))
        o = normalize_opponent(row.get("opponent", ""))
        match = try_match(d, o)
        if match:
            cid, url = match
            df.at[i, "contest_id"] = cid
            df.at[i, "game_url"] = url
            filled += 1

    df.to_csv(out_path, index=False)
    print(f"Filled {filled} contest_id(s). Wrote {out_path}")


if __name__ == "__main__":
    main()
