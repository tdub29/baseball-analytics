"""Shared helpers: name normalization + value coercion.

Used by the importer, entity resolution, and enrichment so every stage keys
players the same way.
"""
from __future__ import annotations

import re
import unicodedata
from typing import Any

# Nicknames seen in college baseball rosters; extend as needed.
_NICKNAMES = {
    "alex": "alexander", "aj": "aj", "cj": "cj", "jj": "jj", "tj": "tj",
    "jake": "jacob", "mike": "michael", "matt": "matthew", "nick": "nicholas",
    "will": "william", "alec": "alexander", "zach": "zachary", "josh": "joshua",
    "ben": "benjamin", "sam": "samuel", "joe": "joseph", "dan": "daniel",
    "tony": "anthony", "chris": "christopher", "rob": "robert", "bobby": "robert",
}

_SUFFIXES = {"jr", "sr", "ii", "iii", "iv", "v"}


def strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c)
    )


def clean_str(v: Any) -> str | None:
    """Trim a cell to a clean string, or None for blanks/NaN/'-'."""
    if v is None:
        return None
    s = str(v).strip()
    if s == "" or s.lower() in {"nan", "none", "-", "n/a", "na"}:
        return None
    return s


def schools_match(a: Any, b: Any, threshold: int = 80) -> bool:
    """True if two school strings refer to the same school (fuzzy, token-set).

    Tolerant of naming variants ('Bradley' vs 'Bradley University') but separates
    genuinely different schools ('UC Riverside' vs 'UNC Wilmington'). Used to decide
    whether two same-name records are one person or two. Blanks never match (unknown).
    """
    from rapidfuzz import fuzz
    na, nb = normalize_name(a), normalize_name(b)
    if not na or not nb:
        return False
    return fuzz.token_set_ratio(na, nb) >= threshold


def normalize_name(name: str | None) -> str:
    """Lowercase, de-accent, drop punctuation/suffixes — for fuzzy matching."""
    s = clean_str(name)
    if not s:
        return ""
    s = strip_accents(s).lower()
    s = re.sub(r"[^a-z\s]", " ", s)        # drop punctuation/digits
    parts = [p for p in s.split() if p and p not in _SUFFIXES]
    parts = [_NICKNAMES.get(p, p) for p in parts]
    # merge runs of single-letter tokens so "a j" (A.J.) == "aj"
    merged: list[str] = []
    buf = ""
    for p in parts:
        if len(p) == 1:
            buf += p
        else:
            if buf:
                merged.append(buf); buf = ""
            merged.append(p)
    if buf:
        merged.append(buf)
    return " ".join(merged)


def name_key(first: Any = None, last: Any = None, full: Any = None) -> str:
    """Stable key for cross-sheet player merge.

    Builds from full name if given, else first+last. Sorted tokens so
    'First Last' and 'Last, First' collapse to the same key.
    """
    if full:
        norm = normalize_name(full)
    else:
        norm = normalize_name(f"{clean_str(first) or ''} {clean_str(last) or ''}")
    return " ".join(sorted(norm.split()))


def to_float(v: Any) -> float | None:
    s = clean_str(v)
    if s is None:
        return None
    s = s.replace("%", "").replace(",", "")
    try:
        return float(s)
    except ValueError:
        return None


def to_int(v: Any) -> int | None:
    f = to_float(v)
    return int(round(f)) if f is not None else None


# Class-year text -> eligibility years remaining (rough; refine per case).
_CLASS_ELIG = {
    "freshman": 3, "fr": 3, "redshirt freshman": 4,
    "sophomore": 2, "so": 2,
    "junior": 1, "jr": 1,
    "senior": 1, "sr": 1,          # often a COVID/grad year remains
    "graduate": 1, "grad": 1, "gr": 1, "5th year": 1,
}


def eligibility_from_class(year: Any) -> int | None:
    s = clean_str(year)
    if not s:
        return None
    return _CLASS_ELIG.get(s.lower())


