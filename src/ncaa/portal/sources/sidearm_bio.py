"""Sidearm roster -> hometown/HS bio CSV  (FALLBACK source).

Most college athletics sites run on Sidearm Sports, whose roster pages carry the
most complete bio: **Hometown, High School, AND Previous School** — richer than
the stats.ncaa.org roster (which has hometown/HS but not previous school). Use
this to backfill players the NCAA spine misses, or where you want previous-school.

Trade-off vs. the NCAA spine: every program is a separate URL and Sidearm has
several template versions, so this is a *targeted fallback*, not a bulk crawl.

OUTPUT CONTRACT (identical to scripts/fetch_ncaa_bio.py so `run.py enrich-bio`
loads it unchanged):
    player, team, season, height_in, class_year, bats, throws,
    hometown_city, hometown_state, high_school

USAGE (plan-only default = parse a cached/saved HTML file; no network):
    # parse an already-saved roster page
    python -m portal.sources.sidearm_bio --html data/cache/usd_roster.html \\
        --team "San Diego" --season 2026 --out data/643_exports/bio/sidearm_usd.csv
    # live fetch (opt-in; uses CloakBrowser like the other adapters)
    python -m portal.sources.sidearm_bio --url https://usdtoreros.com/sports/baseball/roster \\
        --team "San Diego" --season 2026 --fetch --out data/643_exports/bio/sidearm_usd.csv

Then: python run.py enrich-bio --path data/643_exports/bio/sidearm_usd.csv --source sidearm
      python run.py geo-tie

NOTE: Sidearm markup varies by template/version. The selectors below cover the
common modern layout; verify against your target site and extend SELECTORS if a
field comes back empty. Internal USD evaluation use only — respect ToS/rate limits.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.util import parse_height_to_inches, parse_hometown  # type: ignore  # noqa: E402

OUT_COLS = ["player", "team", "season", "height_in", "class_year", "bats", "throws",
            "hometown_city", "hometown_state", "high_school"]

# class-suffix -> field; selectors for the modern Sidearm "card" layout.
SELECTORS = {
    "name": [".sidearm-roster-player-name", "[class*=player-name]", "h3"],
    "hometown": [".sidearm-roster-player-hometown", "[class*=hometown]"],
    "highschool": [".sidearm-roster-player-highschool",
                   ".sidearm-roster-player-previous-school", "[class*=highschool]"],
    "class_year": [".sidearm-roster-player-academic-year", "[class*=academic-year]"],
    "height": [".sidearm-roster-player-height", "[class*=player-height]"],
}


def _first_text(node, selectors) -> str | None:
    for sel in selectors:
        el = node.select_one(sel)
        if el:
            txt = el.get_text(" ", strip=True)
            if txt:
                return txt
    return None


def parse_sidearm_roster(html: str, team: str, season: str) -> list[dict]:
    """Parse Sidearm roster HTML -> bio rows (card layout, with a table fallback)."""
    soup = BeautifulSoup(html, "lxml")
    rows: list[dict] = []

    # --- card layout: one node per player ---
    cards = soup.select("li.sidearm-roster-player, .sidearm-roster-player")
    for c in cards:
        name = _first_text(c, SELECTORS["name"])
        if not name:
            continue
        city, state = parse_hometown(_first_text(c, SELECTORS["hometown"]))
        rows.append({
            "player": name, "team": team, "season": season,
            "height_in": parse_height_to_inches(_first_text(c, SELECTORS["height"])),
            "class_year": _first_text(c, SELECTORS["class_year"]),
            "bats": None, "throws": None,
            "hometown_city": city, "hometown_state": state,
            "high_school": _first_text(c, SELECTORS["highschool"]),
        })
    if rows:
        return rows

    # --- table fallback: header-driven, like the NCAA roster table ---
    for t in soup.find_all("table"):
        heads = [th.get_text(strip=True) for th in t.find_all("th")]
        low = [h.lower() for h in heads]
        if not any("hometown" in h for h in low):
            continue
        idx = {h.lower(): i for i, h in enumerate(heads)}

        def col(cells, *names, idx=idx):   # bind the loop's idx, not the last one
            for n in names:
                for k, i in idx.items():
                    if n in k and i < len(cells):
                        return cells[i]
            return None

        for tr in (t.find("tbody") or t).find_all("tr"):
            cells = [td.get_text(" ", strip=True) for td in tr.find_all("td")]
            if not cells:
                continue
            name = col(cells, "name", "player")
            if not name:
                continue
            city, state = parse_hometown(col(cells, "hometown"))
            rows.append({
                "player": name, "team": team, "season": season,
                "height_in": parse_height_to_inches(col(cells, "height", "ht")),
                "class_year": col(cells, "class", "year"),
                "bats": col(cells, "bats", "b/t"), "throws": col(cells, "throws"),
                "hometown_city": city, "hometown_state": state,
                "high_school": col(cells, "high school", "previous", "last school"),
            })
        if rows:
            break
    return rows


def write_csv(rows: list[dict], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=OUT_COLS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in OUT_COLS})


def main():
    ap = argparse.ArgumentParser(description="Sidearm roster -> hometown/HS bio CSV")
    ap.add_argument("--url", help="roster URL (requires --fetch)")
    ap.add_argument("--html", help="path to a saved/cached roster HTML file (offline)")
    ap.add_argument("--team", required=True, help="export team string (the join key)")
    ap.add_argument("--season", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--fetch", action="store_true",
                    help="opt in to a LIVE CloakBrowser fetch of --url (off by default)")
    ap.add_argument("--cookie", default=None)
    args = ap.parse_args()

    if args.html:
        html = Path(args.html).read_text(encoding="utf-8", errors="ignore")
    elif args.url and args.fetch:
        from ncaa.portal.stealth import stealth_get
        html = stealth_get(args.url, cookie=args.cookie,
                           wait_selector=".sidearm-roster-player, table",
                           cache_as=f"sidearm_{args.team.replace(' ', '_').lower()}.html")
    else:
        sys.exit("provide --html <file> (offline) or --url ... --fetch (live)")

    rows = parse_sidearm_roster(html, args.team, args.season)
    write_csv(rows, Path(args.out))
    have_home = sum(1 for r in rows if r.get("hometown_city") or r.get("hometown_state"))
    print(f"{args.team} {args.season}: {len(rows)} players, {have_home} with hometown "
          f"-> {args.out}")


if __name__ == "__main__":
    main()
