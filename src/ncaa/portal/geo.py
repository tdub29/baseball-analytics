"""Geographic intelligence layer: tie every player to a hometown and flag any
California / San Diego connection — the USD recruiting edge.

Two steps:
  1. score_geo_ties(con): roll a canonical hometown up onto `players` from the
     per-season `player_bio` rows (NCAA roster > Sidearm > Perfect Game/PBR), then
     set players.ca_tie / sd_tie / ca_tie_reasons from FOUR independent signals:
        - hometown state == CA            (the real prize; needs roster hometown)
        - hometown city in San Diego County
        - prior school (`from_school`) is a CA / San Diego program
        - summer team in a CA collegiate league (CCL, etc.)
  2. export_california_board(con): write data/california_board.csv — every
     CA-tie player, San Diego ties first, joined to fit_score when evaluated.

The from_school / summer signals work TODAY with zero scraping (that's the
ca_ties_baseline.csv proxy); hometown/HS signals light up once the extended
NCAA bio scrape (scripts/fetch_ncaa_bio.py) + `enrich-bio` have loaded
player_bio. Pure SQLite/Python — no network.
"""
from __future__ import annotations

import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Lower number = more trusted source for the canonical hometown rollup.
SOURCE_PRIORITY = {
    "ncaa": 0, "sidearm": 1, "perfectgame": 2, "pbr": 3,
    "d1baseball": 4, "manual": 5, "643": 6,
}

# San Diego County cities + the San Diego neighborhoods that show up as
# roster "hometowns". Lowercased; matched as a whole-string or substring of HS.
SD_COUNTY = {
    "san diego", "chula vista", "oceanside", "escondido", "carlsbad", "el cajon",
    "vista", "san marcos", "encinitas", "national city", "la mesa", "santee",
    "poway", "coronado", "imperial beach", "lemon grove", "del mar",
    "solana beach", "bonita", "la jolla", "rancho santa fe", "spring valley",
    "lakeside", "ramona", "fallbrook", "bonsall", "valley center", "alpine",
    "jamul", "julian", "san ysidro", "mira mesa", "rancho bernardo",
    "rancho penasquitos", "scripps ranch", "tierrasanta", "otay mesa",
    "point loma", "ocean beach", "pacific beach", "clairemont", "kearny mesa",
    "mission valley", "carmel valley", "sorrento valley", "eastlake",
    "rancho san diego", "casa de oro", "fletcher hills", "4s ranch",
    "sabre springs", "winter gardens",
}

# Southern California city set (lowercased): the major cities of the eight SoCal
# counties — San Diego, Orange, Los Angeles, Riverside, San Bernardino, Ventura,
# Santa Barbara, Imperial. SD County is a strict subset, so socal_tie nests
# ca_tie ⊇ socal_tie ⊇ sd_tie. CA-only: caller must gate on hometown_state == CA.
SOCAL_CITIES = SD_COUNTY | {
    # Los Angeles County
    "los angeles", "long beach", "pasadena", "glendale", "santa clarita",
    "torrance", "burbank", "downey", "norwalk", "lakewood", "cerritos",
    "west covina", "pomona", "el monte", "inglewood", "carson", "compton",
    "santa monica", "whittier", "lancaster", "palmdale", "pomona valley",
    "alhambra", "lakewood", "hawthorne", "montebello", "monterey park",
    "gardena", "south gate", "bellflower", "baldwin park", "lynwood",
    "redondo beach", "covina", "azusa", "arcadia", "diamond bar", "glendora",
    "culver city", "manhattan beach", "el segundo", "san dimas", "claremont",
    "walnut", "la verne", "rosemead", "temple city", "duarte", "monrovia",
    "san gabriel", "la mirada", "la puente", "paramount", "huntington park",
    "rancho palos verdes", "calabasas", "agoura hills",
    # Orange County
    "anaheim", "santa ana", "irvine", "huntington beach", "newport beach",
    "fullerton", "costa mesa", "mission viejo", "orange", "tustin",
    "yorba linda", "garden grove", "lake forest", "fountain valley",
    "westminster", "buena park", "aliso viejo", "laguna niguel",
    "laguna beach", "laguna hills", "rancho santa margarita", "san clemente",
    "san juan capistrano", "dana point", "placentia", "brea", "cypress",
    "stanton", "los alamitos", "seal beach", "la habra", "la palma",
    "villa park",
    # Riverside County
    "riverside", "corona", "temecula", "murrieta", "moreno valley",
    "hemet", "menifee", "lake elsinore", "perris", "wildomar", "norco",
    "eastvale", "jurupa valley", "san jacinto", "beaumont", "banning",
    "indio", "coachella", "palm springs", "palm desert", "cathedral city",
    "la quinta", "rancho mirage", "desert hot springs", "canyon lake",
    # San Bernardino County
    "san bernardino", "ontario", "rancho cucamonga", "fontana", "redlands",
    "chino", "chino hills", "upland", "rialto", "colton", "highland",
    "victorville", "hesperia", "apple valley", "yucaipa", "montclair",
    "loma linda", "grand terrace", "adelanto", "barstow", "big bear lake",
    # Ventura County
    "ventura", "oxnard", "thousand oaks", "simi valley", "camarillo",
    "moorpark", "fillmore", "santa paula", "port hueneme", "ojai",
    # Santa Barbara County
    "santa barbara", "santa maria", "goleta", "lompoc", "carpinteria",
    "guadalupe", "buellton", "solvang",
    # Imperial County
    "el centro", "calexico", "brawley", "imperial", "holtville", "calipatria",
}


