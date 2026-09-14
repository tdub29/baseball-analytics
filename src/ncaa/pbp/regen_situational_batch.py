"""Regenerate contest_* battle reports from PBP CSVs, then consolidated situational-vs-B1 markdown."""
from __future__ import annotations

import re
import sys
from pathlib import Path

import pandas as pd
from ncaa_situational_stats_playwright import (
    batch_situational_vs_b1_consolidated,
    batch_situational_vs_b1_consolidated_battle_refresh,
)

from ncaa.pbp.baseballr_battle_calc import (
    build_complete_games_lookup,
    run_battle_calc_for_all_games,
    write_battle_report,
)

SCRIPT_DIR = Path(__file__).resolve().parent


def contest_ids_with_pbp() -> list[int]:
    ids = []
    for p in SCRIPT_DIR.glob("contest_*_pbp.csv"):
        m = re.match(r"^contest_(\d+)_pbp\.csv$", p.name, re.I)
        if m:
            ids.append(int(m.group(1)))
    return sorted(ids)


def regenerate_battle_outputs(ids: list[int]) -> None:
    for cid in ids:
        pbp = SCRIPT_DIR / f"contest_{cid}_pbp.csv"
        out_txt = SCRIPT_DIR / f"contest_{cid}_battle_calc_output.txt"
        if not pbp.is_file():
            print(f"skip {cid}: no {pbp.name}", file=sys.stderr)
            continue
        lookup = build_complete_games_lookup(pd.read_csv(pbp), pbp, None)
        results, full = run_battle_calc_for_all_games(pbp, games_lookup=lookup)
        write_battle_report(results, out_txt, games_lookup=lookup, full_battle_df=full)
        print(f"wrote {out_txt.name}")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Regenerate battle reports; optionally update situational-vs-B1 md.")
    parser.add_argument(
        "--battle-only",
        action="store_true",
        help="Refresh B1 from PBP and rewrite the md using NCAA numbers from the existing "
        "situational_vs_b1_batch.md (no NCAA situational scrape).",
    )
    args = parser.parse_args()

    ids = contest_ids_with_pbp()
    if not ids:
        print("No contest_*_pbp.csv files found.", file=sys.stderr)
        sys.exit(1)
    regenerate_battle_outputs(ids)
    md_out = SCRIPT_DIR / "situational_vs_b1_batch.md"
    if args.battle_only:
        body = batch_situational_vs_b1_consolidated_battle_refresh(ids, previous_md_path=md_out)
    else:
        body = batch_situational_vs_b1_consolidated(ids, headless=False, wait_ms=4000)
    md_out.write_text(body, encoding="utf-8")
    print(f"wrote {md_out.name}")


if __name__ == "__main__":
    main()
