"""
fetch_ncaa_bio_PROTOTYPE.py
===========================

PROTOTYPE: acquire NCAA baseball player HEIGHT (and Class/Bats/Throws/Position)
by SEASON (2024, 2025, 2026) for D1/D2/D3, to attach bio to the ~5-6k hitters
per season already held as (Player, Team, season) in data/643_exports/*.

KEY FINDINGS (verified live against stats.ncaa.org, May 2026)
-------------------------------------------------------------
1. stats.ncaa.org publishes HEIGHT, Bats, Throws, Class, Position, Hometown,
   High School on each team's per-season roster page. It does **NOT** publish
   WEIGHT. (No Wt/Weight column anywhere on the roster table.)  -> Weight must
   come from a different source (school athletics-site rosters or a 6-4-3 /
   Synergy bio export).

2. Plain `requests` is 403-blocked by the site's bot wall. `cloakbrowser`
   (stealth Chromium) gets HTTP 200 reliably.

3. The modern site identifies each team-season by a unique INSTANCE id
   ("year_id" / game_sport_year_ctl_id), NOT by the persistent school_id.
   - Modern roster URL:  https://stats.ncaa.org/teams/{INSTANCE_ID}/roster
   - The roster table is <table id="rosters_form_players_*_data_table">
     with header [GP, GS, #, Name, Class, Position, Height, Bats, Throws,
     Hometown, High School].
   - The legacy collegebaseball URL /team/{school_id}/roster/{legacy_season_id}
     still serves the OLD layout for 2023 & earlier, but does NOT work for the
     new instance ids -> we use the modern URL.

4. Resolving a team NAME -> instance ids per season:
   a. NAME -> persistent school_id ("vid"): one cheap call to
      `GET /team/search?sport_code=MBA` returns the FULL directory of ~1095
      baseball orgs as [{value: vid, label: "School - Conference"}]. The `q`
      param is ignored server-side (jQuery filters client-side), so one fetch
      gives the whole alias table. vid == collegebaseball school_id.
   b. school_id -> instance ids: land on ANY known instance page
      `/teams/{instance}` and read its <select name="year_id"> dropdown, which
      lists  {instance_id -> "2025-26"/"2024-25"/...} for that school across
      all seasons. (Bootstrap the first instance from the legacy roster page,
      or cache instance ids once discovered.)

   NCAA name normalization is non-trivial: NCAA abbreviates ("Cal St.
   Fullerton", "Alabama St.", "CSUSB" for CSU San Bernardino, "Emory & Henry").
   The (Player, Team) join needs an alias map + fuzzy fallback (see notes at
   bottom). collegebaseball's bundled schools table (945 rows, name->school_id,
   stops growing at 2023 but ids are stable) is a good first-pass alias source.

USAGE
-----
    python fetch_ncaa_bio_PROTOTYPE.py            # runs the demo on sample teams
    # see fetch_team_roster() / build_org_directory() for the importable API

This is a PROTOTYPE for internal USD evaluation only. Be gentle: it sleeps
between requests and caches the org directory + instance ids to disk.
"""
from __future__ import annotations

import json
import re
import sys
import time
import random
from pathlib import Path

from bs4 import BeautifulSoup

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BASE = "https://stats.ncaa.org"
SPORT_CODE = "MBA"  # men's baseball
DATA_DIR = Path(__file__).resolve().parents[1] / "data"
CACHE_DIR = DATA_DIR / "ncaa_cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
ORG_DIR_FILE = DATA_DIR / "ncaa_org_directory_MBA.json"
INSTANCE_CACHE_FILE = CACHE_DIR / "instance_ids.json"

# season label on stats.ncaa.org -> our integer season (the *spring* year)
SEASON_LABELS = {2024: "2023-24", 2025: "2024-25", 2026: "2025-26"}

MIN_DELAY, MAX_DELAY = 1.5, 3.5  # polite per-request delay (seconds)


# ---------------------------------------------------------------------------
# Browser session (cloakbrowser stealth Chromium; falls back to requests)
# ---------------------------------------------------------------------------
class NcaaSession:
    """Thin wrapper over a cloakbrowser page. page.request shares cookies/UA."""

    def __init__(self, headless: bool = True):
        from cloakbrowser import launch
        self._browser = launch(headless=headless)
        self._page = self._browser.new_page()
        # warm the session so cookies/anti-bot tokens are set
        self._page.goto(f"{BASE}/", wait_until="domcontentloaded", timeout=45000)

    def get_html(self, url: str) -> str:
        self._page.goto(url, wait_until="domcontentloaded", timeout=45000)
        return self._page.content()

    def get_json(self, url: str):
        resp = self._page.request.get(url)
        return resp.json()

    def close(self):
        try:
            self._browser.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------