# CA college-program name fragments (matched against players.from_school).
# 'california' alone is excluded for PennWest California / IUP via the guard.
CA_SCHOOL_FRAGMENTS = [
    "san diego", "long beach", "pepperdine", "stanford", "loyola marymount",
    "santa clara", "saint mary's college of california", "san jose state",
    "university of the pacific", "point loma", "concordia university irvine",
    "biola", "azusa pacific", "chapman", "university of san francisco",
    "san francisco state", "westmont", "vanguard", "menlo", "sonoma state",
    "humboldt", "cal poly", "fresno", "bakersfield", "sacramento state",
    "ucla", "usc", "uc san diego", "uc irvine", "uc riverside", "uc davis",
    "uc santa barbara", "uc berkeley", "university of california", "redlands",
    "occidental", "pomona", "whittier", "la verne", "claremont", "master",
    "dominican university of california", "notre dame de namur",
]
SD_SCHOOL_FRAGMENTS = [
    "san diego", "point loma", "cal state san marcos", "san marcos",
    "university of california, san diego",
]


def is_ca_school(school: str | None) -> bool:
    if not school:
        return False
    s = school.lower()
    if "pennsylvania" in s:               # PennWest California, IUP — not CA
        return False
    return "california" in s or any(f in s for f in CA_SCHOOL_FRAGMENTS)


def is_sd_school(school: str | None) -> bool:
    if not school:
        return False
    s = school.lower()
    return any(f in s for f in SD_SCHOOL_FRAGMENTS)


def is_ca_summer(team: str | None) -> bool:
    if not team:
        return False
    t = team.lower()
    return t.startswith("ccl") or "california collegiate" in t or "slo blues" in t


def _in_sd_county(text: str | None) -> bool:
    """True if text names a San Diego County place.

    Match exact city strings plus multi-word place phrases. Do not let single
    generic city names like "Vista" match unrelated schools such as Mountain
    Vista High School in Colorado.
    """
    if not text:
        return False
    t = re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()
    if t in SD_COUNTY:
        return True
    padded = f" {t} "
    return any(" " in city and f" {city} " in padded for city in SD_COUNTY)


def _in_socal(text: str | None) -> bool:
    """True if a hometown city (or HS string) names a Southern California place.
    SOCAL_CITIES is a superset of SD_COUNTY, so any SD city is also SoCal."""
    if not text:
        return False
    t = re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()
    if t in SOCAL_CITIES:
        return True
    padded = f" {t} "
    return any(" " in city and f" {city} " in padded for city in SOCAL_CITIES)


# Canadian provinces (full + 2-letter). A roster hometown like "Toronto, Ontario"
# reads as a non-US state; but "Ontario, CA" for a Toronto kid (e.g. HS St. Joan of
# Arc) is a MISCODING — "Ontario" is also a real San Bernardino city — so a Canadian
# must never count as a California tie. No US state collides with these tokens.
CANADA_PROVINCES = {
    "ontario", "quebec", "british columbia", "alberta", "manitoba", "saskatchewan",
    "nova scotia", "new brunswick", "newfoundland", "newfoundland and labrador",
    "prince edward island", "yukon", "nunavut", "northwest territories",
    "on", "qc", "bc", "ab", "mb", "sk", "ns", "nb", "nl", "pe", "pei", "yt", "nt", "nu",
}


