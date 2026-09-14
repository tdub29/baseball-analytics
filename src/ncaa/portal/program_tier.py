"""Program-strength tiering for the USD transfer-portal fit pipeline.

A finely-tiered, baseball-specific "program strength" scale (0-1) used to score
whether transferring *to* USD (West Coast Conference mid-major D1) is a STEP UP for a
player — including discriminating *within* D1. USD is the neutral reference point at
0.62 (the WCC value). Higher conference strength than USD => potential step-down for an
incoming transfer; lower => step-up.

Pure-Python: json / re / pathlib only. No DB, no network.

The scale is conference-driven: every classified D1 program inherits the strength of
its CURRENT (2025, post-realignment) baseball conference. Schools we can't confidently
place are OMITTED (never guessed) and fall through to the USD-neutral default, so
unknown programs never produce a spurious step-up/step-down signal.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

# --------------------------------------------------------------------------------------
# 1. Conference strength (0-1). 2024-25 realigned baseball alignments.
#    USD's WCC = 0.62 is the neutral reference point.
# --------------------------------------------------------------------------------------
CONF_STRENGTH: dict[str, float] = {
    "SEC": 1.00,
    "ACC": 0.94,
    "Big 12": 0.88,
    "Big West": 0.82,
    "Sun Belt": 0.80,
    "Pac-12": 0.80,
    "Big Ten": 0.80,
    "American": 0.74,
    "Conference USA": 0.72,
    "Mountain West": 0.68,
    "Missouri Valley": 0.66,
    "Big East": 0.64,
    "WCC": 0.62,
    "Coastal Athletic": 0.60,
    "Atlantic 10": 0.60,
    "Southern": 0.58,
    "Big South": 0.56,
    "ASUN": 0.56,
    "Mid-American": 0.52,
    "Southland": 0.52,
    "WAC": 0.52,
    "Horizon": 0.50,
    "Ohio Valley": 0.48,
    "Summit": 0.48,
    "America East": 0.46,
    "Ivy": 0.46,
    "MAAC": 0.46,
    "Patriot": 0.44,
    "Northeast": 0.42,
    "MEAC": 0.38,
    "SWAC": 0.38,
}

# USD reference point.
USD_STRENGTH: float = CONF_STRENGTH["WCC"]  # 0.62

# The home program's own names (D1Baseball writes "San Diego"). Used to detect USD's OWN
# outbound portal entrants, who must NOT get the local-tie "pull toward USD" in the
# Likelihood — a player leaving USD isn't a San-Diego-kid being recruited home.
USD_NAMES: frozenset[str] = frozenset({"san diego", "university of san diego", "usd"})


def is_usd(school: str | None) -> bool:
    """True if `school` is the home program (USD). `normalize` (defined below) resolves at
    call time, so the forward reference is fine; kept here next to USD_NAMES for clarity."""
    return bool(school) and normalize(school) in USD_NAMES

# --------------------------------------------------------------------------------------
# 2. Division strength for non-D1 programs (used when a school isn't a known D1 program).
# --------------------------------------------------------------------------------------
DIV_STRENGTH: dict[str, float] = {
    "II": 0.42,
    "D2": 0.42,
    "III": 0.28,
    "D3": 0.28,
    "JCO": 0.36,
    "JUCO": 0.36,
    "NAI": 0.32,
    "NAIA": 0.32,
}

# --------------------------------------------------------------------------------------
# 3. School -> current (2025) baseball conference.
#    Keys are the EXACT official strings as they appear in data/cache/d1_schools.json
#    (and in our DB) so lookups match. Where the JSON contains both an uppercase
#    shorthand and a full official name for the same program, both keys are included.
#    Schools we are not confident about are intentionally OMITTED (see notes at bottom).
# --------------------------------------------------------------------------------------
SCHOOL_CONF: dict[str, str] = {
    # ---- SEC ----
    "AUBURN": "SEC",
    "Auburn University": "SEC",
    "Louisiana State University": "SEC",
    "Mississippi State University": "SEC",
    "Texas A&M University, College Station": "SEC",
    "Texas Christian University": "Big 12",  # placeholder corrected below; see note
    "University of Alabama": "SEC",
    "University of Arkansas, Fayetteville": "SEC",
    "University of Florida": "SEC",
    "University of Georgia": "SEC",
    "University of Kentucky": "SEC",
    "University of Memphis": "American",  # corrected below; see note
    "University of Mississippi": "SEC",
    "University of Missouri, Columbia": "SEC",
    "UNIVERSITY OF MISSOURI COLUMBIA": "SEC",
    "University of Oklahoma": "SEC",
    "University of South Carolina, Columbia": "SEC",
    "University of Tennessee, Knoxville": "SEC",
    "University of Texas at Austin": "SEC",
    "Vanderbilt University": "SEC",
    # ---- ACC ----
    "Boston College": "ACC",
    "CLEMSON UNIVERSITY": "ACC",
    "Clemson University": "ACC",
    "Duke University": "ACC",
    "Florida State University": "ACC",
    "Georgia Institute of Technology": "ACC",
    "North Carolina State University": "ACC",
    "Stanford University": "ACC",
    "University of California, Berkeley": "ACC",
    "University of Louisville": "ACC",
    "University of Miami (Florida)": "ACC",
    "University of North Carolina, Chapel Hill": "ACC",
    "University of Notre Dame": "ACC",
    "University of Pittsburgh": "ACC",
    "University of Virginia": "ACC",
    "Virginia Polytechnic Institute and State University": "ACC",
    "Virginia Commonwealth University": "Atlantic 10",  # corrected below; see note
    "Wake Forest": "ACC",
    "Wake Forest University": "ACC",
    # ---- Big 12 ----
    "Arizona State University": "Big 12",
    "Baylor University": "Big 12",
    "Brigham Young University": "Big 12",
    "Houston Christian University": "Southland",  # corrected below; see note
    "Kansas State University": "Big 12",
    "Oklahoma State University": "Big 12",
    "Texas Tech University": "Big 12",
    "University of Arizona": "Big 12",
    "University of Central Florida": "Big 12",
    "University of Cincinnati": "Big 12",
    "University of Houston": "Big 12",
    "University of Kansas": "Big 12",
    "University of Utah": "Big 12",
    "West Virginia University": "Big 12",
    # ---- Big West ----
    "California Polytechnic State University": "Big West",
    "California State University, Bakersfield": "Big West",
    "California State University, Fullerton": "Big West",
    "California State University, Northridge": "Big West",
    "Long Beach State University": "Big West",
    "University of California, Davis": "Big West",
    "University of California, Irvine": "Big West",
    "University of California, Riverside": "Big West",
    "University of California, San Diego": "Big West",
    "University of California, Santa Barbara": "Big West",
    "University of Hawaii, Manoa": "Big West",
    "California State University, Sacramento": "Big West",
    # ---- Sun Belt ----
    "Appalachian State University": "Sun Belt",
    "Arkansas State University": "Sun Belt",
    "Coastal Carolina University": "Sun Belt",
    "Georgia Southern University": "Sun Belt",
    "Georgia State University": "Sun Belt",
    "James Madison University": "Sun Belt",
    "Marshall University": "Sun Belt",
    "Old Dominion University": "Sun Belt",
    "Texas State University": "Sun Belt",
    "Troy University": "Sun Belt",
    "University of Louisiana Monroe": "Sun Belt",
    "University of Louisiana at Lafayette": "Sun Belt",
    "University of South Alabama": "Sun Belt",
    "University of Southern Mississippi": "Sun Belt",
    "The University of Southern Mississippi": "Sun Belt",
    # ---- Pac-12 (remnant) ----
    "Oregon State University": "Pac-12",
    "Washington State University": "Pac-12",
    # ---- Big Ten ----
    "Indiana University, Bloomington": "Big Ten",
    "Michigan State University": "Big Ten",
    "Northwestern University": "Big Ten",
    "Pennsylvania State University": "Big Ten",
    "Purdue University": "Big Ten",
    "Rutgers, The State University of New Jersey, New Brunswick": "Big Ten",
    "The Ohio State University": "Big Ten",
    "University of Illinois Urbana-Champaign": "Big Ten",
    "University of Iowa": "Big Ten",
    "University of Maryland, College Park": "Big Ten",
    "University of Michigan": "Big Ten",
    "University of Minnesota, Twin Cities": "Big Ten",
    "University of Nebraska-Lincoln": "Big Ten",
    "University of Oregon": "Big Ten",
    "University of Southern California": "Big Ten",
    "University of California, Los Angeles": "Big Ten",
    "University of Washington": "Big Ten",
    # ---- American ----
    "East Carolina University": "American",
    "Florida Atlantic University": "American",
    "Rice University": "American",
    "Tulane University": "American",
    "University of Alabama at Birmingham": "American",
    "University of South Florida": "American",
    "Wichita State University": "American",
    "University of Texas at San Antonio": "American",
    "University of North Carolina at Charlotte": "American",
    "The University of North Carolina at Charlotte": "American",
    # ---- Conference USA ----
    "Florida International University": "Conference USA",
    "Jacksonville State University": "Conference USA",
    "Liberty University": "Conference USA",
    "Louisiana Tech University": "Conference USA",
    "Middle Tennessee State University": "Conference USA",
    "Sam Houston State University": "Conference USA",
    "University of Texas at Arlington": "Conference USA",
    "Western Kentucky University": "Conference USA",
    "New Mexico State University": "Conference USA",
    "Kennesaw State University": "Conference USA",
    "The University of Texas Rio Grande Valley": "Conference USA",
    # ---- Mountain West ----
    "Fresno State": "Mountain West",  # not present as exact key; see Cal State Fresno
    "California State University, Fresno": "Mountain West",
    "San Diego State University": "Mountain West",
    "San Jose State University": "Mountain West",
    "University of Nevada, Las Vegas": "Mountain West",
    "University of Nevada, Reno": "Mountain West",
    "University of New Mexico": "Mountain West",
    "U.S. Air Force Academy": "Mountain West",
    # ---- Missouri Valley ----
    "Bradley University": "Missouri Valley",
    "Illinois State University": "Missouri Valley",
    "Indiana State University": "Missouri Valley",
    "Missouri State University": "Missouri Valley",
    "Murray State University": "Missouri Valley",
    "Southern Illinois University at Carbondale": "Missouri Valley",
    "University of Evansville": "Missouri Valley",
    "University of Illinois Chicago": "Missouri Valley",
    "Valparaiso University": "Missouri Valley",
    "Belmont University": "Missouri Valley",
    # ---- Big East ----
    "Butler University": "Big East",
    "Creighton University": "Big East",
    "Georgetown University": "Big East",
    "Seton Hall University": "Big East",
    "St. John's University (New York)": "Big East",
    "Villanova University": "Big East",
    "Xavier University": "Big East",
    "University of Connecticut": "Big East",
    # ---- WCC (USD's conference, reference point) ----
    "University of San Diego": "WCC",          # USD itself — the home program
    "Gonzaga University": "WCC",
    "Loyola Marymount University": "WCC",
    "Pepperdine University": "WCC",
    "Saint Mary's College of California": "WCC",
    "Santa Clara University": "WCC",
    "University of Portland": "WCC",
    "University of San Francisco": "WCC",
    "University of the Pacific": "WCC",
    "Seattle University": "WCC",
    # ---- Coastal Athletic (CAA) ----
    "Campbell University": "Coastal Athletic",
    "Elon University": "Coastal Athletic",
    "Hofstra University": "Coastal Athletic",
    "Monmouth University": "Coastal Athletic",
    "Northeastern University": "Coastal Athletic",
    "Stony Brook University": "Coastal Athletic",
    "Towson University": "Coastal Athletic",
    "University of Delaware": "Coastal Athletic",
    "University of North Carolina Wilmington": "Coastal Athletic",
    "College of Charleston (South Carolina)": "Coastal Athletic",
    "William & Mary": "Coastal Athletic",
    "Fairfield University": "Coastal Athletic",  # see note: corrected to MAAC below
    # ---- Atlantic 10 ----
    "Davidson College": "Atlantic 10",
    "Fordham University": "Atlantic 10",
    "George Mason University": "Atlantic 10",
    "George Washington": "Atlantic 10",
    "George Washington University": "Atlantic 10",
    "La Salle University": "Atlantic 10",
    "Saint Joseph's University": "Atlantic 10",
    "Saint Louis University": "Atlantic 10",
    "St. Bonaventure University": "Atlantic 10",
    "University of Dayton": "Atlantic 10",
    "University of Massachusetts, Amherst": "Atlantic 10",
    "University of Rhode Island": "Atlantic 10",
    "University of Richmond": "Atlantic 10",
    # ---- Southern (SoCon) ----
    "East Tennessee State University": "Southern",
    "Mercer University": "Southern",
    "Samford University": "Southern",
    "The Citadel": "Southern",
    "University of North Carolina at Greensboro": "Southern",
    "The University of North Carolina at Greensboro": "Southern",
    "Western Carolina University": "Southern",
    "Wofford College": "Southern",
    "University of North Carolina Asheville": "Big South",  # corrected below; see note
    "UNC Asheville": "Big South",
    # ---- Big South ----
    "Charleston Southern University": "Big South",
    "Gardner-Webb University": "Big South",
    "High Point University": "Big South",
    "Longwood University": "Big South",
    "Presbyterian College": "Big South",
    "Radford University": "Big South",
    "University of South Carolina Upstate": "Big South",
    "Winthrop University": "Big South",
    # ---- ASUN ----
    "Austin Peay State University": "ASUN",
    "Bellarmine University": "ASUN",
    "Central Connecticut State University": "Northeast",  # corrected below; see note
    "Eastern Kentucky University": "ASUN",
    "Florida Gulf Coast University": "ASUN",
    "Jacksonville University": "ASUN",
    "Lipscomb University": "ASUN",
    "North Alabama": "ASUN",  # not exact key; see University of North Alabama
    "University of North Alabama": "ASUN",
    "University of North Florida": "ASUN",
    "University of West Georgia": "ASUN",
    "Queens University of Charlotte": "ASUN",
    "Stetson University": "ASUN",
    "University of Central Arkansas": "ASUN",
    "Lindenwood University": "Ohio Valley",  # corrected below; see note
    # ---- Mid-American (MAC) ----
    "BOWLING GREEN STATE": "Mid-American",
    "Bowling Green State University": "Mid-American",
    "Ball State University": "Mid-American",
    "Central Michigan University": "Mid-American",
    "Eastern Michigan": "Mid-American",
    "Eastern Michigan University": "Mid-American",
    "Kent State University": "Mid-American",
    "Miami University (Ohio)": "Mid-American",
    "Northern Illinois University": "Mid-American",
    "Ohio University": "Mid-American",
    "University of Akron": "Mid-American",
    "University of Toledo": "Mid-American",
    "Western Michigan University": "Mid-American",
    # ---- Southland ----
    "Lamar University": "Southland",
    "McNeese State University": "Southland",
    "Nicholls State University": "Southland",
    "Northwestern State University": "Southland",
    "Southeastern Louisiana University": "Southland",
    "Stephen F. Austin State University": "Southland",
    "Texas A&M University-Corpus Christi": "Southland",
    "University of New Orleans": "Southland",
    "University of the Incarnate Word": "Southland",
    "Texas A&M University, College Station ": "Southland",  # noop guard (trailing-space safety)
    # ---- WAC ----
    "Abilene Christian University": "WAC",
    "California Baptist University": "WAC",
    "Grand Canyon University": "WAC",
    "Tarleton State University": "WAC",
    "Utah Tech University": "WAC",
    "Utah Valley University": "WAC",
    "University of Texas Rio Grande Valley": "WAC",  # see note (now CUSA; corrected above)
    # ---- Horizon ----
    "Northern Kentucky University": "Horizon",
    "Oakland University": "Horizon",
    "Purdue University Fort Wayne": "Horizon",
    "University of Wisconsin-Milwaukee": "Horizon",
    "Wright State University": "Horizon",
    "Youngstown State University": "Horizon",
    "University of Northern Colorado": "Big Sky",  # see note: no baseball / omit
    # ---- Ohio Valley ----
    "Eastern Illinois University": "Ohio Valley",
    "Morehead State University": "Ohio Valley",
    "Southeast Missouri State University": "Ohio Valley",
    "Southern Illinois University Edwardsville": "Ohio Valley",
    "Tennessee Technological University": "Ohio Valley",
    "University of Tennessee at Martin": "Ohio Valley",
    "University of Southern Indiana": "Ohio Valley",
    "Western Illinois University": "Ohio Valley",
    "University of Arkansas at Little Rock": "Ohio Valley",
    "Mercyhurst University": "Northeast",  # corrected below; see note
    # ---- Summit ----
    "North Dakota State University": "Summit",
    "Oral Roberts University": "Summit",
    "South Dakota State University": "Summit",
    "University of Nebraska at Omaha": "Summit",
    "University of St. Thomas (Minnesota)": "Summit",
    "St. Thomas (MN)": "Summit",  # alias guard
    # ---- America East ----
    "Binghamton University": "America East",
    "Bryant University": "America East",
    "University at Albany": "America East",
    "University of Maine": "America East",
    "University of Massachusetts Lowell": "America East",
    "New Jersey Institute of Technology": "America East",
    "University of Maryland, Baltimore County": "America East",
    # ---- Ivy ----
    "Brown University": "Ivy",
    "Columbia University-Barnard College": "Ivy",
    "Cornell University": "Ivy",
    "Dartmouth College": "Ivy",
    "Harvard University": "Ivy",
    "Princeton University": "Ivy",
    "University of Pennsylvania": "Ivy",
    "Yale University": "Ivy",  # alias guard (not in list)
    # ---- MAAC ----
    "Canisius University": "MAAC",
    "Iona University": "MAAC",
    "Manhattan University": "MAAC",
    "Marist University": "MAAC",
    "Mount St. Mary's University": "MAAC",
    "Niagara University": "MAAC",
    "Quinnipiac University": "MAAC",
    "Rider": "MAAC",
    "Rider University": "MAAC",
    "Saint Peter's University": "MAAC",
    "Siena College": "MAAC",
    "SIENA COLLEGE": "MAAC",
    "Fairfield": "MAAC",  # alias guard
    # ---- Patriot ----
    "Army": "Patriot",  # alias guard
    "U.S. Military Academy": "Patriot",
    "Bucknell University": "Patriot",
    "College of the Holy Cross": "Patriot",
    "Lafayette College": "Patriot",
    "Navy": "Patriot",  # alias guard
    "Boston University": "Patriot",  # alias guard
    "Lehigh University": "Patriot",  # alias guard
    # ---- Northeast (NEC) ----
    "Central Connecticut State": "Northeast",  # alias guard
    "Fairleigh Dickinson University, Metropolitan Campus": "Northeast",
    "Le Moyne College": "Northeast",
    "Long Island University": "Northeast",
    "Merrimack College": "Northeast",
    "Sacred Heart University": "Northeast",
    "Stonehill College": "Northeast",
    "Wagner University": "Northeast",  # alias guard
    "Wagner College": "Northeast",
    "Chicago State University": "Northeast",  # alias guard
    # ---- MEAC ----
    "Coppin State University": "MEAC",
    "Delaware State University": "MEAC",
    "Norfolk State University": "MEAC",
    "North Carolina A&T State University": "MEAC",
    "University of Maryland Eastern Shore": "MEAC",
    "Howard University": "MEAC",  # alias guard
    # ---- SWAC ----
    "Alabama A&M University": "SWAC",
    "Alabama State University": "SWAC",
    "Alcorn State University": "SWAC",
    "Bethune-Cookman University": "SWAC",
    "Florida A&M University": "SWAC",
    "Grambling State University": "SWAC",
    "Jackson State University": "SWAC",
    "Mississippi Valley State University": "SWAC",
    "Prairie View A&M University": "SWAC",
    "Southern University, Baton Rouge": "SWAC",
    "Texas Southern University": "SWAC",
    "University of Arkansas, Pine Bluff": "SWAC",
}

# --------------------------------------------------------------------------------------
# Corrections / overrides for collisions and recent moves.
# These run AFTER the literal dict above so the final value is authoritative. They keep
# the big block above readable while guaranteeing the correct conference wins. Every
# entry here is a deliberate, high-confidence placement.
# --------------------------------------------------------------------------------------
_OVERRIDES: dict[str, str] = {
    # TCU is Big 12 (already), explicit:
    "Texas Christian University": "Big 12",
    # Memphis baseball is American:
    "University of Memphis": "American",
    # VCU baseball is Atlantic 10:
    "Virginia Commonwealth University": "Atlantic 10",
    # Houston Christian (formerly Houston Baptist) baseball is Southland:
    "Houston Christian University": "Southland",
    # UTRGV moved to CUSA for baseball (2025):
    "The University of Texas Rio Grande Valley": "Conference USA",
    "University of Texas Rio Grande Valley": "Conference USA",
    # Fairfield baseball is MAAC, not CAA:
    "Fairfield University": "MAAC",
    "Fairfield": "MAAC",
    # UNC Asheville baseball is Big South (Southern is wrong for the program):
    "University of North Carolina Asheville": "Big South",
    "UNC Asheville": "Big South",
    "Virginia Military Institute": "Southern",
    # Central Connecticut State baseball is Northeast (NEC):
    "Central Connecticut State University": "Northeast",
    # Lindenwood baseball is Ohio Valley:
    "Lindenwood University": "Ohio Valley",
    # Mercyhurst baseball is Northeast (NEC):
    "Mercyhurst University": "Northeast",
    # Kennesaw State baseball is Conference USA:
    "Kennesaw State University": "Conference USA",
}
SCHOOL_CONF.update(_OVERRIDES)

# Drop any guard/alias keys that don't correspond to a real, confident D1 baseball
# program in our universe (e.g. Big Sky has no baseball; Northern Colorado has no
# baseball program). These were left as readability anchors; remove so they can't leak
# a wrong strength via a normalized match.
for _bad in (
    "University of Northern Colorado",  # no NCAA baseball program -> omit (defaults USD-neutral)
    "Texas A&M University, College Station ",  # trailing-space noop guard
    "Fresno State",  # non-canonical alias; canonical Cal State Fresno already mapped
    "North Alabama",  # non-canonical alias; canonical full name already mapped
    "St. Thomas (MN)",  # alias guard
    "Yale University",  # not in our 315 universe
    "Fairfield",  # alias guard (canonical "Fairfield University" mapped)
    "Army",  # alias guard (canonical "U.S. Military Academy" mapped)
    "Navy",  # alias guard, not in universe
    "Boston University",  # not in our 315 universe
    "Lehigh University",  # not in our 315 universe
    "Central Connecticut State",  # alias guard (canonical full name mapped)
    "Wagner University",  # alias guard (canonical "Wagner College" mapped)
    "Chicago State University",  # not in our 315 universe
    "Howard University",  # not in our 315 universe
):
    SCHOOL_CONF.pop(_bad, None)

# Remove the "Big Sky" residue (no value in CONF_STRENGTH for it; never wanted).
SCHOOL_CONF = {k: v for k, v in SCHOOL_CONF.items() if v in CONF_STRENGTH}

# --------------------------------------------------------------------------------------
# 4. Derived strength maps.
# --------------------------------------------------------------------------------------
SCHOOL_STRENGTH: dict[str, float] = {
    name: CONF_STRENGTH[conf] for name, conf in SCHOOL_CONF.items()
}


def normalize(s: str) -> str:
    """Lowercase, strip punctuation, collapse whitespace -> stable match key."""
    s = s.lower()
    s = re.sub(r"[^\w\s]", " ", s)  # punctuation -> space
    s = re.sub(r"\s+", " ", s).strip()
    return s


_NORM: dict[str, float] = {normalize(name): strength for name, strength in SCHOOL_STRENGTH.items()}

# --------------------------------------------------------------------------------------
# Short-name / acronym / flagship aliases.
# Trackers (D1Baseball, etc.) use SHORT names — "Texas Tech", "LSU", "Maryland" — that do
# NOT match the official SCHOOL_CONF keys ("Texas Tech University", ...). Without this,
# ~98% of portal `from_school` values fell through to the USD-neutral default, silently
# killing the conference signal in BOTH the Rating and the step-up Likelihood. Each entry
# maps a normalized short name straight to a conference. Bare state/school names ("Maryland",
# "South Carolina", "Illinois") resolve to the FLAGSHIP program — the tracker's intent —
# which the generic token matcher can't choose because it ties with satellite campuses.
_ALIAS_CONF: dict[str, str] = {
    # SEC flagships / common forms
    "lsu": "SEC", "ole miss": "SEC", "south carolina": "SEC", "tennessee": "SEC",
    "texas": "SEC", "texas a&m": "SEC", "oklahoma": "SEC", "kentucky": "SEC",
    "florida": "SEC", "georgia": "SEC", "alabama": "SEC", "arkansas": "SEC", "missouri": "SEC",
    # ACC
    "virginia": "ACC", "miami": "ACC", "cal": "ACC", "california": "ACC", "nc state": "ACC",
    "florida state": "ACC", "wake forest": "ACC", "virginia tech": "ACC", "georgia tech": "ACC",
    "louisville": "ACC", "pittsburgh": "ACC", "boston college": "ACC", "clemson": "ACC",
    # Big 12
    "tcu": "Big 12", "byu": "Big 12", "houston": "Big 12", "utah": "Big 12",
    "arizona": "Big 12", "arizona state": "Big 12", "ucf": "Big 12", "cincinnati": "Big 12",
    "kansas": "Big 12", "kansas state": "Big 12", "baylor": "Big 12", "west virginia": "Big 12",
    "texas tech": "Big 12", "oklahoma state": "Big 12",
    # Big Ten
    "ucla": "Big Ten", "usc": "Big Ten", "maryland": "Big Ten", "illinois": "Big Ten",
    "indiana": "Big Ten", "penn state": "Big Ten", "michigan": "Big Ten", "minnesota": "Big Ten",
    "washington": "Big Ten", "oregon": "Big Ten", "rutgers": "Big Ten", "ohio state": "Big Ten",
    "nebraska": "Big Ten", "iowa": "Big Ten", "purdue": "Big Ten", "michigan state": "Big Ten",
    "northwestern": "Big Ten",
    # Big West (heavy CA presence in the portal)
    "uc san diego": "Big West", "uc irvine": "Big West", "uc riverside": "Big West",
    "uc davis": "Big West", "uc santa barbara": "Big West", "long beach state": "Big West",
    "csu bakersfield": "Big West", "cal state northridge": "Big West",
    "cal state fullerton": "Big West", "cal poly": "Big West", "hawaii": "Big West",
    "sacramento state": "Big West", "csu sacramento": "Big West",
    # American / CUSA / Mountain West
    "usf": "American", "ecu": "American", "uab": "American", "utsa": "American",
    "charlotte": "American", "memphis": "American", "tulane": "American", "rice": "American",
    "fiu": "Conference USA", "ut arlington": "Conference USA", "wku": "Conference USA",
    "new mexico state": "Conference USA", "ulm": "Conference USA", "utrgv": "Conference USA",
    "dallas baptist": "Conference USA", "kennesaw state": "Conference USA",
    "san diego state": "Mountain West", "fresno state": "Mountain West",
    "san jose state": "Mountain West", "unlv": "Mountain West", "new mexico": "Mountain West",
    "nevada": "Mountain West", "air force": "Mountain West",
    # Mid/low-major short forms
    "fgcu": "ASUN", "usc upstate": "Big South", "queens (nc)": "ASUN", "north alabama": "ASUN",
    "central arkansas": "ASUN", "umass": "Atlantic 10", "vcu": "Atlantic 10",
    "njit": "America East", "umbc": "America East", "ul monroe": "Sun Belt",
    "louisiana": "Sun Belt", "old dominion": "Sun Belt", "southern miss": "Sun Belt",
    "ut martin": "Ohio Valley", "tennessee tech": "Ohio Valley", "southeast missouri": "Ohio Valley",
    "little rock": "Ohio Valley", "siu edwardsville": "Ohio Valley", "siue": "Ohio Valley",
    "unc greensboro": "Southern", "etsu": "Southern", "vmi": "Southern",
    # D1Baseball writes "San Diego" for USD (and "San Diego State" / "UC San Diego" for the
    # others) — pin it to WCC so it doesn't subset-match San Diego State (Mountain West).
    "san diego": "WCC",
    "saint mary's (ca)": "WCC", "st thomas (mn)": "Summit", "delaware": "Coastal Athletic",
    "unc wilmington": "Coastal Athletic", "college of charleston": "Coastal Athletic",
    "north dakota state": "Summit", "omaha": "Summit", "oral roberts": "Summit",
    "penn": "Ivy", "columbia": "Ivy", "yale": "Ivy", "southern": "SWAC",
}
# Drop any alias whose conference isn't on the strength scale (typo guard), then freeze
# to strengths. Keyed on normalize() so lookups match the same way every other key does.
_ALIAS_STRENGTH: dict[str, float] = {
    normalize(k): CONF_STRENGTH[v] for k, v in _ALIAS_CONF.items() if v in CONF_STRENGTH
}

# Official-name token sets, for the generic "common name is a subset of the official name"
# matcher (e.g. {texas, tech} ⊆ {texas, tech, university}). Built once.
_OFF_TOKENS: dict[str, frozenset] = {
    k: frozenset(normalize(k).split()) for k in SCHOOL_STRENGTH
}


def _subset_strength(nkey: str) -> float | None:
    """Match a normalized short name to an official program when its tokens are a SUBSET
    of exactly one program's tokens (the most specific). Returns None if it's ambiguous —
    i.e. it ties between programs of DIFFERENT strength (e.g. a satellite campus) — so a
    bare name only resolves here when it's unambiguous; flagships go through _ALIAS_STRENGTH.
    """
    qt = set(nkey.split())
    if not qt:
        return None
    cands = sorted((len(ot - qt), k) for k, ot in _OFF_TOKENS.items() if qt <= ot)
    if not cands:
        return None
    best = [k for d, k in cands if d == cands[0][0]]
    strengths = {SCHOOL_STRENGTH[k] for k in best}
    if len(best) > 1 and len(strengths) > 1:
        return None  # ambiguous across different strengths
    return SCHOOL_STRENGTH[best[0]]


# --------------------------------------------------------------------------------------
# 5. Public lookup.
# --------------------------------------------------------------------------------------
def program_strength(school: str | None, division: str | None = None) -> float:
    """Return a 0-1 program-strength score for a school.

    Resolution order:
      1. exact match in SCHOOL_STRENGTH;
      2. normalized match in _NORM (handles minor name variants);
      3. curated short-name / acronym / flagship alias (_ALIAS_STRENGTH) — the names
         trackers actually use ("Texas Tech", "LSU", "Maryland");
      4. generic subset match (_subset_strength) — common name ⊆ official name, unambiguous;
      5. division fallback (DIV_STRENGTH) for non-D1 schools;
      6. USD-neutral default (0.62) so unknown D1 programs produce no spurious signal.
    """
    if school:
        if school in SCHOOL_STRENGTH:
            return SCHOOL_STRENGTH[school]
        nkey = normalize(school)
        if nkey in _NORM:
            return _NORM[nkey]
        if nkey in _ALIAS_STRENGTH:
            return _ALIAS_STRENGTH[nkey]
        sub = _subset_strength(nkey)
        if sub is not None:
            return sub
    if division and division in DIV_STRENGTH:
        return DIV_STRENGTH[division]
    return USD_STRENGTH


# --------------------------------------------------------------------------------------
# 6. Self-check / report.
# --------------------------------------------------------------------------------------
if __name__ == "__main__":
    from collections import Counter

    here = Path(__file__).resolve()
    # Walk up to the project root (folder containing data/cache/d1_schools.json).
    candidates = [
        here.parents[2] / "data" / "cache" / "d1_schools.json",  # src/portal/.. -> root
        Path.cwd() / "data" / "cache" / "d1_schools.json",
    ]
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        raise SystemExit("Could not locate data/cache/d1_schools.json")

    schools = json.loads(path.read_text(encoding="utf-8"))
    total = len(schools)

    classified = 0
    defaulted = []
    hist: Counter[float] = Counter()
    for name in schools:
        # "classified" == resolved to a real program (not the USD-neutral fallback)
        is_known = name in SCHOOL_STRENGTH or normalize(name) in _NORM
        strength = program_strength(name)
        hist[round(strength, 2)] += 1
        if is_known:
            classified += 1
        else:
            defaulted.append(name)

    print(f"D1 schools in file:      {total}")
    print(f"Confidently classified:  {classified}")
    print(f"Defaulted (USD-neutral):  {len(defaulted)}")
    print()
    print("Strength histogram (strength -> count):")
    for strength in sorted(hist, reverse=True):
        bar = "#" * hist[strength]
        print(f"  {strength:>4.2f}: {hist[strength]:>3}  {bar}")
    print()
    print("Examples (school -> conf -> strength):")
    examples = [
        "University of Tennessee, Knoxville",
        "Stanford University",
        "Saint Mary's College of California",
        "University of Oregon",
        "San Diego State University",
        "University of Miami (Florida)",
        "Miami University (Ohio)",
        "University of South Florida",
        "Texas Southern University",
    ]
    for ex in examples:
        conf = SCHOOL_CONF.get(ex, SCHOOL_CONF.get(normalize(ex), "(default)"))
        # conf lookup via normalized fallback:
        if ex not in SCHOOL_CONF:
            for k, v in SCHOOL_CONF.items():
                if normalize(k) == normalize(ex):
                    conf = v
                    break
            else:
                conf = "(USD-neutral default)"
        print(f"  {ex:<42} -> {conf:<18} -> {program_strength(ex):.2f}")

    if defaulted:
        print()
        print("Defaulted schools (omitted from SCHOOL_CONF -> USD-neutral 0.62):")
        for d in defaulted:
            print(f"  - {d}")
