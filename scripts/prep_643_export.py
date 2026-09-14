"""Clean a 6-4-3 / Synergy batted-ball CSV export into an importable hitter CSV.

The raw export carries one row per (player, pitch-type) and decorates the Team
cell as "Team Name|logo_url". This:
  - keeps only the overall pitch-type rows (Pitch Type == "All"),
  - strips the "|logo_url" decoration from Team,
then writes a clean CSV that `python run.py enrich-643` can ingest. Source-specific
shaping lives here so the generic importer (enrich.import_643_csv) stays clean.

Usage:
    python scripts/prep_643_export.py "<input.csv>" "<output.csv>"
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd


def prep(inp: str | Path, outp: str | Path) -> int:
    df = pd.read_csv(inp)
    if "Pitch Type" in df.columns:
        df = df[df["Pitch Type"].astype(str).str.strip() == "All"].copy()
    if "Team" in df.columns:
        df["Team"] = df["Team"].astype(str).str.split("|").str[0].str.strip()
    Path(outp).parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(outp, index=False, encoding="utf-8")
    return len(df)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: prep_643_export.py <input.csv> <output.csv>")
    n = prep(sys.argv[1], sys.argv[2])
    print(f"wrote {n} rows -> {sys.argv[2]}")
