"""
fetch_team_bio.py  (PRODUCTION)
===============================

Acquire HEIGHT + WEIGHT (plus Bats/Throws/Class/Hometown/HighSchool/PreviousSchool)
for every NCAA baseball player on each school's OFFICIAL ATHLETICS roster page, and
emit one CSV per season for the 6-4-3 export team universe.

This is the production build of scripts/fetch_team_bio_PROTOTYPE.py. It reuses the
prototype's verified pieces (Browser, CMS detection, table/card/JSON parsers, the
per-team-season fetch + caching) and adds the missing piece: a team-NAME -> athletics
HOST resolver driven by web search (CloakBrowser -> Bing, with DuckDuckGo fallback).

OWNERSHIP (do not touch anything else):
  - WRITES:  scripts/fetch_team_bio.py (this file),
             data/cache/team_bio_*               (url_map, rosters, unresolved),
             data/643_exports/bio/team_bio_<season>.csv   (the deliverable)
  - READS:   data/643_exports/hitters_<season>_overall.csv  (column `Team`)
             data/643_exports/pitching/pitchers_<season>.csv (column `Team`)
  - NEVER touches db/baseball.db, src/portal/*, db/schema.sql, scripts/migrate_db.py,
    scripts/fetch_ncaa_bio*.py, data/ncaa_cache/.

RESOLUTION (team -> {host, cms}):
  1. Curated map  data/cache/team_bio_url_map.json  (authoritative; grows on every run).
  2. Web search  "<team> baseball roster"  via CloakBrowser:
       Bing first (https://www.bing.com/search?q=...); parse the b_algo results,
       decode the bing /ck/a redirect to the true target, take the first result whose
       domain is an official athletics site (not an aggregator/news/social), then
       detect the CMS by fetching the host root.
       If Bing bot-walls / yields nothing, retry on DuckDuckGo html then lite.
     Every successful resolution is cached back to team_bio_url_map.json so reruns are
     cheap; failures go to data/cache/team_bio_unresolved.json and are skipped.
  3. CMS + standard path: deterministic per CMS once the host is known
       Sidearm: /sports/baseball/roster[/<YYYY>]   Presto: /sports/bsb/<slug>/roster

OUTPUT CSV columns (per season):
  player, team, season, height_in, weight_lb, bats, throws, class_year,
  hometown, high_school, previous_school
  -> ALL roster players are emitted (DB loader matches against 6-4-3 names later).

USAGE
-----
    python scripts/fetch_team_bio.py                 # full backfill, 2026 -> 2025 -> 2024
    python scripts/fetch_team_bio.py --verify        # resolve+scrape ~5 teams, no CSV write
    python scripts/fetch_team_bio.py --seasons 2026  # one season only
    python scripts/fetch_team_bio.py --limit 30      # cap teams per season (debug)
    python scripts/fetch_team_bio.py --offline       # parser self-checks, no network

Internal USD evaluation only. Gentle: one render per team-season, 1.5-3s jittered
delay, everything cached to disk so reruns resume without refetching.
"""
from __future__ import annotations

import argparse
import base64
import csv
import json
import random
import re
import sys
import time
import urllib.parse
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths / config  (OWN cache + output namespace)
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
CACHE_DIR = DATA_DIR / "cache"
EXPORTS_DIR = DATA_DIR / "643_exports"
BIO_OUT_DIR = EXPORTS_DIR / "bio"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
BIO_OUT_DIR.mkdir(parents=True, exist_ok=True)

URL_MAP_FILE = CACHE_DIR / "team_bio_url_map.json"
ROSTER_CACHE = CACHE_DIR / "team_bio_rosters.json"   # {team|season: result}
UNRESOLVED_FILE = CACHE_DIR / "team_bio_unresolved.json"  # {team: reason}

SEASONS = (2026, 2025, 2024)  # priority order: current first