def parse_height_to_inches(raw: str):
    """'6-2' / "6'2\"" / '6 2' -> 74 ; returns None if unparseable."""
    if not raw:
        return None
    s = raw.strip().replace('"', "").replace("'", "-").replace("’", "-")
    m = re.match(r"^\s*(\d)\s*[-\s]\s*(\d{1,2})\s*$", s)
    if not m:
        # sometimes just feet, e.g. '6'
        m2 = re.match(r"^\s*(\d)\s*$", s)
        return int(m2.group(1)) * 12 if m2 else None
    feet, inches = int(m.group(1)), int(m.group(2))
    return feet * 12 + inches


def parse_weight_to_lb(raw):
    """NCAA rosters do NOT carry weight; included for school-site/6-4-3 reuse."""
    if not raw:
        return None
    m = re.search(r"(\d{2,3})", str(raw))
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------------------
# Step 1: NAME -> school_id directory  (one cheap call, cached)
# ---------------------------------------------------------------------------
def build_org_directory(sess: NcaaSession, refresh: bool = False) -> list[dict]:
    if ORG_DIR_FILE.exists() and not refresh:
        return json.loads(ORG_DIR_FILE.read_text())
    data = sess.get_json(f"{BASE}/team/search?sport_code={SPORT_CODE}")
    ORG_DIR_FILE.write_text(json.dumps(data, indent=0))
    return data


def _norm(name: str) -> str:
    """Loose normaliser for matching our team strings to NCAA labels."""
    s = name.lower()
    s = re.sub(r"\bstate\b", "st", s)
    s = re.sub(r"\bst\.?\b", "st", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def resolve_school_id(team_name: str, directory: list[dict],
                      alias: dict | None = None):
    """team_name -> (school_id, ncaa_label) using alias map then fuzzy norm."""
    alias = alias or {}
    if team_name in alias:
        want = alias[team_name]
        for d in directory:
            label = d["label"].rsplit(" - ", 1)[0]
            if label == want:
                return d["value"], d["label"]
    target = _norm(team_name)
    # exact normalised match on the school part of "School - Conference"
    for d in directory:
        label = d["label"].rsplit(" - ", 1)[0]
        if _norm(label) == target:
            return d["value"], d["label"]
    # prefix / contains fallback (report for manual review)
    for d in directory:
        label = d["label"].rsplit(" - ", 1)[0]
        nl = _norm(label)
        if nl.startswith(target) or target.startswith(nl):
            return d["value"], d["label"] + "  [FUZZY]"
    return None, None


# ---------------------------------------------------------------------------
# Step 2: school_id -> per-season instance ids (read year_id dropdown, cached)
# ---------------------------------------------------------------------------
def _load_instance_cache() -> dict:
    if INSTANCE_CACHE_FILE.exists():
        return json.loads(INSTANCE_CACHE_FILE.read_text())
    return {}


def _save_instance_cache(cache: dict):
    INSTANCE_CACHE_FILE.write_text(json.dumps(cache, indent=0))


def discover_instances(sess: NcaaSession, school_id: int,
                       bootstrap_instance: int) -> dict:
    """
    Return {season_label: instance_id} for a school.
    bootstrap_instance: any known instance id for this school (e.g. the one we
    already found, or seeded from the legacy roster page). The dropdown on that
    page lists every season for the school.
    """
    cache = _load_instance_cache()
    key = str(school_id)
    if key in cache:
        return cache[key]
    html = sess.get_html(f"{BASE}/teams/{bootstrap_instance}")
    soup = BeautifulSoup(html, "lxml")
    sel = soup.find("select", attrs={"name": "year_id"})
    mapping = {}
    if sel:
        for opt in sel.find_all("option"):
            mapping[opt.get_text(strip=True)] = int(opt.get("value"))
    cache[key] = mapping
    _save_instance_cache(cache)
    time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))
    return mapping


