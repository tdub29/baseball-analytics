"""Fit scoring — split into Rating and Likelihood.

  Rating — an overall future-value grade on the 20-80 scouting scale, in true standard-
  deviation units against the FULL COLLEGE population (every player we have stats for, NOT
  just the portal, and NOT an MLB yardstick): 50 = that population's mean, every 10 pts =
  1 SD (60 = +1 SD, 70 = +2 SD, 80 = +3 SD), clamped to 20-80. The portal is a biased
  subset, so grading against all college players is what makes a high grade meaningful —
  and because portal players aren't +3 SD above the all-college mean, an 80 stays a true
  outlier. It is the 20-80 rescaling of a talent composite built from level-adjusted,
  sample-confidence-weighted performance percentile, the level of competition played at,
  and class year (USD favors older players):

      composite   = w_perf  * perf_component        (talent / value)
                  + w_level * competition_strength  (CONFERENCE-granular: SEC 1.00 … WCC
                                                     0.62 … SWAC 0.38 via program_tier — NOT
                                                     the old division factor, flat 1.00 for
                                                     every D1 program)
                  + w_sen   * seniority             (USD coaches favor older players)
      Rating(OFP) = clamp(50 + 10 * z(composite vs all college), 20, 80)

  Weights are RATING_WEIGHTS (override via config["rating_weights"]); the level term now
  multiplies conference strength, so a SWAC masher no longer grades like an SEC one.

  z(.) here is a plain standard score — the composite is already sample-confidence-weighted,
  so tiny-sample junk lines sink to the bottom and don't distort the top.

  Hitters also carry three 20-80 tool grades, each POSITION-RELATIVE (graded against all
  college hitters at the same position, so the grade reads "for the position" — the right
  lens for a recruiting board): Hit (contact / on-base / swing decisions), Power (slug +
  exit velocity + batted-ball authority), and Speed (stolen bases + triples per game — the
  only base-running speed signals in the data; no sprint/60 time). These z-scores ARE
  winsorized (each metric clipped to its [1st, 99th] percentile before mean/SD), because the
  full-college reference is full of tiny-sample junk (a .700+ wOBA over a few batted balls,
  with no PA to filter on) that would otherwise inflate the SD and mint spurious 80s. Thin
  position groups (< POS_GROUP_MIN) fall back to the whole-hitter pool. Speed is NaN for a
  hitter with no box-score line (unknown wheels). Pitchers carry no tool grades.

  Positional need is intentionally NOT scored: USD's needs aren't known at ingest, so
  guessing them would only add noise. Need profiles, if configured, are still recorded
  for reference but carry zero weight in the Rating.

  Likelihood — how likely USD is this player's best landing spot (gettability).
  Local ties pull the player toward USD; the further their current program sits BELOW
  USD's WCC tier on a finely tiered conference scale (so a step up counts WITHIN D1, not
  just D2/D3/JUCO -> D1) the bigger the step up and the more gettable; but elite talent
  attracts more suitors, so the more talented the player the less likely USD is best:

      step_up    = max(0, USD_strength - program_strength)   # program_tier.py, USD = WCC
      get        = 0.50 + tie + step_up * 0.40 + grad_get - 0.22 * perf_pct
      likelihood = clamp(get * 100, 3, 97)

  where tie = 0.25 (San Diego), 0.18 (SoCal), 0.10 (California), else 0; program_strength
  is a 0-1 baseball conference scale (SEC 1.00 ... WCC 0.62 = USD ... SWAC 0.38, with
  D2/JUCO/NAIA/D3 below); grad_get = +0.06 for grad transfers (more gettable); and the
  Rating's seniority term separately rewards class year per USD's older-player lean.

The Rating (OFP) is stored as the primary `fit_score` (sort key); the pre-rescale
composite is kept in the JSON breakdown as `rating_0_100` and used as the sort tiebreak
so players clipped to 80 still order correctly. Percentiles are computed within role
(hitter / pitcher) across the evaluated pool. Results are written to the `evaluations`
table with a JSON breakdown carrying the rating, the hit/power tool grades, and the
likelihood.
"""
from __future__ import annotations

import json
import sqlite3

import numpy as np
import pandas as pd

from .db import now_iso
from .program_tier import USD_STRENGTH, is_usd, program_strength