# 643 export season (spring year) -> Sidearm past-season path token & Presto slug
SIDEARM_SEASON_PATH = {2024: "2024", 2025: "2025", 2026: ""}   # "" = current
PRESTO_SEASON_SLUG = {2024: "2023-24", 2025: "2024-25", 2026: "2025-26"}

MIN_DELAY, MAX_DELAY = 1.5, 3.0
SEARCH_DELAY = (1.5, 3.0)

OUT_COLUMNS = [
    "player", "team", "season", "height_in", "weight_lb", "bats", "throws",
    "class_year", "hometown", "high_school", "previous_school",
]

# Domains that are NOT a school's official athletics site -- never pick these as host.
AGGREGATOR_DOMAINS = {
    "d1baseball.com", "wikipedia.org", "en.wikipedia.org", "si.com",
    "247sports.com", "facebook.com", "twitter.com", "x.com", "instagram.com",
    "youtube.com", "espn.com", "ncaa.com", "ncaa.org", "maxpreps.com",
    "perfectgame.org", "prepbaseballreport.com", "rivals.com", "on3.com",
    "verbalcommits.com", "secrant.com", "reddit.com", "linkedin.com",
    "tiktok.com", "pointstreak.com", "athletic.net", "milb.com", "mlb.com",
    "baseball-reference.com", "thebaseballcube.com", "usatoday.com",
    "cbssports.com", "sports-reference.com", "google.com", "bing.com",
    "duckduckgo.com", "yahoo.com", "apple.com", "gannett-cdn.com",
}
# News-site hint -- domains containing these tokens are press, not athletics.
NEWS_TOKENS = ("news", "tribune", "gazette", "dispatch", "herald", "times",
               "journal", "register", "advocate", "patch.com", "story")


# ---------------------------------------------------------------------------
# Parse helpers  (copied verbatim from prototype -- verified live May 2026)
# ---------------------------------------------------------------------------
def parse_height_to_inches(raw):
    """'6-2' / "6'2\"" / "6' 2''" / '6 2' / '74' -> inches; None if unparseable."""
    if raw is None:
        return None
    s = str(raw).strip().lower().replace("ft", "-").replace("in", "")
    s = s.replace('"', "").replace("''", "").replace("’", "'")
    m = re.match(r"^\s*(\d)\s*['\-\s]\s*(\d{1,2})\s*$", s)
    if m:
        return int(m.group(1)) * 12 + int(m.group(2))
    m2 = re.match(r"^\s*(\d{2,3})\s*$", s)
    if m2:
        v = int(m2.group(1))
        return v if 40 <= v <= 95 else None
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
    """Strip leading jersey number / whitespace / newlines baked into the name node."""
    if not raw:
        return None
    s = re.sub(r"\s+", " ", str(raw)).strip()
    s = re.sub(r"^#?\d{1,3}\s+", "", s)
    return s or None


def parse_bats_throws(bt):
    """'L/R' / 'R-R' / 'S/L' -> ('L','R'). None-safe."""
    if not bt:
        return (None, None)
    m = re.match(r"\s*([LRSB])\s*[/\-]\s*([LRSB])\s*", str(bt).upper())
    return (m.group(1), m.group(2)) if m else (None, None)


def split_hometown_field(home):
    """'City, ST / High School [/ Previous College]' -> (hometown, high_school, prev)."""
    if not home:
        return (None, None, None)
    parts = [s.strip() for s in str(home).split("/")]
    hometown = parts[0] or None if parts else None
    high_school = parts[1] if len(parts) >= 2 and parts[1] else None
    prev = parts[-1] if len(parts) >= 3 and parts[-1] else None
    return (hometown, high_school, prev)


