"""
Baseballr-style PBP description keyword/pattern mappings for battle evaluation.

Maps play description text to: non-PA exclusion, reached_base, out,
total_bases, any_adv (wild pitch / passed ball / balk / steal / error advances),
run_scored, defensive_error, walk, hit_by_pitch, strikeout.

Used by battle evaluation when data comes from baseballr-style PBP (e.g.
real5_pbp_baseballr_style.csv). B2 (inning run attribution) and B3c (any_adv)
are derived best-effort from score diff and description text; see
real5_battle_feasibility.md.
"""

from __future__ import annotations

import re
from typing import Sequence

# -----------------------------------------------------------------------------
# PA action (batter outcome only): if description contains one of these → PA.
# Do NOT include "advanced", "advance", "stole", "wild pitch", "passed ball",
# "balk" by themselves — those are runner/play outcomes, not plate appearances.
# -----------------------------------------------------------------------------
PA_ACTION_PHRASES: tuple[str, ...] = (
    # From REACHED_BASE_PHRASES (batter reached)
    "homered",
    "singled",
    "doubled",
    "tripled",
    "walked",
    "hit by pitch",
    "hit by pitch (",
    "reached on a fielder's choice",
    "reached on a fielder's choice (",
    "reached on an error",
    "reached on a throwing error",
    "reached on a fielding error",
    "reached on an error (",
    "reached first on",
    # From OUT_PHRASES (batter out)
    "flied out",
    "fouled out",
    "grounded out",
    "lined out",
    "popped out",
    "popped up",
    "struck out",
    "struck out swinging",
    "struck out looking",
    "caught stealing",
    "out at second",
    "out at third",
    "out at home",
    "infield fly",
    "grounded into double play",
    "flied into double play",
    "lined into double play",
    "double play",
    "triple play",
    "out at first",
    "sac",
    "sac bunt",
    "sac fly",
)

# -----------------------------------------------------------------------------
# reached_base: leadoff (B1) and baserunner count (B3a/B3b)
# -----------------------------------------------------------------------------
REACHED_BASE_PHRASES: tuple[str, ...] = (
    "homered",
    "singled",
    "doubled",
    "tripled",
    "walked",
    "hit by pitch",
    "hit by pitch (",
    "reached on a fielder's choice",
    "reached on a fielder's choice (",
    "reached on an error",
    "reached on a throwing error",
    "reached on a fielding error",
    "reached on an error (",
    "reached first on",  # e.g. struck out, reached first on a throwing error (dropped third strike)
)

# -----------------------------------------------------------------------------
# out: batter out (not reached base)
# -----------------------------------------------------------------------------
OUT_PHRASES: tuple[str, ...] = (
    "flied out",
    "fouled out",
    "grounded out",
    "lined out",
    "popped out",
    "struck out",
    "struck out swinging",
    "struck out looking",
    "caught stealing",
    "out at second",
    "out at third",
    "out at home",
    "infield fly",
    "grounded into double play",
    "flied into double play",
    "lined into double play",
    "double play",
    "out at first",
    "sac",
    "sac bunt",
    "sac fly",
)

# -----------------------------------------------------------------------------
# total_bases: B3c bases on hit (1–4); phrase -> value
# -----------------------------------------------------------------------------
TOTAL_BASES_PHRASES: dict[str, int] = {
    "singled": 1,
    "doubled": 2,
    "tripled": 3,
    "homered": 4,
}

# -----------------------------------------------------------------------------
# run_scored: B2 inning had a run (description hints; prefer score diff)
# -----------------------------------------------------------------------------
RUN_SCORED_PHRASES: tuple[str, ...] = (
    "scored",
    "rbi",
    "scored, unearned",
)

# -----------------------------------------------------------------------------
# defensive_error: B4 error while fielding (filter by fielding team in caller)
# -----------------------------------------------------------------------------
ERROR_PHRASES: tuple[str, ...] = (
    "error by",
    "throwing error by",
    "fielding error by",
    "muffed throw",
    "reached on an error",
    "reached on a throwing error",
    "reached on a fielding error",
)

# -----------------------------------------------------------------------------
# walk, hit_by_pitch, strikeout: B5a/B5b
# -----------------------------------------------------------------------------
WALK_PHRASES: tuple[str, ...] = (
    "walked (",
    "walked(",
    "walked ",
    "walked,",  # e.g. "Lobliner walked, RBI (3-1 BBBKB)"
)

HBP_PHRASES: tuple[str, ...] = (
    "hit by pitch",
    "hit by pitch (",
    "hit by pitch(",
)