# Level-of-competition factor — both stats `level` codes and Roman `division`.
LEVEL_FACTOR = {
    "BBC": 1.00, "I": 1.00, "1": 1.00, "D1": 1.00,
    "JCO": 0.72,                                   # JUCO arms can be live
    "NAI": 0.66,
    "ND2": 0.80, "II": 0.80, "D2": 0.80,
    "ND3": 0.58, "III": 0.58, "D3": 0.58,
}

DEFAULT_WEIGHTS = {
    "performance_percentile": 0.45, "positional_need": 0.25,
    "level_of_competition": 0.20, "eligibility": 0.10,
}

# Rating composite weights: talent / level-of-competition / seniority (sum ≈ 1).
# `level` now multiplies a CONFERENCE-granular strength (program_tier.program_strength,
# SEC 1.00 … WCC 0.62 … SWAC 0.38), not the old division-only factor that was a flat 1.00
# for every D1 program (and so did no work separating an SEC bat from a SWAC bat).
# Override per-run via config["rating_weights"].
RATING_WEIGHTS = {"perf": 0.72, "level": 0.18, "seniority": 0.10}

# USD coaches lean toward older, more proven transfers (immediate impact). Class year
# maps to a 0-1 seniority preference that feeds Rating; unknown class stays neutral so
# missing roster data never penalizes a player.
SENIORITY = {"GR": 1.0, "SR": 0.85, "JR": 0.60, "SO": 0.35, "FR": 0.15}
SENIORITY_NEUTRAL = 0.5

# Grad transfers are more gettable in their own right: a one-year eligibility window,
# more mobile, and fewer programs bank a roster spot on a rental -> a small Get% nudge
# (separate from the Rating seniority preference above).
GET_GRAD_BONUS = {"GR": 0.06}

# Local-tie pull (San Diego / SoCal / CA) is EARNED by being a plausible target: scale it by
# performance so a replacement-level local kid doesn't read as highly gettable on the
# hometown bonus alone (a perf≈0.10 local bat was hitting ~60% Get). The gate ramps from
# TIE_PERF_FLOOR at perf≈0 to 1.0 at/above the TIE_PERF_FULL percentile; above that, the
# separate -0.30*perf (elite → more suitors) still bites. Net shape: USD is most likely to
# land a SOLID local player — both weak and elite locals read lower.
TIE_PERF_FLOOR = 0.25
TIE_PERF_FULL = 0.55

PITCHER_POS = {"P", "RHP", "LHP", "TWP", "SP", "RP"}

# Performance metrics ranked within role; sign = +1 higher-is-better, -1 lower.
# A player's perf percentile is the mean of the percentiles of whichever of
# these they have — so Stuff+ (t2_stuff) and xSLG drive fit alongside 6-4-3.
HITTER_METRICS = [("xwoba", 1), ("woba", 1), ("xslg", 1), ("slg", 1),
                  ("obp", 1), ("avg_ev", 1), ("barrel_pct", 1)]
PITCHER_METRICS = [("t2_stuff", 1), ("perceived_value", 1), ("k_bb", 1), ("fip", -1),
                   ("slg_against", -1), ("inzone_whiff_pct", 1), ("xwhiff_pct", 1)]

# Position-relative 20-80 hitter tool grades (50 = average among all college players at the
# player's position, ~10 pts per SD). Each tool blends whichever of its metrics a
# player has; sign = +1 higher-is-better, -1 lower.
#   Hit  = can he hit for average, with contact/zone skill as modifiers. 6-4-3-only lines
#          often have BA/xBA plus multiple whiff/discipline columns but no OBP/K%, so a flat
#          per-column average overweights the whiff side and can bury a strong .300+ xBA bat.
#          Grouping keeps BA/xBA as the primary hit-tool signal while still penalizing swing
#          and miss. Deliberately EXCLUDES xwOBA / wOBA / SLG — those bake in power and walks
#          (overall offense), so including them let low-average power bats grade as plus
#          "hit" tools. Overall offensive value already lives in the Rating.
#   Power = SLG + exit velocity + batted-ball authority.
#   Speed = base-running outcomes (the only speed signals in the data, no sprint/60 time):
#           stolen bases and triples, both as PER-GAME rates so it's not just a
#           playing-time count. NaN for a hitter with no box-score line (unknown wheels),
#           which keeps a slow-but-unsampled bat from grading as average.
HIT_TOOL = [
    ("average", 0.75, [("ba", 1), ("xba", 1)]),
    ("contact", 0.15, [("zcon_pct", 1), ("swstr_pct", -1), ("k_pct", -1)]),
    ("zone", 0.10, [("obp", 1), ("chase_pct", -1), ("decision_value", 1)]),
]
POWER_TOOL = [("xslg", 1), ("slg", 1), ("avg_ev", 1), ("ev90", 1), ("max_ev", 1),
              ("hardhit_pct", 1), ("barrel_pct", 1), ("hr", 1)]