# ---------------------------------------------------------------------------
# Browser session (cloakbrowser stealth Chromium -- beats the bot wall that
# 403/400s plain requests on Learfield sites). Copied from prototype + helpers.
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

    def fetch_root_html(self, host):
        """Fetch host root for CMS detection. Returns html ('' on failure)."""
        try:
            self._p.goto(f"https://{host}/", wait_until="domcontentloaded", timeout=45000)
            self._p.wait_for_timeout(1200)
            return self._p.content()
        except Exception:
            return ""

    def render(self, url, wait="networkidle", timeout=60000):
        self._p.goto(url, wait_until=wait, timeout=timeout)
        try:
            self._p.wait_for_selector("table, .sidearm-roster-player", timeout=12000)
        except Exception:
            pass
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

    def goto(self, url, wait="domcontentloaded", timeout=45000, settle=2000):
        self._p.goto(url, wait_until=wait, timeout=timeout)
        self._p.wait_for_timeout(settle)

    def evaluate(self, js):
        return self._p.evaluate(js)

    def close(self):
        try:
            self._b.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# CMS detection  (copied from prototype)
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
# Roster URL construction per CMS  (copied from prototype)
# ---------------------------------------------------------------------------
def sidearm_roster_url(host, season):
    tok = SIDEARM_SEASON_PATH.get(season, "")
    return f"https://{host}/sports/baseball/roster" + (f"/{tok}" if tok else "")


def presto_roster_url(host, season):
    return f"https://{host}/sports/bsb/{PRESTO_SEASON_SLUG[season]}/roster"


# ---------------------------------------------------------------------------
# DOM extraction JS  (copied from prototype)
# ---------------------------------------------------------------------------
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

# Classic Sidearm uses '.sidearm-roster-player' as the per-player container; the newer
# Sidearm list/grid layout (e.g. alcornsports.com) uses '.sidearm-list-card-item' --
# but BOTH expose the same '.sidearm-roster-player-*' field spans inside the card. Query
# whichever container is present (prefer the one that actually contains height spans).
_JS_SIDEARM_CARDS = r"""
() => {
  const pick = sel => {
    const arr = Array.from(document.querySelectorAll(sel));
    return arr.filter(c => c.querySelector('.sidearm-roster-player-height, .sidearm-roster-player-weight'));
  };
  let cards = pick('.sidearm-roster-player');
  if (!cards.length) cards = pick('.sidearm-list-card-item');
  if (!cards.length) cards = pick('li.sidearm-roster-player, .sidearm-roster-template-individual');
  return cards.map(p => {
    const g = s => { const e=p.querySelector(s); return e?e.innerText.trim():null; };
    return {
      name: g('.sidearm-roster-player-name') || g('.sidearm-roster-player-first-name') &&
            ((g('.sidearm-roster-player-first-name')||'') + ' ' + (g('.sidearm-roster-player-last-name')||'')).trim(),
      height: g('.sidearm-roster-player-height'),
      weight: g('.sidearm-roster-player-weight'),
      cls: g('.sidearm-roster-player-academic-year') || g('.sidearm-roster-player-class'),
      pos: g('.sidearm-roster-player-position-short') || g('.sidearm-roster-player-position-long')
           || g('.sidearm-roster-player-position'),
      bt: g('.sidearm-roster-player-custom1'),
      hometown: g('.sidearm-roster-player-hometown'),
      highschool: g('.sidearm-roster-player-highschool') || g('.sidearm-roster-player-high-school'),
      prev: g('.sidearm-roster-player-previous-school'),
    };
  }).filter(x => x.height || x.weight);
}
"""

# Bing organic results: cite (displayed url) + h2 anchor (ck/a redirect).
_JS_BING_RESULTS = r"""
() => Array.from(document.querySelectorAll('li.b_algo')).slice(0,12).map(li => {
  const cite = li.querySelector('cite');
  const a = li.querySelector('h2 a');
  return {cite: cite ? cite.innerText : null, href: a ? a.href : null};
})
"""