def is_canada_state(state: str | None) -> bool:
    """True if a hometown 'state' token names a Canadian province (full or abbrev)."""
    if not state:
        return False
    s = re.sub(r"[^a-z ]+", " ", str(state).lower())
    return re.sub(r"\s+", " ", s).strip() in CANADA_PROVINCES


# ── canonical bio rollup (hometown + class year + height/weight) ─────────────
def _normalize_class_year(raw) -> str | None:
    """Messy roster/portal class labels -> canonical FR/SO/JR/SR/GR (None if unknown).
    Strips redshirt markers (R-/RS); grad/5th-year -> GR. Handles 'Sr.', 'R-Jr.',
    'RS SO', 'Sophomore', 'Senior?', 'Grad Transfer', '5th', etc."""
    if raw is None:
        return None
    s = str(raw).strip().lower().replace(".", "").replace("-", " ")
    if not s or s in ("---", "--", "n/a"):
        return None
    for pre in ("rs ", "r ", "redshirt ", "rshirt "):   # strip redshirt prefix
        if s.startswith(pre):
            s = s[len(pre):].strip()
    if "grad" in s or "5th" in s or s in ("gr", "g", "graduate"):
        return "GR"
    if s.startswith("fr") or "fresh" in s:
        return "FR"
    if s.startswith("so") or "soph" in s:
        return "SO"
    if s.startswith("jr") or "jun" in s:
        return "JR"
    if s.startswith("sr") or "sen" in s:
        return "SR"
    return None


_BIO_ROLLUP_FIELDS = ("hometown_city", "hometown_state", "high_school",
                      "class_year", "height_in", "weight_lb",
                      "position", "bats", "throws")


def _fill(existing, cand):
    """Fill-where-missing: keep the existing (portal-import) value when present,
    otherwise fall back to the bio-derived candidate. Used for position/bats/throws,
    where the portal-import value on players is authoritative."""
    return existing if (existing is not None and str(existing).strip()) else cand


# Canonical position normalizer. Roster scrapes pollute position with appended bio
# ("RHP 6'2\" 190 lbs R/R"), verbose forms ("Outfielder", "Right Handed Pitcher"),
# and junk ("u"). Map everything to a clean abbreviation (compounds kept as A/B).
_POS_WORD = {
    "righthandedpitcher": "RHP", "righthandpitcher": "RHP", "rhpitcher": "RHP",
    "lefthandedpitcher": "LHP", "lefthandpitcher": "LHP", "lhpitcher": "LHP",
    "pitcher": "P", "reliefpitcher": "RP", "startingpitcher": "SP",
    "outfielder": "OF", "outfield": "OF", "rightfielder": "RF", "rightfield": "RF",
    "centerfielder": "CF", "centerfield": "CF", "leftfielder": "LF", "leftfield": "LF",
    "infielder": "INF", "infield": "INF", "middleinfielder": "INF", "cornerinfielder": "INF",
    "catcher": "C", "shortstop": "SS", "firstbaseman": "1B", "firstbase": "1B",
    "secondbaseman": "2B", "secondbase": "2B", "thirdbaseman": "3B", "thirdbase": "3B",
    "designatedhitter": "DH", "utility": "UTL", "utilityplayer": "UTL", "utilityman": "UTL",
    "twowayplayer": "TWP", "twoway": "TWP",
}
_POS_ABBR = {
    "P": "P", "RHP": "RHP", "LHP": "LHP", "RP": "RP", "SP": "SP", "TWP": "TWP",
    "C": "C", "1B": "1B", "2B": "2B", "3B": "3B", "SS": "SS", "INF": "INF", "IF": "INF",
    "OF": "OF", "LF": "LF", "CF": "CF", "RF": "RF", "DH": "DH",
    "UTL": "UTL", "UT": "UTL", "UTIL": "UTL",
}


def _norm_pos_token(tok: str) -> str | None:
    t = tok.strip()
    if not t:
        return None
    if t.upper() in _POS_ABBR:
        return _POS_ABBR[t.upper()]
    key = re.sub(r"[^a-z]", "", t.lower())
    return _POS_WORD.get(key)


def normalize_position(raw) -> str | None:
    """'RHP 6'2\" 190 lbs' -> 'RHP', 'Outfielder' -> 'OF', '1B/DH' -> '1B/DH', 'u' -> None."""
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    # strip appended bio: cut before a height (6'2"), a weight (lbs), or any 2-3 digit number
    s = re.split(r"\d\s*['’′]", s)[0]
    s = re.split(r"\blbs?\b", s, flags=re.I)[0]
    s = re.split(r"\b\d{2,3}\b", s)[0]
    parts = re.split(r"[/\-,&]| and ", s)
    out: list[str] = []
    for p in parts:
        n = _norm_pos_token(p)
        if n and n not in out:
            out.append(n)
    return "/".join(out) if out else None


