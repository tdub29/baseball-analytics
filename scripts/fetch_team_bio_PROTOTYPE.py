"""
fetch_team_bio_PROTOTYPE.py
===========================

PROTOTYPE: acquire BOTH HEIGHT and WEIGHT (plus Bats/Throws/Class/PreviousSchool)
for NCAA baseball players from each school's OFFICIAL ATHLETICS roster page, to
fill the season-keyed `player_bio` table. Weight is the field stats.ncaa.org does
NOT carry, so school-site rosters are the source of record for it.

Companion to scripts/fetch_ncaa_bio_PROTOTYPE.py (NCAA = height-only). This script
owns the H+W problem and writes ONLY to data/cache/team_bio_* (never touches
db/baseball.db, data/643_exports/bio/, data/ncaa_cache/, or the NCAA scripts).

WHAT WAS VERIFIED LIVE (May 2026)
---------------------------------
~537 unique team names across the 6 export CSVs (2024/25/26 hitters+pitchers).
Three CMSs cover the vast majority of college athletics sites, and ALL THREE
publish Ht AND Wt on the baseball roster page:

  A. CLASSIC SIDEARM (Learfield) -- e.g. CSUSB (csusbathletics.com),
     Wheaton MA (wheatoncollegelyons.com). Card layout:
       <li class="sidearm-roster-player" ...>
         <span class="sidearm-roster-player-height">5'8"</span>
         <span class="sidearm-roster-player-weight">170 lbs</span>
         <span class="sidearm-roster-player-class">Jr.</span> ...
     Past seasons:  /sports/baseball/roster/<YYYY>  (e.g. .../roster/2024)

  B. MODERN (NUXT/VUE) SIDEARM -- e.g. Mississippi State (hailstate.com).
     Renders an "s-table" with headers [#, Full Name, Pos., B/T, Ht., Wt., Yr.,
     Elig., Hometown / High School]. ALSO exposes a clean JSON API:
       GET /api/v2/Sports            -> per-sport {rosterId}
       GET /api/v2/Rosters/{rosterId}-> {players:[{firstName,lastName,weight,
            heightFeet,heightInches,positionShort,academicYearShort,custom1=B/T,
            custom2=elig,previousSchool,hometown,highSchool}, ...]}
     The JSON serves the CURRENT roster only; past seasons via the DOM URL
       /sports/baseball/roster/<YYYY>.
     NOTE: the /api/v2 surface is NOT universal -- classic-Sidearm sites 404 it,
     so JSON is an *optimization*, never a dependency. DOM render is the common
     denominator.

  C. PRESTOSPORTS -- e.g. Huntington (huntington.prestosports.com), Emory & Henry
     (gowasps.com, a custom domain proxying Presto). HTML table:
       headers [No., Name, Pos., B/T, Cl., Ht., Wt., Hometown / Previous School]
       Ht as "6-1", Wt as "140".
     URL pattern: <host>/sports/bsb/<season-slug>/roster   (slug = "2025-26").

KEY ROBUSTNESS RULE: select the roster table BY ITS HEADERS (must contain both an
"Ht"/"Height" and a "Wt"/"Weight" column), never by table position -- roster pages
also render stats/widget tables. For classic Sidearm, fall back to the
`.sidearm-roster-player-*` card spans.

TEAM NAME -> ROSTER URL (the crux)
----------------------------------
Resolution strategy (in priority order):
  1. Curated override map (data/cache/team_bio_url_map.json) -- authoritative,
     grows as we verify schools. ~Handful of seed entries shipped here.
  2. Web search "<team> baseball roster" -> take the athletics domain from the
     top result. In testing the official athletics site is the #1 hit for every
     school tried (MS State, CSUSB, Wheaton MA, Emory & Henry, Huntington). This
     is the bulk auto-resolver; it needs a search tool at runtime (not bundled
     in this offline prototype -- see resolve_roster_url()).
  3. CMS + standard path: once the athletics host is known, the path is
     deterministic per CMS (Sidearm: /sports/baseball/roster[/<YYYY>];
     Presto: /sports/bsb/<slug>/roster).

Coverage estimate: Sidearm + Presto together cover the great majority of DI/DII/
DIII programs. The long tail (WMT/Streamline, fully custom sites, JUCO/NAIA which
aren't NCAA anyway) needs the curated map. Realistic auto-resolve: most of the
~450 NCAA teams via search+CMS; expect a few dozen to need hand-mapping.

USAGE
-----
    python fetch_team_bio_PROTOTYPE.py            # live demo: 2 Sidearm + 1 Presto
    python fetch_team_bio_PROTOTYPE.py --offline  # parser unit checks, no network

Internal USD evaluation only. Be gentle: one render per team-season, polite delay,
results cached to disk so reruns hit cache.
"""
from __future__ import annotations

