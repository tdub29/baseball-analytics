"""
Scrape NCAA play-by-play from stats.ncaa.org — easiest path.

  python Baseball/scrape_ncaa_pbp.py
  python Baseball/scrape_ncaa_pbp.py 6500370
  python Baseball/scrape_ncaa_pbp.py "https://stats.ncaa.org/contests/6500370/play_by_play"
  python Baseball/scrape_ncaa_pbp.py 6500370 -o my_pbp.csv

Output: Baseball/pbp_ncaa_playwright_baseballr_style.csv (or -o path).

Why this approach:
- stats.ncaa.org returns 403 for plain requests and serves an Akamai bot
  challenge for curl_cffi, so the real PBP HTML is only delivered in a real
  browser. Playwright (with a visible window by default) is the reliable way.
- MCP/browser can open the page but cannot extract full HTML from it
  programmatically, so automation here is Playwright-based.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(OUT_DIR))

from ncaa_pbp_playwright import (
    fetch_pbp_with_playwright,
    parse_pbp_table,
    BASEBALLR_COLUMNS,
    extract_contest_id,
)
import pandas as pd


DEFAULT_URL = "https://stats.ncaa.org/contests/6500370/play_by_play"
DEFAULT_CSV = OUT_DIR / "pbp_ncaa_playwright_baseballr_style.csv"


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape NCAA PBP (Playwright)")
    parser.add_argument("url_or_id", nargs="?", help="Contest ID or full play_by_play URL")
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_CSV, help="Output CSV path")
    parser.add_argument("--headless", action="store_true", help="Run browser headless (may get blocked)")
    args = parser.parse_args()

    raw = args.url_or_id
    if not raw:
        url = DEFAULT_URL
    elif raw.isdigit():
        url = f"https://stats.ncaa.org/contests/{raw}/play_by_play"
    else:
        url = raw.strip()

    game_id = extract_contest_id(url)
    if not game_id:
        print("Could not parse contest ID from URL. Use a URL or numeric contest ID.")
        sys.exit(1)

    print(f"Fetching: {url}")
    html = fetch_pbp_with_playwright(url, headless=args.headless)
    rows = parse_pbp_table(html, game_pbp_url=url, game_pbp_id=game_id)

    if not rows:
        print("No play-by-play rows parsed. Raw HTML saved to ncaa_pbp_debug.html")
        (OUT_DIR / "ncaa_pbp_debug.html").write_text(html, encoding="utf-8")
        sys.exit(1)

    df = pd.DataFrame(rows)[BASEBALLR_COLUMNS]
    out = args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    print(f"Rows: {len(df)}")
    print(f"Written: {out}")


if __name__ == "__main__":
    main()