def _canonical_bio(con: sqlite3.Connection) -> dict[int, dict]:
    """player_id -> best non-null value for EACH canonical field, chosen per field
    by source trust (NCAA > Sidearm > ...) then most-recent season. Per-field (not
    one winning row) so a weight that only exists on a Sidearm row still wins even
    when NCAA carries hometown/class/height (NCAA rosters have no weight)."""
    rows = con.execute(
        """SELECT player_id, season, source, hometown_city, hometown_state,
                  high_school, class_year, height_in, weight_lb,
                  position, bats, throws
           FROM player_bio"""
    ).fetchall()
    best: dict[int, dict] = {}   # pid -> {field: (priority, season, value)}
    grad: set[int] = set()       # grad is "sticky up": any source saying Gr/grad/5th wins
    canada: dict[int, tuple] = {}  # pid -> (city, state) from a Canadian-province bio row
    for r in rows:
        pid = r["player_id"]
        pri = SOURCE_PRIORITY.get((r["source"] or "").lower(), 9)
        season = str(r["season"] or "")
        if _normalize_class_year(r["class_year"]) == "GR":
            grad.add(pid)
        if is_canada_state(r["hometown_state"]):
            cur = canada.get(pid)
            # prefer a row that carries a city (e.g. "Toronto, Ontario")
            if cur is None or (not cur[0] and r["hometown_city"]):
                canada[pid] = (r["hometown_city"], r["hometown_state"])
        d = best.setdefault(pid, {})
        for f in _BIO_ROLLUP_FIELDS:
            v = r[f]
            if v is None or (isinstance(v, str) and (not v.strip() or v.strip() == "---")):
                continue
            cur = d.get(f)
            # prefer lower priority number, then later season string
            if cur is None or pri < cur[0] or (pri == cur[0] and season > cur[1]):
                d[f] = (pri, season, v)
    out = {pid: {f: t[2] for f, t in d.items()} for pid, d in best.items()}
    for pid in grad:
        out.setdefault(pid, {})["is_grad"] = True
    for pid, cs in canada.items():
        out.setdefault(pid, {})["_canada"] = cs
    return out


