"""Flatten scraped team rosters into one full bio CSV.

Reads the cached team-roster JSON (which carries position, hometown, bats/throws,
weight that the current team_bio CSVs dropped) and writes one row per player to
data/643_exports/bio/team_bio_full.csv.
"""

import json
from pathlib import Path

import pandas as pd

BASE = Path(r"c:\Users\TrevorWhite\Downloads\Big Projects\baseball")
INPUT = BASE / "data" / "cache" / "team_bio_rosters.json"
OUTPUT = BASE / "data" / "643_exports" / "bio" / "team_bio_full.csv"

COLUMNS = [
    "player",
    "team",
    "season",
    "height_in",
    "weight_lb",
    "bats",
    "throws",
    "class_year",
    "position",
    "hometown",
    "high_school",
]


def main() -> None:
    with INPUT.open("r", encoding="utf-8") as fh:
        data = json.load(fh)

    records = []
    for value in data.values():
        team = value.get("team")
        season = value.get("season")
        for row in value.get("rows", []):
            player = row.get("player")
            if not player or not str(player).strip():
                continue
            records.append(
                {
                    "player": player,
                    "team": team,
                    "season": season,
                    "height_in": row.get("height_in"),
                    "weight_lb": row.get("weight_lb"),
                    "bats": row.get("bats"),
                    "throws": row.get("throws"),
                    "class_year": row.get("class_year"),
                    "position": row.get("position"),
                    "hometown": row.get("hometown"),
                    "high_school": row.get("high_school"),
                }
            )

    df = pd.DataFrame(records, columns=COLUMNS)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUTPUT, index=False)

    print(f"Wrote {len(df)} rows to {OUTPUT}")


if __name__ == "__main__":
    main()