# DuckDuckGo html/lite results: result anchors carry the target directly or via uddg=.
# Grab the dedicated result anchors AND any external anchor whose path already looks
# like a roster page (strongest official-athletics signal -- DDG surfaces these first).
_JS_DDG_RESULTS = r"""
() => {
  const sel = 'a.result__a, a.result-link, .result__title a, .results_links a, .result__url';
  let hrefs = Array.from(document.querySelectorAll(sel)).map(a => a.href);
  // Also any link pointing at a sidearm/presto roster path -- these are the wins.
  const rosterish = Array.from(document.querySelectorAll('a[href]'))
    .map(a => a.href)
    .filter(h => /\/sports\/baseball\/roster|\/sports\/bsb\//.test(h));
  return Array.from(new Set([...hrefs, ...rosterish])).slice(0, 20)
    .map(href => ({href, text: ''}));
}
"""


# ---------------------------------------------------------------------------
# Parsers -> normalized rows  (copied from prototype, extended for hometown/HS)
# ---------------------------------------------------------------------------
def _hdr_index(headers):
    idx = {}
    for i, h in enumerate(headers):
        hl = h.lower()
        if re.match(r"^ht\.?$", hl) or "height" in hl:
            idx["ht"] = i
        elif re.match(r"^wt\.?$", hl) or "weight" in hl:
            idx["wt"] = i
        elif "name" in hl or hl == "full name":
            idx["name"] = i
        elif hl.startswith("b/t") or hl == "bt":
            idx["bt"] = i
        elif hl in ("yr.", "cl.", "year", "class", "yr") or "elig" in hl:
            idx.setdefault("cls", i)
        elif "pos" in hl:
            idx["pos"] = i
        elif "hometown" in hl:
            idx["home"] = i
    return idx


def parse_table_rows(headers, rows):
    idx = _hdr_index(headers)
    if "ht" not in idx or "wt" not in idx:
        return []
    nhdr = len(headers)
    out = []
    for cells in rows:
        # Some templates (Presto) repeat the jersey number as an extra leading cell,
        # so a row has MORE cells than headers. Right-align by offset.
        offset = max(0, len(cells) - nhdr)
        if len(cells) <= max(idx.values()) + offset:
            continue
        get = lambda k: cells[idx[k] + offset] if k in idx else None
        name = clean_name(get("name"))
        bats, throws = parse_bats_throws(get("bt"))
        hometown, high_school, prev = split_hometown_field(get("home"))
        out.append({
            "player": name,
            "height_in": parse_height_to_inches(get("ht")),
            "weight_lb": parse_weight_to_lb(get("wt")),
            "bats": bats, "throws": throws,
            "class_year": get("cls"),
            "position": get("pos"),
            "hometown": hometown,
            "high_school": high_school,
            "previous_school": prev,
            "source": "table",
        })
    return out


def parse_sidearm_cards(cards):
    out = []
    for c in cards:
        bats, throws = parse_bats_throws(c.get("bt"))
        # hometown span may itself pack "City, ST / HS / Prev" on some templates
        hometown, hs2, prev2 = split_hometown_field(c.get("hometown"))
        out.append({
            "player": clean_name(c.get("name")),
            "height_in": parse_height_to_inches(c.get("height")),
            "weight_lb": parse_weight_to_lb(c.get("weight")),
            "bats": bats, "throws": throws,
            "class_year": c.get("cls"),
            "position": c.get("pos"),
            "hometown": hometown,
            "high_school": c.get("highschool") or hs2,
            "previous_school": c.get("prev") or prev2,
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
            "hometown": pl.get("hometown"),
            "high_school": pl.get("highSchool"),
            "previous_school": pl.get("previousSchool"),
            "source": "sidearm-json",
        })
    return out