import json
import random
import re
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths / config  (OWN cache namespace -- data/cache/team_bio_*)
# ---------------------------------------------------------------------------
DATA_DIR = Path(__file__).resolve().parents[1] / "data"
CACHE_DIR = DATA_DIR / "cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
URL_MAP_FILE = CACHE_DIR / "team_bio_url_map.json"
ROSTER_CACHE = CACHE_DIR / "team_bio_rosters.json"   # {cache_key: [rows]}

# 643 export season (spring year) -> Sidearm past-season path token & Presto slug
SIDEARM_SEASON_PATH = {2024: "2024", 2025: "2025", 2026: ""}   # "" = current
PRESTO_SEASON_SLUG = {2024: "2023-24", 2025: "2024-25", 2026: "2025-26"}

MIN_DELAY, MAX_DELAY = 1.5, 3.0

# Seed curated map: 6-4-3 Team string -> {host, cms}. cms in {sidearm, presto}.
# host is the athletics domain (no scheme). Grows as schools are verified.
SEED_URL_MAP = {
    "Mississippi State":   {"host": "hailstate.com",            "cms": "sidearm"},
    "CSU San Bernardino":  {"host": "csusbathletics.com",       "cms": "sidearm"},
    "Wheaton (MA)":        {"host": "wheatoncollegelyons.com",  "cms": "sidearm"},
    "Emory & Henry":       {"host": "gowasps.com",              "cms": "presto"},
    # Presto on a real *.prestosports.com host (clean example):
    "Huntington (IN)":     {"host": "huntington.prestosports.com", "cms": "presto"},
}


# ---------------------------------------------------------------------------
# Parse helpers  (deliverable #3)
# ---------------------------------------------------------------------------
def parse_height_to_inches(raw):
    """'6-2' / "6'2\"" / "6' 2''" / '6 2' / '74' -> inches; None if unparseable."""
    if raw is None:
        return None
    s = str(raw).strip().lower().replace("ft", "-").replace("in", "")
    s = s.replace('"', "").replace("''", "").replace("’", "'")
    # feet'inches  or  feet-inches  or  feet inches
    m = re.match(r"^\s*(\d)\s*['\-\s]\s*(\d{1,2})\s*$", s)
    if m:
        return int(m.group(1)) * 12 + int(m.group(2))
    # already in inches (two/three digit, plausible 50-90)
    m2 = re.match(r"^\s*(\d{2,3})\s*$", s)
    if m2:
        v = int(m2.group(1))
        return v if 40 <= v <= 95 else None
    # bare feet only e.g. "6'"
    m3 = re.match(r"^\s*(\d)\s*'?\s*$", s)
    return int(m3.group(1)) * 12 if m3 else None


def parse_weight_to_lb(raw):
    """'190' / '190 lbs' / '190lb.' -> 190 (int); None if missing/implausible."""
    if raw is None:
        return None
    m = re.search(r"(\d{2,3})", str(raw))
    if not m:
        return None
    v = int(m.group(1))
    return v if 90 <= v <= 400 else None


def clean_name(raw):
    """Strip leading jersey number / whitespace / newlines that some templates
    bake into the name node, e.g. '1\\n\\nMichael Gonsalez' -> 'Michael Gonsalez'."""
    if not raw:
        return None
    s = re.sub(r"\s+", " ", str(raw)).strip()
    s = re.sub(r"^#?\d{1,3}\s+", "", s)          # leading jersey number
    return s or None


def parse_bats_throws(bt):
    """'L/R' / 'R-R' / 'S/L' -> ('L','R'). None-safe."""
    if not bt:
        return (None, None)
    m = re.match(r"\s*([LRSB])\s*[/\-]\s*([LRSB])\s*", str(bt).upper())
    return (m.group(1), m.group(2)) if m else (None, None)


