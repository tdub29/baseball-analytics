"""
Test baseballr battle calculation: all games in the PBP CSV are processed.
Run: pytest Baseball/battles/test_baseballr_battle_calc.py -v
From repo root with Baseball on PYTHONPATH, or: python -m pytest Baseball/battles/test_baseballr_battle_calc.py -v
"""

from pathlib import Path

import pandas as pd
import pytest

from ncaa.pbp.baseballr_battle_calc import (
    load_and_convert,
    run_battle_calc_for_all_games,
)


@pytest.fixture(scope="module")
def csv_path():
    # PBP CSV lives in battles/ alongside test
    # fixtures live in data/pbp/, not inside the package: src/ holds code
    return Path(__file__).resolve().parents[3] / "data" / "pbp" / "real5_pbp_baseballr_style.csv"


def test_csv_exists(csv_path):
    assert csv_path.is_file(), f"Missing {csv_path}"


def test_load_and_convert_produces_battle_columns(csv_path):
    df = load_and_convert(csv_path)
    required = [
        "battingTeam", "pitchingTeam", "inn", "inning_leadoff", "Runs Scored",
        "event_category", "pitchResult", "total_bases", "any_adv",
        "gameDate", "totalRuns", "opponentRuns", "opponent", "gameId",
    ]
    for c in required:
        assert c in df.columns, f"Missing column {c}"


def test_usd_teams_present(csv_path):
    df = load_and_convert(csv_path)
    assert (df["battingTeam"] == "USD").any() or (df["pitchingTeam"] == "USD").any(), \
        "At least one row should have USD as batting or pitching"


def test_all_games_in_pbp_are_in_results(csv_path):
    """Every game_id in the PBP CSV must appear in battle calc results."""
    raw = pd.read_csv(csv_path)
    raw["game_pbp_id"] = pd.to_numeric(raw["game_pbp_id"], errors="coerce")
    unique_gids = set()
    for v in raw["game_pbp_id"].dropna().unique():
        try:
            unique_gids.add(int(float(v)))
        except (ValueError, TypeError):
            pass
    results, _ = run_battle_calc_for_all_games(csv_path)
    assert len(results) == len(unique_gids), f"Expected {len(unique_gids)} games in results, got {len(results)}"
    for gid in unique_gids:
        assert gid in results, f"Missing game {gid} in results"
        tab = results[gid]
        assert "_error" not in tab, f"Game {gid} error: {tab.get('_error', '')}"


def test_battle_metrics_structure(csv_path):
    results, _ = run_battle_calc_for_all_games(csv_path)
    for gid, tab in results.items():
        if isinstance(tab, dict) and "_error" in tab:
            continue
        expected_metrics = [
            "B1a Leadoff Runners (Off)",
            "B1b Leadoff Runners (Def)",
            "B2a Leadoff Runs % (Off)",
            "B2b Leadoff Stranded % (Def)",
            "B3a Total Baserunners (Off)",
            "B3b Total Baserunners (Def)",
            "B3c Total Bases + XBs (Off)",
            "B4 Defensive Errors (Pitch)",
            "B5a BB+HBP (Off) vs K",
            "B5b BB+HBP (Def)",
        ]
        for m in expected_metrics:
            assert m in tab, f"Game {gid} missing metric {m}"
            assert "display" in tab[m] and "met" in tab[m], f"Game {gid} metric {m} missing display/met"


def test_at_least_one_game_has_offense_metrics(csv_path):
    """San Diego is away in 6419683 and 6455090, so those games should have non-zero USD offense when data has top halves."""
    results, _ = run_battle_calc_for_all_games(csv_path)
    # At least one game should have B1a or B3a > 0 (USD batting rows present)
    has_offense = False
    for gid, tab in results.items():
        if isinstance(tab, dict) and "_error" in tab:
            continue
        if tab.get("B1a Leadoff Runners (Off)", {}).get("value", 0) > 0:
            has_offense = True
            break
        if tab.get("B3a Total Baserunners (Off)", {}).get("value", 0) > 0:
            has_offense = True
            break
    assert has_offense, "At least one game should have USD offense metrics (B1a or B3a > 0)"
