"""
Sample Play-by-Play DataFrames for Assessing Level of Detail
============================================================

Builds test PBP DataFrames that mirror the typical output of:
  1. baseballr (R) ncaa_pbp() — play-level, text descriptions
  2. Retrosheet/pbpy-style    — event-level, coded events

Saves CSVs to the Baseball folder and prints a detail summary.
Run: python sample_pbp_dfs_for_detail.py [--out-dir PATH]
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import pandas as pd


BASEBALLR_DESCRIPTIONS = [
    "Smith singled to center.",
    "Jones flied out to right.",
    "Williams walked.",
    "Davis struck out swinging.",
    "Brown grounded out to short.",
    "Wilson doubled down the left field line.",
    "Taylor popped out to second.",
    "Martinez hit by pitch.",
    "Anderson singled to right.",
    "Thomas struck out looking.",
    "Jackson grounded into double play.",
    "White homered to left center.",
    "Harris lined out to third.",
    "Clark singled to left.",
    "Lewis flied out to center.",
    "Robinson walked.",
    "Young grounded out to first.",
    "King struck out swinging.",
    "Wright singled to right.",
    "Scott flied out to left.",
    "Green doubled to right.",
    "Adams grounded out to second.",
    "Nelson struck out looking.",
    "Hill popped out to first.",
    "Baker singled to center.",
    "Garcia flied out to right.",
    "Lee grounded out to third.",
    "Hall walked.",
    "Allen struck out swinging.",
    "Turner singled to left.",
    "Phillips flied out to center.",
    "Campbell grounded out to short.",
    "Parker homered to right.",
    "Evans lined out to short.",
    "Edwards struck out looking.",
    "Collins singled to right.",
    "Stewart flied out to left.",
    "Morris grounded out to second.",
    "Rogers walked.",
    "Reed struck out swinging.",
    "Cook singled to center.",
    "Morgan flied out to right.",
    "Bell grounded out to first.",
    "Brooks doubled to left.",
    "Ward popped out to third.",
    "Russell struck out looking.",
    "Diaz singled to left.",
    "Myers flied out to center.",
    "Foster grounded out to short.",
]


def make_baseballr_style_df() -> pd.DataFrame:
    """
    Mimics baseballr::ncaa_pbp() output.
    One row per play; columns: game_date, location, attendance, inning,
    inning_top_bot, score, batting, fielding, description, game_pbp_url, game_pbp_id.
    Level of detail: play-level, narrative description only (no pitch location, no coded event).
    """
    rows = []
    url = "https://stats.ncaa.org/game/play_by_play/12345"
    game_id = 12345
    descs = BASEBALLR_DESCRIPTIONS
    score_by_inning = [(0, 0), (1, 0), (1, 1), (2, 1), (2, 2), (3, 2), (3, 3), (4, 3), (4, 4), (5, 4)]
    for i in range(50):
        inn = (i // 5) % 9 + 1
        top_bot = "top" if (i // 5) % 2 == 0 else "bot"
        batting = "USD" if top_bot == "top" else "Opponent"
        fielding = "Opponent" if top_bot == "top" else "USD"
        s, o = score_by_inning[(i // 5) % len(score_by_inning)]
        score = f"{s}-{o}" if top_bot == "top" else f"{o}-{s}"
        rows.append({
            "game_date": "02/15/2024",
            "location": "San Diego, CA",
            "attendance": None,
            "inning": inn,
            "inning_top_bot": top_bot,
            "score": score,
            "batting": batting,
            "fielding": fielding,
            "description": descs[i % len(descs)],
            "game_pbp_url": url,
            "game_pbp_id": game_id,
        })
    return pd.DataFrame(rows)


# -----------------------------------------------------------------------------
# Retrosheet lookup tables (event_cd, event_tx, runs_outs, bases)
# Source: Retrosheet/Chadwick (e.g. Analyzing Baseball Data with R 3e, Appendix A)
# -----------------------------------------------------------------------------

# event_cd: main event type. event_tx for event_cd=2 refines "Generic Out" (F=fly, G=ground, L=line, P=pop).
RETROSHEET_EVENT_CD_LOOKUP = pd.DataFrame([
    {"event_cd": 2, "event_tx": "", "event_desc": "Generic Out (see event_tx: F=fly, G=ground, L=line, P=pop)"},
    {"event_cd": 3, "event_tx": "K", "event_desc": "Strikeout"},
    {"event_cd": 4, "event_tx": "", "event_desc": "Stolen Base"},
    {"event_cd": 5, "event_tx": "", "event_desc": "Defensive Indifference"},
    {"event_cd": 6, "event_tx": "", "event_desc": "Caught Stealing"},
    {"event_cd": 8, "event_tx": "", "event_desc": "Pickoff"},
    {"event_cd": 9, "event_tx": "", "event_desc": "Wild Pitch"},
    {"event_cd": 10, "event_tx": "", "event_desc": "Passed Ball"},
    {"event_cd": 11, "event_tx": "", "event_desc": "Balk"},
    {"event_cd": 12, "event_tx": "", "event_desc": "Other Advance"},
    {"event_cd": 13, "event_tx": "", "event_desc": "Foul Error"},
    {"event_cd": 14, "event_tx": "W", "event_desc": "Nonintentional Walk"},
    {"event_cd": 15, "event_tx": "", "event_desc": "Intentional Walk"},
    {"event_cd": 16, "event_tx": "H", "event_desc": "Hit By Pitch"},
    {"event_cd": 17, "event_tx": "", "event_desc": "Interference"},
    {"event_cd": 18, "event_tx": "E", "event_desc": "Error"},
    {"event_cd": 19, "event_tx": "", "event_desc": "Fielder's Choice"},
    {"event_cd": 20, "event_tx": "S", "event_desc": "Single"},
    {"event_cd": 21, "event_tx": "D", "event_desc": "Double"},
    {"event_cd": 22, "event_tx": "T", "event_desc": "Triple"},
    {"event_cd": 23, "event_tx": "H", "event_desc": "Homerun"},
])
# event_tx for event_cd=2 (Generic Out) only
RETROSHEET_EVENT_TX_FOR_OUT = pd.DataFrame([
    {"event_tx": "F", "event_tx_desc": "Fly out"},
    {"event_tx": "G", "event_tx_desc": "Ground out"},
    {"event_tx": "L", "event_tx_desc": "Line out"},
    {"event_tx": "P", "event_tx_desc": "Pop out"},
])

RETROSHEET_RUNS_OUTS_LOOKUP = pd.DataFrame([
    {"runs_outs": "0", "meaning": "No out recorded on this play"},
    {"runs_outs": "1", "meaning": "One out recorded on this play"},
    {"runs_outs": "2", "meaning": "Two outs recorded on this play (e.g. double play)"},
    {"runs_outs": "3", "meaning": "Three outs (inning ended); sometimes used as end-of-inning marker"},
])

# Base state (START_BASES_CD / END_BASES_CD in full Retrosheet)
RETROSHEET_BASES_CD_LOOKUP = pd.DataFrame([
    {"bases_cd": 0, "bases_desc": "Empty"},
    {"bases_cd": 1, "bases_desc": "1B only"},
    {"bases_cd": 2, "bases_desc": "2B only"},
    {"bases_cd": 3, "bases_desc": "1B & 2B"},
    {"bases_cd": 4, "bases_desc": "3B only"},
    {"bases_cd": 5, "bases_desc": "1B & 3B"},
    {"bases_cd": 6, "bases_desc": "2B & 3B"},
    {"bases_cd": 7, "bases_desc": "Loaded (1B, 2B, 3B)"},
])

# How to know when runs were scored (Retrosheet/Chadwick columns). Source: Retrosheet pbpcrosswalk.
RETROSHEET_RUNS_SCORED_REF = pd.DataFrame([
    {"column_plays": "score_v", "column_cwevent": "AWAY_SCORE_CT", "meaning": "Visitor (away) team cumulative score after this play"},
    {"column_plays": "score_h", "column_cwevent": "HOME_SCORE_CT", "meaning": "Home team cumulative score after this play"},
    {"column_plays": "runs", "column_cwevent": "EVENT_RUNS_CT", "meaning": "Number of runs scored on this play (extended field)"},
    {"column_plays": "run_b", "column_cwevent": "run_b", "meaning": "1 if batter scored on this play, else 0 (extended)"},
    {"column_plays": "run1", "column_cwevent": "run1", "meaning": "1 if runner on 1st scored on this play (extended)"},
    {"column_plays": "run2", "column_cwevent": "run2", "meaning": "1 if runner on 2nd scored on this play (extended)"},
    {"column_plays": "run3", "column_cwevent": "run3", "meaning": "1 if runner on 3rd scored on this play (extended)"},
    {"column_plays": "rbi", "column_cwevent": "RBI_CT", "meaning": "RBI credited on this play (not same as runs if earned/unearned)"},
    {"column_plays": "(derived)", "column_cwevent": "—", "meaning": "Runs on play = score_v diff or score_h diff from previous event (same game)"},
])

# Short event_desc by (event_cd, event_tx) for merging into sample
def _event_desc_for_row(event_cd: int, event_tx: str) -> str:
    if event_cd == 2:
        d = {"F": "Fly out", "G": "Ground out", "L": "Line out", "P": "Pop out"}
        return d.get(event_tx, "Out")
    m = {
        (3, "K"): "Strikeout",
        (14, "W"): "Walk",
        (16, "H"): "Hit by pitch",
        (20, "S"): "Single",
        (21, "D"): "Double",
        (22, "T"): "Triple",
        (23, "H"): "Homerun",
    }
    # 16=HBP and 23=HR both use event_tx "H"; disambiguate by event_cd
    return m.get((event_cd, event_tx), f"Event {event_cd} ({event_tx})")


# Retrosheet-style: event_cd 2=out, 3=K, 14=walk, 20=single, 21=double, 22=triple, 23=HR, etc.
RETROSHEET_EVENTS = [
    (20, "S"), (2, "F"), (14, "W"), (3, "K"), (2, "G"), (21, "D"), (2, "L"), (16, "H"), (20, "S"),
    (3, "K"), (2, "G"), (23, "H"), (2, "L"), (20, "S"), (2, "F"), (14, "W"), (2, "G"), (3, "K"),
    (20, "S"), (2, "F"), (21, "D"), (2, "G"), (3, "K"), (2, "L"), (20, "S"), (2, "F"), (2, "G"),
    (23, "H"), (2, "L"), (3, "K"), (20, "S"), (2, "F"), (2, "G"), (14, "W"), (3, "K"), (20, "S"),
    (2, "F"), (2, "G"), (21, "D"), (2, "L"), (3, "K"), (20, "S"), (2, "F"), (2, "G"), (14, "W"),
    (3, "K"),
]


def make_retrosheet_style_df() -> pd.DataFrame:
    """
    Mimics Retrosheet-like / pbpy target format: event-level with coded event types.
    One row per plate appearance (or event); coded fields for analysis.
    Level of detail: event-level with event_cd, no pitch-level, no location.
    """
    rows = []
    events = RETROSHEET_EVENTS
    bat_ids = [f"bat{i:02d}" for i in range(1, 51)]
    for i in range(50):
        inn = (i // 5) % 9 + 1
        bat_home = (i // 5) % 2
        bat_team = "USD" if bat_home == 0 else "OPP"
        fld_team = "OPP" if bat_home == 0 else "USD"
        pit_id = "opp01" if bat_home == 0 else "usd01"
        event_cd, event_tx = events[i % len(events)]
        runs_outs = str((i % 3) if event_cd in (2, 3) else "0")
        event_desc = _event_desc_for_row(event_cd, event_tx)
        runs_outs_desc = RETROSHEET_RUNS_OUTS_LOOKUP.loc[
            RETROSHEET_RUNS_OUTS_LOOKUP["runs_outs"] == runs_outs, "meaning"
        ].iloc[0] if runs_outs in RETROSHEET_RUNS_OUTS_LOOKUP["runs_outs"].tolist() else "—"
        rows.append({
            "game_id": "12345",
            "inning": inn,
            "bat_home_id": bat_home,
            "bat_team_id": bat_team,
            "fld_team_id": fld_team,
            "bat_id": bat_ids[i],
            "pit_id": pit_id,
            "event_cd": event_cd,
            "event_tx": event_tx,
            "event_desc": event_desc,
            "runs_outs": runs_outs,
            "runs_outs_desc": runs_outs_desc,
        })
    return pd.DataFrame(rows)


def print_detail_summary(name: str, df: pd.DataFrame) -> None:
    print(f"\n--- {name} ---")
    print(f"  Rows: {len(df)}, Columns: {len(df.columns)}")
    print(f"  Columns: {list(df.columns)}")
    print(f"  Granularity: ", end="")
    if "pitchResult" in df.columns and "balls" in df.columns:
        print("pitch-level (one row per pitch)")
    elif "event_cd" in df.columns or "event_tx" in df.columns:
        print("event-level (one row per plate appearance / event)")
    else:
        print("play-level (one row per play, text description)")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description="Build sample PBP DataFrames and save CSVs.")
    parser.add_argument(
        "--out-dir",
        type=str,
        default=None,
        help="Directory to write CSV files (default: same folder as this script)",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir) if args.out_dir else Path(__file__).resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)

    # Build DataFrames
    dfs = {
        "baseballr_style": make_baseballr_style_df(),
        "retrosheet_style": make_retrosheet_style_df(),
    }

    # Write Retrosheet lookup tables first (so runs_scored reference is saved even if sample CSV is locked)
    RETROSHEET_EVENT_CD_LOOKUP.to_csv(out_dir / "retrosheet_event_codes.csv", index=False)
    RETROSHEET_EVENT_TX_FOR_OUT.to_csv(out_dir / "retrosheet_event_tx_for_out.csv", index=False)
    RETROSHEET_RUNS_OUTS_LOOKUP.to_csv(out_dir / "retrosheet_runs_outs.csv", index=False)
    RETROSHEET_BASES_CD_LOOKUP.to_csv(out_dir / "retrosheet_bases_cd.csv", index=False)
    RETROSHEET_RUNS_SCORED_REF.to_csv(out_dir / "retrosheet_runs_scored_reference.csv", index=False)
    print("Wrote retrosheet_event_codes.csv, retrosheet_event_tx_for_out.csv, retrosheet_runs_outs.csv, retrosheet_bases_cd.csv, retrosheet_runs_scored_reference.csv")

    for name, df in dfs.items():
        path = out_dir / f"sample_pbp_{name}.csv"
        df.to_csv(path, index=False)
        print(f"Wrote {path}")

    # Summary for assessing level of detail
    print("\n" + "=" * 60)
    print("LEVEL OF DETAIL SUMMARY")
    print("=" * 60)
    print_detail_summary("1. baseballr (ncaa_pbp) — play-level, text only", dfs["baseballr_style"])
    print_detail_summary("2. Retrosheet/pbpy — event-level, coded", dfs["retrosheet_style"])

    print("Sample rows (first 2):")
    for name, df in dfs.items():
        print(f"\n{name}:")
        print(df.head(2).to_string())
    print()


if __name__ == "__main__":
    main()
