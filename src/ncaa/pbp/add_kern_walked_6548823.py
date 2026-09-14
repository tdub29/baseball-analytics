"""
One-time script: Insert missing play "Kern walked." (top of 7th) for game 6548823
into real5_pbp_baseballr_style.csv with all columns correct for battle calc.
Run from battles/ with the CSV closed.

  python add_kern_walked_6548823.py
  python baseballr_battle_calc.py
"""
from pathlib import Path
import pandas as pd

CSV = Path(__file__).resolve().parent / "real5_pbp_baseballr_style.csv"

# All columns set so battle calc counts: leadoff (inning_leadoff=1), reached_base, walk (event_category, is_walk), is_pa
ROW = {
    "game_date": "02/24/2026",
    "location": "",
    "attendance": 507,
    "inning": 7,
    "inning_top_bot": "top",
    "outs": 0,
    "score": "5-5",
    "batting": "San Diego Toreros",
    "fielding": "UC San Diego Tritons",
    "batting_team_norm": "USD",
    "pitching_team_norm": "UC San Diego Tritons",
    "inning_leadoff": 1,   # first batter of inning = leadoff
    "is_pa": 1,            # walk is a plate appearance
    "reached_base": 1,     # walk = reached base
    "runs_scored_half": 0, # no run on this play
    "event_category": "walk",  # for B3a baserunners, B5a
    "total_bases": 0,
    "any_adv": 0,
    "is_walk": 1,
    "is_hbp": 0,
    "is_k": 0,
    "defensive_error": 0,
    "description": "Kern walked.",
    "game_pbp_url": "https://stats.ncaa.org/contests/6548823/play_by_play",
    "game_pbp_id": 6548823,
}


def main():
    if not CSV.is_file():
        print(f"Not found: {CSV}")
        return
    df = pd.read_csv(CSV)
    # Idempotent: skip if already present with correct leadoff/walk
    g = (df["game_pbp_id"].astype(str) == "6548823") & (df["inning"] == 7) & (df["inning_top_bot"] == "top")
    kern_walk = df[g & (df["description"].astype(str).str.strip() == "Kern walked.")]
    if not kern_walk.empty:
        # Fix existing row if columns are wrong
        idx = kern_walk.index[0]
        for k, v in ROW.items():
            if k in df.columns:
                df.at[idx, k] = v
        df.to_csv(CSV, index=False)
        print(f"Updated existing 'Kern walked.' row (leadoff=1, is_pa=1, event_category=walk, is_walk=1). Wrote {CSV}")
        print("Run: python baseballr_battle_calc.py")
        return
    # Insert after last row of bot 6 for 6548823
    g = df["game_pbp_id"].astype(str) == "6548823"
    last_bot6 = df[g & (df["inning"] == 6) & (df["inning_top_bot"] == "bot")].index.max()
    insert_at = last_bot6 + 1
    new_row = pd.DataFrame([ROW])
    for c in df.columns:
        if c not in new_row.columns:
            new_row[c] = None
    new_row = new_row[df.columns]
    df = pd.concat([df.iloc[:insert_at], new_row, df.iloc[insert_at:]], ignore_index=True)
    df.to_csv(CSV, index=False)
    print(f"Inserted 'Kern walked.' at row {insert_at} (leadoff=1, is_pa=1, event_category=walk, is_walk=1). Wrote {CSV}")
    print("Run: python baseballr_battle_calc.py")


if __name__ == "__main__":
    main()