STRIKEOUT_PHRASES: tuple[str, ...] = (
    "struck out swinging",
    "struck out looking",
    "struck out, out at first",
    "struck out, out at first c to 1b",
    "struck out (",
)

# -----------------------------------------------------------------------------
# any_adv: B3c extra base advances (wild pitch, passed ball, balk, steal, error)
# Literal phrases (lowercase); each distinct advance counts 1.
# -----------------------------------------------------------------------------
ANY_ADV_PHRASES: tuple[str, ...] = (
    # Wild pitch
    "advanced to second on a wild pitch",
    "advanced to third on a wild pitch",
    "advanced to home on a wild pitch",
    "advanced to 2nd on a wild pitch",
    "advanced to 3rd on a wild pitch",
    "advanced to second on wild pitch",
    "advanced to third on wild pitch",
    "went to second on a wild pitch",
    "went to third on a wild pitch",
    "moved to second on a wild pitch",
    "moved to third on a wild pitch",
    "reached second on a wild pitch",
    "reached third on a wild pitch",
    "advanced to second on wp",
    "advanced to third on wp",
    "scored on a wild pitch",
    "scored on wild pitch",
    # Passed ball
    "advanced to second on a passed ball",
    "advanced to third on a passed ball",
    "advanced to home on a passed ball",
    "advanced to second on passed ball",
    "advanced to third on passed ball",
    "went to second on a passed ball",
    "went to third on a passed ball",
    "moved to second on a passed ball",
    "moved to third on a passed ball",
    "reached second on a passed ball",
    "reached third on a passed ball",
    "scored on a passed ball",
    "scored on passed ball",
    "advanced to second on a pb",
    "advanced to third on a pb",
    # Balk
    "advanced to second on a balk",
    "advanced to third on a balk",
    "advanced to home on a balk",
    "advanced to second on balk",
    "advanced to third on balk",
    "went to second on a balk",
    "went to third on a balk",
    "moved to second on a balk",
    "moved to third on a balk",
    "advanced on a balk",
    "scored on a balk",
    # Throwing error
    "advanced to second on a throwing error",
    "advanced to third on a throwing error",
    "advanced to home on a throwing error",
    "advanced to second on throwing error",
    "advanced to third on throwing error",
    "advanced to second on a throwing error by",
    "advanced to third on a throwing error by",
    "went to second on a throwing error",
    "went to third on a throwing error",
    "moved to second on a throwing error",
    "moved to third on a throwing error",
    "reached second on a throwing error",
    "reached third on a throwing error",
    "scored on a throwing error",
    "scored on the throwing error",
    "advanced to third on the error",
    "advanced to second on the error",
    "scored on the error",
    # Fielding error
    "advanced to second on a fielding error",
    "advanced to third on a fielding error",
    "advanced to second on fielding error",
    "advanced to third on fielding error",
    "advanced to second on an error by",
    "advanced to third on an error by",
    "went to second on a fielding error",
    "went to third on a fielding error",
    "moved to second on a fielding error",
    "moved to third on a fielding error",
    "reached second on an error",
    "reached third on an error",
    "scored on a fielding error",
    "scored on an error",
    # Muffed throw / other
    "advanced to second on a muffed throw",
    "advanced to third on a muffed throw",
    "advanced to third on muffed throw by",
    "scored on a muffed throw",
    "advanced to second on an error",
    "advanced to third on an error",
    "advanced on the error",
    # Stolen bases
    "stole second",
    "stole third",
    "stole home",
    "stole 2nd",
    "stole 3rd",
    "stolen second",
    "stolen third",
    "stolen home",
)

# Sort by length descending so longer matches win (avoid subphrase double-count)
_ANY_ADV_PHRASES_SORTED: tuple[str, ...] = tuple(
    sorted(ANY_ADV_PHRASES, key=len, reverse=True)
)

# Regex patterns for any_adv (case-insensitive, non-overlapping)
ANY_ADV_REGEX: tuple[str, ...] = (
    r"advanced?\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball|balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
    r"went\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball|balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
    r"moved\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball|balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
    r"reached\s+(second|third)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball|balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
    r"stole\s+(second|third|home|2nd|3rd)",
    r"stolen\s+(second|third|home)",
    r"scored\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball|balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)",
)

# Compiled once for reuse
_ANY_ADV_REGEX_COMPILED: tuple[re.Pattern[str], ...] = tuple(
    re.compile(p, re.IGNORECASE) for p in ANY_ADV_REGEX
)