# ---------------------------------------------------------------------------
# Disk helpers
# ---------------------------------------------------------------------------
def _load(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _save(path, obj):
    path.write_text(json.dumps(obj, indent=1, ensure_ascii=False), encoding="utf-8")


def load_url_map():
    """Curated map. Strip the leading _comment key for lookups but preserve on save."""
    raw = _load(URL_MAP_FILE, {})
    return raw


def save_url_map(raw):
    _save(URL_MAP_FILE, raw)


# ---------------------------------------------------------------------------
# Web-search team -> host resolver
# ---------------------------------------------------------------------------
def _domain_of(url):
    try:
        net = urllib.parse.urlparse(url).netloc.lower()
        return net[4:] if net.startswith("www.") else net
    except Exception:
        return ""


def _registrable(domain):
    """Crude eTLD+1 for aggregator matching (handles sub.domain.tld)."""
    parts = domain.split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else domain


def _is_aggregator(domain):
    if domain in AGGREGATOR_DOMAINS or _registrable(domain) in AGGREGATOR_DOMAINS:
        return True
    return any(tok in domain for tok in NEWS_TOKENS)


def _bing_decode(href):
    """Decode a bing /ck/a redirect href to its true target URL."""
    if not href:
        return None
    if "bing.com/ck/a" not in href:
        return href
    m = re.search(r"[?&]u=a1([^&]+)", href)
    if not m:
        return None
    s = m.group(1)
    s += "=" * (-len(s) % 4)
    try:
        return base64.b64decode(s).decode("utf-8", "ignore")
    except Exception:
        return None


def _ddg_decode(href):
    """DDG html/lite wraps targets in /l/?uddg=<encoded>. Unwrap if present."""
    if not href:
        return None
    if "uddg=" in href:
        m = re.search(r"[?&]uddg=([^&]+)", href)
        if m:
            return urllib.parse.unquote(m.group(1))
    return href


def _pick_athletics_host(candidates):
    """candidates: list of target_url. Return (host, cms_hint) for the best official
    athletics result, or (None, None).

    The ONLY reliable signal is a result URL whose path is itself a college-athletics
    roster page: '/sports/baseball/roster' (Sidearm) or '/sports/bsb/.../roster'
    (Presto). DuckDuckGo surfaces this as the #1 organic hit for essentially every
    NCAA program. We REQUIRE that signal rather than guessing from a bare domain --
    bare-domain guessing produced junk (city .gov sites, uakron.edu, airbnb.com).
    A roster path on an aggregator (maxpreps, etc.) is still rejected."""
    for url in candidates:
        if not url or not url.startswith("http"):
            continue
        dom = _domain_of(url)
        if not dom or _is_aggregator(dom):
            continue
        path = urllib.parse.urlparse(url).path.lower()
        if "/sports/bsb/" in path:
            return dom, "presto"
        if "/sports/baseball/roster" in path or path.rstrip("/").endswith("/sports/baseball"):
            return dom, "sidearm"
    return None, None


def _search_bing(br, query):
    q = urllib.parse.quote(query)
    try:
        br.goto(f"https://www.bing.com/search?q={q}", settle=2500)
    except Exception:
        return []
    try:
        res = br.evaluate(_JS_BING_RESULTS)
    except Exception:
        return []
    out = []
    for r in res or []:
        target = _bing_decode(r.get("href"))
        if not target and r.get("cite"):
            # cite displays the domain with arrows; fall back to its scheme+host
            cite = re.sub(r"\s*[›>]\s*", "/", r["cite"]).strip()
            if cite.startswith("http"):
                target = cite
        if target:
            out.append(target)
    return out


def _search_ddg(br, query, variant="html"):
    q = urllib.parse.quote(query)
    base = "https://html.duckduckgo.com/html/" if variant == "html" else "https://lite.duckduckgo.com/lite/"
    try:
        br.goto(f"{base}?q={q}", settle=2500)
    except Exception:
        return []
    try:
        res = br.evaluate(_JS_DDG_RESULTS)
    except Exception:
        res = []
    out = []
    for r in res or []:
        target = _ddg_decode(r.get("href"))
        if target:
            out.append(target)
    # lite layout has no result__a class -- grab any external anchor as fallback
    if not out:
        try:
            anchors = br.evaluate("() => Array.from(document.querySelectorAll('a[href]')).map(a=>a.href)")
        except Exception:
            anchors = []
        for href in anchors or []:
            t = _ddg_decode(href)
            if t and t.startswith("http"):
                out.append(t)
    return out


def resolve_host_via_search(br, team, search_stats):
    """team -> (host, cms_hint, engine) using web search; (None, None, None) if all
    engines fail / bot-wall.

    Engine order: DuckDuckGo html FIRST (verified to return the exact official roster
    URL as the #1 organic hit, and to survive repeated queries in one session), then
    DDG lite, then Bing. Bing was demoted: after its first query in a session it
    degrades to cached generic geographic results regardless of query text."""
    query = f"{team} baseball roster"
    for engine, fn in (("ddg-html", lambda: _search_ddg(br, query, "html")),
                       ("ddg-lite", lambda: _search_ddg(br, query, "lite")),
                       ("bing", lambda: _search_bing(br, query))):
        candidates = fn()
        time.sleep(random.uniform(*SEARCH_DELAY))
        if candidates:
            host, cms_hint = _pick_athletics_host(candidates)
            if host:
                search_stats[engine] = search_stats.get(engine, 0) + 1
                return host, cms_hint, engine
    return None, None, None


def resolve_team(br, team, url_map, unresolved, search_stats):
    """team -> {host, cms} via curated map first, then web search + CMS detect.

    Mutates url_map / unresolved and persists them. Returns dict or None."""
    info = url_map.get(team)
    if isinstance(info, dict) and info.get("host") and info.get("cms"):
        return info

    # web-search resolution
    host, cms_hint, engine = resolve_host_via_search(br, team, search_stats)
    if not host:
        unresolved[team] = "search-no-host"
        _save(UNRESOLVED_FILE, unresolved)
        return None

    # CMS: prefer the hint derived from the result URL path (we matched a roster path
    # to find the host in the first place, so the path already tells us the CMS).
    cms = cms_hint
    if not cms or cms == "unknown":
        cms = detect_cms(host)
    if cms == "unknown":
        html = br.fetch_root_html(host)
        cms = detect_cms(host, html)
    if cms == "unknown":
        # Default to sidearm: it is by far the most common CMS and shares the
        # /sports/baseball/roster path; the roster fetch will simply yield 0 rows
        # if wrong, which we record rather than dropping the host entirely.
        cms = "sidearm"

    info = {"host": host, "cms": cms, "via": f"search:{engine}"}
    url_map[team] = info
    save_url_map(url_map)
    unresolved.pop(team, None)
    return info


# ---------------------------------------------------------------------------
# Fetch one team-season -> rows  (CMS dispatch + caching; from prototype)
# ---------------------------------------------------------------------------
def fetch_team_season(br, team, season, info, cache):
    key = f"{team}|{season}"
    if key in cache and not cache[key].get("error"):
        return cache[key]

    host, cms = info["host"], info["cms"]
    url = presto_roster_url(host, season) if cms == "presto" else sidearm_roster_url(host, season)

    br.warm(host)
    rows = []

    try:
        if cms == "sidearm":
            # (a) modern JSON API for current season
            if season == 2026:
                sports = br.get_json(f"https://{host}/api/v2/Sports")
                rid = None
                items = sports if isinstance(sports, list) else (sports or {}).get("items", [])
                for s in (items or []):
                    nm = (s.get("title") or s.get("shortName") or "").lower()
                    seg = (s.get("urlSegment") or s.get("slug") or "").lower()
                    if (("baseball" in nm and "soft" not in nm) or seg == "baseball") and s.get("rosterId"):
                        rid = s["rosterId"]
                        break
                if rid:
                    data = br.get_json(f"https://{host}/api/v2/Rosters/{rid}")
                    if data and data.get("players"):
                        rows = parse_sidearm_json(data["players"])
            # (b) DOM render -- modern s-table OR classic cards
            if not rows:
                br.render(url)
                res = br.page().evaluate(_JS_HEADER_TABLE)
                if res and res.get("rows"):
                    rows = parse_table_rows(res["headers"], res["rows"])
                if not rows:
                    cards = br.page().evaluate(_JS_SIDEARM_CARDS)
                    if cards:
                        rows = parse_sidearm_cards(cards)

        elif cms == "presto":
            br.render(url)
            res = br.page().evaluate(_JS_HEADER_TABLE)
            if res and res.get("rows"):
                rows = parse_table_rows(res["headers"], res["rows"])
    except Exception as e:
        result = {"team": team, "season": season, "host": host, "cms": cms,
                  "url": url, "n": 0, "rows": [], "error": f"fetch:{type(e).__name__}"}
        cache[key] = result
        _save(ROSTER_CACHE, cache)
        time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))
        return result

    # keep any player that has at least one of H/W (DB loader matches by name later)
    rows = [r for r in rows if r.get("height_in") or r.get("weight_lb")]
    result = {"team": team, "season": season, "host": host, "cms": cms,
              "url": url, "n": len(rows), "rows": rows}
    cache[key] = result
    _save(ROSTER_CACHE, cache)
    time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))
    return result