SPEED_TOOL = [("sb_per_g", 1), ("tr_per_g", 1)]   # steals + triples per game
# When a hitter has wRC+ (box-score line), his performance percentile is weighted this
# heavily on it, the rest on the 6-4-3 metric blend. Hitters without wRC+ use the blend alone.
WRC_WEIGHT = 0.70
# A tool is graded within a player's position only when that position has at least this
# many hitters in the pool; thinner groups (UTIL, two-way) fall back to the whole pool.
POS_GROUP_MIN = 20
# Sample size for full performance credit, and pitch-count → sample fallbacks.
FULL_SAMPLE = {"hitter": 150.0, "pitcher": 40.0}     # PA / IP
PITCHES_PER = {"hitter": 3.9, "pitcher": 15.0}       # pitches per PA / per IP


def normalize_pos(pos) -> str:
    if pos is None or (isinstance(pos, float) and pos != pos):  # None or NaN
        return ""
    p = str(pos).upper().strip()
    if not p:
        return ""
    if p in PITCHER_POS or p.startswith("P") or "HP" in p:
        return "P" if p in {"P", "TWP"} else p
    return p


def _pos_matches(player_pos: str | None, need_pos: str | None) -> bool:
    if not need_pos:
        return True
    pp, npos = normalize_pos(player_pos), normalize_pos(need_pos)
    if not pp:
        return False
    if npos in PITCHER_POS and (pp in PITCHER_POS or pp.startswith("P")):
        return True
    return pp == npos or pp.startswith(npos) or npos.startswith(pp)


def level_factor(level: str | None, division: str | None) -> float:
    for v in (level, division):
        if v and v in LEVEL_FACTOR:
            return LEVEL_FACTOR[v]
    return 0.7  # unknown level → middle


def _perf_percentile(df: pd.DataFrame) -> pd.Series:
    """Within-role mean percentile across whichever perf metrics each player has."""
    out = pd.Series(0.0, index=df.index, dtype=float)
    for role, metrics in (("hitter", HITTER_METRICS), ("pitcher", PITCHER_METRICS)):
        sub = df[df["role"] == role]
        if sub.empty:
            continue
        pcts = [(sign * sub[col]).rank(pct=True)
                for col, sign in metrics if col in sub and sub[col].notna().any()]
        comp = pd.concat(pcts, axis=1).mean(axis=1, skipna=True) if pcts else pd.Series(0.0, index=sub.index)
        out.loc[sub.index] = comp.fillna(0.0)
    return out


_WINSOR = (0.01, 0.99)   # clip each metric to [1st, 99th] pctile before standardizing


def _winsorized_z(s: pd.Series) -> pd.Series:
    """Standard score in true SD units — 0 = pool mean, 1.0 = one standard deviation —
    after clipping the metric to its [1st, 99th] percentile. The clip matters because the
    full-college reference is riddled with tiny-sample junk (e.g. a .700+ wOBA over a
    handful of batted balls, with no PA to filter on); winsorizing stops those from both
    inflating the SD and earning a spurious grade, while leaving the SD interpretation
    intact for everyone else. NaN in -> NaN out; < 2 values or zero spread -> all NaN."""
    x = s.astype(float)
    if int(x.notna().sum()) < 2:
        return pd.Series(np.nan, index=s.index)
    xc = x.clip(x.quantile(_WINSOR[0]), x.quantile(_WINSOR[1]))
    sd = xc.std(ddof=0)
    if not sd or pd.isna(sd):
        return pd.Series(np.nan, index=s.index)
    return (xc - xc.mean()) / sd


