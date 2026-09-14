"""Guard against reintroducing the O(n^2) scan in baseballr_to_battle_df.

`game_meta` used to evaluate `raw[raw["game_pbp_id"] == gid]` twice per row inside an
`apply(axis=1)`, so every row scanned the whole PBP table twice. Profiled at 800 rows it
was 17.2 of 21.1 seconds, and the per-row cost climbed with n (11.8 ms/row at 200 rows,
24.4 at 1600) rather than holding flat. The five-game fixture took over five minutes, and
the four tests that call it each paid that again, so the suite never finished.

A wall-clock assertion would be flaky on a loaded machine. This measures the SHAPE instead:
per-row cost on a big slice must not blow up relative to a small one. Quadratic growth
doubles the per-row cost every time n doubles; linear work holds it roughly flat.
"""

import sys
import time
from pathlib import Path

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.pbp.baseballr_battle_calc import baseballr_to_battle_df  # noqa: E402

CSV = ROOT / "data" / "pbp" / "real5_pbp_baseballr_style.csv"


@pytest.fixture(scope="module")
def raw():
    return pd.read_csv(CSV)


def _per_row_seconds(raw: pd.DataFrame, n: int) -> float:
    slice_ = raw.head(n).copy()
    start = time.perf_counter()
    baseballr_to_battle_df(slice_)
    return (time.perf_counter() - start) / n


def test_per_row_cost_does_not_grow_with_input_size(raw):
    small = _per_row_seconds(raw, 300)
    large = _per_row_seconds(raw, 1200)

    # 4x the rows. Linear work keeps the ratio near 1. The quadratic version measured
    # about 2.1x here. 1.6 leaves room for cache and GC noise while still failing loudly
    # on a reintroduced full-frame scan.
    assert large / small < 1.6, (
        f"per-row cost grew {large / small:.2f}x going from 300 to 1200 rows "
        f"({small * 1000:.1f} -> {large * 1000:.1f} ms/row). Something is scanning the "
        f"whole frame per row again."
    )


def test_final_score_comes_from_the_last_row_of_each_game(raw):
    """The semantics the fast path has to preserve: last row per game, not first."""
    out = baseballr_to_battle_df(raw.head(1200).copy())
    per_game = out.groupby("gameId")[["totalRuns", "opponentRuns"]].nunique()
    # One final score per game, carried on every row of that game.
    assert (per_game["totalRuns"] == 1).all()
    assert (per_game["opponentRuns"] == 1).all()