# ---------------------------------------------------------------------------
# Browser session (cloakbrowser stealth Chromium -- beats the bot wall that
# 403/400s plain requests on Learfield sites)
# ---------------------------------------------------------------------------
class Browser:
    def __init__(self, headless=True):
        from cloakbrowser import launch
        self._b = launch(headless=headless)
        self._p = self._b.new_page()
        self._warmed = set()

    def page(self):
        return self._p

    def warm(self, host):
        if host not in self._warmed:
            try:
                self._p.goto(f"https://{host}/", wait_until="domcontentloaded", timeout=45000)
            except Exception:
                pass
            self._warmed.add(host)

    def render(self, url, wait="networkidle", timeout=60000):
        self._p.goto(url, wait_until=wait, timeout=timeout)
        try:
            self._p.wait_for_selector("table, .sidearm-roster-player", timeout=12000)
        except Exception:
            pass
        # let Vue/JS hydrate the roster table rows before we read the DOM
        self._p.wait_for_timeout(1500)
        return self._p.content()

    def get_json(self, url):
        r = self._p.request.get(url)
        if r.status != 200:
            return None
        try:
            return r.json()
        except Exception:
            return None

    def close(self):
        try:
            self._b.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# CMS detection
# ---------------------------------------------------------------------------
def detect_cms(host, html=""):
    if "prestosports.com" in host:
        return "presto"
    h = html.lower()
    if "prestosports" in h or "/sports/bsb/" in h:
        return "presto"
    if ("sidearm" in h or "_nuxt" in h or "/api/v2/" in h or "data-v-" in h
            or "sidearm-roster" in h):
        return "sidearm"
    return "unknown"


# ---------------------------------------------------------------------------
# Roster URL construction per CMS
# ---------------------------------------------------------------------------
def sidearm_roster_url(host, season):
    tok = SIDEARM_SEASON_PATH.get(season, "")
    return f"https://{host}/sports/baseball/roster" + (f"/{tok}" if tok else "")


def presto_roster_url(host, season):
    return f"https://{host}/sports/bsb/{PRESTO_SEASON_SLUG[season]}/roster"


# ---------------------------------------------------------------------------
# Parsers -> normalized rows
#   {player, first, last, height_in, weight_lb, bats, throws, class_year,
#    position, previous_school, source}
# ---------------------------------------------------------------------------
# Header-matched table extraction (works for modern Sidearm s-table AND Presto)
_JS_HEADER_TABLE = r"""
() => {
  const tables = Array.from(document.querySelectorAll('table'));
  for (const t of tables) {
    const ths = Array.from(t.querySelectorAll('thead th, thead td')).map(x=>x.innerText.trim());
    const hasHt = ths.some(h=>/^ht\.?$/i.test(h)||/height/i.test(h));
    const hasWt = ths.some(h=>/^wt\.?$/i.test(h)||/weight/i.test(h));
    if (hasHt && hasWt) {
      const rows = Array.from(t.querySelectorAll('tbody tr')).map(
        r=>Array.from(r.querySelectorAll('th,td')).map(c=>c.innerText.trim()));
      return {headers: ths, rows};
    }
  }
  return null;
}
"""

# Classic Sidearm card spans
_JS_SIDEARM_CARDS = r"""
() => Array.from(document.querySelectorAll('.sidearm-roster-player')).map(p => {
  const g = s => { const e=p.querySelector(s); return e?e.innerText.trim():null; };
  return {
    name: g('.sidearm-roster-player-name'),
    height: g('.sidearm-roster-player-height'),
    weight: g('.sidearm-roster-player-weight'),
    cls: g('.sidearm-roster-player-academic-year') || g('.sidearm-roster-player-class'),
    pos: g('.sidearm-roster-player-position-short') || g('.sidearm-roster-player-position'),
    hometown: g('.sidearm-roster-player-hometown'),
    prev: g('.sidearm-roster-player-previous-school') || g('.sidearm-roster-player-highschool'),
  };
}).filter(x => x.height || x.weight);
"""


def _hdr_index(headers):
    idx = {}
    for i, h in enumerate(headers):
        hl = h.lower()
        if re.match(r"^ht\.?$", hl) or "height" in hl: idx["ht"] = i
        elif re.match(r"^wt\.?$", hl) or "weight" in hl: idx["wt"] = i
        elif "name" in hl or hl in ("full name",): idx["name"] = i
        elif hl.startswith("b/t") or hl == "bt": idx["bt"] = i
        elif hl in ("yr.", "cl.", "year", "class", "yr") or "elig" in hl: idx.setdefault("cls", i)
        elif "pos" in hl: idx["pos"] = i
        elif "hometown" in hl: idx["home"] = i
    return idx