def _scale_20_80(s: pd.Series, slope: float = 10.0) -> pd.Series:
    """Map a composite onto the 20-80 scouting scale in true standard-deviation units:
    50 = pool mean, every 10 pts = 1 SD (60 = +1 SD, 70 = +2 SD, 80 = +3 SD), clamped to
    [20, 80]. This is a plain z (no winsorizing): the composite it scores is already
    sample-confidence-weighted, so tiny-sample junk sinks to the BOTTOM rather than the top
    — clipping here would only flatten legitimate top talent. NaN composites stay NaN; a
    degenerate pool (zero spread / single value) grades everyone present 50 (average)."""
    x = s.astype(float)
    sd = x.std(ddof=0)
    if not sd or pd.isna(sd):
        return x.where(x.isna(), 50.0)
    return (50 + slope * (x - x.mean()) / sd).clip(20, 80)


def _is_grouped_tool(metrics) -> bool:
    return bool(metrics) and len(metrics[0]) == 3 and isinstance(metrics[0][2], (list, tuple))


def _tool_composite_z(sub: pd.DataFrame, metrics) -> pd.Series:
    """SD-unit blend of a tool's metrics within `sub`.

    Flat tools average per-metric winsorized z-scores, then re-standardize so the composite
    is itself in SD units (this also keeps correlated metrics — e.g. avg_ev/ev90/max_ev all
    measuring power — from double-counting the spread).

    Grouped tools first average metrics inside each named group, then apply group weights
    before the final re-standardization. That prevents groups with more available columns
    from accidentally overpowering the tool definition. NaN where the tool has no usable
    metric.
    """
    if _is_grouped_tool(metrics):
        groups = []
        weights = []
        for _, weight, group_metrics in metrics:
            zs = [_winsorized_z(sign * sub[col].astype(float))
                  for col, sign in group_metrics if col in sub and sub[col].notna().any()]
            zs = [z for z in zs if z.notna().any()]
            if zs:
                groups.append(pd.concat(zs, axis=1).mean(axis=1, skipna=True))
                weights.append(float(weight))
        if not groups:
            return pd.Series(np.nan, index=sub.index)
        gdf = pd.concat(groups, axis=1)
        w = pd.Series(weights, index=gdf.columns, dtype=float)
        denom = gdf.notna().mul(w, axis=1).sum(axis=1)
        raw = gdf.mul(w, axis=1).sum(axis=1, skipna=True).where(denom > 0) / denom.replace(0, np.nan)
        return _winsorized_z(raw)

    zs = [_winsorized_z(sign * sub[col].astype(float))
          for col, sign in metrics if col in sub and sub[col].notna().any()]
    zs = [z for z in zs if z.notna().any()]
    if not zs:
        return pd.Series(np.nan, index=sub.index)
    return _winsorized_z(pd.concat(zs, axis=1).mean(axis=1, skipna=True))


def _tool_grade(hitters: pd.DataFrame, metrics) -> pd.Series:
    """Position-relative 20-80 tool grade for hitters: each player graded against peers at
    his own position (so it reads "for the position" — the recruiting-board lens). Positions
    with fewer than POS_GROUP_MIN hitters fall back to the whole-hitter pool so thin groups
    don't get noisy grades. Returns NaN where the tool has no usable metric."""
    z_overall = _tool_composite_z(hitters, metrics)
    z_final = z_overall.copy()
    pos = hitters["position"].map(normalize_pos).replace("", "UNK")
    for _, idx in hitters.groupby(pos).groups.items():
        if len(idx) >= POS_GROUP_MIN:
            zp = _tool_composite_z(hitters.loc[idx], metrics)
            z_final.loc[idx] = zp.where(zp.notna(), z_overall.loc[idx])
    return (50 + 10 * z_final).clip(20, 80)


def _r1(v):
    """Round to one decimal, or None for missing — for JSON-safe grade fields."""
    return None if v is None or pd.isna(v) else round(float(v), 1)


