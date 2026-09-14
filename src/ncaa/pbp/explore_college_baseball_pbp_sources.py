"""
Explore College Baseball Play-by-Play Data Sources (R & Python)
===============================================================

This script documents packages and methods to gather college (NCAA) baseball
play-by-play data in R and Python. The primary public source is stats.ncaa.org;
there is no official NCAA API, so all tools scrape or parse that site.

Run this file to print the summary and optionally test available Python packages.
Usage: python explore_college_baseball_pbp_sources.py [--test]
"""

from __future__ import annotations

import argparse
from textwrap import dedent

# -----------------------------------------------------------------------------
# SUMMARY: PACKAGES AND DATA SOURCES
# -----------------------------------------------------------------------------

R_PACKAGES = """
R PACKAGES FOR NCAA BASEBALL PLAY-BY-PLAY
-----------------------------------------

1. baseballr (CRAN)
   - Install: install.packages("baseballr")
   - Docs: https://billpetti.github.io/baseballr/
   - NCAA functions: ncaa_pbp(), ncaa_schedule_info(), ncaa_roster(), ncaa_game_logs(), ncaa_lineups(), ncaa_teams()
   - Play-by-play: ncaa_pbp(game_info_url = ..., game_pbp_url = ...)
     * Get URLs from ncaa_schedule_info(team_id, year); returns game_info_url and game_pbp_url per game.
     * Returns: game_date, location, attendance, inning, inning_top_bot, score, batting, fielding, description, game_pbp_url, game_pbp_id
   - Optional: raw_html_to_disk = TRUE to cache HTML; read_from_file to read cached HTML later.
   - Source: stats.ncaa.org (scraped).

2. bigbaseballR (GitHub only)
   - Install: devtools::install_github("joffejackS/bigbaseballR")
   - Focus: schedule, roster, play-by-play via stats.ncaa.com.
   - Key functions: get_team_schedule(), get_play_by_play(game_ids), scrape_game(game_id), get_team_roster(), get_date_games().
   - get_play_by_play(schedule$Game_ID) returns aggregated play-by-play; scrape_game(game_id) for one game.
   - Note: Docs may be outdated; team/season params may be limited to certain seasons (e.g. 2016–2019).
   - Source: stats.ncaa.org.
"""

PYTHON_PACKAGES = """
PYTHON PACKAGES FOR NCAA BASEBALL (PLAY-BY-PLAY OR RELATED)
----------------------------------------------------------

1. pbpy (GitHub, no PyPI)
   - Install: pip install git+https://github.com/milesokamoto/pbpy
   - Purpose: Play-by-play scraper/parser from stats.ncaa.org; aims for Retrosheet-like format.
   - Best fit for: Raw play-by-play in a structured format. Check repo for exact API (scrape by game/schedule).

2. ncaa_stats_py (PyPI)
   - Install: pip install ncaa_stats_py
   - Purpose: Download/parse NCAA data; includes baseball teams and rosters.
   - Functions: get_baseball_teams(season, level), get_baseball_team_roster(...). Caching and rate limiting (5s between calls).
   - Play-by-play: Not clearly documented in main docs; repo may have game/play-by-play helpers. Worth checking ncaa_stats_py.baseball submodule.

3. ncaa-bbStats (PyPI)
   - Install: pip install ncaa_bbStats
   - Purpose: Team stats (batting/pitching/fielding) and MLB draft results; Div I/II/III, 2002–2025.
   - Functions: get_team_stat(), display_specific_team_stat(), parse_mlb_draft(), get_drafted_players_mlb(), etc.
   - Play-by-play: No; aggregate season/career stats and draft only. Useful for context, not PBP.

4. collegebaseball (GitHub)
   - Install: pip install git+https://github.com/nathanblumenfeld/collegebaseball
   - Purpose: College baseball analysis; data acquisition and advanced metrics.
   - Play-by-play: Listed as "Planned Feature" on repo; may not be implemented yet.

5. NCAA-baseball (davmiller, GitHub)
   - Scraper/parser for NCAA D1; play-by-play and expected runs. Example seasons 2017–2018. No standard pip package; clone repo and run scripts.

6. armstjc/ncaa_baseball_data (GitHub)
   - Data repo with play_by_play_data/raw, season_stats, rosters. Scripts: get_game_stats.py, get_day_game_stats.py, etc. Not a single installable package; reference for scraping patterns.
"""

