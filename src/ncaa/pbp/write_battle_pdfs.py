"""
Regenerate per-game and season-long battle PDFs in battle_pdf/.

Reads real5_pbp_baseballr_style.csv and real5_selected_games.csv, runs battle calc,
builds rows_df and summary_df, then calls battle_logic.render_season_summary_pdf for:
  - battle_pdf/season_summary.pdf (all games + season totals)
  - battle_pdf/<date>_at_<opponent>.pdf (one per game; contest_id appended if duplicate)

Run from the battles/ directory:
  python write_battle_pdfs.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(OUT_DIR))

import pandas as pd

from ncaa.pbp.baseballr_battle_calc import (
    build_complete_games_lookup,
    build_rows_df_and_summary_df,
    run_battle_calc_for_all_games,
)
from ncaa.pbp.battle_logic import render_season_summary_pdf


def _safe_filename(s: str) -> str:
    """Replace spaces and invalid path chars with underscores; collapse repeated."""
    s = re.sub(r'[\s\\/:*?"<>|]+', "_", str(s).strip())
    return re.sub(r"_+", "_", s).strip("_") or "game"


def main() -> None:
    battles_dir = OUT_DIR
    csv_path = battles_dir / "real5_pbp_baseballr_style.csv"
    games_csv = battles_dir / "real5_selected_games.csv"
    pdf_dir = battles_dir / "battle_pdf"

    if not csv_path.is_file():
        print(f"CSV not found: {csv_path}")
        return

    raw = pd.read_csv(csv_path)
    lookup = build_complete_games_lookup(raw, csv_path, games_csv)
    results, full = run_battle_calc_for_all_games(csv_path, games_lookup=lookup, games_csv_path=games_csv)

    if not results:
        print("No game results.")
        return

    rows_df, summary_df = build_rows_df_and_summary_df(results, full)
    if rows_df.empty:
        print("No rows for PDF.")
        return

    pdf_dir.mkdir(parents=True, exist_ok=True)
    # Remove old per-game PDFs named game_<contest_id>.pdf so we don't keep both schemes
    for old in pdf_dir.glob("game_*.pdf"):
        old.unlink(missing_ok=True)

    # Season-long PDF
    season_path = pdf_dir / "season_summary.pdf"
    render_season_summary_pdf(rows_df, summary_df, str(season_path))
    print(f"Wrote: {season_path}")

    # Per-game PDFs: name by date and opponent (e.g. 2026-03-07_at_California_Golden_Bears.pdf)
    used_basenames: set[str] = set()
    for gid in rows_df["GameId"].dropna().unique():
        gid_int = int(gid)
        rows_one = rows_df[rows_df["GameId"] == gid_int].copy()
        if rows_one.empty:
            continue
        r = rows_one.iloc[0]
        date_str = str(r.get("GameDate", "")).strip() or str(gid_int)
        opponent = _safe_filename(str(r.get("Opponent", "?")))
        base = f"{date_str}_at_{opponent}"
        if base in used_basenames:
            base = f"{base}_{gid_int}"
        used_basenames.add(base)
        sum_rows = []
        for metric in summary_df["Metric"].values:
            met_col = metric + "__met"
            pct_col = metric + "__vs_goal_pct"
            met = 1 if r.get(met_col) else 0
            pct = float(r[pct_col]) if pct_col in r and pd.notna(r.get(pct_col)) else 0.0
            sum_rows.append({"Metric": metric, "Games": 1, "Games_Met": met, "Avg_Vs_Goal_Pct": pct})
        sum_one = pd.DataFrame(sum_rows)
        game_path = pdf_dir / f"{base}.pdf"
        render_season_summary_pdf(rows_one, sum_one, str(game_path))
        print(f"Wrote: {game_path}")

    print("Done.")


if __name__ == "__main__":
    main()
