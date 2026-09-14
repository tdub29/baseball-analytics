"""Print leadoff-flagged halves for contest PBP."""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

from ncaa.pbp.baseballr_battle_calc import baseballr_to_battle_df, build_complete_games_lookup


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: _debug_b1_halfs.py contest_id ")
    cid = int(sys.argv[1])
    d = Path(__file__).resolve().parent
    pbp_path = d / f"contest_{cid}_pbp.csv"
    raw = pd.read_csv(pbp_path)
    lg = build_complete_games_lookup(raw, pbp_path, None)
    b = baseballr_to_battle_df(raw, games_lookup=lg)
    b = b[b["gameId"] == str(cid)]
    lf = b[(b["inning_leadoff"] == 1)]
    cols = [c for c in ("inn", "battingTeam", "pitchingTeam", "pitchResult") if c in lf.columns]
    sort_keys = [k for k in ("inn",) if k in lf.columns]
    lf2 = lf[cols].sort_values(sort_keys) if sort_keys else lf[cols]
    print(lf2.to_string())


if __name__ == "__main__":
    main()
