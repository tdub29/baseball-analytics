"""
Fetch USD (San Diego) baseball schedule from stats.ncaa.org by loading the team
page and parsing the Schedule/Results table. Optionally follows each game link
to confirm contest IDs. Uses Playwright (visible browser) like ncaa_pbp_playwright.

Usage:
  pip install playwright pandas beautifulsoup4
  playwright install chromium
  python ncaa_schedule_playwright.py

  Optional: --team-id 614731  --year 2026  -o usd_2026_schedule.csv

Output: usd_2026_schedule.csv with game_date, opponent, home_away, result,
        attendance, contest_id, game_url
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import pandas as pd

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    raise SystemExit("Install Playwright: pip install playwright && playwright install chromium")

try:
    from bs4 import BeautifulSoup
except ImportError:
    raise SystemExit("Install BeautifulSoup: pip install beautifulsoup4")

OUT_DIR = Path(__file__).resolve().parent
DEFAULT_TEAM_ID = "614731"  # San Diego Toreros
DEFAULT_OUT_CSV = OUT_DIR / "usd_2026_schedule.csv"


def fetch_page_with_playwright(url: str, headless: bool = False) -> str:
    """Load URL with Playwright and return page HTML."""
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"] if headless else [],
        )
        try:
            context = browser.new_context(
                viewport={"width": 1280, "height": 720},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
                locale="en-US",
            )
            context.add_init_script("Object.defineProperty(navigator, 'webdriver', { get: () => undefined })")
            page = context.new_page()
            page.goto(url, wait_until="domcontentloaded", timeout=30000)
            page.wait_for_timeout(3000)
            return page.content()
        finally:
            browser.close()


def extract_contest_id_from_href(href: str | None) -> str:
    if not href:
        return ""
    m = re.search(r"/contests/(\d+)", href)
    return m.group(1) if m else ""


def parse_schedule_table(html: str, base_url: str = "https://stats.ncaa.org") -> list[dict]:
    """
    Parse the Schedule/Results table on the team page.
    Returns list of dicts: game_date, opponent, home_away, result, attendance, contest_id, game_url.
    """
    soup = BeautifulSoup(html, "html.parser")
    rows_out = []

    # Find all tables; the schedule table usually has "Date" and "Opponent" in header
    for table in soup.find_all("table"):
        thead = table.find("thead")
        if not thead:
            continue
        header_cells = [th.get_text(strip=True).lower() for th in thead.find_all(["th", "td"])]
        if not any("date" in h for h in header_cells) or not any("opponent" in h for h in header_cells):
            continue

        def idx(key: str, default: int = 0, header_cells=header_cells) -> int:
            for i, h in enumerate(header_cells):
                if key in h:
                    return i
            return default

        date_idx = idx("date", 0)
        opp_idx = idx("opponent", 1)
        result_idx = idx("result", 2)
        att_idx = idx("attendance", 3)

        tbody = table.find("tbody") or table
        for tr in tbody.find_all("tr"):
            cells = tr.find_all(["td", "th"])
            if len(cells) <= max(date_idx, opp_idx):
                continue

            date_cell = cells[date_idx].get_text(strip=True)
            opp_cell = cells[opp_idx]
            result_cell = cells[result_idx].get_text(strip=True) if result_idx < len(cells) else ""
            att_cell = cells[att_idx].get_text(strip=True) if att_idx < len(cells) else ""

            # Skip header or empty rows
            if not date_cell or date_cell.lower() == "date":
                continue
            # Skip non-date patterns (e.g. "Total" row)
            if not re.search(r"\d{1,2}/\d{1,2}/\d{2,4}", date_cell):
                continue

            # Opponent: link text; contest link may be in any cell of the row (date or opponent)
            row_contest_link = tr.find("a", href=re.compile(r"/contests/\d+"))
            href = row_contest_link.get("href") if row_contest_link else None
            if href and not href.startswith("http"):
                href = base_url.rstrip("/") + "/" + href.lstrip("/")
            contest_id = extract_contest_id_from_href(href)

            opp_link = opp_cell.find("a", href=True)
            raw_opp_text = opp_cell.get_text(strip=True)
            opponent = (opp_link.get_text(strip=True) if opp_link else raw_opp_text).lstrip("@")

            # Home/away: @ in opponent cell usually means away
            home_away = "Away" if raw_opp_text.startswith("@") else "Home"

            rows_out.append({
                "game_date": date_cell,
                "opponent": opponent,
                "home_away": home_away,
                "result": result_cell,
                "attendance": att_cell,
                "contest_id": contest_id,
                "game_url": href or "",
            })

        if rows_out:
            break

    return rows_out


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch USD baseball schedule from NCAA team page")
    parser.add_argument("--team-id", default=DEFAULT_TEAM_ID, help=f"NCAA team ID (default {DEFAULT_TEAM_ID})")
    parser.add_argument("--year", type=int, default=2026, help="Season year for display")
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUT_CSV, help="Output CSV path")
    parser.add_argument("--headless", action="store_true", help="Run browser headless (may get blocked)")
    args = parser.parse_args()

    url = f"https://stats.ncaa.org/teams/{args.team_id}"
    print(f"Fetching: {url}")
    html = fetch_page_with_playwright(url, headless=args.headless)
    rows = parse_schedule_table(html)

    if not rows:
        debug_html = OUT_DIR / "ncaa_schedule_debug.html"
        Path(debug_html).write_text(html, encoding="utf-8")
        print(f"No schedule rows parsed. Saved HTML to {debug_html}")
        return

    df = pd.DataFrame(rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    print(f"Wrote {len(df)} games to {args.output}")
    print(df.to_string())


if __name__ == "__main__":
    main()