DATA_SOURCE = """
COMMON DATA SOURCE
-----------------
- stats.ncaa.org (official NCAA statistics). No public API; all tools scrape HTML or use undocumented endpoints.
- Typical workflow: get team ID / schedule (with game IDs or box_score/play_by_play URLs), then fetch PBP per game.
- Rate limiting and caching are recommended to avoid overloading the site.
"""

R_USAGE_EXAMPLE = """
R USAGE EXAMPLE (baseballr)
--------------------------
# Install: install.packages("baseballr")
library(baseballr)

# Get schedule for a team (need team_id and year from ncaa_teams or manual lookup)
# team_id 736 is one example; get URLs for each game:
sched <- ncaa_schedule_info(team_id = 736, year = 2022)
# sched has game_info_url and game_pbp_url (or similar) per row

# Fetch play-by-play for one game (use URLs from sched)
pbp <- ncaa_pbp(game_info_url = sched$game_info_url[1])
# Returns: game_date, location, inning, inning_top_bot, score, batting, fielding, description, etc.

# Optional: cache raw HTML to disk
pbp <- ncaa_pbp(game_info_url = url, raw_html_to_disk = TRUE, raw_html_path = "./cache")
"""


def print_section(title: str, body: str) -> None:
    print("\n" + "=" * 60)
    print(title)
    print("=" * 60)
    print(dedent(body).strip())
    print()


def test_python_packages() -> None:
    """Try importing and (where possible) minimal usage of Python packages."""
    print("\n--- Testing Python package availability ---\n")

    # ncaa_stats_py
    try:
        from ncaa_stats_py.baseball import get_baseball_teams  # type: ignore
        print("[OK] ncaa_stats_py: import succeeded (get_baseball_teams).")
    except ImportError as e:
        print("[--] ncaa_stats_py: not installed.", str(e))

    # ncaa_bbStats (ncaa-bbStats on PyPI)
    try:
        import ncaa_bbStats  # type: ignore
        print("[OK] ncaa_bbStats: import succeeded (team/draft stats only, no PBP).")
    except ImportError:
        try:
            import ncaa_bbstats  # type: ignore
            print("[OK] ncaa_bbStats (alt name): import succeeded.")
        except ImportError as e:
            print("[--] ncaa_bbStats: not installed.", str(e))

    # pbpy
    try:
        import pbpy  # type: ignore
        print("[OK] pbpy: import succeeded.")
    except ImportError as e:
        print("[--] pbpy: not installed (install from GitHub: pip install git+https://github.com/milesokamoto/pbpy).", str(e))

    # collegebaseball
    try:
        import collegebaseball  # type: ignore
        print("[OK] collegebaseball: import succeeded.")
    except ImportError as e:
        print("[--] collegebaseball: not installed.", str(e))

    print("\n--- End package checks ---\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Explore college baseball PBP data sources (R & Python).")
    parser.add_argument("--test", action="store_true", help="Test which Python packages are installed.")
    args = parser.parse_args()

    print_section("R PACKAGES", R_PACKAGES)
    print_section("PYTHON PACKAGES", PYTHON_PACKAGES)
    print_section("DATA SOURCE", DATA_SOURCE)
    print_section("R USAGE EXAMPLE (baseballr)", R_USAGE_EXAMPLE)

    if args.test:
        test_python_packages()
    else:
        print("Run with --test to check which Python packages are installed.")


if __name__ == "__main__":
    main()