def parse_table_rows(headers, rows):
    idx = _hdr_index(headers)
    if "ht" not in idx or "wt" not in idx:
        return []
    nhdr = len(headers)
    out = []
    for cells in rows:
        # Some templates (PrestoSports) repeat the jersey number as an extra
        # leading cell, so a row has MORE cells than headers. Right-align: the
        # data columns match the LAST nhdr cells, so offset the header indices.
        offset = max(0, len(cells) - nhdr)
        if len(cells) <= max(idx.values()) + offset:
            continue
        get = lambda k: cells[idx[k] + offset] if k in idx else None
        name = clean_name(get("name"))
        bats, throws = parse_bats_throws(get("bt"))
        home = get("home") or ""
        prev = None
        if home and "/" in home:                 # "City, ST / HS [/ Prev College]"
            parts = [s.strip() for s in home.split("/")]
            if len(parts) >= 3:
                prev = parts[-1]
        out.append({
            "player": name,
            "height_in": parse_height_to_inches(get("ht")),
            "weight_lb": parse_weight_to_lb(get("wt")),
            "bats": bats, "throws": throws,
            "class_year": get("cls"),
            "position": get("pos"),
            "previous_school": prev,
            "source": "table",
        })
    return out


def parse_sidearm_cards(cards):
    out = []
    for c in cards:
        out.append({
            "player": clean_name(c.get("name")),
            "height_in": parse_height_to_inches(c.get("height")),
            "weight_lb": parse_weight_to_lb(c.get("weight")),
            "bats": None, "throws": None,         # classic cards put B/T in a sub-span; omitted here
            "class_year": c.get("cls"),
            "position": c.get("pos"),
            "previous_school": c.get("prev"),
            "source": "sidearm-card",
        })
    return out


def parse_sidearm_json(players):
    out = []
    for pl in players:
        ht = None
        if pl.get("heightFeet") is not None:
            ht = int(pl["heightFeet"]) * 12 + int(pl.get("heightInches") or 0)
        bats, throws = parse_bats_throws(pl.get("custom1"))
        nm = " ".join(x for x in (pl.get("firstName"), pl.get("lastName")) if x)
        out.append({
            "player": nm or None,
            "first": pl.get("firstName"), "last": pl.get("lastName"),
            "height_in": ht,
            "weight_lb": parse_weight_to_lb(pl.get("weight")),
            "bats": bats, "throws": throws,
            "class_year": pl.get("academicYearShort"),
            "position": pl.get("positionShort"),
            "previous_school": pl.get("previousSchool"),
            "source": "sidearm-json",
        })
    return out


# ---------------------------------------------------------------------------
# Fetch one team-season -> rows  (CMS dispatch + caching)
# ---------------------------------------------------------------------------
def _load(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _save(path, obj):
    path.write_text(json.dumps(obj, indent=0, ensure_ascii=False), encoding="utf-8")


def resolve_roster_url(team, season, url_map):
    """team -> (host, cms, url). Uses curated map; web-search fallback is a
    runtime hook (see module docstring) -- not wired in this offline prototype."""
    info = url_map.get(team)
    if not info:
        return None, None, None
    host, cms = info["host"], info["cms"]
    url = presto_roster_url(host, season) if cms == "presto" else sidearm_roster_url(host, season)
    return host, cms, url


def fetch_team_season(br, team, season, url_map, cache):
    key = f"{team}|{season}"
    if key in cache:
        return cache[key]

    host, cms, url = resolve_roster_url(team, season, url_map)
    if not url:
        return {"error": "unresolved", "rows": []}

    br.warm(host)
    rows = []

    if cms == "sidearm":
        # (a) try modern JSON API for current season
        if season == 2026:
            sports = br.get_json(f"https://{host}/api/v2/Sports")
            rid = None
            items = sports if isinstance(sports, list) else (sports or {}).get("items", [])
            for s in (items or []):
                nm = (s.get("title") or s.get("shortName") or "").lower()
                seg = (s.get("urlSegment") or s.get("slug") or "").lower()
                if (("baseball" in nm and "soft" not in nm) or seg == "baseball") and s.get("rosterId"):
                    rid = s["rosterId"]; break
            if rid:
                data = br.get_json(f"https://{host}/api/v2/Rosters/{rid}")
                if data and data.get("players"):
                    rows = parse_sidearm_json(data["players"])
        # (b) DOM render -- modern s-table OR classic cards
        if not rows:
            html = br.render(url)
            res = br.page().evaluate(_JS_HEADER_TABLE)
            if res and res["rows"]:
                rows = parse_table_rows(res["headers"], res["rows"])
            if not rows:
                cards = br.page().evaluate(_JS_SIDEARM_CARDS)
                if cards:
                    rows = parse_sidearm_cards(cards)

    elif cms == "presto":
        br.render(url)
        res = br.page().evaluate(_JS_HEADER_TABLE)
        if res and res["rows"]:
            rows = parse_table_rows(res["headers"], res["rows"])

    rows = [r for r in rows if r.get("height_in") or r.get("weight_lb")]
    result = {"team": team, "season": season, "host": host, "cms": cms,
              "url": url, "n": len(rows), "rows": rows}
    cache[key] = result
    _save(ROSTER_CACHE, cache)
    time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))
    return result


