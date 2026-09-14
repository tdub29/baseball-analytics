"""
Fetch PBP for multiple NCAA contest IDs (play_by_play URLs), combine into one
baseballr-style CSV and selected_games, then optionally run battle calc.

Usage:
  python Baseball/fetch_multiple_ncaa_pbp.py [contest_id ...]
  python Baseball/fetch_multiple_ncaa_pbp.py 6536340 6536345 6536347

Uses ncaa_pbp_playwright (Playwright, visible browser by default).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pandas as pd

# Import from same dir
OUT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(OUT_DIR))
from ncaa_pbp_playwright import (
    fetch_pbp_with_playwright,
    parse_pbp_table,
    BASEBALLR_COLUMNS,
)
from ncaa.pbp.baseballr_battle_calc import add_leadoff_column_to_pbp


def contest_to_play_by_play_url(contest_id: str) -> str:
    return f"https://stats.ncaa.org/contests/{contest_id}/play_by_play"


def main() -> None:
    argv = [a.strip() for a in sys.argv[1:] if a.strip()]
    refresh_ids = set()
    if "--refresh" in sys.argv:
        i = sys.argv.index("--refresh")
        argv = [a for a in argv if a != "--refresh"]
        # IDs to re-fetch (exclude from existing so we fetch again)
        refresh_ids = {int(x) for x in argv if x.isdigit()}
    if len(argv) == 0 and not refresh_ids:
        contest_ids = ["6500370", "6536340", "6536345", "6536347"]
        refresh_ids = set()
    else:
        contest_ids = [a for a in argv if a.isdigit()] or list(refresh_ids)

    battles_dir = OUT_DIR
    battles_dir.mkdir(parents=True, exist_ok=True)
    pbp_path = battles_dir / "real5_pbp_baseballr_style.csv"
    games_path = battles_dir / "real5_selected_games.csv"

    # Append mode: load existing PBP/games and only fetch IDs not already present (or in refresh_ids)
    existing_games_df = None
    existing_pbp_base = None
    if pbp_path.is_file() and games_path.is_file():
        try:
            existing_games_df = pd.read_csv(games_path)
            existing_pbp = pd.read_csv(pbp_path)
            if all(c in existing_pbp.columns for c in BASEBALLR_COLUMNS):
                existing_pbp_base = existing_pbp[BASEBALLR_COLUMNS].copy()
            # If refreshing, drop those contests from existing so we re-fetch and replace
            if refresh_ids and existing_pbp_base is not None and "game_pbp_id" in existing_pbp_base.columns:
                existing_pbp_base = existing_pbp_base[~pd.to_numeric(existing_pbp_base["game_pbp_id"], errors="coerce").isin(refresh_ids)]
            if refresh_ids and existing_games_df is not None and "contest_id" in existing_games_df.columns:
                existing_games_df = existing_games_df[~pd.to_numeric(existing_games_df["contest_id"], errors="coerce").isin(refresh_ids)]
        except Exception:
            existing_games_df = None
            existing_pbp_base = None

    requested_ids = [str(c) for c in contest_ids]
    existing_ids = set()
    if existing_games_df is not None and "contest_id" in existing_games_df.columns:
        existing_ids = set(pd.to_numeric(existing_games_df["contest_id"], errors="coerce").dropna().astype(int))
    to_fetch = [c for c in requested_ids if int(c) not in existing_ids]

    all_rows = []
    games_meta = []  # (contest_id, away_short, home_short)

    for cid in to_fetch:
        url = contest_to_play_by_play_url(cid)
        print(f"Fetching {cid}: {url}")
        html = fetch_pbp_with_playwright(url, headless=False)
        rows = parse_pbp_table(html, game_pbp_url=url, game_pbp_id=cid)
        if not rows:
            print(f"  No rows for {cid}, skipping.")
            continue
        # Infer away/home from first top-of-1st row
        first_top = next((r for r in rows if str(r.get("inning")) == "1" and (r.get("inning_top_bot") or "").strip().lower() == "top"), None)
        if first_top:
            away = (first_top.get("batting") or "Away").strip()
            home = (first_top.get("fielding") or "Home").strip()
            games_meta.append((cid, away, home))
        else:
            games_meta.append((cid, "Away", "Home"))
        all_rows.extend(rows)
        print(f"  Rows: {len(rows)}")

    # Build combined PBP: existing (base columns only) + newly fetched
    if existing_pbp_base is not None and existing_games_df is not None:
        if all_rows:
            new_df = pd.DataFrame(all_rows)[BASEBALLR_COLUMNS]
            df = pd.concat([existing_pbp_base, new_df], ignore_index=True)
            print(f"Merged {len(existing_pbp_base)} existing + {len(new_df)} new PBP rows.")
        else:
            df = existing_pbp_base.copy()
            print("No new games to fetch; using existing PBP.")
        games_df = pd.concat([
            existing_games_df,
            pd.DataFrame(games_meta, columns=["contest_id", "away_short", "home_short"])
        ], ignore_index=True) if games_meta else existing_games_df.copy()
    else:
        if not all_rows:
            print("No data collected.")
            return
        df = pd.DataFrame(all_rows)[BASEBALLR_COLUMNS]
        games_df = pd.DataFrame(games_meta, columns=["contest_id", "away_short", "home_short"])

    df = add_leadoff_column_to_pbp(df)
    df.to_csv(pbp_path, index=False)
    print(f"Wrote {len(df)} rows to {pbp_path}")

    games_df.to_csv(games_path, index=False)
    print(f"Wrote {len(games_df)} games to {games_path}")

    # Run battle calc from this dir (battles/)
    if str(OUT_DIR) not in sys.path:
        sys.path.insert(0, str(OUT_DIR))
    from ncaa.pbp.baseballr_battle_calc import run_battle_calc_for_all_games, write_battle_report
    results, full = run_battle_calc_for_all_games(pbp_path, games_csv_path=games_path)
    # Text report first; PDF (e.g. render_season_summary_pdf) is a separate step.
    out_path = OUT_DIR / "real5_battle_calc_output.txt"
    lookup = {int(r["contest_id"]): (r["away_short"], r["home_short"]) for _, r in games_df.iterrows()}
    write_battle_report(results, out_path, games_lookup=lookup, full_battle_df=full)
    print(f"Wrote battle report: {out_path}")

    # Node PDFs: season_battle_report.pdf always; per-game only for games we just fetched
    pdf_dir = battles_dir / "battle_pdf"
    mjs = pdf_dir / "generate-pdf.mjs"
    if mjs.is_file():
        out_pdf = pdf_dir / "season_battle_report.pdf"
        pbp_csv = battles_dir / "real5_pbp_baseballr_style.csv"
        logo = pdf_dir / "sd_logo.png"
        cmd = [
            "node",
            str(mjs),
            str(out_path),
            str(out_pdf),
            str(pbp_csv),
            str(logo),
            *[str(cid) for cid in to_fetch],
        ]
        try:
            subprocess.run(cmd, check=True, cwd=str(battles_dir))
            if to_fetch:
                print(f"Wrote PDFs: {out_pdf} + {len(to_fetch)} per-game (this run only)")
            else:
                print(f"Wrote PDF: {out_pdf}")
        except (FileNotFoundError, subprocess.CalledProcessError) as e:
            print(f"Node PDF step skipped: {e}")
    else:
        print("battle_pdf/generate-pdf.mjs not found; PDF step skipped.")
    print("Done.")


if __name__ == "__main__":
    main()
