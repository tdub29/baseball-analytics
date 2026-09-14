"""
fetch_team_bio_presto.py  (RECOVERY)
====================================

Recover HEIGHT + WEIGHT (plus Bats/Throws/Class/Position/Hometown/HighSchool) for the
season-2026 teams that the main scraper (scripts/fetch_team_bio.py) returned ZERO rows
on -- the ~48 programs whose sites use a CMS the cloakbrowser DOM/JSON path didn't
handle (Presto Sports HTML tables, and the modern WMT/Nuxt "next-gen Sidearm" sites
whose roster data is embedded as an SSR devalue blob rather than the /api/v2 JSON the
old parser expected).

This is a TARGETED, requests-only companion to fetch_team_bio.py -- it does NOT
re-scrape teams that already have rows. It reads the failure list straight from the
roster cache and writes its own deliverable, so it never touches the main CSV or DB.

WHY PLAIN REQUESTS WORK HERE
----------------------------
The main scraper went through cloakbrowser because Learfield/old-Sidearm sites bot-wall
plain requests. The 48 failures are a different population:
  * Modern WMT-Digital "next-gen Sidearm" (Clemson, Stanford, Auburn, ASU, LSU, ...):
    the roster page is server-side-rendered Nuxt; ALL player data is in the
    <script id="__NUXT_DATA__"> devalue blob. A plain GET (browser UA) returns 200 with
    the full blob. We decode the devalue index-graph and pull every player record
    structurally (no hardcoded indices), so it generalizes across every WMT site.
  * Presto Sports (Tusculum, Tennessee Tech, Georgetown KY, ...): the roster is a real
    HTML <table> with a `Label: value` cell convention. A plain GET returns the rows;
    we find the roster table by its Ht./Wt. header and parse tbody rows, stripping the
    cell label prefix.
  * A couple of bespoke CMSes (LSU's own /sports/bsb/roster table) fall through to the
    same generic HTML-table parser.

A genuinely JS-rendered table (rows injected client-side, e.g. gpacsports.com) yields 0
static rows -- we record it as skipped (cms-js-rendered) rather than spinning up a
headless browser, since it's a single site out of 48.

OUTPUT
------
data/643_exports/bio/team_bio_presto.csv  (its OWN file; the loader can union it with
team_bio_<season>.csv later). Columns:
  player, team, season, height_in, weight_lb, bats, throws, class_year, position,
  hometown, high_school

Raw responses cached under data/cache/presto_recover/<host>.html (resume-friendly,
and an audit trail of exactly what each site served).

USAGE
-----
    python scripts/fetch_team_bio_presto.py            # recover all 2026 zero-row teams
    python scripts/fetch_team_bio_presto.py --limit 5  # cap (debug)
    python scripts/fetch_team_bio_presto.py --offline   # parser self-checks, no network

Internal USD evaluation only. Polite: ~1 req/sec, descriptive UA, everything cached.
Reuses the verified value parsers from fetch_team_bio.py (height/weight/bats-throws/
hometown-split) so normalization matches the main deliverable exactly.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
from pathlib import Path

import requests

# Reuse the verified normalizers from the main scraper (same dir).
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_team_bio import (  # noqa: E402
    clean_name,
    parse_bats_throws,
    parse_height_to_inches,
    parse_weight_to_lb,
    split_hometown_field,
)

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
CACHE_DIR = DATA_DIR / "cache"
RAW_DIR = CACHE_DIR / "presto_recover"
BIO_OUT_DIR = DATA_DIR / "643_exports" / "bio"
RAW_DIR.mkdir(parents=True, exist_ok=True)
BIO_OUT_DIR.mkdir(parents=True, exist_ok=True)

ROSTER_CACHE = CACHE_DIR / "team_bio_rosters.json"
OUT_CSV = BIO_OUT_DIR / "team_bio_presto.csv"
SKIPPED_FILE = CACHE_DIR / "team_bio_presto_skipped.json"

TARGET_SEASON = 2026
DELAY = 1.1  # ~1 req/sec, polite
TIMEOUT = 30

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 "
    "(USD-Baseball-Scout internal roster recovery; contact trevor@good360.org)"
)

OUT_COLUMNS = [
    "player", "team", "season", "height_in", "weight_lb", "bats", "throws",
    "class_year", "position", "hometown", "high_school",
]

sys.setrecursionlimit(300000)


# ---------------------------------------------------------------------------
# Target list: season-2026 teams with an empty rows[] in the roster cache
# ---------------------------------------------------------------------------
def load_targets():
    cache = json.loads(ROSTER_CACHE.read_text(encoding="utf-8"))
    targets = []
    for v in cache.values():
        if v.get("season") != TARGET_SEASON:
            continue
        if v.get("rows"):  # already has players -> not a failure
            continue
        targets.append({
            "team": v.get("team"),
            "host": v.get("host"),
            "cms": v.get("cms"),
            "url": v.get("url"),
        })
    # stable order: presto first then sidearm, alpha within
    targets.sort(key=lambda t: (t.get("cms") or "", t.get("team") or ""))
    return targets


# ---------------------------------------------------------------------------
# HTTP with on-disk raw cache (resume + audit)
# ---------------------------------------------------------------------------
_session = requests.Session()
_session.headers.update({"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})


def _raw_path(host, tag):
    safe = re.sub(r"[^a-z0-9._-]", "_", (host or "unknown").lower())
    return RAW_DIR / f"{safe}.{tag}.html"


def fetch(url, host, tag, use_cache=True):
    """GET url, caching the body to disk. Returns (status, text) or (None, '')."""
    cp = _raw_path(host, tag)
    if use_cache and cp.exists() and cp.stat().st_size > 0:
        try:
            head = cp.read_text(encoding="utf-8", errors="ignore")
            # first line stores 'STATUS\t<code>\t<final_url>'
            if head.startswith("STATUS\t"):
                first, _, body = head.partition("\n")
                code = int(first.split("\t")[1])
                return code, body
        except Exception:
            pass
    try:
        r = _session.get(url, timeout=TIMEOUT, allow_redirects=True)
    except Exception as e:
        return None, f"__ERR__:{type(e).__name__}"
    try:
        cp.write_text(f"STATUS\t{r.status_code}\t{r.url}\n{r.text}", encoding="utf-8")
    except Exception:
        pass
    time.sleep(DELAY)
    return r.status_code, r.text


# ---------------------------------------------------------------------------
# Parser A: WMT / next-gen Sidearm  -> decode __NUXT_DATA__ devalue blob
# ---------------------------------------------------------------------------
_NUXT_RE = re.compile(
    r'<script[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', re.S
)


def _devalue_deref(data):
    """Return a memoized dereferencer for a devalue flat index-graph (list `data`)."""
    cache = {}

    def deref(idx, stack=()):
        if not isinstance(idx, int) or idx < 0 or idx >= len(data):
            return idx
        if idx in stack:          # cycle guard (devalue graphs self-reference)
            return None
        if idx in cache:
            return cache[idx]
        v = data[idx]
        ns = stack + (idx,)
        if isinstance(v, dict):
            out = {k: deref(val, ns) for k, val in v.items()}
        elif isinstance(v, list):
            out = [deref(e, ns) for e in v]
        else:
            out = v
        cache[idx] = out
        return out

    return deref


def _extract_bt_from_profile(rec):
    """B/T lives in profile_field_values[*] where profile_field.name == 'bt'."""
    for f in (rec.get("profile_field_values") or []):
        if not isinstance(f, dict):
            continue
        fld = (f.get("profile_field") or {})
        name = (fld.get("name") or fld.get("title") or "").strip().lower()
        if name in ("bt", "b/t", "bats/throws", "bats / throws"):
            return f.get("value")
    return None


def parse_wmt_nuxt(html):
    """Decode the SSR devalue blob and pull every roster player. [] if not a WMT page."""
    m = _NUXT_RE.search(html)
    if not m:
        return []
    try:
        data = json.loads(m.group(1))
    except Exception:
        return []
    if not isinstance(data, list):
        return []
    deref = _devalue_deref(data)

    out, seen = [], set()
    for i, x in enumerate(data):
        # A roster-player record: dict carrying height_feet AND a nested `player` dict.
        if not (isinstance(x, dict) and "height_feet" in x and "player" in x):
            continue
        rec = deref(i)
        pl = rec.get("player")
        if not (isinstance(pl, dict) and pl.get("first_name")):
            continue
        pid = rec.get("player_id") or pl.get("id") or rec.get("id")
        if pid in seen:
            continue
        seen.add(pid)

        # height: prefer feet/inches on the record, fall back to the player subdoc
        hf = rec.get("height_feet")
        hi = rec.get("height_inches")
        if hf is None and pl.get("height_feet") is not None:
            hf, hi = pl.get("height_feet"), pl.get("height_inches")
        height_in = None
        if hf not in (None, 0) or hi not in (None, 0):
            try:
                height_in = int(hf or 0) * 12 + int(hi or 0)
                if not (40 <= height_in <= 95):
                    height_in = None
            except Exception:
                height_in = None

        weight_lb = parse_weight_to_lb(rec.get("weight") or pl.get("weight"))
        bats, throws = parse_bats_throws(_extract_bt_from_profile(rec))
        pos = (rec.get("player_position") or {})
        pos = pos.get("abbreviation") or pos.get("name") if isinstance(pos, dict) else None
        cls = (rec.get("class_level") or {})
        cls = cls.get("name") or cls.get("abbreviation") if isinstance(cls, dict) else None
        name = pl.get("full_name") or " ".join(
            x for x in (pl.get("first_name"), pl.get("last_name")) if x)

        out.append({
            "player": clean_name(name),
            "height_in": height_in,
            "weight_lb": weight_lb,
            "bats": bats, "throws": throws,
            "class_year": cls,
            "position": pos,
            "hometown": pl.get("hometown"),
            "high_school": pl.get("high_school"),
            "source": "wmt-nuxt",
        })
    return out


# ---------------------------------------------------------------------------
# Parser B: generic HTML roster <table>  (Presto + LSU + similar)
# ---------------------------------------------------------------------------
def _cell_text(cell):
    """Cell text with the Presto 'Label:' span removed and whitespace collapsed."""
    for lab in cell.select("span.label, .label, .data-label"):
        lab.extract()
    txt = re.sub(r"\s+", " ", cell.get_text(" ", strip=True)).strip()
    # Presto bakes the column label into the cell text as 'Ht.: 6-2' -- strip it.
    txt = re.sub(r"^[A-Za-z./ &]{1,28}:\s*", "", txt)
    return txt


def _header_index(headers):
    """Map normalized header tokens -> column position."""
    idx = {}
    for i, h in enumerate(headers):
        hl = h.lower().strip()
        if re.match(r"^ht\.?$", hl) or "height" in hl:
            idx["ht"] = i
        elif re.match(r"^wt\.?$", hl) or "weight" in hl:
            idx["wt"] = i
        elif hl in ("name", "full name", "player"):
            idx.setdefault("name", i)
        elif hl.startswith("b/t") or hl == "bt":
            idx["bt"] = i
        elif hl in ("cl.", "class", "yr.", "year", "cl", "yr") or "elig" in hl or "class" in hl:
            idx.setdefault("cls", i)
        elif "pos" in hl:
            idx.setdefault("pos", i)
        elif "previous" in hl or "prev" in hl:
            idx["prev"] = i
        elif "hometown" in hl:
            # 'Hometown' alone, or a combined 'Hometown/High School' column
            idx["home"] = i
            if "high school" in hl or "/ hs" in hl or hl.endswith("hs"):
                idx["home_combo"] = True
        elif "high school" in hl or hl in ("hs", "high sch."):
            idx["hs"] = i
    return idx


def parse_html_table(html):
    """Find the roster <table> by its Ht/Wt header and parse static tbody rows.

    Accepts a table with EITHER a Ht. or a Wt. column (some Presto sites drop weight).
    [] if no roster table or no static rows (e.g. JS-injected body)."""
    from bs4 import BeautifulSoup
    soup = BeautifulSoup(html, "lxml")

    best = None
    for tbl in soup.find_all("table"):
        heads = [_clean_header(th) for th in tbl.select("thead th, thead td")]
        if not heads:
            continue
        has_ht = any(re.match(r"^ht\.?$", h.lower()) or "height" in h.lower() for h in heads)
        has_wt = any(re.match(r"^wt\.?$", h.lower()) or "weight" in h.lower() for h in heads)
        has_name = any(h.lower() in ("name", "player", "full name") for h in heads)
        if (has_ht or has_wt) and has_name:
            best = (tbl, heads)
            break
    if not best:
        return []
    tbl, headers = best
    idx = _header_index(headers)
    body_rows = tbl.select("tbody tr")
    if not body_rows:
        return []

    nhdr = len(headers)
    out = []
    for tr in body_rows:
        cells = tr.find_all(["th", "td"])
        if len(cells) < 2:
            continue
        texts = [_cell_text(c) for c in cells]
        # right-align if a site emits an extra leading cell (jersey repeated, etc.)
        offset = max(0, len(texts) - nhdr)

        def get(key):
            if key not in idx:
                return None
            j = idx[key] + offset
            return texts[j] if 0 <= j < len(texts) else None

        name = clean_name(get("name"))
        if not name:
            continue
        bats, throws = parse_bats_throws(get("bt"))

        # hometown / high school: combined column vs separate columns
        if idx.get("home_combo") and "hs" not in idx:
            hometown, high_school, _prev = split_hometown_field(get("home"))
        else:
            hometown = get("home")
            high_school = get("hs")

        out.append({
            "player": name,
            "height_in": parse_height_to_inches(get("ht")),
            "weight_lb": parse_weight_to_lb(get("wt")),
            "bats": bats, "throws": throws,
            "class_year": get("cls"),
            "position": get("pos"),
            "hometown": hometown or None,
            "high_school": high_school or None,
            "source": "html-table",
        })
    return out


def _clean_header(th):
    from_text = re.sub(r"\s+", " ", th.get_text(" ", strip=True)).strip()
    return from_text


# ---------------------------------------------------------------------------
# Parser C: classic Sidearm card layout  (.sidearm-roster-player static cards)
# ---------------------------------------------------------------------------
def parse_sidearm_cards_html(html):
    """Parse the classic Sidearm `.sidearm-roster-player` static cards.

    Some classic Sidearm sites (e.g. gorunners.com / CSU Bakersfield) render the full
    roster server-side as cards with `.sidearm-roster-player-height/-weight/...` spans.
    Others gate H/W behind a 'Full Bio' JS fetch -- those cards have no height span and
    are dropped by the H/W filter downstream, recorded as js-rendered. [] if no cards."""
    from bs4 import BeautifulSoup
    soup = BeautifulSoup(html, "lxml")
    # Two card layouts exist. Classic '.sidearm-roster-player' OR the newer list/grid
    # '.sidearm-list-card-item' (e.g. gorunners.com / CSU Bakersfield) -- pick whichever
    # container actually holds the height/weight spans.
    cards = [c for c in soup.select(".sidearm-roster-player")
             if c.select_one(".sidearm-roster-player-height, .sidearm-roster-player-weight")]
    if not cards:
        cards = [c for c in soup.select(".sidearm-list-card-item")
                 if c.select_one(".sidearm-roster-player-height, .sidearm-roster-player-weight")]
    if not cards:
        return []

    def first_text(card, *selectors):
        for sel in selectors:
            el = card.select_one(sel)
            if el:
                t = re.sub(r"\s+", " ", el.get_text(" ", strip=True)).strip()
                if t:
                    return t
        return None

    out = []
    for c in cards:
        height = first_text(c, ".sidearm-roster-player-height")
        weight = first_text(c, ".sidearm-roster-player-weight")
        if not (height or weight):
            continue  # H/W gated behind JS -> not recoverable from static HTML
        name = first_text(c, ".sidearm-roster-player-name")
        bats, throws = parse_bats_throws(first_text(c, ".sidearm-roster-player-custom1"))
        cls = first_text(c, ".sidearm-roster-player-academic-year",
                         ".sidearm-roster-player-class")
        pos = first_text(c, ".sidearm-roster-player-position-long-short",
                         ".sidearm-roster-player-position-short",
                         ".sidearm-roster-player-position-long",
                         ".sidearm-roster-player-position")
        hometown = first_text(c, ".sidearm-roster-player-hometown")
        hs = first_text(c, ".sidearm-roster-player-highschool",
                        ".sidearm-roster-player-high-school")
        prev = first_text(c, ".sidearm-roster-player-previous-school")
        # hometown span sometimes packs 'City, ST / HS'
        if hometown and "/" in hometown:
            hometown, hs2, _p = split_hometown_field(hometown)
            hs = hs or hs2
        out.append({
            "player": clean_name(name),
            "height_in": parse_height_to_inches(height),
            "weight_lb": parse_weight_to_lb(weight),
            "bats": bats, "throws": throws,
            "class_year": cls,
            "position": pos,
            "hometown": hometown,
            # a '...HS' previous-school is really the high school on some templates
            "high_school": hs or (prev if prev and re.search(r"\b(HS|High)\b", prev, re.I) else None),
            "source": "sidearm-card",
        })
    return out


# ---------------------------------------------------------------------------
# Per-team recovery: try WMT-nuxt then HTML-table on the roster page(s)
# ---------------------------------------------------------------------------
def candidate_urls(target):
    """Roster URLs to try for one team. The recorded url first, then the alt-CMS path
    (CMS labels in the cache are unreliable -- LSU was tagged presto but serves a custom
    HTML table at the sidearm path)."""
    host = target["host"]
    urls = []
    if target.get("url"):
        urls.append(target["url"])
    sidearm = f"https://{host}/sports/baseball/roster"
    presto = f"https://{host}/sports/bsb/2025-26/roster"
    for u in (sidearm, presto):
        if u not in urls:
            urls.append(u)
    return urls


def recover_team(target):
    """Return (rows, meta) where meta records what happened for the report."""
    host = target["host"]
    for ci, url in enumerate(candidate_urls(target)):
        status, html = fetch(url, host, tag=f"try{ci}")
        if status is None or html.startswith("__ERR__"):
            continue
        if status != 200 or not html:
            continue
        # Parser A: WMT/Nuxt SSR blob
        rows = parse_wmt_nuxt(html)
        if rows:
            return rows, {"status": status, "url": url, "parser": "wmt-nuxt"}
        # Parser B: generic HTML table
        rows = parse_html_table(html)
        if rows:
            return rows, {"status": status, "url": url, "parser": "html-table"}
        # Parser C: classic Sidearm static cards (H/W in spans)
        rows = parse_sidearm_cards_html(html)
        if rows:
            return rows, {"status": status, "url": url, "parser": "sidearm-card"}
        # 200 but no rows -> likely JS-rendered body; remember and keep trying alts
        last = {"status": status, "url": url, "parser": "none"}
    return [], last if "last" in dir() else {"status": None, "url": None, "parser": "none"}


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def run(limit=None):
    targets = load_targets()
    if limit:
        targets = targets[:limit]
    print(f"[init] {len(targets)} season-{TARGET_SEASON} zero-row teams to recover")
    print(f"[init] output: {OUT_CSV}")

    skipped = {}
    attempted = recovered = total_rows = 0
    with_weight = 0

    f = OUT_CSV.open("w", encoding="utf-8", newline="")
    w = csv.DictWriter(f, fieldnames=OUT_COLUMNS, extrasaction="ignore")
    w.writeheader()

    for i, t in enumerate(targets, 1):
        attempted += 1
        rows, meta = recover_team(t)
        # keep players with at least one of H/W (matches the main deliverable rule)
        rows = [r for r in rows if r.get("player") and (r.get("height_in") or r.get("weight_lb"))]
        if rows:
            recovered += 1
            for r in rows:
                w.writerow({
                    "player": r.get("player"),
                    "team": t["team"],
                    "season": TARGET_SEASON,
                    "height_in": r.get("height_in"),
                    "weight_lb": r.get("weight_lb"),
                    "bats": r.get("bats"),
                    "throws": r.get("throws"),
                    "class_year": r.get("class_year"),
                    "position": r.get("position"),
                    "hometown": r.get("hometown"),
                    "high_school": r.get("high_school"),
                })
                total_rows += 1
                if r.get("weight_lb"):
                    with_weight += 1
            f.flush()
            print(f"  [{i}/{len(targets)}] {t['team']:28} {t['host']:34} "
                  f"{meta['parser']:10} {len(rows)} rows")
        else:
            reason = "cms-js-rendered" if meta.get("status") == 200 else (
                "http-error" if meta.get("status") else "blocked-or-unreachable")
            skipped[t["team"]] = {"host": t["host"], "reason": reason,
                                  "status": meta.get("status")}
            print(f"  [{i}/{len(targets)}] {t['team']:28} {t['host']:34} "
                  f"SKIPPED ({reason})")

    f.close()
    SKIPPED_FILE.write_text(json.dumps(skipped, indent=1), encoding="utf-8")

    cov = (with_weight / total_rows * 100) if total_rows else 0.0
    print("\n================ RECOVERY SUMMARY ================")
    print(f"teams attempted : {attempted}")
    print(f"teams recovered : {recovered}")
    print(f"teams skipped   : {len(skipped)}  -> {SKIPPED_FILE.name}")
    print(f"player rows     : {total_rows}")
    print(f"weight coverage : {with_weight}/{total_rows} = {cov:.1f}%")
    print(f"output          : {OUT_CSV}")
    if skipped:
        print("skipped teams:")
        for tm, info in skipped.items():
            print(f"  - {tm} ({info['host']}): {info['reason']}")
    return {"attempted": attempted, "recovered": recovered, "rows": total_rows,
            "weight_coverage": cov, "skipped": skipped}


# ---------------------------------------------------------------------------
# Offline self-checks (no network)
# ---------------------------------------------------------------------------
def offline_checks():
    print("=== WMT-nuxt parser (synthetic devalue blob) ===")
    # devalue flat index-graph: idx0 unused; build a minimal player record.
    data = [
        0,                                   # 0
        {"first_name": 2, "last_name": 3, "full_name": 4, "height_feet": 5,
         "height_inches": 6, "weight": 7, "hometown": 8, "high_school": 9},  # 1 player subdoc
        "Nate", "Savoie", "Nate Savoie", 6, 2, "215", "Newport Beach, Calif.", "Orange Lutheran",  # 2-9
        {"abbreviation": 11, "name": 11}, "C",                                # 10 pos, 11
        {"name": 13}, "So.",                                                  # 12 class, 13
        {"profile_field": 15, "value": 17}, {"name": 16}, "bt", "R/R",        # 14-17
        # 18 = the roster-player record (top-level dict carrying height_feet + player)
        {"player_id": 99, "player": 1, "height_feet": 5, "height_inches": 6,
         "weight": 7, "player_position": 10, "class_level": 12,
         "profile_field_values": 19},
        [14],                                                                 # 19 profile list
    ]
    html = '<script id="__NUXT_DATA__">' + json.dumps(data) + "</script>"
    rows = parse_wmt_nuxt(html)
    print("  parsed:", json.dumps(rows, indent=1))
    assert rows and rows[0]["player"] == "Nate Savoie", "name"
    assert rows[0]["height_in"] == 74, "height"
    assert rows[0]["weight_lb"] == 215, "weight"
    assert rows[0]["bats"] == "R" and rows[0]["throws"] == "R", "bt"
    assert rows[0]["position"] == "C" and rows[0]["class_year"] == "So.", "pos/class"
    print("  OK")

    print("=== HTML-table parser (Presto label-cell + combined hometown) ===")
    html2 = """<table><thead>
      <tr><th>No.</th><th>Name</th><th>Pos.</th><th>B/T</th><th>Ht.</th><th>Wt.</th>
          <th>Cl.</th><th>Hometown/High School</th></tr></thead><tbody>
      <tr><td><span class="label">No.:</span>1</td><td>Jake Smith</td>
          <td><span class="label">Pos.:</span>IF</td>
          <td><span class="label">B/T:</span>R/R</td>
          <td><span class="label">Ht.:</span>5-10</td>
          <td><span class="label">Wt.:</span>160</td>
          <td><span class="label">Cl.:</span>RFr.</td>
          <td><span class="label">Hometown/High School:</span>Winston-Salem, N.C. / Oak Grove HS</td></tr>
    </tbody></table>"""
    rows2 = parse_html_table(html2)
    print("  parsed:", json.dumps(rows2, indent=1))
    assert rows2 and rows2[0]["player"] == "Jake Smith"
    assert rows2[0]["height_in"] == 70 and rows2[0]["weight_lb"] == 160
    assert rows2[0]["bats"] == "R" and rows2[0]["throws"] == "R"
    assert rows2[0]["hometown"] == "Winston-Salem, N.C." and rows2[0]["high_school"] == "Oak Grove HS"
    print("  OK")

    print("=== HTML-table parser (LSU-style separate columns, no labels) ===")
    html3 = """<table><thead><tr><th>Number</th><th>Name</th><th>Position</th>
      <th>Height</th><th>Weight</th><th>Class</th><th>Experience</th><th>B/T</th>
      <th>Hometown</th><th>High School</th><th>Previous School</th></tr></thead><tbody>
      <tr><td>1</td><td>Chris Stanfield</td><td>Outfield</td><td>6-2</td><td>196</td>
          <td>Senior</td><td>1L</td><td>R-R</td><td>Tallahassee, Fla.</td>
          <td>Chiles HS</td><td>Auburn</td></tr></tbody></table>"""
    rows3 = parse_html_table(html3)
    print("  parsed:", json.dumps(rows3, indent=1))
    assert rows3 and rows3[0]["player"] == "Chris Stanfield"
    assert rows3[0]["height_in"] == 74 and rows3[0]["weight_lb"] == 196
    assert rows3[0]["hometown"] == "Tallahassee, Fla." and rows3[0]["high_school"] == "Chiles HS"
    print("  OK")

    print("=== Sidearm-card parser (classic static cards) ===")
    html4 = """<li class="sidearm-roster-player">
      <div class="sidearm-roster-player-name">1 Adam Salazar</div>
      <span class="sidearm-roster-player-position">IF</span>
      <span class="sidearm-roster-player-custom1">L/R</span>
      <span class="sidearm-roster-player-height">5'8&quot;</span>
      <span class="sidearm-roster-player-weight">170 lbs</span>
      <span class="sidearm-roster-player-academic-year">So.</span>
      <span class="sidearm-roster-player-hometown">Bakersfield, Calif.</span>
      <span class="sidearm-roster-player-previous-school">Ridgeview HS</span>
    </li>"""
    rows4 = parse_sidearm_cards_html(html4)
    print("  parsed:", json.dumps(rows4, indent=1))
    assert rows4 and rows4[0]["player"] == "Adam Salazar"
    assert rows4[0]["height_in"] == 68 and rows4[0]["weight_lb"] == 170
    assert rows4[0]["bats"] == "L" and rows4[0]["throws"] == "R"
    assert rows4[0]["hometown"] == "Bakersfield, Calif." and rows4[0]["high_school"] == "Ridgeview HS"
    print("  OK")
    print("\nall offline checks passed.")


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Recover zero-row 2026 team rosters (Presto/WMT).")
    ap.add_argument("--offline", action="store_true", help="parser self-checks, no network")
    ap.add_argument("--limit", type=int, default=None, help="cap teams (debug)")
    args = ap.parse_args()
    if args.offline:
        offline_checks()
        return
    run(limit=args.limit)


if __name__ == "__main__":
    main()
