"""
Fetch NCAA baseball play-by-play from stats.ncaa.org using Playwright and write
baseballr-style CSV. Bypasses 403 issues from direct HTTP requests.

Usage:
  pip install playwright pandas beautifulsoup4
  playwright install chromium
  python Baseball/ncaa_pbp_playwright.py [URL]

  Use --no-headless (default) to show the browser; stats.ncaa.org often blocks
  headless automation. Omit --no-headless to try headless (may get Access Denied).

Default URL: https://stats.ncaa.org/contests/6500370/play_by_play
  Output: Baseball/pbp_ncaa_playwright_baseballr_style.csv

  By default the CSV includes validation columns (inning_leadoff, is_pa, reached_base,
  runs_scored_half, event totals, batting_team_norm/pitching_team_norm, etc.) for
  parity with baseballr_battle_calc. Use --raw-only for scrape columns only.
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

DEFAULT_URL = "https://stats.ncaa.org/contests/6500370/play_by_play"
OUT_DIR = Path(__file__).resolve().parent
OUT_CSV = OUT_DIR / "pbp_ncaa_playwright_baseballr_style.csv"

BASEBALLR_COLUMNS = [
    "game_date",
    "location",
    "attendance",
    "inning",
    "inning_top_bot",
    "outs",
    "score",
    "batting",
    "fielding",
    "description",
    "game_pbp_url",
    "game_pbp_id",
]


def extract_contest_id(url: str) -> str:
    m = re.search(r"/contests/(\d+)", url)
    return m.group(1) if m else ""


# Patterns that indicate a real play description (player name + action)
PLAY_DESC_PATTERN = re.compile(
    r"(struck out|walked|singled|doubled|tripled|homered|grounded|flied|infield\s+fly|lined|popped|fouled out|"
    r"hit by pitch|sacrifice|scored|advanced|out|reached|stole|caught stealing|picked off|"
    r"wild pitch|passed ball|balk|interference|error|E\d)",
    re.I,
)

# One-time exception: this sac bunt should not be coded as an out (per user request).
_MEIDROTH_SAC_BUNT_NO_OUT = (
    "Meidroth,Connor sacrifice bunt in front of the plate, unassisted (1-1 BF); Mestas,Gage advanced to third base."
)


def _effective_outs_added(outs_so_far_this_half: int, outs_on_play_raw: int) -> int:
    """Cap outs so a half-inning never exceeds 3 (e.g. GIDP with 2 outs already is only the 3rd out)."""
    room = max(0, 3 - outs_so_far_this_half)
    return min(max(0, outs_on_play_raw), room)


def _outs_on_play(description: str) -> int:
    """Infer number of outs recorded on this play (0, 1, 2, or 3) from description text."""
    if not description:
        return 0
    if description.strip() == _MEIDROTH_SAC_BUNT_NO_OUT:
        return 0
    d = description.lower()
    # Replay-review banners (no plate outcome yet); often mention "caught stealing" etc.
    # and must not advance outs / flip halves (contest 6507273).
    if "under review" in d:
        return 0
    # Replay challenge result only (e.g. "... challenge of out at second is unsuccessful"):
    # the out was already on the batted play; "out at second" here must not add another out.
    if "challenge" in d:
        return 0
    # Runner advances on an error; trailing ", picked off" is often a balky throw / no out on this row
    # (e.g. "Moran advanced to third on an error by p, picked off." — not a 1-out play for half-inning state).
    if re.search(
        r"advanced to (first|second|third|home) on an error",
        d,
    ) and "picked off" in d:
        return 0
    # Triple play = 3 outs
    if "triple play" in d:
        return 3
    # Double play = 2 outs (batter + one runner)
    if "double play" in d or "dp)" in d:
        return 2
    # Struck out but batter reaches (dropped 3K + reached first / on wild pitch / on error) = no out
    if ("struck out" in d or "struck out swinging" in d or "struck out looking" in d) and (
        "reached first" in d
        or "reached on" in d
        or re.search(r"\breached (first|second|third|home)\b", d)
    ):
        return 0
    # Sacrifice bunt with error (batter safe, e.g. "sacrifice bunt, error throwing by p") = no out
    if "sacrifice bunt" in d and ("error" in d or re.search(r"\be\d\b", d)):
        return 0
    # Multiple outs: count explicit "out at [base]" only (sec = second). One "out at" = 1 out; two = 2 outs.
    # e.g. "Mestas reached on a fielder's choice; Greer out at second" = 1 out. "Kern reached on a fielder's choice; Lobliner out at second; Springer out at third" = 2 outs.
    out_at_base = len(re.findall(r"out at (first|second|third|home|1b|2b|3b|sec)\b", d))
    if out_at_base >= 2:
        return min(out_at_base, 3)
    # Batter fly/line/pop/foul out PLUS explicit runner "... out at base ..." on the same row
    # (NCAA joins with ";"). Otherwise ``flied out`` alone returns 1 and we miss the runner out —
    # half stays open and the next half's plays stay mis-tagged (e.g. 6522574 inn 1 top:
    # "Lobliner flied out to lf; Gauna out at third lf to 3b.").
    batter_air_out = (
        "flied out" in d
        or "lined out" in d
        or "popped out" in d
        or "popped up to" in d
        or "popped up to " in d
        or "fouled out" in d
    )
    if (
        batter_air_out
        and out_at_base >= 1
        and "double play" not in d
        and "triple play" not in d
    ):
        return min(1 + out_at_base, 3)
    # One out: batter or runner out on a clear out play
    # "to 1b"/"to ss" etc. only count as out when part of a putout (not e.g. "Gonzalez, D. to ss." substitution)
    to_pos_match = bool(re.search(r"\b(to 1b|to 2b|to 3b|to ss| to c| to p| to lf| to rf| to cf)\s*[\),.]", d))
    to_pos_is_putout = to_pos_match and (
        "out" in d or "grounded" in d or "flied" in d or "lined" in d or "popped" in d or "putout" in d
    )
    one_out = (
        "struck out" in d or "struck out swinging" in d or "struck out looking" in d
        or "grounded out" in d or "grounded into" in d
        or "flied out" in d or "flied out to" in d
        or "lined out" in d or "popped out" in d or "fouled out" in d
        or "infield fly" in d  # IFR: batter out though text may not say "flied out"
        or "popped up to" in d or "popped up to " in d  # "popped up to 3b"
        or "caught stealing" in d or "picked off" in d
        or "sacrifice fly" in d or "sacrifice bunt" in d
        or "putout by" in d
        or "out at " in d
        or to_pos_is_putout
    )
    # Batter/main putout plus a trailing runner "... out on the play" (often no literal "double play").
    # Counting as 1 desyncs top/bottom and batting/fielding for the rest of the feed (contest 6535305 bot 4).
    if re.search(r"\bout on the play\b", d) and (
        "grounded out" in d
        or "grounded into" in d
        or "flied out" in d
        or "lined out" in d
        or "popped out" in d
        or "popped up to" in d
        or "popped up to " in d
        or "fouled out" in d
        or "sacrifice fly" in d
        or "sacrifice bunt" in d
    ):
        return 2
    if one_out:
        return 1
    return 0


def _is_challenge_result_banner(desc: str) -> bool:
    """Replay/challenge outcome lines that NCAA often places *after* the 3rd-out row.

    Those rows belong to the half that just ended, not the next half (e.g. 6507273
    top 6 CS review: 'Call of caught stealing stands...' should not be tagged bot 6).
    """
    if not desc:
        return False
    d = desc.lower().strip()
    if "under review" in d:
        return False
    if "challenge" in d and ("remaining" in d or "exhausted" in d):
        return True
    if "call of" in d and ("stands" in d or "overturned" in d or "upheld" in d or "confirmed" in d):
        return True
    return False


def _looks_like_play(desc: str) -> bool:
    if not desc:
        return False
    # Allow short play text that matches a known action (e.g. "Kern walked.")
    if len(desc) < 15 and not PLAY_DESC_PATTERN.search(desc):
        return False
    # Skip header/nav/UI text
    skip = (
        "attendance:", "box score", "individual stats", "situational stats", "play by play",
        "umpires", "conf ", "blair field", "02/17/2026", "02/18/2026",
    )
    lower = desc.lower()
    if any(s in lower for s in skip):
        return False
    if re.match(r"^\d+-\d+$", desc) or re.match(r"^\d{1,2}/\d{1,2}/\d{2,4}", desc):
        return False
    if len(desc) <= 3 or desc in ("H", "5", "R", "E"):
        return False
    return bool(PLAY_DESC_PATTERN.search(desc)) or ("," in desc and "." in desc)


def parse_pbp_table(html: str, game_pbp_url: str, game_pbp_id: str) -> list[dict]:
    soup = BeautifulSoup(html, "html.parser")
    rows_out = []

    tables = soup.find_all("table")
    if not tables:
        return rows_out

    game_date = ""
    location = ""
    attendance = ""
    away_team = ""
    home_team = ""

    for tag in soup.find_all(["h1", "h2", "h3"]):
        t = tag.get_text(strip=True)
        if re.search(r"\d{1,2}/\d{1,2}/\d{2,4}", t):
            game_date = re.sub(r"\s+\d{1,2}:\d{2}\s*[AP]M$", "", t)
            break

    # NCAA uses /teams/ in URLs (e.g. stats.ncaa.org/teams/614731).
    # Prefer the two links that appear in the same table row (score header); else use first two with full names.
    def _clean_team_name(s: str) -> str:
        s = (s or "").strip()
        for _ in range(2):
            if "," in s:
                s = s.split(",")[0].strip()
        s = re.sub(r" \d+-\d+$", "", s).strip()
        return s

    team_links = soup.select('a[href*="/teams/"]')
    # Find a row that contains exactly two /teams/ links (away and home in order)
    two_in_row = []
    for tr in soup.find_all("tr"):
        links = tr.select('a[href*="/teams/"]')
        if len(links) == 2:
            t0 = (links[0].get_text(strip=True) or "").strip()
            t1 = (links[1].get_text(strip=True) or "").strip()
            if len(t0) > 2 and len(t1) > 2:
                two_in_row = [t0, t1]
                break
    if two_in_row:
        away_team = _clean_team_name(two_in_row[0])
        home_team = _clean_team_name(two_in_row[1])
    elif len(team_links) >= 2:
        # Fallback: first two links with non-empty, multi-word text (skip duplicates)
        seen = set()
        candidates = []
        for a in team_links:
            t = (a.get_text(strip=True) or "").strip()
            t_clean = _clean_team_name(t)
            if len(t_clean) > 2 and t_clean not in seen:
                seen.add(t_clean)
                candidates.append(t_clean)
        if len(candidates) >= 2:
            away_team = candidates[0]
            home_team = candidates[1]
        else:
            away_team = _clean_team_name(team_links[0].get_text(strip=True))
            home_team = _clean_team_name(team_links[1].get_text(strip=True))

    # First pass: collect cell text to infer game_date, location, attendance
    all_cells = []
    for t in tables:
        for tr in (t.find("tbody") or t).find_all("tr"):
            for c in tr.find_all(["td", "th"]):
                all_cells.append(c.get_text(strip=True))
    for c in all_cells:
        if not game_date and re.match(r"\d{1,2}/\d{1,2}/\d{4}", c):
            game_date = re.sub(r"\s+\d{1,2}:\d{2}\s*[AP]M.*$", "", c).strip()
        if not location and 10 < len(c) < 80 and "field" in c.lower() and "(" in c and not _looks_like_play(c):
            location = c
        if not attendance and c.lower().strip().startswith("attendance:"):
            attendance = c.replace("Attendance:", "").replace(",", "").strip()

    current_inning = 1
    current_top_bot = "top"
    score_away = 0
    score_home = 0
    outs_this_half = 0
    prev_play_description = ""
    # After a half ends, NCAA may insert a challenge/review banner; attribute it to the half that closed.
    last_closed_half_key: tuple[int, str] | None = None

    for table in tables:
        tbody = table.find("tbody") or table
        body_rows = tbody.find_all("tr") if tbody else []
        has_any_play = any(
            _looks_like_play(c.get_text(strip=True))
            for tr in body_rows
            for c in tr.find_all(["td", "th"])
        )
        if not has_any_play:
            continue

        for tr in body_rows:
            cells = tr.find_all(["td", "th"])
            if not cells:
                continue
            cell_texts = [c.get_text(strip=True) for c in cells]

            for c in cell_texts:
                if re.match(r"^\d+-\d+$", c):
                    parts = c.split("-")
                    if len(parts) == 2:
                        try:
                            score_away, score_home = int(parts[0]), int(parts[1])
                        except ValueError:
                            pass
                    break

            description = ""
            for c in cell_texts:
                if _looks_like_play(c):
                    description = c
                    break
            if not description:
                continue

            # Assign inning and half to this play (state at start of play)
            reattached_challenge_footer = False
            row_half = current_top_bot
            if _is_challenge_result_banner(description) and last_closed_half_key is not None:
                inn_use, tb_use = last_closed_half_key
                inning_str = str(inn_use)
                top_bot_str = tb_use.replace("bottom", "bot")
                row_half = tb_use
                last_closed_half_key = None
                reattached_challenge_footer = True
            else:
                if last_closed_half_key is not None and not _is_challenge_result_banner(description):
                    last_closed_half_key = None
                inning_str = str(current_inning)
                top_bot_str = current_top_bot.replace("bottom", "bot")

            batting_team = away_team or "Away" if row_half == "top" else home_team or "Home"
            fielding_team = home_team or "Home" if row_half == "top" else away_team or "Away"

            # Outs: cumulative in this half-inning after this play (for debugging top/bot flip)
            outs_raw = _outs_on_play(description)
            # NCAA often emits "under review" then repeats "out caught stealing" at the top of the next half;
            # that row duplicates the third out already applied — skip counting it (contest 6507273).
            if (
                outs_this_half == 0
                and "out caught stealing" in description.lower()
                and prev_play_description
                and "under review" in prev_play_description.lower()
            ):
                outs_raw = 0
            outs_on_play = _effective_outs_added(outs_this_half, outs_raw)
            outs_after_play = outs_this_half + outs_on_play
            # Footer was written after we flipped state; without this it gets outs=0 and looks identical
            # to the first play of the next half (also 0 outs).
            if reattached_challenge_footer:
                outs_after_play = 3

            rows_out.append({
                "game_date": game_date,
                "location": location,
                "attendance": attendance,
                "inning": inning_str,
                "inning_top_bot": top_bot_str,
                "outs": outs_after_play,
                "score": f"{score_away}-{score_home}",
                "batting": batting_team,
                "fielding": fielding_team,
                "description": description,
                "game_pbp_url": game_pbp_url,
                "game_pbp_id": game_pbp_id,
            })

            # Count outs on this play and advance half-inning every 3 outs
            outs_this_half += outs_on_play
            if outs_this_half >= 3:
                closing_inn, closing_tb = current_inning, current_top_bot
                outs_this_half = 0
                if current_top_bot == "top":
                    current_top_bot = "bottom"
                else:
                    current_top_bot = "top"
                    current_inning += 1
                last_closed_half_key = (closing_inn, closing_tb)

            prev_play_description = description

    return rows_out


def fetch_pbp_with_playwright(url: str, headless: bool = True) -> str:
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


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch NCAA PBP via Playwright and write baseballr-style CSV")
    parser.add_argument("url", nargs="?", default=DEFAULT_URL, help="Play-by-play page URL")
    parser.add_argument("--no-headless", action="store_true", default=True, help="Show browser (default; site often blocks headless)")
    parser.add_argument("--headless", action="store_true", help="Run browser headless (may get Access Denied)")
    parser.add_argument("-o", "--output", type=Path, default=OUT_CSV, help="Output CSV path")
    parser.add_argument(
        "--raw-only",
        action="store_true",
        help="Write only NCAA scrape columns (no battle-calc validation columns)",
    )
    parser.add_argument("--debug", action="store_true", help="Write table structure to ncaa_pbp_table_debug.txt")
    args = parser.parse_args()

    url = args.url
    game_pbp_id = extract_contest_id(url)
    if not game_pbp_id:
        print("Could not parse contest ID from URL")
        return

    print(f"Fetching: {url}")
    html = fetch_pbp_with_playwright(url, headless=args.headless)
    rows = parse_pbp_table(html, game_pbp_url=url, game_pbp_id=game_pbp_id)

    if not rows:
        print("No play-by-play rows parsed. Saving raw HTML for inspection.")
        debug_html = OUT_DIR / "ncaa_pbp_debug.html"
        Path(debug_html).write_text(html, encoding="utf-8")
        print(f"Saved: {debug_html}")
    # Debug: dump first table structure (first 25 rows) to see column order
    if rows and args.debug:
        soup = BeautifulSoup(html, "html.parser")
        tables = soup.find_all("table")
        lines = []
        for ti, t in enumerate(tables[:4]):
            tbody = t.find("tbody") or t
            for ri, tr in enumerate((tbody.find_all("tr") if tbody else [])[:25]):
                cells = [c.get_text(strip=True)[:40] for c in tr.find_all(["td", "th"])]
                lines.append(f"T{ti} R{ri}: {cells}")
        (OUT_DIR / "ncaa_pbp_table_debug.txt").write_text("\n".join(lines), encoding="utf-8")
        print("Debug: saved ncaa_pbp_table_debug.txt")
    df = pd.DataFrame(rows) if rows else pd.DataFrame(columns=BASEBALLR_COLUMNS)
    if rows:
        df = df[BASEBALLR_COLUMNS]

    if rows and len(df) and not args.raw_only:
        # Same enrichment as fetch_multiple_ncaa_pbp / battle calc troubleshooting CSV
        from ncaa.pbp.baseballr_battle_calc import add_leadoff_column_to_pbp, build_complete_games_lookup

        lookup = build_complete_games_lookup(df, args.output)
        df = add_leadoff_column_to_pbp(df, games_lookup=lookup)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    print(f"Rows: {len(df)}")
    print(f"Written: {args.output}")


if __name__ == "__main__":
    main()