def _load_pool(con: sqlite3.Connection) -> pd.DataFrame:
    """ALL players with a stat line (hitter & pitcher), each joined to their best line.

    Grades are anchored to the full college population, not just the portal — so 50 means
    "average among all college players we have stats for", not "average portal entrant"
    (the portal is a biased subset). We load everyone here and compute the pool-relative
    distributions over the lot; `evaluate` then writes only the portal (`is_portal`) rows.
    Multiple sources (6-4-3, trackman, collegebaseball) can each store a line per player;
    we keep the most-sampled one per role so a player is referenced once.
    """
    hit = pd.read_sql_query(
        """SELECT p.player_id, p.full_name, p.position, p.division, p.current_status,
                  p.eligibility_remaining, p.class_year, p.from_school, p.ca_tie, p.sd_tie, p.socal_tie,
                  sh.team, sh.level AS s_level, sh.pa, sh.pitches,
                  sh.xwoba, sh.woba, sh.obp, sh.slg, sh.xslg, sh.avg_ev, sh.barrel_pct,
                  sh.ba, sh.xba, sh.ev90, sh.max_ev, sh.hardhit_pct,
                  sh.k_pct, sh.zcon_pct, sh.chase_pct, sh.swstr_pct, sh.decision_value, sh.hr
           FROM players p JOIN stats_hitting sh ON sh.player_id=p.player_id
           -- D1Baseball box-score lines are display-only (season totals, no advanced
           -- metrics); keep them out of the Rating so they don't out-sample the 6-4-3 line.
           WHERE COALESCE(sh.source,'') != 'd1baseball'""", con)
    hit["role"] = "hitter"
    hit["sample"] = hit["pa"].fillna(hit["pitches"] / PITCHES_PER["hitter"])

    pit = pd.read_sql_query(
        """SELECT p.player_id, p.full_name, p.position, p.division, p.current_status,
                  p.eligibility_remaining, p.class_year, p.from_school, p.ca_tie, p.sd_tie, p.socal_tie,
                  sp.team, sp.level AS s_level, sp.ip, sp.pitches,
                  sp.fip, sp.k_bb, sp.perceived_value, sp.t2_stuff,
                  sp.slg_against, sp.inzone_whiff_pct, sp.xwhiff_pct
           FROM players p JOIN stats_pitching sp ON sp.player_id=p.player_id
           -- D1Baseball box-score lines are display-only; keep them out of the Rating.
           WHERE COALESCE(sp.source,'') != 'd1baseball'""", con)
    pit["role"] = "pitcher"
    pit["sample"] = pit["ip"].fillna(pit["pitches"] / PITCHES_PER["pitcher"])

    pool = pd.concat([hit, pit], ignore_index=True)
    # one row per (player, role): keep the most-sampled stat line
    pool = (pool.sort_values("sample", ascending=False, na_position="last")
                .drop_duplicates(subset=["player_id", "role"], keep="first")
                .reset_index(drop=True))
    pool["is_portal"] = pool["current_status"] == "ENTERED"

    # Speed signals (SB / triples / games) AND wRC+ live ONLY on the box-score line, which
    # is kept out of the metric rating above — pull them separately. wRC+ is the best single
    # park/league-adjusted offensive-value number, so the hitter Rating leans on it heavily
    # when present (see evaluate()).
    box = pd.read_sql_query(
        """SELECT player_id, MAX(sb) AS sb, MAX(triples) AS triples, MAX(gp) AS gp,
                  MAX(wrc_plus) AS wrc_plus
           FROM stats_hitting WHERE sb IS NOT NULL OR wrc_plus IS NOT NULL GROUP BY player_id""", con)
    pool = pool.merge(box, on="player_id", how="left")
    g = pool["gp"].where(pool["gp"] > 0)
    pool["sb_per_g"] = pool["sb"] / g
    pool["tr_per_g"] = pool["triples"] / g
    return pool


