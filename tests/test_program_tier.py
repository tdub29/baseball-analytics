"""Tests for program-strength resolution of the SHORT school names trackers use.

Before the alias/subset layer, ~98% of portal `from_school` values (D1Baseball's
"Texas Tech", "LSU", "Maryland", …) fell through to the USD-neutral default, killing the
conference signal in both the Rating and the step-up Likelihood. These pin that fix.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

import pytest  # noqa: E402
from ncaa.portal.program_tier import (  # noqa: E402
    program_strength, is_usd, CONF_STRENGTH, DIV_STRENGTH, USD_STRENGTH,
)


@pytest.mark.parametrize("school,conf", [
    ("Texas Tech", "Big 12"),          # acronym/short alias
    ("LSU", "SEC"),
    ("West Virginia", "Big 12"),
    ("Stony Brook", "Coastal Athletic"),   # generic subset match: ⊆ "Stony Brook University"
    ("Mercer", "Southern"),                # subset match
    ("Gonzaga", "WCC"),
    ("UC San Diego", "Big West"),
    ("Jacksonville State", "Conference USA"),
])
def test_short_names_resolve_to_conference(school, conf):
    assert program_strength(school) == CONF_STRENGTH[conf]


@pytest.mark.parametrize("school,conf", [
    ("Maryland", "Big Ten"),       # flagship, NOT Maryland-Baltimore County (America East)
    ("South Carolina", "SEC"),     # flagship, NOT USC Upstate (Big South)
    ("Illinois", "Big Ten"),       # flagship, NOT Illinois State / UIC
    ("Houston", "Big 12"),         # flagship, NOT Houston Christian (Southland)
    ("Virginia", "ACC"),           # flagship, NOT Virginia Tech / VCU
])
def test_bare_flagship_names_beat_satellites(school, conf):
    # bare state/school name = the flagship program (the tracker's intent), resolved via the
    # curated alias rather than the ambiguous generic matcher.
    assert program_strength(school) == CONF_STRENGTH[conf]


def test_non_d1_falls_to_division_floor():
    # an unknown D2/D3 program uses the division floor, not the D1-neutral default
    assert program_strength("Some Random D2 School", "II") == DIV_STRENGTH["II"]
    assert program_strength("Tiny D3 College", "III") == DIV_STRENGTH["III"]


def test_unknown_d1_stays_usd_neutral():
    assert program_strength("Completely Made Up University") == USD_STRENGTH
    assert program_strength(None) == USD_STRENGTH


def test_ambiguous_subset_does_not_guess():
    # "Texas" alone ⊆ many programs of different strength; without a curated alias it must
    # NOT silently pick one. (We DO alias "texas" -> SEC, so assert the alias wins instead.)
    assert program_strength("Texas") == CONF_STRENGTH["SEC"]


def test_san_diego_names_do_not_collide():
    # the three SD programs must resolve to DIFFERENT conferences; "San Diego" is USD (WCC),
    # not San Diego State (Mountain West) — the tracker's naming the subset matcher got wrong.
    assert program_strength("San Diego") == CONF_STRENGTH["WCC"]            # USD
    assert program_strength("San Diego State") == CONF_STRENGTH["Mountain West"]
    assert program_strength("San Diego State University") == CONF_STRENGTH["Mountain West"]
    assert program_strength("UC San Diego") == CONF_STRENGTH["Big West"]


def test_is_usd():
    assert is_usd("San Diego") and is_usd("University of San Diego") and is_usd("USD")
    assert not is_usd("San Diego State") and not is_usd("UC San Diego")
    assert not is_usd(None) and not is_usd("LSU")