# ---------------------------------------------------------------------------
# Read team universe from the 6-4-3 exports
# ---------------------------------------------------------------------------
def teams_for_season(season):
    """Union of `Team` values across hitters_overall + pitchers for one season."""
    teams = set()
    paths = [
        EXPORTS_DIR / f"hitters_{season}_overall.csv",
        EXPORTS_DIR / "pitching" / f"pitchers_{season}.csv",
    ]
    for p in paths:
        if not p.exists():
            continue
        with p.open(encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                t = (row.get("Team") or "").strip()
                if t:
                    teams.add(t)
    return sorted(teams)


# ---------------------------------------------------------------------------
# Incremental CSV writer (append per team, flush)
# ---------------------------------------------------------------------------
class SeasonCsvWriter:
    """Append rows per team and flush so partial progress survives a crash.

    Tracks which teams are already written (resume support) by re-reading the
    existing CSV on open."""

    def __init__(self, season):
        self.season = season
        self.path = BIO_OUT_DIR / f"team_bio_{season}.csv"
        self.written_teams = set()
        new_file = not self.path.exists()
        if not new_file:
            try:
                with self.path.open(encoding="utf-8", newline="") as f:
                    for row in csv.DictReader(f):
                        if row.get("team"):
                            self.written_teams.add(row["team"])
            except Exception:
                new_file = True
        self._f = self.path.open("a", encoding="utf-8", newline="")
        self._w = csv.DictWriter(self._f, fieldnames=OUT_COLUMNS, extrasaction="ignore")
        if new_file or self.path.stat().st_size == 0:
            self._w.writeheader()
            self._f.flush()
        self.row_count = self._count_existing_rows()

    def _count_existing_rows(self):
        try:
            with self.path.open(encoding="utf-8", newline="") as f:
                return sum(1 for _ in csv.DictReader(f))
        except Exception:
            return 0

    def already_done(self, team):
        return team in self.written_teams

    def write_team(self, team, rows):
        n = 0
        for r in rows:
            if not r.get("player"):
                continue
            self._w.writerow({
                "player": r.get("player"),
                "team": team,
                "season": self.season,
                "height_in": r.get("height_in"),
                "weight_lb": r.get("weight_lb"),
                "bats": r.get("bats"),
                "throws": r.get("throws"),
                "class_year": r.get("class_year"),
                "hometown": r.get("hometown"),
                "high_school": r.get("high_school"),
                "previous_school": r.get("previous_school"),
            })
            n += 1
        self._f.flush()
        self.written_teams.add(team)
        self.row_count += n
        return n

    def close(self):
        try:
            self._f.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Backfill driver
# ---------------------------------------------------------------------------
def run_backfill(seasons, limit=None, verify=False):
    url_map = load_url_map()
    cache = _load(ROSTER_CACHE, {})
    unresolved = _load(UNRESOLVED_FILE, {})
    search_stats = {}
    stats = {s: {"resolved": 0, "unresolved": 0, "rows": 0, "teams": 0, "zero": 0}
             for s in seasons}

    print(f"[init] seasons={seasons} verify={verify} limit={limit}")
    print(f"[init] curated map entries: {len([k for k in url_map if not k.startswith('_')])}")
    print("[init] launching cloakbrowser (stealth Chromium)...")
    br = Browser(headless=True)

    try:
        for season in seasons:
            teams = teams_for_season(season)
            if limit:
                teams = teams[:limit]
            print(f"\n========== SEASON {season}: {len(teams)} teams ==========")
            writer = None if verify else SeasonCsvWriter(season)
            if writer:
                print(f"[{season}] output: {writer.path}  (already written: {len(writer.written_teams)} teams)")

            for i, team in enumerate(teams, 1):
                if writer and writer.already_done(team):
                    continue

                info = resolve_team(br, team, url_map, unresolved, search_stats)
                if not info:
                    stats[season]["unresolved"] += 1
                    print(f"  [{i}/{len(teams)}] {team:32} UNRESOLVED")
                    continue

                res = fetch_team_season(br, team, season, info, cache)
                n = res.get("n", 0)
                stats[season]["resolved"] += 1
                stats[season]["teams"] += 1
                stats[season]["rows"] += n
                if n == 0:
                    stats[season]["zero"] += 1

                if writer:
                    writer.write_team(team, res.get("rows", []))

                tag = res.get("error") or f"{n} rows"
                print(f"  [{i}/{len(teams)}] {team:32} {info['cms']:7} {info['host']:34} {tag}")

                if verify and stats[season]["resolved"] >= 5:
                    print("  [verify] reached 5 resolved teams, stopping.")
                    break

            if writer:
                print(f"[{season}] CSV rows now: {writer.row_count}")
                writer.close()
    finally:
        br.close()

    # ---- report ----
    print("\n================ SUMMARY ================")
    print(f"search engines used: {search_stats}")
    total_unres = len([k for k in unresolved])
    print(f"unresolved (cumulative): {total_unres}  -> {UNRESOLVED_FILE.name}")
    for season in seasons:
        s = stats[season]
        p = BIO_OUT_DIR / f"team_bio_{season}.csv"
        print(f"  {season}: resolved={s['resolved']} unresolved={s['unresolved']} "
              f"teams_scraped={s['teams']} zero_row_teams={s['zero']} rows={s['rows']}  -> {p}")
    print(f"curated map now has {len([k for k in url_map if not k.startswith('_')])} entries.")
    return stats, search_stats, unresolved


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
    print("=== split_hometown_field ===")
    for raw in ["Dallas, TX / Jesuit HS / TCU", "Miami, FL / Columbus", "Reno, NV", ""]:
        print(f"  {raw!r:34} -> {split_hometown_field(raw)}")
    print("=== _bing_decode ===")
    import base64 as _b64
    enc = _b64.b64encode(b"https://rolltide.com/sports/baseball/roster").decode().rstrip("=")
    print("  ", _bing_decode(f"https://www.bing.com/ck/a?!&&p=x&u=a1{enc}&ntb=1"))
    print("=== _is_aggregator ===")
    for d in ("rolltide.com", "d1baseball.com", "en.wikipedia.org", "hailstate.com",
              "tuscaloosanews.com", "huntington.prestosports.com"):
        print(f"  {d:34} aggregator={_is_aggregator(d)}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    # Unbuffered stdout so long-run progress is visible live when redirected to a file.
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Productionized team-site H+W roster scraper.")
    ap.add_argument("--offline", action="store_true", help="parser self-checks, no network")
    ap.add_argument("--verify", action="store_true", help="resolve+scrape ~5 teams/season, no CSV")
    ap.add_argument("--seasons", type=str, default=None, help="comma list, e.g. 2026,2025")
    ap.add_argument("--limit", type=int, default=None, help="cap teams per season")
    args = ap.parse_args()

    if args.offline:
        offline_checks()
        return

    seasons = SEASONS
    if args.seasons:
        seasons = tuple(int(s) for s in args.seasons.split(",") if s.strip())

    run_backfill(seasons, limit=args.limit, verify=args.verify)


if __name__ == "__main__":
    main()