# ── Hometown parsing ─────────────────────────────────────────────────────────
# Map full state names + AP-style abbreviations (NCAA rosters use "Calif.",
# "Ariz.", etc.) + USPS codes -> USPS 2-letter. Lowercased, periods stripped.
_USPS = {
    "alabama": "AL", "ala": "AL", "al": "AL",
    "alaska": "AK", "ak": "AK",
    "arizona": "AZ", "ariz": "AZ", "az": "AZ",
    "arkansas": "AR", "ark": "AR", "ar": "AR",
    "california": "CA", "calif": "CA", "cal": "CA", "ca": "CA",
    "colorado": "CO", "colo": "CO", "co": "CO",
    "connecticut": "CT", "conn": "CT", "ct": "CT",
    "delaware": "DE", "del": "DE", "de": "DE",
    "district of columbia": "DC", "washington dc": "DC", "dc": "DC",
    "florida": "FL", "fla": "FL", "fl": "FL",
    "georgia": "GA", "ga": "GA",
    "hawaii": "HI", "hawai i": "HI", "hi": "HI",
    "idaho": "ID", "id": "ID",
    "illinois": "IL", "ill": "IL", "il": "IL",
    "indiana": "IN", "ind": "IN", "in": "IN",
    "iowa": "IA", "ia": "IA",
    "kansas": "KS", "kan": "KS", "kans": "KS", "ks": "KS",
    "kentucky": "KY", "ky": "KY",
    "louisiana": "LA", "la": "LA",
    "maine": "ME", "me": "ME",
    "maryland": "MD", "md": "MD",
    "massachusetts": "MA", "mass": "MA", "ma": "MA",
    "michigan": "MI", "mich": "MI", "mi": "MI",
    "minnesota": "MN", "minn": "MN", "mn": "MN",
    "mississippi": "MS", "miss": "MS", "ms": "MS",
    "missouri": "MO", "mo": "MO",
    "montana": "MT", "mont": "MT", "mt": "MT",
    "nebraska": "NE", "neb": "NE", "nebr": "NE", "ne": "NE",
    "nevada": "NV", "nev": "NV", "nv": "NV",
    "new hampshire": "NH", "nh": "NH",
    "new jersey": "NJ", "nj": "NJ",
    "new mexico": "NM", "nm": "NM",
    "new york": "NY", "ny": "NY",
    "north carolina": "NC", "nc": "NC",
    "north dakota": "ND", "nd": "ND",
    "ohio": "OH", "oh": "OH",
    "oklahoma": "OK", "okla": "OK", "ok": "OK",
    "oregon": "OR", "ore": "OR", "or": "OR",
    "pennsylvania": "PA", "pa": "PA",
    "rhode island": "RI", "ri": "RI",
    "south carolina": "SC", "sc": "SC",
    "south dakota": "SD", "sd": "SD",
    "tennessee": "TN", "tenn": "TN", "tn": "TN",
    "texas": "TX", "tex": "TX", "tx": "TX",
    "utah": "UT", "ut": "UT",
    "vermont": "VT", "vt": "VT",
    "virginia": "VA", "va": "VA",
    "washington": "WA", "wash": "WA", "wa": "WA",
    "west virginia": "WV", "w va": "WV", "wva": "WV", "wv": "WV",
    "wisconsin": "WI", "wis": "WI", "wisc": "WI", "wi": "WI",
    "wyoming": "WY", "wyo": "WY", "wy": "WY",
    "puerto rico": "PR", "pr": "PR",
}


def to_usps(token: Any) -> str | None:
    """Normalize a state token ('Calif.', 'CA', 'California') -> USPS 'CA'.

    Returns None for non-US / unrecognized tokens (e.g. a country or province),
    so the caller can keep the raw string instead.
    """
    s = clean_str(token)
    if not s:
        return None
    key = re.sub(r"[.\-]", " ", s).lower()
    key = re.sub(r"\s+", " ", key).strip()
    # try the spaced form ("new york") then de-spaced ("n c" -> "nc" for N.C.)
    return _USPS.get(key) or _USPS.get(key.replace(" ", ""))


def parse_height_to_inches(raw: Any) -> int | None:
    """Roster height ('6-2', '6\\'2\"', '6’2') -> inches. Shared by the NCAA and
    Sidearm bio parsers so a height string is read the same way everywhere."""
    s = clean_str(raw)
    if not s:
        return None
    s = s.replace('"', "").replace("'", "-").replace("’", "-")
    m = re.match(r"^\s*(\d)\s*[-\s]\s*(\d{1,2})\s*$", s)
    if not m:
        m2 = re.match(r"^\s*(\d)\s*$", s)
        return int(m2.group(1)) * 12 if m2 else None
    return int(m.group(1)) * 12 + int(m.group(2))


def parse_hometown(raw: Any) -> tuple[str | None, str | None]:
    """Split a roster hometown cell -> (city, state_usps_or_raw).

    Handles 'San Diego, Calif.', 'Phoenix, Ariz.', 'Chicago, IL', and falls back
    to the raw trailing token for international hometowns ('Toronto, Ontario').
    """
    s = clean_str(raw)
    if not s:
        return (None, None)
    parts = [p.strip() for p in s.split(",") if p.strip()]
    if not parts:
        return (None, None)
    city = parts[0]
    state: str | None = None
    for p in parts[1:]:
        usps = to_usps(p)
        if usps:
            state = usps
            break
    if state is None and len(parts) >= 2:
        state = parts[1]  # keep raw (province / country) when not a US state
    return (city, state)