def evaluate(con: sqlite3.Connection, config: dict) -> dict:
    weights = {**DEFAULT_WEIGHTS, **(config.get("fit_weights") or {})}
    profiles = config.get("need_profiles") or []
    df = _load_pool(con)   # ALL players with stats — the reference frame for every grade
    if df.empty:
        return {"evaluated": 0, "note": "no players with stats yet"}

    # multi-metric percentile within role (Stuff+ / xSLG included via metric lists)
    df["perf_pct"] = _perf_percentile(df)
    # wRC+ is the single best park/league-adjusted offensive value — when a hitter has it,
    # weight his performance percentile HEAVILY on it (the 6-4-3 metric blend stays as a
    # secondary signal / tie-break). Hitters without wRC+ keep the pure metric blend.
    if "wrc_plus" in df:
        hmask = (df["role"] == "hitter") & df["wrc_plus"].notna()
        if hmask.any():
            wrcp_pct = df.loc[df["role"] == "hitter", "wrc_plus"].rank(pct=True)  # within hitters
            base = df["perf_pct"]
            df.loc[hmask, "perf_pct"] = WRC_WEIGHT * wrcp_pct[hmask] + (1 - WRC_WEIGHT) * base[hmask]
    # sample confidence: hitters ~150 PA, pitchers ~40 IP for full credit
    full = df["role"].map(FULL_SAMPLE)
    df["sample_conf"] = (df["sample"].fillna(0) / full).clip(upper=1.0)
    df["perf_component"] = df["perf_pct"].fillna(0) * df["sample_conf"]
    # Division-only factor (kept for the JSON breakdown / back-compat) …
    df["level_component"] = [level_factor(l, d) for l, d in zip(df["s_level"], df["division"])]
    # … and the CONFERENCE-granular strength that now actually drives the Rating's
    # level-of-competition term (resolves the tracker's short school names → conference).
    df["comp_strength"] = [program_strength(s if isinstance(s, str) else None, d)
                           for s, d in zip(df["from_school"], df["division"])]

    # Seniority (USD favors older transfers), the talent composite, and its 20-80 rescale
    # (OFP). All pool-relative, so compute vectorized before scoring each player.
    df["seniority"] = [SENIORITY.get(c if isinstance(c, str) and c else "", SENIORITY_NEUTRAL)
                       for c in df["class_year"]]
    rw = {**RATING_WEIGHTS, **(config.get("rating_weights") or {})}
    df["rating_raw"] = 100 * (rw["perf"] * df["perf_component"].astype(float)
                              + rw["level"] * df["comp_strength"].astype(float)
                              + rw["seniority"] * df["seniority"].astype(float))
    df["ofp"] = _scale_20_80(df["rating_raw"])
    # Hit / Power / Speed tool grades — hitters only, position-relative (see _tool_grade).
    for col in ("hit_tool", "power_grade", "speed_grade"):
        df[col] = np.nan
    hidx = df.index[df["role"] == "hitter"]
    if len(hidx):
        h = df.loc[hidx]
        df.loc[hidx, "hit_tool"] = _tool_grade(h, HIT_TOOL)
        df.loc[hidx, "power_grade"] = _tool_grade(h, POWER_TOOL)
        df.loc[hidx, "speed_grade"] = _tool_grade(h, SPEED_TOOL)

    con.execute("DELETE FROM evaluations")
    # seed need_profiles table for the record
    con.execute("DELETE FROM need_profiles")
    for pr in profiles:
        con.execute(
            """INSERT INTO need_profiles (label, position, priority, min_eligibility, min_class, target_metrics, active)
               VALUES (?,?,?,?,?,?,1)""",
            (pr.get("label"), pr.get("position"), pr.get("priority"),
             pr.get("min_eligibility"), pr.get("min_class"),
             json.dumps(pr.get("target_metrics") or {})),
        )

    max_prio = max((p.get("priority", 1) for p in profiles), default=1)
    written = 0
    # Distributions were computed over the whole pool above; only the portal players are
    # scored onto the board / written to `evaluations`.
    for _, row in df[df["is_portal"]].iterrows():
        # best matching need profile
        best_need, best_prof = 0.2, None  # base credit so non-need players still rank
        elig_fit = 0.5
        for pr in profiles:
            if _pos_matches(row["position"], pr.get("position")):
                need_val = (max_prio - (pr.get("priority", 1)) + 1) / max_prio
                if need_val > best_need:
                    best_need, best_prof = need_val, pr
        if best_prof is not None:
            req = best_prof.get("min_eligibility")
            elig = row["eligibility_remaining"]
            if req is None or pd.isna(elig):
                elig_fit = 0.5
            else:
                elig_fit = 1.0 if elig >= req else max(0.0, elig / req)

        # Rating — talent/value + level of competition + seniority. Positional need is
        # deliberately excluded (USD's needs aren't known); coaches favor older transfers.
        cy = row.get("class_year")
        cy = cy if isinstance(cy, str) and cy else None
        seniority = float(row["seniority"])
        rating = float(row["ofp"])   # 20-80 OFP — the primary fit_score / sort key
        # Likelihood — gettability. Local ties pull toward USD; a bigger step UP to
        # D1 (lower level_component) is more gettable; elite talent has more suitors
        # so USD is less likely to be their best landing spot.
        sd = bool(row.get("sd_tie")); socal = bool(row.get("socal_tie")); ca = bool(row.get("ca_tie"))
        # USD's OWN outbound players: a player leaving USD isn't a local kid being recruited
        # home, so the "pull toward USD" tie bonus is meaningless — zero it. (step_up is
        # already 0 for a USD→USD move.) Without this they read as ~59% gettable while
        # actively leaving. Their from_school still shows on the board for retention triage.
        school = row.get("from_school")
        outbound_usd = is_usd(school if isinstance(school, str) else None)
        base_tie = 0.0 if outbound_usd else (0.25 if sd else (0.18 if socal else (0.10 if ca else 0.0)))
        # Earn the local pull by being a plausible target: gate the tie on performance so a
        # replacement-level local kid doesn't ride the hometown bonus to a high Get%.
        perf = float(row["perf_pct"] or 0)
        tie_gate = TIE_PERF_FLOOR + (1 - TIE_PERF_FLOOR) * min(1.0, perf / TIE_PERF_FULL)
        tie = base_tie * tie_gate
        # Step up to USD: how far the player's current program sits BELOW USD's WCC tier
        # on a finely tiered conference scale (so a step up counts WITHIN D1, not just from
        # D2/D3/JUCO). A low-major/JUCO arm climbing to USD is a bigger, more gettable step;
        # an SEC/ACC player would be stepping down, so no step-up credit.
        ps = program_strength(school if isinstance(school, str) else None, row.get("division"))
        step_up = max(0.0, USD_STRENGTH - ps)
        grad_get = GET_GRAD_BONUS.get(cy, 0.0)   # grad transfers a touch more gettable
        # Conservative by design: landing a transfer is hard, so anchor BELOW a coin
        # flip, discount elite talent harder (more suitors), and cap the ceiling — Get%
        # should read as "realistic, not optimistic". Ties/step-up still lift it.
        get = (
            0.38
            + tie
            + step_up * 0.32
            + grad_get
            - 0.30 * perf
        )
        likelihood = max(2.0, min(85.0, get * 100))
        components = {
            "role": row["role"],
            "rating": round(rating, 1),                          # 20-80 OFP (overall future value)
            "rating_0_100": round(float(row["rating_raw"]), 1),  # pre-rescale composite — sort tiebreak
            "hit_tool": _r1(row["hit_tool"]),
            "power_grade": _r1(row["power_grade"]),
            "speed_grade": _r1(row["speed_grade"]),
            "likelihood": round(likelihood, 1),
            "perf_pct": round(float(row["perf_pct"] or 0), 3),
            "sample_conf": round(float(row["sample_conf"]), 3),
            "need": round(best_need, 3),
            "need_label": best_prof.get("label") if best_prof else None,
            "level": round(float(row["level_component"]), 3),           # division-only factor (ref)
            "comp_strength": round(float(row["comp_strength"]), 3),     # conference strength → drives Rating
            "program_strength": round(float(ps), 3),
            "step_up": round(float(step_up), 3),
            "grad_get": round(grad_get, 3),
            "eligibility": round(elig_fit, 3),
            "seniority": round(seniority, 3),
            "class_year": cy,
            "ca": int(bool(row.get("ca_tie"))),
            "socal": int(socal),
            "sd": int(bool(row.get("sd_tie"))),
            "outbound_usd": int(outbound_usd),   # our own player leaving → no local-tie pull
            "tie": round(tie, 3),                # performance-scaled local-tie pull actually applied
        }
        pid_profile = None
        if best_prof:
            pp = con.execute(
                "SELECT id FROM need_profiles WHERE label IS ?", (best_prof.get("label"),)
            ).fetchone()
            pid_profile = pp["id"] if pp else None
        con.execute(
            """INSERT INTO evaluations (player_id, need_profile_id, fit_score, components, run_at)
               VALUES (?,?,?,?,?)""",
            (int(row["player_id"]), pid_profile, round(rating, 1),
             json.dumps(components), now_iso()),
        )
        written += 1
    con.commit()
    return {"evaluated": written, "weights": weights, "profiles": len(profiles)}