# ---------------------------------------------------------------------------
# Offline parser self-checks
# ---------------------------------------------------------------------------
def offline_checks():
    print("=== parse_height_to_inches ===")
    for raw, exp in [("6-2", 74), ("6'2\"", 74), ("6' 2''", 74), ("5-8", 68),
                     ("6", 72), ("74", 74), ("", None), ("N/A", None)]:
        got = parse_height_to_inches(raw)
        print(f"  {raw!r:10} -> {got}  {'OK' if got == exp else f'EXPECTED {exp}'}")
    print("=== parse_weight_to_lb ===")
    for raw, exp in [("190", 190), ("190 lbs", 190), ("170lb.", 170), ("", None),
                     ("-", None), ("9999", None)]:
        got = parse_weight_to_lb(raw)
        print(f"  {raw!r:10} -> {got}  {'OK' if got == exp else f'EXPECTED {exp}'}")
    print("=== parse_bats_throws ===")
    for raw in ["L/R", "R-R", "S/L", "", None]:
        print(f"  {raw!r:6} -> {parse_bats_throws(raw)}")


# ---------------------------------------------------------------------------
# Live demo
# ---------------------------------------------------------------------------
def demo():
    url_map = {**SEED_URL_MAP, **_load(URL_MAP_FILE, {})}
    cache = _load(ROSTER_CACHE, {})
    print("Launching stealth browser (cloakbrowser)...")
    br = Browser(headless=True)
    targets = [
        ("Mississippi State", 2026),   # modern Sidearm -> JSON API
        ("CSU San Bernardino", 2026),  # classic Sidearm -> card spans
        ("Huntington (IN)", 2026),     # PrestoSports table
        ("Mississippi State", 2024),   # past-season DOM (s-table)
    ]
    try:
        for team, season in targets:
            res = fetch_team_season(br, team, season, url_map, cache)
            print(f"\n=== {team} {season}  [{res.get('cms')}]  {res.get('url')} ===")
            if res.get("error"):
                print("  ERROR:", res["error"]); continue
            rows = res["rows"]
            wt = sum(1 for r in rows if r["weight_lb"])
            ht = sum(1 for r in rows if r["height_in"])
            print(f"  {len(rows)} players  (height: {ht}, weight: {wt})  via {rows[0]['source'] if rows else '-'}")
            print(f"  {'player':24} {'ht_in':>5} {'wt_lb':>5} {'B':>2}/{'T':<2} {'class':>6}  prev")
            for r in rows[:6]:
                print(f"  {str(r['player'])[:24]:24} {str(r['height_in']):>5} "
                      f"{str(r['weight_lb']):>5} {str(r['bats'] or '-'):>2}/"
                      f"{str(r['throws'] or '-'):<2} {str(r['class_year'])[:6]:>6}  "
                      f"{r['previous_school'] or ''}")
    finally:
        br.close()
    print(f"\nCache written: {ROSTER_CACHE}")


def main():
    if "--offline" in sys.argv:
        offline_checks()
    else:
        offline_checks()
        print()
        demo()


if __name__ == "__main__":
    main()