# Breakdown: SB vs WP/PB vs other (balk, error) for any_adv counts
_ANY_ADV_SB_PHRASES: tuple[str, ...] = tuple(
    p for p in ANY_ADV_PHRASES if "stole" in p or "stolen" in p
)
_ANY_ADV_WP_PB_PHRASES: tuple[str, ...] = tuple(
    p for p in ANY_ADV_PHRASES
    if "wild pitch" in p or "passed ball" in p or " on wp" in p or " on a pb" in p or " on pb" in p
)
_ANY_ADV_OTHER_PHRASES: tuple[str, ...] = tuple(
    p for p in ANY_ADV_PHRASES
    if p not in _ANY_ADV_SB_PHRASES and p not in _ANY_ADV_WP_PB_PHRASES
)
_ANY_ADV_SB_PHRASES_SORTED = tuple(sorted(_ANY_ADV_SB_PHRASES, key=len, reverse=True))
_ANY_ADV_WP_PB_PHRASES_SORTED = tuple(sorted(_ANY_ADV_WP_PB_PHRASES, key=len, reverse=True))
_ANY_ADV_OTHER_PHRASES_SORTED = tuple(sorted(_ANY_ADV_OTHER_PHRASES, key=len, reverse=True))

_ANY_ADV_REGEX_SB: tuple[re.Pattern[str], ...] = (
    re.compile(r"stole\s+(second|third|home|2nd|3rd)", re.IGNORECASE),
    re.compile(r"stolen\s+(second|third|home)", re.IGNORECASE),
)
_ANY_ADV_REGEX_WP_PB: tuple[re.Pattern[str], ...] = (
    re.compile(
        r"advanced?\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"went\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"moved\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"reached\s+(second|third)\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(r"scored\s+on\s+(a\s+)?(wild\s+pitch|passed\s+ball)", re.IGNORECASE),
)
_ANY_ADV_REGEX_OTHER: tuple[re.Pattern[str], ...] = (
    re.compile(
        r"advanced?\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"went\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"moved\s+to\s+(second|third|home|2nd|3rd)\s+on\s+(a\s+)?(balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"reached\s+(second|third)\s+on\s+(a\s+)?(balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)(\s+by\s+\w+)?",
        re.IGNORECASE,
    ),
    re.compile(
        r"scored\s+on\s+(a\s+)?(balk|throwing\s+error|fielding\s+error|error|muffed\s+throw)",
        re.IGNORECASE,
    ),
)


def _count_category_spans(
    text: str,
    phrases_sorted: tuple[str, ...],
    regexes: tuple[re.Pattern[str], ...],
) -> int:
    """Non-overlapping span count for one category (sb, wp_pb, or other)."""
    spans: list[tuple[int, int]] = []
    for phrase in phrases_sorted:
        start = 0
        while True:
            i = text.find(phrase, start)
            if i == -1:
                break
            spans.append((i, i + len(phrase)))
            start = i + 1
    for pat in regexes:
        for m in pat.finditer(text):
            spans.append((m.start(), m.end()))
    return len(_merge_overlapping(spans))


def count_any_adv_breakdown(description: str) -> dict[str, int]:
    """
    Return breakdown of any_adv counts: sb (stolen base), wp_pb (wild pitch/passed ball), other (balk, error, sacrifice).
    Keys: "sb", "wp_pb", "other". Total advances = sb + wp_pb + other.
    """
    if not description or not isinstance(description, str):
        return {"sb": 0, "wp_pb": 0, "other": 0}
    text = description.strip().lower()
    if not text:
        return {"sb": 0, "wp_pb": 0, "other": 0}
    other = _count_category_spans(text, _ANY_ADV_OTHER_PHRASES_SORTED, _ANY_ADV_REGEX_OTHER)
    if "sacrifice" in text:
        other += 1
    return {
        "sb": _count_category_spans(text, _ANY_ADV_SB_PHRASES_SORTED, _ANY_ADV_REGEX_SB),
        "wp_pb": _count_category_spans(text, _ANY_ADV_WP_PB_PHRASES_SORTED, _ANY_ADV_REGEX_WP_PB),
        "other": other,
    }


def _merge_overlapping(spans: Sequence[tuple[int, int]]) -> list[tuple[int, int]]:
    """Merge overlapping (start, end) spans and return sorted non-overlapping."""
    if not spans:
        return []
    sorted_spans = sorted(spans)
    out: list[tuple[int, int]] = [sorted_spans[0]]
    for s, e in sorted_spans[1:]:
        if s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out


def count_any_adv(description: str) -> int:
    """
    Count distinct extra-base advances in description (wild pitch, passed ball,
    balk, steal, error). Case-insensitive; non-overlapping matches only.
    Sacrifice (bunt/fly) in description counts as 1 any_adv for B3c.

    Combined plays yield multiple counts (e.g. "stole second, advanced to third
    on a throwing error by c" -> 2).
    """
    if not description or not isinstance(description, str):
        return 0
    text = description.strip().lower()
    if not text:
        return 0

    spans: list[tuple[int, int]] = []

    # Phrase matches (longest first to avoid subphrase double-count)
    for phrase in _ANY_ADV_PHRASES_SORTED:
        start = 0
        while True:
            i = text.find(phrase, start)
            if i == -1:
                break
            spans.append((i, i + len(phrase)))
            start = i + 1

    # Regex matches
    for pat in _ANY_ADV_REGEX_COMPILED:
        for m in pat.finditer(text):
            spans.append((m.start(), m.end()))

    merged = _merge_overlapping(spans)
    total = len(merged)
    if "sacrifice" in text:
        total += 1
    return total


def is_ncaa_replay_metadata_row(description: str) -> bool:
    """NCAA inserts replay/challenge lines that are not plate appearances.

    They can contain substrings that match ``PA_ACTION_PHRASES`` (e.g. *caught stealing*
    in ``Call of caught stealing stands...``) and would steal the leadoff PA slot
    for the next half (contest 6507273 bot 6).
    """
    if not description or not isinstance(description, str):
        return True
    d = description.strip().lower()
    if "under review" in d:
        return True
    if "challenge" in d and ("remaining" in d or "exhausted" in d):
        return True
    if "call of" in d and ("stands" in d or "overturned" in d or "upheld" in d or "confirmed" in d):
        return True
    return False


def has_pa_action(description: str) -> bool:
    """True if description contains a batter outcome (PA action). Runner advancing, steals, etc. are not PA actions."""
    if not description or not isinstance(description, str):
        return False
    if is_ncaa_replay_metadata_row(description):
        return False
    t = description.strip()
    # No min-length gate: NCAA sometimes emits short but valid PA lines (e.g. "Moran walked.") which would fail a character count but match PA_ACTION_PHRASES.
    return any(p in t.lower() for p in PA_ACTION_PHRASES)


def is_non_pa(description: str) -> bool:
    """True if description indicates a non–plate appearance row. Non-PA iff no PA action (and no description)."""
    if not description or not isinstance(description, str):
        return True
    return not has_pa_action(description)


# One-time exception: this sac bunt should not be coded as an out (per user request).
_MEIDROTH_SAC_BUNT_NO_OUT = (
    "Meidroth,Connor sacrifice bunt in front of the plate, unassisted (1-1 BF); Mestas,Gage advanced to third base."
)


def reached_base(description: str) -> bool:
    """True if description indicates batter reached base."""
    if not description or not isinstance(description, str):
        return False
    if description.strip() == _MEIDROTH_SAC_BUNT_NO_OUT:
        return True
    t = description.strip().lower()
    return any(p in t for p in REACHED_BASE_PHRASES)


def is_out(description: str) -> bool:
    """True if description indicates batter out (not reached base)."""
    if not description or not isinstance(description, str):
        return False
    if description.strip() == _MEIDROTH_SAC_BUNT_NO_OUT:
        return False
    t = description.strip().lower()
    return any(p in t for p in OUT_PHRASES)


def total_bases_from_description(description: str) -> int:
    """Return 1–4 for single/double/triple/homer, else 0."""
    if not description or not isinstance(description, str):
        return 0
    t = description.strip().lower()
    for phrase, bases in TOTAL_BASES_PHRASES.items():
        if phrase in t:
            return bases
    return 0


def run_scored_in_description(description: str) -> bool:
    """True if description suggests a run scored (use with score diff when possible)."""
    if not description or not isinstance(description, str):
        return False
    t = description.strip().lower()
    return any(p in t for p in RUN_SCORED_PHRASES)


def defensive_error_in_description(description: str) -> bool:
    """True if description mentions an error (caller filters by fielding team)."""
    if not description or not isinstance(description, str):
        return False
    t = description.strip().lower()
    return any(p in t for p in ERROR_PHRASES)


def is_walk(description: str) -> bool:
    """True if description indicates a walk."""
    if not description or not isinstance(description, str):
        return False
    t = description.strip().lower()
    return any(p in t for p in WALK_PHRASES)


def is_hit_by_pitch(description: str) -> bool:
    """True if description indicates hit by pitch."""
    if not description or not isinstance(description, str):
        return False
    t = description.strip().lower()
    return any(p in t for p in HBP_PHRASES)


def is_strikeout(description: str) -> bool:
    """True if description indicates a strikeout."""
    if not description or not isinstance(description, str):
        return False
    t = description.strip().lower()
    return any(p in t for p in STRIKEOUT_PHRASES)