def score_geo_ties(con: sqlite3.Connection) -> dict:
    """Roll up canonical bio (hometown + class year + height/weight) and set
    ca_tie / socal_tie / sd_tie / ca_tie_reasons on every player. Idempotent;
    safe to re-run after each bio enrichment."""
    canon = _canonical_bio(con)
    players = con.execute(
        "SELECT player_id, from_school, summer_team, class_year, "
        "position, bats, throws FROM players"
    ).fetchall()

    n_ca = n_socal = n_sd = n_home = n_class = n_wt = 0
    # position/bats/throws counts = players that ended with a non-empty value
    # (fill-where-missing: portal value kept if present, else filled from bio).
    n_pos = n_bats = n_throws = 0
    for p in players:
        pid = p["player_id"]
        h = canon.get(pid, {})
        city = h.get("hometown_city")
        state = h.get("hometown_state")
        hs = h.get("high_school")
        # Canada guard: a Canadian-province bio row (e.g. "Toronto, Ontario") means a
        # sibling "Ontario, CA" / "London, CA" reading is a miscoding. Show the real
        # Canadian hometown and never let it score a California tie from hometown.
        canada = h.get("_canada")
        if canada:
            city = canada[0] or city
            state = canada[1] or state
        if city or state or hs:
            n_home += 1

        reasons: list[str] = []
        sd = False
        socal = False

        if state == "CA" and not canada:
            reasons.append("hometown=CA")
        if _in_sd_county(city) and not canada:
            reasons.append(f"hometown={city} (SD County)")
            sd = True
        # SoCal hometown (CA-only): a SoCal city outside SD County (SD already
        # set sd above, and SD ⊆ SoCal, so sd ⟹ socal below regardless).
        elif state == "CA" and _in_socal(city) and not canada:
            reasons.append(f"hometown={city} (SoCal)")
            socal = True
        if is_ca_school(p["from_school"]):
            reasons.append("prev_school=CA")
        if is_sd_school(p["from_school"]):
            sd = True
        if is_ca_summer(p["summer_team"]):
            reasons.append("summer=CA league")
        if hs and _in_sd_county(hs):
            reasons.append("HS in SD County")
            sd = True
        elif hs and (", ca" in hs.lower() or "(ca" in hs.lower()) and _in_socal(hs):
            reasons.append("HS in SoCal")
            socal = True
        if hs and (", ca" in hs.lower() or "(ca" in hs.lower()):
            reasons.append("HS in CA")

        ca = bool(reasons) or sd or socal
        # Maintain the nesting invariant: sd ⟹ socal ⟹ ca.
        if sd:
            socal = True
        if socal:
            ca = True
        if ca:
            n_ca += 1
        if socal:
            n_socal += 1
        if sd:
            n_sd += 1

        # Class year comes from the d1baseball PORTAL entry (set on players at ingest) —
        # that's the source of truth for a player's current class. Prefer the portal value;
        # only fall back to roster bio when the player carries no class at all. Grad sticks
        # from a portal "Grad Transfer"/GR label; a bio-only grad signal fills only when blank.
        existing_cls = p["class_year"]
        ex = str(existing_cls or "").strip().lower()
        if ex and ("grad" in ex or "5th" in ex or ex == "gr"):
            cls = "GR"
        elif _normalize_class_year(existing_cls):
            cls = _normalize_class_year(existing_cls)        # portal class wins
        elif h.get("is_grad"):
            cls = "GR"
        else:
            cls = _normalize_class_year(h.get("class_year")) or existing_cls   # bio fills
        height = h.get("height_in")
        weight = h.get("weight_lb")
        if cls:
            n_class += 1
        if weight is not None:
            n_wt += 1

        # position/bats/throws: fill-where-missing — keep the authoritative
        # portal-import value when present, only fall back to bio when blank/NULL.
        pos = normalize_position(_fill(p["position"], h.get("position")))
        bats = _fill(p["bats"], h.get("bats"))
        throws = _fill(p["throws"], h.get("throws"))
        if pos is not None and str(pos).strip():
            n_pos += 1
        if bats is not None and str(bats).strip():
            n_bats += 1
        if throws is not None and str(throws).strip():
            n_throws += 1

        con.execute(
            """UPDATE players SET hometown_city=?, hometown_state=?, high_school=?,
                   class_year=?, height_in=?, weight_lb=?,
                   position=?, bats=?, throws=?,
                   ca_tie=?, socal_tie=?, sd_tie=?, ca_tie_reasons=? WHERE player_id=?""",
            (city, state, hs, cls, height, weight,
             pos, bats, throws,
             1 if ca else 0, 1 if socal else 0, 1 if sd else 0,
             ";".join(reasons) if reasons else None, pid),
        )
    con.commit()
    return {"players": len(players), "with_hometown": n_home,
            "ca_tie": n_ca, "socal_tie": n_socal, "sd_tie": n_sd,
            "class_year": n_class, "weight": n_wt,
            # counts = players ending with a non-empty value after fill-where-missing
            "position": n_pos, "bats": n_bats, "throws": n_throws}


# ── California board export ──────────────────────────────────────────────────
CA_BOARD_SQL = """
SELECT
    pl.sd_tie, pl.socal_tie, pl.ca_tie,
    e.fit_score AS fit,
    pl.full_name AS player, pl.position, pl.class_year, pl.division,
    pl.hometown_city, pl.hometown_state, pl.high_school,
    pl.from_school, pl.summer_team, pl.current_status AS status,
    pl.ca_tie_reasons
FROM players pl
LEFT JOIN evaluations e ON e.id = (
    SELECT id FROM evaluations x WHERE x.player_id = pl.player_id
    ORDER BY x.fit_score DESC LIMIT 1)
WHERE pl.ca_tie = 1 AND pl.current_status = 'ENTERED'
ORDER BY pl.sd_tie DESC, pl.socal_tie DESC, COALESCE(e.fit_score, -1) DESC, pl.full_name
"""


def export_california_board(con: sqlite3.Connection,
                            csv_path: str | Path | None = None) -> dict:
    import pandas as pd
    df = pd.read_sql_query(CA_BOARD_SQL, con)
    out = Path(csv_path) if csv_path else ROOT / "data" / "california_board.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    return {"rows": len(df),
            "sd_rows": int(df["sd_tie"].sum()) if len(df) else 0,
            "socal_rows": int(df["socal_tie"].sum()) if len(df) else 0,
            "csv": str(out)}
