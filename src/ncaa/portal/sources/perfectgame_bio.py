"""Perfect Game / PBR -> hometown/HS bio CSV  (VERIFICATION source — scaffold).

Perfect Game (perfectgame.org) and Prep Baseball Report (prepbaseballreport.com)
are recruiting databases keyed to the player's amateur career: they carry
**hometown city/state, high school, grad year, and state** with high coverage —
the richest *cross-check* for the hometown/CA-tie layer, and often the only
source for a player whose college roster omits hometown.

Why this is a SCAFFOLD, not a working crawler:
  - Both sit behind JS rendering + login/marketing walls; profiles aren't a clean
    server-rendered table like the NCAA/Sidearm rosters.
  - Matching a PG/PBR amateur profile to a portal player needs name + grad-year +
    state disambiguation (many duplicate names), which is its own resolve step.
So the intended path is: pull a profile page (saved HTML or an authenticated
export), parse it to the shared bio contract, then load + resolve like any other
bio CSV. Implement parse_pg_profile / parse_pbr_profile against a saved page and
verify selectors before running at scale.

OUTPUT CONTRACT (matches sidearm_bio.py / fetch_ncaa_bio.py):
    player, team, season, height_in, class_year, bats, throws,
    hometown_city, hometown_state, high_school

Internal USD evaluation use only — respect each source's ToS, rate limits, and
subscription terms; do not redistribute.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.util import clean_str, parse_hometown  # type: ignore  # noqa: E402

OUT_COLS = ["player", "team", "season", "height_in", "class_year", "bats", "throws",
            "hometown_city", "hometown_state", "high_school"]


def _row(player, *, team=None, season=None, hometown=None, high_school=None,
         class_year=None) -> dict:
    city, state = parse_hometown(hometown)
    return {"player": player, "team": team, "season": season,
            "height_in": None, "class_year": class_year, "bats": None, "throws": None,
            "hometown_city": city, "hometown_state": state, "high_school": high_school}


def parse_pg_profile(html: str, *, team: str | None = None, season: str | None = None) -> list[dict]:
    """Parse a saved Perfect Game profile/search page -> bio rows.

    TODO: verify selectors against a saved profile. PG profiles surface hometown
    and high school as labeled fields ("Hometown:", "High School:"); the helper
    below does a generic label->value scan as a starting point.
    """
    return _parse_labeled(html, team, season)


def parse_pbr_profile(html: str, *, team: str | None = None, season: str | None = None) -> list[dict]:
    """Parse a saved PBR profile page -> bio rows. TODO: verify selectors."""
    return _parse_labeled(html, team, season)


def _parse_labeled(html: str, team, season) -> list[dict]:
    """Generic 'Label: value' scan for hometown / high school / name on a profile
    page. A deliberate starting point — replace with exact selectors per source."""
    soup = BeautifulSoup(html, "lxml")
    text_nodes = {}
    for el in soup.find_all(string=True):
        s = clean_str(el)
        if s and ":" in s:
            k, _, v = s.partition(":")
            text_nodes.setdefault(k.strip().lower(), v.strip())
    name = (clean_str(soup.find("h1").get_text()) if soup.find("h1") else None)
    home = text_nodes.get("hometown")
    hs = text_nodes.get("high school") or text_nodes.get("school")
    if not (name or home or hs):
        return []
    return [_row(name or "(unknown)", team=team, season=season,
                 hometown=home, high_school=hs)]


def write_csv(rows: list[dict], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=OUT_COLS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in OUT_COLS})


def main():
    ap = argparse.ArgumentParser(description="Perfect Game / PBR profile -> bio CSV (scaffold)")
    ap.add_argument("--html", required=True, help="path to a saved profile/search HTML file")
    ap.add_argument("--source", choices=["pg", "pbr"], default="pg")
    ap.add_argument("--team", default=None)
    ap.add_argument("--season", default=None)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    html = Path(args.html).read_text(encoding="utf-8", errors="ignore")
    parse = parse_pg_profile if args.source == "pg" else parse_pbr_profile
    rows = parse(html, team=args.team, season=args.season)
    write_csv(rows, Path(args.out))
    print(f"{args.source}: parsed {len(rows)} rows -> {args.out}  "
          f"(verify selectors in parse_{args.source}_profile)")


if __name__ == "__main__":
    main()