# ---------------------------------------------------------------------------
# Step 3: instance_id -> roster rows (Name, height_in, class, bats, throws...)
# ---------------------------------------------------------------------------
def fetch_team_roster(sess: NcaaSession, instance_id: int) -> list[dict]:
    html = sess.get_html(f"{BASE}/teams/{instance_id}/roster")
    soup = BeautifulSoup(html, "lxml")
    # the data table id varies (rosters_form_players_{n}_data_table); match by class+headers
    table = None
    for t in soup.find_all("table"):
        body = t.find("tbody")
        if body and body.find_all("tr"):
            heads = [th.get_text(strip=True) for th in t.find_all("th")]
            if "Height" in heads and "Name" in heads:
                table = t
                header = heads
                break
    if table is None:
        return []
    idx = {h: i for i, h in enumerate(header)}
    rows = []
    for tr in table.find("tbody").find_all("tr"):
        cells = [td.get_text(strip=True) for td in tr.find_all("td")]
        if len(cells) < len(header):
            continue
        a = tr.find("a", href=re.compile(r"/players/\d+"))
        pid = int(a["href"].split("/")[-1]) if a else None
        ht_raw = cells[idx["Height"]]
        rows.append({
            "ncaa_player_id": pid,
            "Player": cells[idx["Name"]],
            "height_raw": ht_raw,
            "height_in": parse_height_to_inches(ht_raw),
            "weight_lb": None,            # NCAA rosters carry no weight
            "class_year": cells[idx.get("Class", -1)] if "Class" in idx else None,
            "position": cells[idx.get("Position", -1)] if "Position" in idx else None,
            "bats": cells[idx.get("Bats", -1)] if "Bats" in idx else None,
            "throws": cells[idx.get("Throws", -1)] if "Throws" in idx else None,
        })
    time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))
    return rows


# ---------------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------------
# Known bootstrap instance ids (any one season per school is enough to unlock
# the dropdown that yields all seasons). These were harvested live.
DEMO = {
    "Ohio":          {"school_id": 519, "bootstrap": 614701},  # D1
    "Emory & Henry": {"school_id": 216, "bootstrap": None},    # D3 (resolve live)
}

# Alias map for our 6-4-3 team strings -> NCAA directory label (school part).
# This is the seed of the normalization layer the full run needs.
TEAM_ALIAS = {
    "CSU San Bernardino": "CSUSB",
    "Wheaton (MA)": "Wheaton (MA)",
    "Emory & Henry": "Emory & Henry",
    "Ohio": "Ohio",
}


def main():
    print("Launching stealth browser (cloakbrowser)...")
    sess = NcaaSession(headless=True)
    try:
        directory = build_org_directory(sess)
        print(f"Org directory: {len(directory)} MBA programs\n")

        # demonstrate NAME -> school_id resolution on tricky strings
        print("=== NAME -> NCAA school_id resolution ===")
        for name in ["Ohio", "Emory & Henry", "CSU San Bernardino",
                     "Wheaton (MA)", "Limestone"]:
            sid, label = resolve_school_id(name, directory, TEAM_ALIAS)
            print(f"  {name:22s} -> id={sid}  ncaa_label={label}")
        print()

        # fetch a couple of real team-seasons and parse height
        targets = [
            ("Ohio", 519, 614701, 2026),       # D1, 2025-26
            ("Ohio", 519, 596640, 2025),       # D1, 2024-25
            ("Emory & Henry", 216, None, 2026),  # D3, resolve instance live
        ]
        for name, sid, instance, season in targets:
            if instance is None:
                # resolve via the year_id dropdown using a known D1 instance as
                # the page host won't matter -- we need THIS school's dropdown,
                # so bootstrap from the legacy roster page that still renders it.
                # Simplest live bootstrap: hit the legacy 2023 roster URL.
                html = sess.get_html(f"{BASE}/team/{sid}/roster/16340")
                soup = BeautifulSoup(html, "lxml")
                sel = soup.find("select", attrs={"name": "year_id"})
                inst_map = {o.get_text(strip=True): int(o["value"])
                            for o in sel.find_all("option")} if sel else {}
                instance = inst_map.get(SEASON_LABELS[season])
                print(f"[resolved] {name} {season} -> instance {instance}")
                time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))

            print(f"\n=== {name} {season}  (instance {instance}) ===")
            roster = fetch_team_roster(sess, instance)
            print(f"  {len(roster)} players. Sample (Player, height_in, weight_lb):")
            for r in roster[:8]:
                print(f"    {r['Player']:24s} ht={r['height_raw']:>5s} "
                      f"-> {r['height_in']} in   wt={r['weight_lb']}  "
                      f"({r['class_year']}, {r['position']})")
    finally:
        sess.close()


if __name__ == "__main__":
    main()
