from pathlib import Path

import pandas as pd

from ncaa.pbp.baseballr_battle_calc import build_complete_games_lookup, load_and_convert


def dump_usd_leadoffs(cid: int) -> None:
    p = Path(__file__).parent / f"contest_{cid}_pbp.csv"
    lookup = build_complete_games_lookup(pd.read_csv(p), p, None)
    bf = load_and_convert(p, games_lookup=lookup)
    g = bf[(bf["gameId"].astype(str) == str(cid)) & (bf["battingTeam"] == "USD")]
    for inn in sorted(g["inn"].unique()):
        sub = g[g["inn"] == inn]
        if sub["inning_leadoff"].max():
            row = sub[sub["inning_leadoff"] == 1].iloc[0]
            print(f"inn {inn} leadoff 1 | {row['pitchResult'][:120]}")


for cid in (6507272, 6437867, 6507956, 6540018, 6507273):
    print("===", cid)
    dump_usd_leadoffs(cid)
