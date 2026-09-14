#!/usr/bin/env python
"""Generate the USD portal hot-board dashboard (self-contained HTML).

    python scripts/build_html.py            # -> data/portal_board.html

Product register: an internal scouting instrument (see PRODUCT.md / DESIGN.md).
Light, dense, navy-tinted. A Leaflet map plots each player's HOMETOWN and SCHOOL
(clustered; journey line on select; San Diego / California ties carry the color),
above sortable/filterable Hitter, Pitcher and per-pitch Arsenal tables with a
stat heatmap. Geocoded offline; state-level placements are flagged approximate.
"""
from __future__ import annotations

import base64
import datetime
import json
import random
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from ncaa.portal.config import load_config  # noqa: E402
from ncaa.portal.db import connect  # noqa: E402
from ncaa.portal.overlay import build_overlay_payload  # noqa: E402

random.seed(7)

STATE_CENTROIDS = {
    "AL": (32.8, -86.8), "AK": (64.2, -149.5), "AZ": (34.3, -111.7), "AR": (34.9, -92.4),
    "CA": (37.2, -119.3), "CO": (39.0, -105.5), "CT": (41.6, -72.7), "DE": (39.0, -75.5),
    "FL": (28.6, -81.5), "GA": (32.6, -83.4), "HI": (20.3, -156.4), "ID": (44.4, -114.6),
    "IL": (40.0, -89.2), "IN": (39.9, -86.3), "IA": (42.0, -93.5), "KS": (38.5, -98.4),
    "KY": (37.5, -85.3), "LA": (31.0, -92.0), "ME": (45.4, -69.2), "MD": (39.0, -76.8),
    "MA": (42.3, -71.8), "MI": (44.3, -85.4), "MN": (46.3, -94.3), "MS": (32.7, -89.7),
    "MO": (38.4, -92.5), "MT": (46.9, -110.0), "NE": (41.5, -99.8), "NV": (39.3, -116.6),
    "NH": (43.7, -71.6), "NJ": (40.2, -74.7), "NM": (34.4, -106.1), "NY": (42.9, -75.5),
    "NC": (35.6, -79.4), "ND": (47.5, -100.3), "OH": (40.3, -82.8), "OK": (35.6, -97.5),
    "OR": (44.0, -120.5), "PA": (40.9, -77.8), "RI": (41.7, -71.5), "SC": (33.9, -80.9),
    "SD": (44.4, -100.2), "TN": (35.9, -86.4), "TX": (31.5, -99.3), "UT": (39.3, -111.7),
    "VT": (44.1, -72.7), "VA": (37.5, -78.9), "WA": (47.4, -120.5), "WV": (38.6, -80.6),
    "WI": (44.6, -89.9), "WY": (43.0, -107.6), "DC": (38.9, -77.0),
}
CITY_COORDS = {
    "san diego,ca": (32.72, -117.16), "chula vista,ca": (32.64, -117.08), "el cajon,ca": (32.79, -116.96),
    "carlsbad,ca": (33.16, -117.35), "oceanside,ca": (33.20, -117.38), "escondido,ca": (33.12, -117.09),
    "san marcos,ca": (33.14, -117.17), "la mesa,ca": (32.77, -117.02), "vista,ca": (33.20, -117.24),
    "encinitas,ca": (33.04, -117.29), "poway,ca": (32.96, -117.04), "santee,ca": (32.84, -116.97),
    "national city,ca": (32.68, -117.10), "coronado,ca": (32.69, -117.18),
    "los angeles,ca": (34.05, -118.24), "san francisco,ca": (37.77, -122.42), "sacramento,ca": (38.58, -121.49),
    "san jose,ca": (37.34, -121.89), "fresno,ca": (36.74, -119.78), "long beach,ca": (33.77, -118.19),
    "irvine,ca": (33.68, -117.83), "riverside,ca": (33.95, -117.40), "bakersfield,ca": (35.37, -119.02),
    "anaheim,ca": (33.84, -117.91), "santa barbara,ca": (34.42, -119.70), "stockton,ca": (37.96, -121.29),
    "sonoma,ca": (38.29, -122.46), "phoenix,az": (33.45, -112.07), "dallas,tx": (32.78, -96.80),
    "houston,tx": (29.76, -95.37), "austin,tx": (30.27, -97.74), "atlanta,ga": (33.75, -84.39),
    "denver,co": (39.74, -104.99), "chicago,il": (41.88, -87.63), "nashville,tn": (36.16, -86.78),
    "knoxville,tn": (35.96, -83.92), "seattle,wa": (47.61, -122.33), "miami,fl": (25.76, -80.19),
    "tampa,fl": (27.95, -82.46), "las vegas,nv": (36.17, -115.14), "portland,or": (45.52, -122.68),
    "new orleans,la": (29.95, -90.07), "columbia,sc": (34.00, -81.03), "fort wayne,in": (41.08, -85.14),
    "wichita,ks": (37.69, -97.34), "dayton,oh": (39.76, -84.19),
}
SD_COUNTY = {"san diego", "chula vista", "el cajon", "carlsbad", "oceanside", "escondido",
             "san marcos", "la mesa", "vista", "encinitas", "poway", "santee", "national city", "coronado"}
US_STATES = {
    "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
    "colorado": "CO", "connecticut": "CT", "delaware": "DE", "florida": "FL", "georgia": "GA",
    "hawaii": "HI", "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
    "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD", "massachusetts": "MA",
    "michigan": "MI", "minnesota": "MN", "mississippi": "MS", "missouri": "MO", "montana": "MT",
    "nebraska": "NE", "nevada": "NV", "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM",
    "new york": "NY", "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
    "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
    "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT",
    "virginia": "VA", "washington": "WA", "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
}
SCHOOL_STATE = {
    "duke university": "NC", "limestone university": "SC", "barry university": "FL",
    "saint peter's university": "NJ", "bradley university": "IL", "mount st. mary's university": "MD",
    "lake erie college": "OH", "university of the incarnate word": "TX", "wichita state university": "KS",
    "purdue university fort wayne": "IN", "sonoma state university": "CA", "regis university": "CO",
    "coppin state university": "MD", "niagara university": "NY", "xavier university": "OH",
    "stanford": "CA", "stanford university": "CA", "gonzaga university": "WA", "creighton university": "NE",
    "vanderbilt university": "TN", "marshall university": "WV", "liberty university": "VA",
    "wake forest university": "NC", "clemson university": "SC", "auburn university": "AL",
    "tulane university": "LA", "rice university": "TX", "baylor university": "TX", "tcu": "TX",
    "harvard university": "MA", "yale university": "CT", "princeton university": "NJ",
    "dallas baptist university": "TX", "wofford college": "SC", "elon university": "NC",
    "campbell university": "NC", "samford university": "AL", "mercer university": "GA",
    "lipscomb university": "TN", "belmont university": "TN", "butler university": "IN",
    "seton hall university": "NJ", "fordham university": "NY", "monmouth university": "NJ",
    "rider university": "NJ", "villanova university": "PA", "george mason university": "VA",
    "old dominion university": "VA", "high point university": "NC", "presbyterian college": "SC",
    "the citadel": "SC", "furman university": "SC", "davidson college": "NC", "stetson university": "FL",
    "biola university": "CA", "azusa pacific university": "CA", "point loma nazarene university": "CA",
}


def geocode_home(city, state):
    """-> (lat, lon, approx). Known cities are exact (no jitter); state-only is approximate."""
    st = (state or "").strip().upper()
    cy = (city or "").strip().lower()
    if cy and st and f"{cy},{st.lower()}" in CITY_COORDS:
        la, lo = CITY_COORDS[f"{cy},{st.lower()}"]
        return (la, lo, False)
    if st == "CA" and cy in SD_COUNTY:
        la, lo = CITY_COORDS["san diego,ca"]
        return (la, lo, False)
    if st in STATE_CENTROIDS:
        la, lo = STATE_CENTROIDS[st]
        return (la + random.uniform(-0.35, 0.35), lo + random.uniform(-0.35, 0.35), True)
    return (None, None, None)


# Real campus coordinates from scripts/geocode_schools.py (Nominatim), if available.
_SCHOOL_COORDS = {}
_scp = ROOT / "data" / "cache" / "school_coords.json"
if _scp.exists():
    try:
        _SCHOOL_COORDS = {k: v for k, v in json.loads(_scp.read_text(encoding="utf-8")).items() if v}
    except Exception:
        _SCHOOL_COORDS = {}


def geocode_school(name):
    """-> (lat, lon, approx). Real campus coords when geocoded; state-level fallback (approx)."""
    if not name:
        return (None, None, None)
    real = _SCHOOL_COORDS.get(name) or _SCHOOL_COORDS.get(name.strip())
    if real:
        return (real[0], real[1], False)   # actual campus location
    nl = name.lower()
    if nl in SCHOOL_STATE:
        la, lo = STATE_CENTROIDS[SCHOOL_STATE[nl]]
        return (la + random.uniform(-0.3, 0.3), lo + random.uniform(-0.3, 0.3), True)
    for ckey, (la, lo) in CITY_COORDS.items():
        if len(ckey.split(",")[0]) > 4 and ckey.split(",")[0] in nl:
            return (la, lo, False)
    for sname, usps in US_STATES.items():
        if sname in nl:
            la, lo = STATE_CENTROIDS[usps]
            return (la + random.uniform(-0.3, 0.3), lo + random.uniform(-0.3, 0.3), True)
    return (None, None, None)


HIT_SQL = """
SELECT ROUND(e.fit_score,1) fit, json_extract(e.components,'$.likelihood') lik,
       json_extract(e.components,'$.hit_tool') hitg, json_extract(e.components,'$.power_grade') powg,
       json_extract(e.components,'$.speed_grade') spdg,
       pl.player_id pid, pl.full_name name, pl.from_school school, pl.position pos,
       pl.division div, sh.level slevel, pl.class_year yr, pl.height_in ht_in, pl.weight_lb wt,
       pl.hometown_city city, pl.hometown_state st, pl.ca_tie ca, pl.sd_tie sd, pl.socal_tie socal,
       (CASE WHEN lower(pl.from_school) IN ('san diego','university of san diego') THEN 1 ELSE 0 END) usd,
       pl.high_school hs, pl.summer_team summer, pl.ca_tie_reasons tie_reasons,
       (SELECT MAX(pe.event_date) FROM portal_events pe WHERE pe.player_id=pl.player_id AND pe.event_type='ENTERED') entered,
       sh.pa, sh.ba, sh.xwoba, sh.woba, sh.xba, sh.xslg, sh.decision_value decval,
       sh.avg_ev ev, sh.ev90, sh.max_ev maxev, sh.hardhit_pct hh, sh.barrel_pct barrel, sh.barrels,
       sh.swspot_pct swspot, sh.la, sh.gb_pct gb, sh.fb_pct fb, sh.ld_pct ld, sh.pull_pct pull,
       sh.k_pct k, sh.swing_pct sw, sh.zswing_pct zsw, sh.zcon_pct zcon, sh.chase_pct chase,
       sh.swstr_pct swstr, sh.sd_plus sdp, sh.bbe,
       bx.gp, bx.ab, bx.h hits, bx.r runs, bx.rbi, bx.bb bb, bx.so, bx.sb, bx.doubles dbl, bx.triples tpl, bx.ops,
       bx.pu_pct pupct, bx.hr_fb_pct hrfb,
       bx.iso, bx.babip, bx.bb_pct bbp, bx.k_bb_ratio kbbr, bx.wrc, bx.wraa, bx.wrc_plus wrcp
FROM evaluations e JOIN players pl ON pl.player_id=e.player_id
-- "advanced" line: the 6-4-3 line (most pitches) — xwOBA/EV/barrel/discipline.
LEFT JOIN stats_hitting sh ON sh.id=(SELECT id FROM stats_hitting x WHERE x.player_id=e.player_id
       ORDER BY COALESCE(x.pitches,0) DESC, COALESCE(x.pa,0) DESC, x.id LIMIT 1)
-- "box" line: the D1Baseball season totals (GP/AB/H/R/RBI/BB/SO/SB/2B/3B/OPS), merged so a
-- hitter shows both his batted-ball profile and his box score.
LEFT JOIN stats_hitting bx ON bx.id=(SELECT id FROM stats_hitting x WHERE x.player_id=e.player_id
       AND x.source='d1baseball' ORDER BY COALESCE(x.pa,0) DESC, x.id LIMIT 1)
WHERE json_extract(e.components,'$.role')='hitter' AND pl.current_status='ENTERED'
ORDER BY e.fit_score DESC
"""
# Platoon splits — the same hitting-stat columns from the vs-LHP / vs-RHP 6-4-3 lines, so
# the site can toggle All / vs LHP / vs RHP per hitter. Keyed by player_id; the JS swaps
# only these stat columns (Rating/Hit/Power/bio stay on the overall line).
HIT_SPLITS_SQL = """
SELECT sh.player_id pid, sh.source,
       sh.pa, sh.ba, sh.xwoba, sh.woba, sh.xba, sh.xslg, sh.decision_value decval,
       sh.avg_ev ev, sh.ev90, sh.max_ev maxev, sh.hardhit_pct hh, sh.barrel_pct barrel, sh.barrels,
       sh.swspot_pct swspot, sh.la, sh.gb_pct gb, sh.fb_pct fb, sh.ld_pct ld, sh.pull_pct pull,
       sh.k_pct k, sh.swing_pct sw, sh.zswing_pct zsw, sh.zcon_pct zcon, sh.chase_pct chase,
       sh.swstr_pct swstr, sh.sd_plus sdp, sh.bbe, sh.pitches
FROM stats_hitting sh JOIN players pl ON pl.player_id=sh.player_id
WHERE pl.current_status='ENTERED' AND sh.source IN ('643-vlhp','643-vrhp')
"""
PIT_SQL = """
SELECT ROUND(e.fit_score,1) fit, json_extract(e.components,'$.likelihood') lik, pl.player_id pid, pl.full_name name, pl.from_school school, pl.throws t,
       pl.division div, sp.level slevel, pl.class_year yr, pl.height_in ht_in, pl.weight_lb wt,
       pl.hometown_city city, pl.hometown_state st, pl.ca_tie ca, pl.sd_tie sd, pl.socal_tie socal,
       (CASE WHEN lower(pl.from_school) IN ('san diego','university of san diego') THEN 1 ELSE 0 END) usd,
       pl.high_school hs, pl.summer_team summer, pl.ca_tie_reasons tie_reasons,
       (SELECT MAX(pe.event_date) FROM portal_events pe WHERE pe.player_id=pl.player_id AND pe.event_type='ENTERED') entered,
       COALESCE(bx.ip, sp.ip) ip, COALESCE(bx.fip, sp.fip) fip,
       COALESCE(sp.slg_against, bx.slg_against) slg, COALESCE(sp.k_bb, bx.k_bb) kbb,
       COALESCE(sp.perceived_value, bx.perceived_value) pv,
       bx.era, bx.w wins, bx.l losses, bx.sv sv, bx.k kct,
       sp.t2_stuff stuff, sp.fb_velo velo, sp.fb_ivb fbivb, sp.fb_hb fbhb,
       sp.fb_stuff fbs, sp.si_stuff sis, sp.sl_stuff sls, sp.cb_stuff cbs, sp.ch_stuff chs, sp.ct_stuff cts,
       sp.hardhit_pct hh, sp.ground_pct gb, sp.strike_pct strike, sp.miss_pct miss,
       sp.inzone_whiff_pct izw, sp.chase_pct chase, sp.xwhiff_pct xwh
FROM evaluations e JOIN players pl ON pl.player_id=e.player_id
-- "stuff" line: the most-pitch-tracked line (6-4-3) — Stuff+, velocity, per-pitch shape.
LEFT JOIN stats_pitching sp ON sp.id=(SELECT id FROM stats_pitching x WHERE x.player_id=e.player_id
       ORDER BY COALESCE(x.pitches,0) DESC, COALESCE(x.ip,0) DESC, x.id LIMIT 1)
-- "box" line: the best line that actually carries innings — IP/FIP/box-score totals (6-4-3
-- exports don't carry these; they come from the box-score/NCAA line). Merged per-column so
-- a pitcher shows BOTH his Stuff+ and his IP/FIP instead of one blanking the other.
LEFT JOIN stats_pitching bx ON bx.id=(SELECT id FROM stats_pitching x WHERE x.player_id=e.player_id
       AND x.ip IS NOT NULL ORDER BY COALESCE(x.ip,0) DESC, x.id LIMIT 1)
WHERE json_extract(e.components,'$.role')='pitcher' AND pl.current_status='ENTERED'
ORDER BY e.fit_score DESC
"""
ARS_SQL = """
SELECT pl.player_id pid, pl.full_name name, pl.from_school school, pl.division div,
       pl.hometown_city city, pl.hometown_state st, pl.ca_tie ca, pl.sd_tie sd, pl.socal_tie socal,
       (CASE WHEN lower(pl.from_school) IN ('san diego','university of san diego') THEN 1 ELSE 0 END) usd,
       pl.high_school hs, pl.summer_team summer, pl.ca_tie_reasons tie_reasons,
       (SELECT ROUND(e.fit_score,1) FROM evaluations e WHERE e.player_id=a.player_id
        AND json_extract(e.components,'$.role')='pitcher' LIMIT 1) fit,
       (SELECT json_extract(e.components,'$.likelihood') FROM evaluations e WHERE e.player_id=a.player_id
        AND json_extract(e.components,'$.role')='pitcher' LIMIT 1) lik,
       a.season, a.pitch_type pitch, a.pitches p, a.bbe, a.barrels,
       a.velo, a.velo90, a.max_velo maxv, a.spin, a.ivb, a.hb, a.vaa, a.haa,
       a.rel_height relh, a.rel_side rels, a.extension ext,
       a.stuff_plus stuff, a.location_plus loc, a.xrv_plus xrv, a.anomaly_plus anom,
       a.tunnel_plus tun, a.predmovdiff_plus pmd, a.ev, a.hardhit_pct hh, a.barrel_pct brl,
       a.ba, a.xba, a.woba, a.xwoba, a.swing_pct sw, a.zcontact_pct zcon, a.chase_pct chase, a.whiff_pct whiff
FROM pitch_arsenal a JOIN players pl ON pl.player_id=a.player_id
WHERE pl.current_status='ENTERED'
ORDER BY a.stuff_plus DESC
"""


def fmt_ht(v):
    return f"{int(v)//12}'{int(v)%12}\"" if v else ""


# Level of competition -> readable D1/D2/D3/NAIA/JUCO. Player division (I/II/III) and the
# finer 6-4-3 stat-line level codes (BBC/ND2/ND3/NAI/JCO) both map here; the stat-line
# level wins when present since it distinguishes JUCO/NAIA that division alone collapses.
LEVEL_LABEL = {"BBC": "D1", "I": "D1", "1": "D1", "D1": "D1",
               "ND2": "D2", "II": "D2", "2": "D2", "D2": "D2",
               "ND3": "D3", "III": "D3", "3": "D3", "D3": "D3",
               "NAI": "NAIA", "NAIA": "NAIA", "JCO": "JUCO", "JUCO": "JUCO"}


def fmt_level(v):
    if not v:
        return ""
    return LEVEL_LABEL.get(str(v).strip().upper(), str(v).strip())


def _records(df):
    recs = json.loads(df.where(pd.notna(df), None).to_json(orient="records"))
    for r in recs:
        if "ht_in" in r:
            r["ht"] = fmt_ht(r.pop("ht_in"))
        if "div" in r or "slevel" in r:
            r["lvl"] = fmt_level(r.pop("slevel", None) or r.pop("div", None))
    return recs


def _source_maps(con, pids: set[int]) -> tuple[dict[str, list[dict]], dict[str, list[dict]]]:
    """Small source payload for the selected-player card.

    Bio rows back hometown/HS evidence. Portal event rows back the "from school"
    lineage used for prior-school CA/SD/SoCal ties. Keys are strings so the JSON
    object can be addressed directly from JavaScript by row.pid.
    """
    if not pids:
        return {}, {}
    placeholders = ",".join("?" for _ in pids)
    params = tuple(sorted(pids))
    bio_rows = con.execute(
        f"""SELECT player_id, season, source, source_file, source_url, team,
                  hometown_city, hometown_state, high_school
            FROM player_bio_evidence
            WHERE player_id IN ({placeholders})
              AND (hometown_city IS NOT NULL OR hometown_state IS NOT NULL OR high_school IS NOT NULL)
            ORDER BY player_id,
              CASE lower(COALESCE(source,''))
                WHEN 'ncaa' THEN 0 WHEN 'sidearm' THEN 1 WHEN 'perfectgame' THEN 2
                WHEN 'pbr' THEN 3 WHEN 'd1baseball' THEN 4 WHEN 'manual' THEN 5
                WHEN '643' THEN 6 ELSE 9 END,
              season DESC""",
        params,
    ).fetchall()
    event_rows = con.execute(
        f"""SELECT player_id, source, event_date, source_url
            FROM portal_events
            WHERE player_id IN ({placeholders})
            ORDER BY player_id, COALESCE(event_date, observed_at) DESC""",
        params,
    ).fetchall()

    bio: dict[str, list[dict]] = {}
    for r in bio_rows:
        bio.setdefault(str(r["player_id"]), []).append({
            "season": r["season"], "source": r["source"],
            "source_file": r["source_file"], "source_url": r["source_url"],
            "team": r["team"],
            "city": r["hometown_city"], "st": r["hometown_state"], "hs": r["high_school"],
        })
    events: dict[str, list[dict]] = {}
    seen: set[tuple] = set()
    for r in event_rows:
        key = (r["player_id"], r["source"], r["event_date"], r["source_url"])
        if key in seen:
            continue
        seen.add(key)
        events.setdefault(str(r["player_id"]), []).append({
            "source": r["source"], "date": r["event_date"], "url": r["source_url"],
        })
    return bio, events


def main() -> None:
    con = connect()
    hit = _records(pd.read_sql_query(HIT_SQL, con))
    pit = _records(pd.read_sql_query(PIT_SQL, con))
    ars = _records(pd.read_sql_query(ARS_SQL, con))
    # Attach vs-LHP / vs-RHP stat lines to each hitter for the site's split toggle.
    splits: dict[str, dict[str, dict]] = {}
    for r in _records(pd.read_sql_query(HIT_SPLITS_SQL, con)):
        pid = str(r.pop("pid")); key = "vlhp" if str(r.pop("source")).endswith("vlhp") else "vrhp"
        splits.setdefault(pid, {})[key] = {k: v for k, v in r.items() if v is not None}
    for r in hit:
        sp = splits.get(str(r.get("pid")))
        if sp:
            r["sp"] = sp
    pids = {int(r["pid"]) for r in hit + pit + ars if r.get("pid") is not None}
    bio, events = _source_maps(con, pids)
    # Coach-interaction overlay (lead temp / favorites / notes). Backend-tagged so the
    # board JS knows whether to render editable controls (supabase) or read-only chips
    # (sheet); {"backend":"none"} when unconfigured, leaving the board exactly as before.
    try:
        overlay = build_overlay_payload(con, load_config())
    except Exception as e:  # noqa: BLE001 — never let overlay setup break the board build
        print(f"  overlay disabled ({e})")
        overlay = {"backend": "none"}
    con.close()

    mappts, n_home, n_school, n_both = [], 0, 0, 0
    for role, rows in (("H", hit), ("P", pit)):
        for r in rows:
            hlat, hlon, hap = geocode_home(r.get("city"), r.get("st"))
            slat, slon, sap = geocode_school(r.get("school"))
            pts = []
            if hlat is not None:
                pts.append({"lat": round(hlat, 3), "lon": round(hlon, 3), "k": "home", "ap": int(hap)})
            if slat is not None:
                pts.append({"lat": round(slat, 3), "lon": round(slon, 3), "k": "school", "ap": int(sap)})
            if not pts:
                continue
            n_home += hlat is not None
            n_school += slat is not None
            n_both += hlat is not None and slat is not None
            mappts.append({"pid": r.get("pid"), "n": r["name"], "r": role, "f": r.get("fit"),
                           "ca": r.get("ca"), "sd": r.get("sd"), "socal": r.get("socal"),
                           "usd": r.get("usd"), "sc": r.get("school"),
                           "h": f'{r.get("city") or "?"}, {r.get("st") or "?"}',
                           "s": (f'Stuff+ {r.get("stuff")}' if role == "P" else f'xwOBA {r.get("xwoba")}'),
                           "p": pts})

    # USD's OWN players who entered the portal — count distinct ids across hit + pit.
    usd_ids = {r.get("pid") for r in (hit + pit) if r.get("usd")}
    summary = {"hitters": len(hit), "pitchers": len(pit), "ca": sum(1 for m in mappts if m["ca"]),
               "socal": sum(1 for m in mappts if m["socal"]), "sd": sum(1 for m in mappts if m["sd"]),
               "usd": len(usd_ids), "home": n_home, "journey": n_both, "arsenal": len(ars)}
    out = ROOT / "data" / "portal_board.html"
    payload = json.dumps({"hit": hit, "pit": pit, "ars": ars, "map": mappts, "sum": summary,
                          "bio": bio, "events": events},
                         separators=(",", ":"))
    logo = ROOT / "San_Diego_Toreros_logo.svg.png"
    logo_b64 = base64.b64encode(logo.read_bytes()).decode() if logo.exists() else ""
    d = datetime.date.today()
    gen = f"{d:%b} {d.day}, {d.year}"
    overlay_json = json.dumps(overlay, separators=(",", ":"))
    html = (_TEMPLATE.replace("/*DATA*/", payload)
            .replace("/*OVERLAY*/", overlay_json)
            .replace("/*GEN*/", gen).replace("/*LOGO*/", logo_b64))
    out.write_text(html, encoding="utf-8")
    print(f"wrote {out}\n  {summary}\n  overlay: {overlay.get('backend')}"
          + (f" ({len(overlay.get('data', {}))} tagged)" if overlay.get("backend") != "none" else ""))


_TEMPLATE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>USD Toreros · Portal Hot Board</title>
<link rel="icon" type="image/png" href="data:image/png;base64,/*LOGO*/">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Saira+Condensed:wght@500;600;700;800&display=swap">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js"></script>
<style>
 :root{
   --bg:oklch(0.985 0.004 250); --panel:oklch(1 0 0); --line:oklch(0.90 0.008 245);
   --ink:oklch(0.25 0.03 255); --muted:oklch(0.52 0.02 255);
   /* University of San Diego Toreros: deep Navy + Torero/Columbia Blue + white */
   --navy:oklch(0.30 0.078 256); --navy-deep:oklch(0.22 0.072 259);
   --torero:oklch(0.72 0.11 242); --torero-ink:oklch(0.52 0.12 245);
   --sd:oklch(0.58 0.20 22); --ca:oklch(0.72 0.16 65); --other:oklch(0.55 0.03 258);
   --sd-bg:oklch(0.95 0.04 22); --ca-bg:oklch(0.96 0.05 80);
   --display:"Saira Condensed",ui-sans-serif,system-ui,"Segoe UI",sans-serif;
 }
 *{box-sizing:border-box} html{-webkit-text-size-adjust:100%}
 body{margin:0;background:var(--bg);color:var(--ink);
   font:13px/1.45 ui-sans-serif,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
 header{background:linear-gradient(103deg,var(--navy-deep),var(--navy));color:oklch(0.97 0.01 255);
   border-bottom:3px solid var(--torero)}
 .mast{max-width:1340px;margin:0 auto;padding:14px 22px;display:flex;align-items:center;gap:16px}
 .crest{flex:none;height:54px;width:54px;background:oklch(1 0 0);border-radius:13px;padding:5px;
   object-fit:contain;box-shadow:0 1px 4px oklch(0.18 0.05 260/.45)}
 .mast .id{display:flex;flex-direction:column;gap:1px;min-width:0}
 .mast .ey{font:700 11px/1 var(--display);letter-spacing:.2em;text-transform:uppercase;color:var(--torero)}
 .mast h1{margin:1px 0 0;font:800 26px/1.0 var(--display);letter-spacing:.012em;text-transform:uppercase;
   color:oklch(0.985 0.008 250)}
 .mast .sub{font-size:12px;color:oklch(0.82 0.03 245);margin-top:3px}
 .mast .meta{margin-left:auto;display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end;align-self:flex-start;padding-top:3px}
 .chip2{font:600 11px/1 var(--display);letter-spacing:.09em;text-transform:uppercase;color:oklch(0.87 0.03 245);
   border:1px solid oklch(0.62 0.08 245/.45);border-radius:999px;padding:5px 11px;white-space:nowrap}
 .chip2 b{color:var(--torero);font-weight:700}
 .wrap{max-width:1340px;margin:0 auto;padding:18px}
 .stats{display:flex;gap:28px;flex-wrap:wrap;padding:18px 2px 14px;border-bottom:1px solid var(--line);margin-bottom:14px}
 .stat b{display:inline-block;font:800 27px/1 var(--display);color:var(--navy);font-variant-numeric:tabular-nums;
   letter-spacing:.01em;border-bottom:2.5px solid var(--torero);padding-bottom:2px}
 .stat b.sd{color:#c0392b;border-color:#c0392b} .stat b.socal{color:#e8730c;border-color:#e8730c} .stat b.ca{color:#caa00a;border-color:#caa00a}
 .stat b.usd{color:var(--torero-ink);border-color:var(--torero)}
 .stat span{display:block;font-size:10px;letter-spacing:.07em;text-transform:uppercase;color:var(--muted);margin-top:6px;font-weight:600}
 #map{height:480px;border-radius:12px;border:1px solid var(--line);box-shadow:0 1px 2px oklch(0.4 0.03 258 / .06)}
 .leaflet-control.legend{background:var(--panel);padding:8px 11px;border-radius:9px;border:1px solid var(--line);
   font-size:11.5px;line-height:1.7;box-shadow:0 1px 6px oklch(0.4 0.03 258/.12);color:var(--ink)}
 .legend .k{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;vertical-align:middle}
 .legend .ring{width:7px;height:7px;border:1.5px solid var(--other);background:transparent}
 .legend hr{border:0;border-top:1px solid var(--line);margin:6px 0}
 .maprow{display:flex;justify-content:space-between;align-items:center;gap:12px;margin:8px 2px 20px;flex-wrap:wrap}
 .maprow .note{font-size:11px;color:var(--muted);max-width:62ch}
 .toggles label{font-size:12px;color:var(--ink);margin-left:14px;cursor:pointer;white-space:nowrap}
 .tabs{display:flex;gap:2px;border-bottom:2px solid var(--line)}
 .tabs button{border:0;background:none;padding:9px 16px;font:inherit;font-weight:600;color:var(--muted);cursor:pointer;
   border-bottom:2px solid transparent;margin-bottom:-2px;transition:color .15s}
 .tabs button:hover{color:var(--ink)} .tabs button.on{color:var(--navy);border-bottom-color:var(--torero)}
 .ctl{display:flex;gap:10px;align-items:center;margin:12px 0 8px;flex-wrap:wrap}
 .ctl input[type=text]{padding:7px 11px;border:1px solid var(--line);border-radius:8px;width:230px;font:inherit;color:var(--ink);background:var(--panel)}
 .ctl input[type=text]:focus{outline:2px solid var(--navy);outline-offset:-1px;border-color:transparent}
 .ctl label{font-size:12.5px;color:var(--ink);cursor:pointer} .ctl .sp{flex:1}
 .ctl .cnt{font-size:12px;color:var(--muted);font-variant-numeric:tabular-nums}
 .ctl .grp{display:inline-flex;align-items:center;gap:7px}
 .ctl .lbl{font-size:10px;letter-spacing:.05em;text-transform:uppercase;color:var(--muted);font-weight:600}
 .ctl .seg{display:inline-flex;border:1px solid var(--line);border-radius:8px;overflow:hidden}
 .ctl .seg button{border:0;border-left:1px solid var(--line);background:var(--panel);padding:6px 11px;font:inherit;font-size:12px;color:var(--muted);cursor:pointer;transition:background .12s}
 .ctl .seg button:first-child{border-left:0} .ctl .seg button:hover{color:var(--ink)}
 .ctl .seg button.on{background:var(--navy);color:oklch(0.97 0.01 255);font-weight:650}
 .ctl .chips{display:inline-flex;gap:4px}
 .ctl .chip{border:1px solid var(--line);background:var(--panel);border-radius:7px;padding:5px 9px;font:inherit;font-size:11.5px;font-weight:650;color:var(--muted);cursor:pointer;transition:background .12s}
 .ctl .chip:hover{color:var(--ink)} .ctl .chip.on{background:var(--navy);color:oklch(0.97 0.01 255);border-color:transparent}
 .ctl select{padding:6px 9px;border:1px solid var(--line);border-radius:8px;font:inherit;font-size:12px;color:var(--ink);background:var(--panel);cursor:pointer;max-width:140px}
 .ctl .num{width:58px;padding:6px 8px;border:1px solid var(--line);border-radius:8px;font:inherit;font-size:12px;color:var(--ink);background:var(--panel);text-align:right}
 .ctl .num:focus,.ctl select:focus{outline:2px solid var(--navy);outline-offset:-1px;border-color:transparent}
 .ctl .fl{display:inline-flex;align-items:center;gap:5px;font-size:12px;color:var(--muted)}
 .ctl .reset{border:1px solid var(--line);background:var(--panel);border-radius:8px;padding:6px 12px;font:inherit;font-size:12px;color:var(--muted);cursor:pointer}
 .ctl .reset:hover{color:var(--ink);border-color:var(--muted)}
 .ctl .exp{border:1px solid var(--navy);background:var(--navy);color:oklch(0.97 0.01 255);border-radius:8px;padding:6px 12px;font:inherit;font-size:12px;font-weight:650;cursor:pointer}
 .ctl .exp:hover{background:var(--navy-deep)}
 .rowsel,#selAll{vertical-align:middle;margin-right:4px;cursor:pointer;accent-color:var(--navy)}
 #tbl tbody tr.picked td{background:oklch(0.965 0.022 244)} #tbl tbody tr.picked td.nm{background:oklch(0.95 0.028 244)}
 .ctl .div{width:1px;align-self:stretch;background:var(--line);margin:2px 2px}
 .method{margin:2px 2px 12px;border:1px solid var(--line);border-radius:9px;background:var(--panel);overflow:hidden}
 .method summary{cursor:pointer;padding:9px 13px;font:700 11.5px/1 var(--display);letter-spacing:.08em;
   text-transform:uppercase;color:var(--navy);list-style:none}
 .method summary::-webkit-details-marker{display:none}
 .method summary::before{content:"▸ ";color:var(--torero)} .method[open] summary::before{content:"▾ "}
 .method .methbody{padding:2px 14px 12px;border-top:1px solid var(--line)}
 .method p{margin:9px 0;font-size:12px;line-height:1.5;color:var(--ink);max-width:94ch}
 .method b{color:var(--navy)}
 .tbl-wrap{overflow:auto;max-height:64vh;border:1px solid var(--line);border-radius:10px;background:var(--panel)}
 table{border-collapse:separate;border-spacing:0;font-size:12.5px;font-variant-numeric:tabular-nums}
 th,td{padding:5px 9px;text-align:right;white-space:nowrap;border-bottom:1px solid var(--line)}
 th{position:sticky;top:23px;z-index:3;background:oklch(0.96 0.006 255);cursor:pointer;user-select:none;
   font-size:11px;font-weight:650;letter-spacing:.02em;color:var(--muted)}
 th:hover{color:var(--ink)}
 /* section header band: a NAVY top row of group labels spanning their columns, so it
    clearly reads as a tier above the (grey) column headers */
 .grp-row th{position:sticky;top:0;z-index:6;height:23px;padding:3px 10px;text-align:center;cursor:default;
   background:var(--navy-deep);color:oklch(0.95 0.025 245);border-bottom:2px solid var(--torero);
   font:800 10px/1 var(--display);letter-spacing:.14em;text-transform:uppercase}
 .grp-row th:hover{color:oklch(0.97 0.02 245)}
 .grp-row th+th{border-left:1px solid oklch(0.62 0.10 245/.55)}   /* divider between sections */
 .grp-row th:empty{background:var(--navy-deep)}
 .grp-row th.gnm{position:sticky;left:0;z-index:7;background:var(--navy-deep);border-left:0}
 th.l,td.l{text-align:left}
 td.l,th.l{max-width:200px;overflow:hidden;text-overflow:ellipsis}
 td.nm,th.nm{position:sticky;left:0;z-index:2;background:var(--panel);text-align:left;font-weight:600;
   max-width:230px;overflow:hidden;box-shadow:1px 0 0 var(--line)}
 th.nm{z-index:4;background:oklch(0.96 0.006 255)}
 /* name cell as a flex row: only the name text truncates — star, lead badge and tie pill stay visible */
 .nmwrap{display:flex;align-items:center;gap:4px;min-width:0}
 .nmwrap .nmtxt{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 .nmwrap .rowsel{flex:none;margin:0 1px 0 0} .nmwrap .ovstar,.nmwrap .leadnum,.nmwrap .pill{flex:none}
 .notescell{min-width:360px;width:420px;max-width:520px;color:var(--muted);white-space:normal;vertical-align:top}
 .inline-note{width:100%;min-width:340px;min-height:31px;height:31px;border:1px solid var(--line);border-radius:7px;padding:6px 8px;
   font:inherit;font-size:12px;line-height:1.3;color:var(--ink);background:var(--panel);resize:none;overflow:hidden;white-space:pre-wrap}
 .inline-note:focus{outline:2px solid var(--navy);outline-offset:-1px;border-color:transparent}
 .inline-note[readonly]{color:var(--muted);background:oklch(0.975 0.004 250);cursor:pointer}
 .inline-note-all{margin-top:5px;font-size:11.5px;line-height:1.3;color:var(--muted);white-space:pre-wrap}
 .inline-note-ro{max-width:520px;white-space:pre-wrap;line-height:1.3;color:var(--ink)}
 #tbl tbody tr{cursor:pointer}
 tr:hover td{filter:brightness(0.985)} tr:hover td.nm{background:oklch(0.975 0.006 255)}
 #tbl tbody tr.sel td{background:oklch(0.97 0.018 244)}
 #tbl tbody tr.sel td.nm{background:oklch(0.955 0.024 244)}
 .pill{font-size:9.5px;font-weight:700;padding:1px 5px;border-radius:8px;color:oklch(1 0 0);margin-left:5px;vertical-align:middle}
 .pill.sd{background:#c0392b} .pill.socal{background:#e8730c} .pill.ca{background:#caa00a}
 .player-card{display:none;margin:10px 2px 12px;border:1px solid var(--line);border-radius:9px;background:var(--panel);
   box-shadow:0 1px 2px oklch(0.4 0.03 258 / .05)}
 .player-card.on{display:grid;grid-template-columns:minmax(220px,.9fr) minmax(380px,1.5fr) minmax(220px,.95fr);gap:0;align-items:stretch}
 .pc-head,.pc-block{padding:12px 14px}.pc-head,.pc-block+.pc-block{border-left:1px solid var(--line)}
 .pc-k{font:700 10px/1 var(--display);letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:6px}
 .pc-name{font:800 22px/1 var(--display);letter-spacing:.01em;text-transform:uppercase;color:var(--navy);overflow-wrap:anywhere}
 .pc-sub{margin-top:6px;color:var(--muted);font-size:12px}
 .pc-metrics{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
 .pc-metric{border:1px solid var(--line);border-radius:7px;padding:5px 8px;font-size:12px;color:var(--ink);background:oklch(0.985 0.004 250)}
 .pc-metric b{font:800 16px/1 var(--display);color:var(--navy);margin-right:3px}
 .pc-source{margin-top:12px;padding-top:10px;border-top:1px solid var(--line)}
 .pc-source .pc-list{max-height:132px;overflow:auto;scrollbar-width:thin;padding-right:4px}
 .pctchart{border-left:1px solid var(--line);border-right:1px solid var(--line);padding:0 12px 10px;background:oklch(0.992 0.003 250);
   max-height:286px;overflow:auto;overscroll-behavior:contain;scrollbar-width:thin}
 .pct-head{position:sticky;top:0;z-index:1;background:oklch(0.992 0.003 250);padding:10px 0 6px;border-bottom:1px solid var(--line)}
 .pct-title{display:flex;align-items:baseline;justify-content:center;gap:8px;color:var(--navy)}
 .pct-title b{font:800 15px/1 var(--display);text-transform:uppercase}.pct-title span{font-size:11px;color:var(--muted)}
 .pct-scale{display:grid;grid-template-columns:104px minmax(170px,1fr) 44px;gap:4px 7px;align-items:center;margin-top:5px}
 .pct-scale span{grid-column:2;position:relative;display:grid;grid-template-columns:1fr 1fr 1fr;text-align:center;
   font:700 9.5px/1 var(--display);letter-spacing:.08em;text-transform:uppercase}
 .pct-scale span:after{content:"MED";position:absolute;left:50%;top:13px;transform:translateX(-50%);
   font:800 8.5px/1 var(--display);letter-spacing:.08em;color:var(--navy);background:oklch(0.992 0.003 250);padding:0 3px}
 .pct-scale b{font-weight:700}.pct-scale b:first-child{color:#2d6ca2}.pct-scale b:nth-child(2){color:var(--muted)}.pct-scale b:last-child{color:#d21f2b}
 .pct-sec{display:grid;grid-template-columns:104px minmax(170px,1fr) 44px;gap:4px 7px;align-items:center;margin-top:7px}
 .pct-sec h3{grid-column:1/-1;margin:7px 0 2px;padding-top:6px;border-top:2px solid var(--sky);
   font:800 11px/1 var(--display);letter-spacing:.04em;text-transform:uppercase;color:var(--ink)}
 .pct-lbl{font-size:11px;color:var(--ink);text-align:right;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 .pct-bar{position:relative;height:18px;background:linear-gradient(90deg,#9bb8c8 0,#9bb8c8 1px,transparent 1px,transparent calc(50% - 1px),#203a55 calc(50% - 1px),#203a55 calc(50% + 1px),transparent calc(50% + 1px),transparent calc(100% - 1px),#9bb8c8 calc(100% - 1px)),oklch(0.9 0.012 205);
   border-radius:2px;overflow:hidden}
 .pct-bar:after{content:"";position:absolute;left:50%;top:0;bottom:0;width:2px;transform:translateX(-1px);background:var(--navy);opacity:.72;pointer-events:none}
 .pct-fill{height:100%;min-width:2px;background:#9ab4c8}
 .pct-fill.good{background:#df252c}.pct-fill.mid{background:#d18d7e}
 .pct-badge{position:absolute;top:50%;transform:translate(-50%,-50%);min-width:24px;height:18px;border-radius:10px;background:#8aa8bf;color:white;
   font:800 11px/18px var(--display);text-align:center;box-shadow:0 0 0 2px white}
 .pct-val{font-size:11px;color:var(--ink);text-align:right;font-variant-numeric:tabular-nums}
 .pc-list{margin:0;padding:0;list-style:none;display:grid;gap:5px}
 .pc-list li{font-size:12px;line-height:1.35;color:var(--ink)}
 .pc-src{color:var(--muted)}
 .pc-src b{color:var(--navy)}
 .pc-empty{color:var(--muted);font-style:italic}
 .pc-close{position:absolute;right:8px;top:8px;border:1px solid var(--line);background:var(--panel);border-radius:7px;
   padding:3px 7px;font:inherit;font-size:11px;color:var(--muted);cursor:pointer}
 .pc-close:hover{color:var(--ink)}
 .player-card{position:relative}
 @media (max-width:900px){
   .player-card.on{grid-template-columns:1fr}
   .pc-head,.pc-block+.pc-block{border-left:0}
   .pc-block{border-top:1px solid var(--line)}
   .pctchart{border-left:0;border-right:0;border-top:1px solid var(--line);max-height:260px}
 }
 .ftnote{font-size:11px;color:var(--muted);margin:14px 2px 0}
 .seclbl{font:700 11px/1 var(--display);letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin:26px 2px 10px}
 td.st,th.st{max-width:40px;width:40px;text-align:center;padding-left:4px;padding-right:4px}
 .brandfoot{margin:20px 2px 10px;padding-top:12px;border-top:2px solid var(--torero);
   font:600 11px/1.5 var(--display);letter-spacing:.07em;text-transform:uppercase;color:var(--muted)}
 .brandfoot b{color:var(--navy);font-weight:700}
 .usd-badge{font:800 11px/1 var(--display);letter-spacing:.04em;color:oklch(0.97 0.01 255);
   background:var(--navy-deep);border:1.5px solid var(--torero);border-radius:6px;padding:3px 7px;
   text-align:center;box-shadow:0 1px 4px oklch(0.2 0.05 260/.5);white-space:nowrap}
 .leaflet-marker-icon.usd-pin{background:none;border:0}
 /* ── coach overlay: lead temperature / favorites / notes ── */
 .ovstar{color:#caa00a;font-size:19px;margin-right:5px;vertical-align:middle;line-height:1}
 .ovstar.on{color:#e8a90a} .ovstar.clickable{cursor:pointer}
 /* 1-5 lead rating (5 = hottest). Shared bg colors for the badge / chip. */
 .lead1{background:#3a78c2} .lead2{background:#3a9bb5} .lead3{background:#caa00a} .lead4{background:#e8730c} .lead5{background:#c0392b}
 .leadnum{display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;margin-left:6px;
   border-radius:5px;color:#fff;font:800 11px/1 var(--display);vertical-align:middle}
 .leadchip{display:inline-flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:7px;color:#fff;font:800 15px/1 var(--display)}
 .leadseg{display:inline-flex;border:1px solid var(--line);border-radius:8px;overflow:hidden;margin-top:3px}
 .leadbtn{border:0;border-left:1px solid var(--line);background:var(--panel);padding:7px 13px;font:inherit;font-size:13px;font-weight:700;color:var(--muted);cursor:pointer;transition:background .12s}
 .leadbtn:first-child{border-left:0} .leadbtn:hover{color:var(--ink)} .leadbtn.on{color:#fff}
 .leadbtn[data-v="1"].on{background:#3a78c2} .leadbtn[data-v="2"].on{background:#3a9bb5} .leadbtn[data-v="3"].on{background:#caa00a}
 .leadbtn[data-v="4"].on{background:#e8730c} .leadbtn[data-v="5"].on{background:#c0392b} .leadbtn.clr.on{background:var(--navy)}
 .inline-lead{width:54px;border:1px solid var(--line);border-radius:7px;padding:5px 6px;font:inherit;font-size:12px;font-weight:700;
   color:var(--ink);background:var(--panel);cursor:pointer}
 .inline-lead.lead1{background:#fde8e8;color:#8b1a1a;border-color:#f3b7b7}
 .inline-lead.lead2{background:#f8c7c7;color:#8b1a1a;border-color:#ec9292}
 .inline-lead.lead3{background:#ef8f8f;color:#5f1111;border-color:#df6868}
 .inline-lead.lead4{background:#dd4d4d;color:#fff;border-color:#c93434}
 .inline-lead.lead5{background:#b91f2c;color:#fff;border-color:#9f1722}
 .inline-lead option{color:var(--ink);background:var(--panel)}
 .inline-lead:focus{outline:2px solid var(--navy);outline-offset:-1px;border-color:transparent}
 .inline-lead[disabled]{cursor:default;opacity:.7}
 .leadcell{width:64px;min-width:64px;text-align:center}
 .ovrow{display:flex;align-items:center;gap:10px;margin-top:9px;flex-wrap:wrap}
 .ovstarbtn{border:1px solid var(--line);background:var(--panel);border-radius:8px;padding:6px 11px;font:inherit;font-size:12px;font-weight:650;color:var(--muted);cursor:pointer}
 .ovstarbtn.on{background:#fbf3d0;color:#9a7b06;border-color:#e8d68a}
 .ovby{font-size:11px;color:var(--muted)}
 .ovnote{width:100%;min-height:62px;border:1px solid var(--line);border-radius:8px;padding:7px 9px;font:inherit;font-size:12.5px;
   color:var(--ink);background:var(--panel);resize:vertical;margin-top:5px}
 .ovnote:focus{outline:2px solid var(--navy);outline-offset:-1px;border-color:transparent}
 #coachSel{padding:6px 9px;border:1px solid var(--line);border-radius:8px;font:inherit;font-size:12px;color:var(--ink);background:var(--panel);cursor:pointer}
 .ovblock .pc-k{margin-top:0}
</style></head><body>
<header><div class="mast">
  <img class="crest" src="data:image/png;base64,/*LOGO*/" alt="USD Toreros">
  <div class="id">
    <div class="ey">University of San Diego Baseball</div>
    <h1>Toreros Portal Hot Board</h1>
    <div class="sub">Fit-ranked transfer targets, with San Diego and California ties surfaced from the live database.</div>
  </div>
  <div class="meta">
    <span class="chip2">2026 DI Window · <b>Jun 1&ndash;30</b></span>
    <span class="chip2">Updated <b>/*GEN*/</b></span>
  </div>
</div></header>
<div class="wrap">
 <div class="stats" id="stats"></div>
 <div class="tabs"><button data-t="hit" class="on">Hitters</button><button data-t="pit">Pitchers</button><button data-t="ars">Arsenal · per pitch</button></div>
 <div class="ctl">
   <input type="text" id="q" placeholder="filter name, school, hometown…">
   <span class="grp"><span class="lbl">Tie</span>
     <span class="seg" id="prox">
       <button data-v="any" class="on">Any</button><button data-v="ca">CA</button><button data-v="socal">SoCal</button><button data-v="sd">SD</button>
     </span></span>
   <span class="grp"><span class="lbl">Ours</span>
     <span class="chips"><button class="chip" id="usdChip">USD only</button></span></span>
   <span class="grp ovctl" style="display:none"><span class="lbl">Lead</span>
     <span class="seg" id="leadSeg">
       <button data-v="any" class="on">Any</button><button data-v="5">5</button><button data-v="4">4</button><button data-v="3">3</button><button data-v="2">2</button><button data-v="1">1</button>
     </span></span>
   <span class="grp ovctl" style="display:none"><span class="lbl">Fav</span>
     <span class="chips"><button class="chip" id="favChip">★ only</button></span></span>
   <span class="grp" id="coachGrp" style="display:none"><span class="lbl">You</span>
     <select id="coachSel"><option value="">— pick your name —</option></select></span>
   <span class="grp" id="splitGrp"><span class="lbl">Split</span>
     <span class="seg" id="splitSeg">
       <button data-v="all" class="on">All</button><button data-v="vlhp">vs LHP</button><button data-v="vrhp">vs RHP</button>
     </span></span>
   <span class="grp" id="yrGrp"><span class="lbl">Yr</span>
     <span class="chips" id="yrChips">
       <button class="chip" data-v="FR">FR</button><button class="chip" data-v="SO">SO</button><button class="chip" data-v="JR">JR</button><button class="chip" data-v="SR">SR</button><button class="chip" data-v="GR">GR</button>
     </span></span>
   <span class="grp"><span class="lbl" id="posLbl">POS</span><select id="posSel"><option value="">All</option></select></span>
   <span class="grp"><span class="lbl">Lvl</span><select id="lvlSel"><option value="">All</option><option>D1</option><option>D2</option><option>D3</option><option>NAIA</option><option>JUCO</option></select></span>
   <span class="div"></span>
   <span class="fl">Rating ≥ <input type="number" class="num" id="minFit" min="0" max="100" step="1"></span>
   <span class="fl">Get% ≥ <input type="number" class="num" id="minLik" min="0" max="100" step="1"></span>
   <span class="fl"><span id="sampLbl">PA</span> ≥ <input type="number" class="num" id="minSamp" min="0" step="1"></span>
   <button class="reset" id="reset">Reset</button>
   <button class="exp" id="exportBtn" title="Download the selected players (or the whole filtered view) as CSV — the active filters are written at the top of the file">Export</button>
   <label><input type="checkbox" id="allcols" checked> all columns</label>
   <span class="sp"></span><span class="cnt" id="count"></span>
 </div>
 <details class="method"><summary>How Rating &amp; Get% are scored</summary>
   <div class="methbody">
     <p><b>Rating</b> is the 20&ndash;80 scouting scale you already use. 50 is an average college player,
        60 is above-average, 70 is elite, and 80 is the best in the country. We grade against all of
        college, not just the portal. For hitters it leans <b>heavily on wRC+</b> (one park- and
        league-adjusted number for total offense) whenever we have it, backed by xwOBA, wOBA, slugging
        and expected slugging, exit velo and barrel rate; hitters without a wRC+ use those advanced
        metrics alone. For pitchers, Stuff+, perceived value, K/BB, FIP, opponent slugging, and in-zone
        and expected whiff rate. We then adjust for the level he faced and his class year, giving favor
        toward older/grad transfers.</p>
     <p><b>Hit</b>, <b>Power</b> and <b>Speed</b> use the same 20&ndash;80 scale, but each is graded against other
        players at his position. <b>Hit</b> is contact and strike-zone control: batting average, expected BA,
        on-base, zone-contact %, swinging-strike %, strikeout % and chase %. <b>Power</b> is slugging and
        expected slugging, average and peak exit velo, hard-hit % and barrel %. <b>Speed</b> is base-running:
        stolen bases and triples per game (the only speed signals we have, no 60 times). Speed is blank
        when a player has no box-score line yet, and pitchers don't get tool grades.</p>
     <p><b>Split</b> (hitters only): All / vs LHP / vs RHP. Only the 6-4-3 rate &amp; quality stats have
        platoon lines, so <b>only those change</b> with the toggle: the metric columns in the
        <b>Hit</b>, <b>Power</b>, <b>Batted ball</b> and <b>Discipline</b> sections. Everything else
        <b>stays full-season</b>: Rating, Get%, the tool grades, bio, the whole <b>Box score</b> section
        (incl. SB and 3B), and the season value rates.</p>
     <p><b>Get%</b> is our likelihood of landing a player. It starts low, with local kids (San Diego,
        SoCal, California) being more likely, as well as players from worse schools. Players unlikely to
        look at the WCC based on value get penalized.</p>
   </div>
 </details>
 <section class="player-card" id="playerCard" aria-live="polite"></section>
 <div class="tbl-wrap"><table id="tbl"><thead></thead><tbody></tbody></table></div>
 <div class="seclbl">Geographic view · hometown to school</div>
 <div id="map"></div>
 <div class="maprow">
   <span class="note">Each player sits at their <b>hometown</b> (filled) and <b>school</b> (ring); click a marker to trace the line between them. Hollow/faint markers are placed at state level (approximate).</span>
   <span class="toggles">
     <label><input type="checkbox" id="mTargets" checked> Targets only (CA)</label>
     <label><input type="checkbox" id="mHome" checked> Hometowns</label>
     <label><input type="checkbox" id="mSchool"> Schools</label>
   </span>
 </div>
 <div class="ftnote" id="ft"></div>
 <footer class="brandfoot"><b>University of San Diego Baseball</b> · Toreros · internal scouting instrument. Not for redistribution.</footer>
</div>
<script>
const D=/*DATA*/;
function esc(v){return String(v==null?"":v).replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[m]));}
// ── coach overlay: lead temperature / favorites / notes ──────────────────────
// OV.backend: "supabase" (edit on the board, shared+live via PostgREST) | "sheet"
// (read-only here; coaches edit a linked Google Sheet) | "none" (overlay off).
const OV=/*OVERLAY*/;
let ovData=(OV&&OV.data)||{}, ovBackend=(OV&&OV.backend)||"none";
let ovEditable=(ovBackend=="supabase"), ovSB=(OV&&OV.supabase)||null, ovCoach="";
let leadFilter="any", favOnly=false;
function ovEnabled(){return ovBackend=="supabase"||ovBackend=="sheet";}
function cleanTemp(v){v=String(v==null?"":v).trim();return /^[1-5]$/.test(v)?v:null;}  // lead rating 1-5 (5=hot)
function ovOf(pid){return ovData[String(pid)]||null;}
function ovEnsure(pid){pid=String(pid); if(!ovData[pid])ovData[pid]={temp:null,fav:0,by:null,at:null,notes:{}};
  if(!ovData[pid].notes)ovData[pid].notes={}; return ovData[pid];}
// inline indicators rendered into the frozen Name cell
function ovStar(pid){if(!ovEnabled())return ""; const o=ovOf(pid), on=o&&o.fav;
  if(ovEditable)return `<span class="ovstar clickable${on?' on':''}" title="Favorite" onclick="ovStarClick(event,'${pid}')">${on?'★':'☆'}</span>`;
  return on?`<span class="ovstar on" title="Favorite">★</span>`:"";}
function ovTempDot(pid){if(!ovEnabled())return ""; const o=ovOf(pid); return (o&&o.temp)?`<span class="leadnum lead${o.temp}" title="Lead ${o.temp}/5">${o.temp}</span>`:"";}
function ovInlineLead(pid){if(!ovEnabled())return ""; const o=ovOf(pid), val=(o&&o.temp)||"";
  if(!ovEditable)return val?`<span class="leadchip lead${val}" title="Lead ${val}/5">${val}</span>`:"";
  const opts=["","5","4","3","2","1"].map(x=>`<option value="${x}"${val==x?" selected":""}>${x||"—"}</option>`).join("");
  return `<select class="inline-lead${val?` lead${val}`:""}" data-pid="${pid}" title="Lead rating" onclick="event.stopPropagation()" onfocus="event.stopPropagation();${ovCoach?"":"ensureCoach();this.blur();"}" onchange="event.stopPropagation();ovSetTemp('${pid}',this.value,false)">${opts}</select>`;}
function ovNotesText(pid,skipAuthor){const o=ovOf(pid); if(!o||!o.notes)return "";
  return Object.entries(o.notes).filter(([a,b])=>a!==skipAuthor&&(b||"").trim()).map(([a,b])=>`${a}: ${b}`).join(" · ");}
function ovMineNote(pid){const o=ovOf(pid); return ovCoach&&o&&o.notes?(o.notes[ovCoach]||""):"";}
function ovInlineNotes(pid){if(!ovEnabled())return ""; const all=ovNotesText(pid);
  if(!ovEditable)return all?`<div class="inline-note-ro">${esc(all)}</div>`:"";
  const mine=ovMineNote(pid), other=ovNotesText(pid,ovCoach), ph=ovCoach?"Your note":"Pick your name above to add a note";
  return `<textarea class="inline-note" rows="1" data-pid="${pid}" placeholder="${esc(ph)}"${ovCoach?"":" readonly"} onclick="event.stopPropagation()" onfocus="event.stopPropagation();${ovCoach?"":"ensureCoach();this.blur();"}" onkeydown="event.stopPropagation()" oninput="autoGrowNote(this)" onchange="event.stopPropagation();ovSaveInlineNote('${pid}',this)">${esc(mine)}</textarea>${other?`<div class="inline-note-all">${esc(other)}</div>`:""}`;}
function autoGrowNote(ta){ta.style.height="31px"; ta.style.height=Math.max(31,ta.scrollHeight)+"px";}
// ── coach name picker (attribution without a login) ──
function setupCoach(coaches){const sel=document.getElementById("coachSel");
  (coaches||[]).forEach(c=>{const o=document.createElement("option");o.value=c;o.textContent=c;sel.appendChild(o);});
  ovCoach=localStorage.getItem("usd_board_coach")||""; sel.value=ovCoach;
  sel.addEventListener("change",()=>{ovCoach=sel.value;localStorage.setItem("usd_board_coach",ovCoach);
    render(); if(selectedPid)showCard(findPlayer(selectedPid));});
  render();}
function ensureCoach(){if(!ovEditable)return false;
  if(!ovCoach){const g=document.getElementById("coachGrp");g.style.outline="2px solid #c0392b";
    setTimeout(()=>g.style.outline="",1600); document.getElementById("coachSel").focus(); return false;}
  return true;}
// ── edits (optimistic local update + persist + repaint) ──
function ovSetTemp(pid,t,updateCard=true){if(!ensureCoach())return; const o=ovEnsure(pid);
  o.temp=cleanTemp(t); o.by=ovCoach; o.at=new Date().toISOString(); persistOverlay(pid); render(); if(updateCard)showCard(findPlayer(pid));}
function ovStarClick(ev,pid){ev.stopPropagation(); if(!ensureCoach())return; const o=ovEnsure(pid);
  o.fav=o.fav?0:1; o.by=ovCoach; o.at=new Date().toISOString(); persistOverlay(pid); render();
  if(String(selectedPid)==String(pid))showCard(findPlayer(pid));}
function ovSaveNote(pid){if(!ovCoach)return; const ta=document.getElementById("ovnote"); if(!ta)return;
  const o=ovEnsure(pid), body=ta.value.trim(); o.notes[ovCoach]=body; persistNote(pid,ovCoach,body);}
function ovSaveInlineNote(pid,ta){if(!ensureCoach())return; const o=ovEnsure(pid), body=ta.value.trim();
  o.notes[ovCoach]=body; o.by=ovCoach; o.at=new Date().toISOString(); persistNote(pid,ovCoach,body);
  render();}
// ── Supabase PostgREST (no client lib; anon key gated by row-level security) ──
function sbHeaders(write){const h={apikey:ovSB.anonKey,Authorization:"Bearer "+ovSB.anonKey};
  if(write){h["Content-Type"]="application/json"; h["Prefer"]="resolution=merge-duplicates,return=minimal";} return h;}
function persistOverlay(pid){if(ovBackend!="supabase"||!ovSB)return; const o=ovEnsure(pid);
  fetch(ovSB.url+"/rest/v1/"+ovSB.overlayTable,{method:"POST",headers:sbHeaders(true),
    body:JSON.stringify({player_id:Number(pid),lead_temp:o.temp||null,favorite:!!o.fav,
      updated_by:ovCoach||null,updated_at:new Date().toISOString()})}).catch(e=>console.warn("overlay save failed",e));}
function persistNote(pid,author,body){if(ovBackend!="supabase"||!ovSB)return;
  fetch(ovSB.url+"/rest/v1/"+ovSB.notesTable,{method:"POST",headers:sbHeaders(true),
    body:JSON.stringify({player_id:Number(pid),author:author,body:body,
      updated_at:new Date().toISOString()})}).catch(e=>console.warn("note save failed",e));}
function sbFetch(){if(!ovSB)return;
  Promise.all([
    fetch(ovSB.url+"/rest/v1/"+ovSB.overlayTable+"?select=*",{headers:sbHeaders(false)}).then(r=>r.ok?r.json():[]),
    fetch(ovSB.url+"/rest/v1/"+ovSB.notesTable+"?select=*",{headers:sbHeaders(false)}).then(r=>r.ok?r.json():[])
  ]).then(([ovr,nts])=>{const m={};
    (ovr||[]).forEach(x=>{const p=String(x.player_id); m[p]={temp:cleanTemp(x.lead_temp),fav:x.favorite?1:0,by:x.updated_by,at:x.updated_at,notes:{}};});
    (nts||[]).forEach(x=>{const p=String(x.player_id), b=String(x.body||"").trim(); if(!b)return;
      m[p]=m[p]||{temp:null,fav:0,by:null,at:null,notes:{}}; m[p].notes=m[p].notes||{}; m[p].notes[x.author]=b;});
    ovData=m; const ae=document.activeElement, editing=ae&&(ae.id=="ovnote"||ae.classList.contains("inline-note")||ae.classList.contains("inline-lead"));
    if(!editing)render();
    if(selectedPid&&!editing)showCard(findPlayer(selectedPid));  // don't clobber an inline edit in progress
  }).catch(e=>console.warn("overlay fetch failed",e));}
// detail-card block: editable controls (supabase) or read-only display (sheet)
function ovCardBlock(row){if(!ovEnabled())return ""; const pid=String(row.pid), o=ovOf(pid)||{temp:null,fav:0,notes:{}};
  if(ovEditable){
    const seg=["5","4","3","2","1"].map(t=>`<button class="leadbtn${o.temp==t?' on':''}" data-v="${t}" onclick="ovSetTemp('${pid}','${t}')">${t}</button>`).join("")
      +`<button class="leadbtn clr${!o.temp?' on':''}" data-v="clr" onclick="ovSetTemp('${pid}','')" title="Clear">—</button>`;
    const star=`<button class="ovstarbtn${o.fav?' on':''}" onclick="ovStarClick(event,'${pid}')">${o.fav?'★ Favorited':'☆ Favorite'}</button>`;
    const mine=ovCoach?((o.notes&&o.notes[ovCoach])||""):"";
    const noteBox=ovCoach
      ?`<textarea class="ovnote" id="ovnote" placeholder="Your note…" onchange="ovSaveNote('${pid}')">${esc(mine)}</textarea>`
      :`<div class="pc-empty">Pick your name (top of the page) to add a note.</div>`;
    const others=Object.entries(o.notes||{}).filter(([a])=>a!=ovCoach&&((o.notes||{})[a]||"").trim())
      .map(([a,b])=>`<li><b>${esc(a)}</b>: ${esc(b)}</li>`).join("");
    return `<div class="pc-block ovblock"><div class="pc-k">Lead rating &middot; 5 = hot</div>
      <div class="leadseg">${seg}</div>
      <div class="ovrow">${star}${o.by?`<span class="ovby">last set by ${esc(o.by)}</span>`:""}</div>
      <div class="pc-k" style="margin-top:11px">Notes</div>${noteBox}
      ${others?`<ul class="pc-list" style="margin-top:7px">${others}</ul>`:""}</div>`;
  }
  const chip=o.temp?`<span class="leadchip lead${o.temp}">${o.temp}</span>`:`<span class="pc-empty">No lead set</span>`;
  const star=o.fav?`<span class="ovstar on">★ Favorite</span>`:"";
  const notes=Object.entries(o.notes||{}).filter(([,b])=>(b||"").trim()).map(([a,b])=>`<li><b>${esc(a)}</b>: ${esc(b)}</li>`).join("");
  return `<div class="pc-block ovblock"><div class="pc-k">Lead rating &middot; 5 = hot</div>
    <div class="ovrow">${chip} ${star}</div>
    <div class="pc-k" style="margin-top:11px">Notes</div>
    ${notes?`<ul class="pc-list">${notes}</ul>`:`<span class="pc-empty">No notes yet.</span>`}
    ${OV.sheetUrl?`<div style="margin-top:9px"><a href="${esc(OV.sheetUrl)}" target="_blank" rel="noopener">✎ Edit in the team sheet →</a></div>`:""}</div>`;}
function ovInit(){
  if(!ovEnabled())return;
  document.querySelectorAll(".ovctl").forEach(e=>e.style.display="");
  document.querySelectorAll("#leadSeg button").forEach(b=>b.onclick=()=>{
    document.querySelectorAll("#leadSeg button").forEach(x=>x.classList.remove("on")); b.classList.add("on");
    leadFilter=b.dataset.v; render();});
  document.getElementById("favChip").onclick=function(){favOnly=!favOnly; this.classList.toggle("on",favOnly); render();};
  if(ovBackend=="supabase"){document.getElementById("coachGrp").style.display="";
    setupCoach(OV.coaches); sbFetch(); setInterval(sbFetch,25000);}
}
// columns: [key, label, isText, isKey]
const COLS={
  hit:[["name","Name",1,1],["lead","Lead",1,1],["notes","Notes",1,1],["fit","Rating",0,1],["lik","Get%",0,1],["hitg","Hit",0,1],["powg","Pwr",0,1],["spdg","Spd",0,1],["school","From School",1,1],["lvl","Lvl",1,1],["pos","POS",1,1],["yr","Yr",1,1],["entered","Entered",1,1],["ht","Ht",1,1],["wt","Wt",1,1],["city","Hometown",1,1],["st","ST",1,1],
   ["pa","PA",0,1],["gp","GP"],["ab","AB"],["hits","H",0,1],["runs","R"],["rbi","RBI",0,1],["bb","BB",0,1],["so","SO",0,1],["sb","SB",0,1],["dbl","2B"],["tpl","3B"],["ops","OPS",0,1],
   ["ba","BA"],["xba","xBA"],["woba","wOBA"],["xwoba","xWOBA",0,1],["wrcp","wRC+",0,1],["wrc","wRC"],["wraa","wRAA"],["babip","BABIP"],
   ["xslg","xSLG"],["iso","ISO",0,1],["ev","AVG EV",0,1],["ev90","90EV"],["maxev","Max EV"],["hh","HardHit%",0,1],["barrel","Barrel%",0,1],["barrels","Brls"],
   ["la","LA"],["gb","GB%"],["fb","FB%"],["ld","LD%"],["pull","Pull%"],["swspot","SwSpot%"],["pupct","PU%"],["hrfb","HR/FB%"],["bbe","BBE"],
   ["bbp","BB%",0,1],["k","K%",0,1],["kbbr","K:BB"],["sw","Swing%"],["zsw","Z-Swing%"],["zcon","Z-Con%"],["chase","Chase%",0,1],["swstr","SwStr%"],["sdp","SD+",0,1],["decval","DecVal"]],
  pit:[["name","Name",1,1],["lead","Lead",1,1],["notes","Notes",1,1],["fit","Rating",0,1],["lik","Get%",0,1],["school","School",1,1],["lvl","Lvl",1,1],["t","T",1,1],["yr","Yr",1,1],["entered","Entered",1,1],["ht","Ht",1,1],["wt","Wt",1,1],["city","Hometown",1,1],["st","ST",1,1],
   ["ip","IP",0,1],["era","ERA",0,1],["wins","W"],["losses","L"],["sv","SV"],["kct","K",0,1],["fip","FIP"],["slg","SLG"],["kbb","K/BB",0,1],["pv","PV"],["stuff","Stuff+",0,1],
   ["velo","FB velo",0,1],["fbivb","FB iVB"],["fbhb","FB HB"],
   ["fbs","FB stuff+",0,1],["sis","SI stuff+"],["sls","SL stuff+",0,1],["cbs","CB stuff+"],["chs","CH stuff+"],["cts","CT stuff+"],
   ["hh","HH%"],["gb","GB%"],["strike","Strike%"],["miss","Miss%"],["izw","IZWhiff%",0,1],["chase","Chase%"],["xwh","xWhiff%"]],
  ars:[["name","Name",1,1],["lead","Lead",1,1],["notes","Notes",1,1],["fit","Rating",0,1],["lik","Get%",0,1],["school","School",1,1],["lvl","Lvl",1,1],["pitch","Pitch",1,1],["p","P",0,1],["bbe","BBE"],["barrels","Brls"],
   ["velo","Velo",0,1],["velo90","Velo90"],["maxv","Max"],["spin","Spin",0,1],["ivb","iVB",0,1],["hb","HB",0,1],["vaa","VAA"],["haa","HAA"],
   ["relh","RelHt"],["rels","RelS"],["ext","Ext"],["stuff","Stuff+",0,1],["loc","Loc+"],["xrv","xRV+",0,1],["anom","Anom+"],["tun","Tun+"],["pmd","PMD+"],
   ["ev","EV"],["hh","HH%"],["brl","Barrel%"],["ba","BA"],["xba","xBA"],["woba","wOBA"],["xwoba","xwOBA"],["sw","Swing%"],["zcon","Z-Con%"],["chase","Chase%",0,1],["whiff","Whiff%",0,1]]};
// Column section headers — a top band grouping the columns. name is "" (its own blank,
// sticky-left cell so it stays aligned with the frozen Name column on horizontal scroll).
const GROUP=(()=>{const g={hit:{},pit:{},ars:{}};
  const set=(t,label,keys)=>keys.split(" ").forEach(k=>g[t][k]=label);
  set("hit","Fit","fit lik"); set("hit","Tool grades","hitg powg spdg"); g.hit.name="Player"; set("hit","Coach","lead notes");
  set("hit","Profile","school lvl pos yr entered ht wt city st");
  set("hit","Box score","pa gp ab hits runs rbi bb so sb dbl tpl ops");
  set("hit","Hit","ba xba woba xwoba wrcp wrc wraa babip");
  set("hit","Power","xslg iso ev ev90 maxev hh barrel barrels");
  set("hit","Batted ball","la gb fb ld pull swspot pupct hrfb bbe");
  set("hit","Discipline","bbp k kbbr sw zsw zcon chase swstr sdp decval");
  set("pit","Fit","fit lik"); g.pit.name="Player"; set("pit","Coach","lead notes");
  set("pit","Profile","school lvl t yr entered ht wt city st");
  set("pit","Performance","ip era wins losses sv kct fip slg kbb pv stuff");
  set("pit","Fastball shape","velo fbivb fbhb");
  set("pit","Pitch Stuff+","fbs sis sls cbs chs cts");
  set("pit","Contact / discipline","hh gb strike miss izw chase xwh");
  set("ars","Fit","fit lik"); g.ars.name="Player"; set("ars","Coach","lead notes");
  set("ars","Pitch","school lvl pitch");
  set("ars","Sample","p bbe barrels");
  set("ars","Shape","velo velo90 maxv spin ivb hb vaa haa relh rels ext");
  set("ars","6-4-3 models","stuff loc xrv anom tun pmd");
  set("ars","Outcomes","ev hh brl ba xba woba xwoba sw zcon chase whiff");
  return g;})();
// heatmap direction: default +1 (higher better, green high); flip to -1 for these per-tab "lower is better" keys
const LOWER={hit:new Set(["k","chase","swstr","gb","so","kbbr"]),
             pit:new Set(["fip","slg","hh","era","losses"]),
             ars:new Set(["ev","hh","brl","ba","xba","woba","xwoba","zcon","barrels"])};
const dirOf=(t,k)=>LOWER[t].has(k)?-1:1;
// contextual categorical filter + sample-size field, per tab: [key, label]
const CAT={hit:["pos","POS"],pit:["t","Throws"],ars:["pitch","Pitch"]};
const SAMP={hit:["pa","PA"],pit:["ip","IP"],ars:["p","Pitches"]};
let tab="hit", sortK="fit", sortDir=-1;
let prox="any", years=new Set(), posSel="", lvlSel="", splitMode="all", usdOnly=false;
let visibleRows=[], selectedPid=null;
const GEN="/*GEN*/";                 // build date (injected); used in the export preamble
let picked=new Set();                // pids checked for export (per-tab; cleared on tab switch)
// Columns that stay on the overall line when a platoon split is active (Rating/Get%/tool
// grades are computed on the full season; bio is identity). Everything else is a hitting
// stat that swaps to the vs-LHP / vs-RHP line.
const SPLIT_FIXED=new Set(["fit","lik","hitg","powg","spdg","name","school","lvl","pos","yr","ht","wt","city","st",
  "entered","usd","gp","ab","hits","runs","rbi","bb","so","sb","dbl","tpl","ops","pupct","hrfb",
  "iso","babip","bbp","kbbr","wrc","wraa","wrcp"]);  // box-score / advanced = season totals (no split)
// Value of column k for row r under the active split (hitters only; falls back to the
// overall value when there's no split line or the column isn't split-aware).
function splitVal(r,k){
  if(tab=="hit"&&splitMode!="all"&&!SPLIT_FIXED.has(k)&&r.sp&&r.sp[splitMode]){
    const v=r.sp[splitMode][k]; return v===undefined?null:v;
  }
  return r[k];
}

function tiePill(r){
  return r.sd?'<span class="pill sd">SD</span>':(r.socal?'<span class="pill socal">SoCal</span>':(r.ca?'<span class="pill ca">CA</span>':''));
}
function playerTab(row){
  if(row.pitch!=null)return "ars";
  if(row.ip!=null||row.era!=null||row.kct!=null||row.t!=null)return "pit";
  return "hit";
}
function statValFor(t,row,k){
  if(t=="hit"&&splitMode!="all"&&!SPLIT_FIXED.has(k)&&row.sp&&row.sp[splitMode]){
    const v=row.sp[splitMode][k]; return v===undefined?null:v;
  }
  return row[k];
}
function statPct(t,k,v){
  if(typeof v!="number"||!isFinite(v))return null;
  const vals=D[t].map(r=>statValFor(t,r,k)).filter(x=>typeof x=="number"&&isFinite(x)).sort((a,b)=>a-b);
  if(vals.length<3)return null;
  let le=0; while(le<vals.length&&vals[le]<=v)le++;
  let p=Math.round(100*(le-.5)/vals.length);
  if(dirOf(t,k)<0)p=101-p;
  return Math.max(1,Math.min(99,p));
}
function pctChart(row){
  const t=playerTab(row), groups=[];
  let current="";
  COLS[t].forEach(c=>{
    const k=c[0]; if(c[2]||k=="lead")return;
    const v=statValFor(t,row,k); if(typeof v!="number"||!isFinite(v))return;
    const p=statPct(t,k,v); if(p==null)return;
    const g=(GROUP[t]||{})[k]||"Stats";
    if(g!==current){groups.push({name:g,items:[]}); current=g;}
    groups[groups.length-1].items.push({label:c[1],v,p});
  });
  const body=groups.filter(g=>g.items.length).map(g=>`<div class="pct-sec"><h3>${esc(g.name)}</h3>${
    g.items.map(x=>{const cls=x.p>=80?"good":(x.p>=60?"mid":""); return `<div class="pct-lbl" title="${esc(x.label)}">${esc(x.label)}</div>
      <div class="pct-bar"><div class="pct-fill ${cls}" style="width:${x.p}%"></div><span class="pct-badge" style="left:clamp(13px,${x.p}%,calc(100% - 13px))">${x.p}</span></div>
      <div class="pct-val">${fmt(x.v)}</div>`;}).join("")
  }</div>`).join("");
  return body?`<div class="pctchart"><div class="pct-head"><div class="pct-title"><b>Percentile Rankings</b><span>${esc(TABNAME[t]||"Player")} stats</span></div>
    <div class="pct-scale"><span><b>Poor</b><b>Average</b><b>Great</b></span></div></div>${body}</div>`:"";
}
function tieName(r){return r.sd?"San Diego":(r.socal?"SoCal":(r.ca?"California":"No local"));}
function sourceName(s){s=String(s||"").toLowerCase();
  if(s=="ncaa")return "NCAA roster"; if(s=="sidearm")return "Team site roster";
  if(s=="perfectgame")return "Perfect Game"; if(s=="pbr")return "PBR";
  if(s=="643")return "6-4-3"; if(s=="d1baseball")return "D1Baseball";
  if(s.startsWith("excel"))return "Excel import"; return s||"source";
}
function reasonText(reason,r){
  if(reason=="hometown=CA")return "Hometown state is California";
  if(reason=="prev_school=CA")return `Prior school is a CA/SD program: ${r.school||""}`;
  if(reason=="summer=CA league")return `Summer team points to a CA league: ${r.summer||""}`;
  if(reason=="HS in CA")return `High school is listed in California: ${r.hs||""}`;
  if(reason=="HS in SoCal")return `High school is listed in SoCal: ${r.hs||""}`;
  if(reason=="HS in SD County")return `High school is listed in San Diego County: ${r.hs||""}`;
  return reason.replace(/^hometown=/,"Hometown: ");
}
function uniqueLines(lines){
  const seen=new Set(), out=[];
  lines.forEach(x=>{const k=String(x||"").trim(); if(k&&!seen.has(k)){seen.add(k);out.push(k);}});
  return out;
}
function bioEvidence(r){
  const rows=D.bio[String(r.pid)]||[];
  return uniqueLines(rows.map(b=>{
    const home=[b.city,b.st].filter(Boolean).join(", ");
    const bits=[];
    if(home)bits.push(home);
    if(b.hs)bits.push(`HS ${b.hs}`);
    if(!bits.length)return "";
    const src=[sourceName(b.source),b.season,b.team?`(${b.team})`:"",b.source_file?`[${b.source_file}]`:""].filter(Boolean).join(" ");
    return `<b>${esc(src)}</b>: ${esc(bits.join(" · "))}`;
  })).slice(0,4);
}
function eventEvidence(r){
  const rows=D.events[String(r.pid)]||[];
  return uniqueLines(rows.map(e=>{
    if(!e.source&&!e.url)return "";
    const src=[sourceName(e.source),e.date].filter(Boolean).join(" ");
    const label=esc(src||e.url);
    return e.url?`<a href="${esc(e.url)}" target="_blank" rel="noopener">${label}</a>`:`${label}`;
  })).slice(0,3);
}
function findPlayer(pid){
  const s=String(pid);
  return [...D[tab],...D.hit,...D.pit,...D.ars].find(r=>String(r.pid)==s);
}
function paintSelection(){
  document.querySelectorAll("#tbl tbody tr").forEach(tr=>tr.classList.toggle("sel", String(tr.dataset.pid)==String(selectedPid)));
}
function showCard(row){
  if(!row)return;
  selectedPid=String(row.pid);
  const card=document.getElementById("playerCard");
  const rawReasons=String(row.tie_reasons||"").split(";").map(x=>x.trim()).filter(Boolean);
  const reasons=uniqueLines(rawReasons.map(x=>reasonText(x,row)));
  const bio=bioEvidence(row), events=eventEvidence(row);
  const role=row.pitch?"Pitch Arsenal":(D.pit.some(p=>String(p.pid)==String(row.pid))?"Pitcher":"Hitter");
  const playerLine=[row.pos||row.t||row.pitch||role,row.yr,row.ht,row.wt?`${row.wt} lb`:"",row.lvl].filter(Boolean).join(" · ");
  const usesBio=rawReasons.some(x=>x.startsWith("hometown=")||x.startsWith("HS "));
  const usesEvents=rawReasons.some(x=>x=="prev_school=CA");
  const srcLines=[...(usesBio?bio:[]), ...(usesEvents?events:[])];
  card.innerHTML=`<button class="pc-close" type="button" id="pcClose">Close</button>
    <div class="pc-head">
      <div class="pc-k">${esc(tieName(row))} tie ${tiePill(row)}</div>
      <div class="pc-name">${esc(row.name)}</div>
      <div class="pc-sub">${esc(row.school||"")} ${playerLine?`· ${esc(playerLine)}`:""}</div>
      <div class="pc-metrics"><span class="pc-metric"><b>${fmt(row.fit)}</b>Rating</span><span class="pc-metric"><b>${fmt(row.lik)}</b>Get%</span></div>
      <div class="pc-source">
        <div class="pc-k">Source behind it</div>
        <ul class="pc-list pc-src">${(srcLines.length?srcLines:[`<span class="pc-empty">No detailed source row loaded for this tie yet.</span>`]).map(x=>`<li>${x}</li>`).join("")}</ul>
      </div>
    </div>
    ${pctChart(row)}
    ${ovCardBlock(row)}
    <div class="pc-block">
      <div class="pc-k">Why local</div>
      <ul class="pc-list">${(reasons.length?reasons:["No CA/SoCal/SD reason stored yet."]).map(x=>`<li>${esc(x)}</li>`).join("")}</ul>
    </div>`;
  card.classList.add("on");
  document.getElementById("pcClose").onclick=()=>{selectedPid=null;card.classList.remove("on");card.innerHTML="";paintSelection();};
  paintSelection();
}

// ---- header stats ----
document.getElementById("stats").innerHTML=[
  ["hitters","Hitters","",],["pitchers","Pitchers",""],["usd","USD in portal","usd"],
  ["ca","California ties","ca"],["socal","SoCal ties","socal"],["sd","San Diego ties","sd"]]
  .map(([k,l,c])=>`<div class="stat"><b class="${c}">${D.sum[k]}</b><span>${l}</span></div>`).join("");

// ---- map ----
const map=L.map("map",{scrollWheelZoom:false}).setView([39.5,-98],4);
L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
  {maxZoom:12,subdomains:"abcd",attribution:"© OpenStreetMap, © CARTO"}).addTo(map);
const homeCluster=L.markerClusterGroup({maxClusterRadius:42,spiderfyOnMaxZoom:true,chunkedLoading:true});
const schoolLayer=L.layerGroup();
let selLine=null;
function tieColor(m){return m.sd?"#c0392b":(m.socal?"#e8730c":(m.ca?"#caa00a":"#5b6472"));}
function clearLine(){if(selLine){map.removeLayer(selLine);selLine=null;}}
function buildMap(){
  homeCluster.clearLayers(); schoolLayer.clearLayers(); clearLine();
  const targets=document.getElementById("mTargets").checked;
  D.map.forEach(m=>{
    if(targets && !m.ca) return;
    const c=tieColor(m);
    const home=m.p.find(p=>p.k=="home"), sch=m.p.find(p=>p.k=="school");
    const pop=`<b>${esc(m.n)}</b>${m.sd?'<span class="pill sd">SD</span>':(m.socal?'<span class="pill socal">SoCal</span>':(m.ca?'<span class="pill ca">CA</span>':''))}`
      +`<br>${m.r=="P"?"Pitcher":"Hitter"} · ${m.sc||""}<br>Home: ${m.h}<br>FIT ${m.f} · ${m.s}`;
    const drawLine=()=>{showCard(findPlayer(m.pid)); clearLine(); if(home&&sch){selLine=L.polyline([[home.lat,home.lon],[sch.lat,sch.lon]],
        {color:c,weight:1.5,opacity:.7,dashArray:"5 4"}).addTo(map);} };
    if(home){const mk=L.circleMarker([home.lat,home.lon],{radius:5,color:c,weight:home.ap?1:1.4,
        fillColor:c,fillOpacity:home.ap?0.25:0.78}).bindPopup(pop); mk.on("click",drawLine); homeCluster.addLayer(mk);}
    if(sch){const mk=L.circleMarker([sch.lat,sch.lon],{radius:4,color:c,weight:1.4,fillColor:c,fillOpacity:0}).bindPopup(pop);
        mk.on("click",drawLine); schoolLayer.addLayer(mk);}
  });
  document.getElementById("mHome").checked ? homeCluster.addTo(map) : map.removeLayer(homeCluster);
  document.getElementById("mSchool").checked ? schoolLayer.addTo(map) : map.removeLayer(schoolLayer);
}
const legend=L.control({position:"bottomright"});
legend.onAdd=function(){const d=L.DomUtil.create("div","legend");
  d.innerHTML=`<span class="k" style="background:var(--navy-deep);border:1.5px solid var(--torero)"></span><b>USD</b> home base<hr>`
   +`<span class="k" style="background:#c0392b"></span>San Diego tie<br>`
   +`<span class="k" style="background:#e8730c"></span>SoCal tie<br>`
   +`<span class="k" style="background:#caa00a"></span>California tie<br>`
   +`<span class="k" style="background:#5b6472"></span>Other<hr>`
   +`<span class="k" style="background:#5b6472"></span>hometown · <span class="k ring"></span>school<br>`
   +`<span style="color:#888">faint = approx (state-level)</span>`; return d;};
legend.addTo(map);
// USD home base — the recruiting anchor (Fowler Park, Alcalá Park, San Diego)
L.marker([32.7715,-117.1881],{zIndexOffset:1000,
  icon:L.divIcon({className:"usd-pin",html:'<div class="usd-badge">USD</div>',iconSize:[42,20],iconAnchor:[21,10]})})
  .bindPopup("<b>University of San Diego</b><br>Toreros · home base<br>Fowler Park, Alcalá Park").addTo(map);
["mTargets","mHome","mSchool"].forEach(id=>document.getElementById(id).addEventListener("change",buildMap));
buildMap(); setTimeout(()=>map.invalidateSize(),120);

// ---- tables + heatmap ----
function fmt(v){return v==null?"":(typeof v=="number"?(Number.isInteger(v)?v:v.toFixed(3).replace(/0+$/,"").replace(/\.$/,"")):v);}
function pct(arr,p){if(!arr.length)return null;const s=[...arr].sort((a,b)=>a-b);return s[Math.min(s.length-1,Math.max(0,Math.round(p*(s.length-1))))];}
function lerp(a,b,t){return a.map((x,i)=>Math.round(x+(b[i]-x)*t));}
const RED=[244,179,179],MID=[244,243,236],GRN=[176,221,186];
function heat(v,lo,hi,dir){if(v==null||lo==null||hi==null||hi<=lo)return"";let t=(v-lo)/(hi-lo);t=Math.max(0,Math.min(1,t));if(dir<0)t=1-t;
  const c=t<.5?lerp(RED,MID,t*2):lerp(MID,GRN,(t-.5)*2);return `background:rgb(${c[0]},${c[1]},${c[2]})`;}
// row comparator under the active sort + split (shared by render and export)
function cmp(a,b){let x=splitVal(a,sortK),y=splitVal(b,sortK); if(x==null)return 1; if(y==null)return -1;
  if(typeof x=="string")return sortDir*x.localeCompare(y); return sortDir*(x-y);}
// ── selection + export ───────────────────────────────────────────────────────
const TABNAME={hit:"Hitters",pit:"Pitchers",ars:"Arsenal (per pitch)"};
// keep the select-all box + export label in sync with the picked set and current view
function syncSel(){
  const vis=visibleRows.map(r=>String(r.pid));
  const inView=vis.filter(p=>picked.has(p)).length;
  const sa=document.getElementById("selAll");
  if(sa){sa.checked=vis.length>0&&inView===vis.length; sa.indeterminate=inView>0&&inView<vis.length;}
  document.querySelectorAll("#tbl tbody tr").forEach(tr=>tr.classList.toggle("picked",picked.has(String(tr.dataset.pid))));
  const btn=document.getElementById("exportBtn");
  btn.textContent=picked.size?("Export "+picked.size):("Export view ("+visibleRows.length+")");
}
// human-readable list of the filters currently in force — written atop the export
function filterSummary(){
  const p=[];
  const q=document.getElementById("q").value.trim(); if(q)p.push('Search="'+q+'"');
  if(prox!="any")p.push("Tie="+({ca:"California",socal:"SoCal",sd:"San Diego"}[prox]||prox));
  if(usdOnly)p.push("USD players only");
  if(tab!="ars"&&years.size)p.push("Class year="+[...years].join("/"));
  if(posSel)p.push(CAT[tab][1]+"="+posSel);
  if(lvlSel)p.push("Level="+lvlSel);
  const mf=document.getElementById("minFit").value; if(mf!=="")p.push("Rating ≥ "+mf);
  const ml=document.getElementById("minLik").value; if(ml!=="")p.push("Get% ≥ "+ml);
  const ms=document.getElementById("minSamp").value; if(ms!=="")p.push(SAMP[tab][1]+" ≥ "+ms);
  if(tab=="hit"&&splitMode!="all")p.push("Split="+(splitMode=="vlhp"?"vs LHP":"vs RHP"));
  if(ovEnabled()){if(leadFilter!="any")p.push("Lead="+leadFilter); if(favOnly)p.push("Favorites only");}
  if(!document.getElementById("allcols").checked)p.push("Key columns only");
  return p.length?p.join("; "):"none — all rows in this tab";
}
function csvCell(v){v=(v==null?"":String(v)); return /[",\n\r]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v;}
function download(name,text){const b=new Blob(["﻿"+text],{type:"text/csv;charset=utf-8"});
  const u=URL.createObjectURL(b),a=document.createElement("a");
  a.href=u; a.download=name; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(u);}
function exportCSV(){
  const cols=COLS[tab].filter(c=>(document.getElementById("allcols").checked||c[3])&&!((c[0]=="notes"||c[0]=="lead")&&!ovEnabled()));
  // picked players if any (across the tab, even if filtered out of view now); else the view
  let rows=picked.size?D[tab].filter(r=>picked.has(String(r.pid))):visibleRows.slice();
  rows.sort(cmp);
  const scope=picked.size?(picked.size+" selected player(s)"):("all "+rows.length+" players in the current view");
  const pre=[
    ["USD Toreros — Portal Hot Board export"],
    ["Generated", GEN],
    ["Tab", TABNAME[tab]],
    ["Active filters", filterSummary()],
    ["Rows exported", scope],
    [],
  ];
  const head=cols.map(c=>c[1]);
  const body=rows.map(r=>cols.map(c=>{
    const v=(c[0]=="name")?r.name:(c[0]=="lead")?((ovOf(r.pid)||{}).temp||""):(c[0]=="notes")?ovNotesText(r.pid):(c[0]=="lvl"?r.lvl:splitVal(r,c[0]));
    return fmt(v);
  }));
  const lines=pre.map(a=>a.map(csvCell).join(","))
    .concat([head.map(csvCell).join(",")], body.map(a=>a.map(csvCell).join(",")));
  download("usd-hotboard-"+tab+"-"+GEN.replace(/[ ,]+/g,"-")+".csv", lines.join("\r\n"));
}
document.getElementById("exportBtn").onclick=exportCSV;

function render(){
  const all=document.getElementById("allcols").checked;
  const cols=COLS[tab].filter(c=>(all||c[3])&&!((c[0]=="notes"||c[0]=="lead")&&!ovEnabled()));
  const q=document.getElementById("q").value.toLowerCase();
  const catKey=CAT[tab][0], sampKey=SAMP[tab][0];
  const minFit=parseFloat(document.getElementById("minFit").value);
  const minLik=parseFloat(document.getElementById("minLik").value);
  const minSamp=parseFloat(document.getElementById("minSamp").value);
  let rows=D[tab].filter(r=>{
    if(favOnly||leadFilter!="any"){const o=ovOf(r.pid);
      if(favOnly&&!(o&&o.fav))return false;
      if(leadFilter!="any"&&!(o&&o.temp==leadFilter))return false;}
    if(usdOnly&&!r.usd)return false;
    if(prox=="sd"&&!r.sd)return false;
    if(prox=="socal"&&!r.socal)return false;
    if(prox=="ca"&&!r.ca)return false;
    if(tab!="ars"&&years.size&&!years.has(r.yr))return false;
    if(posSel&&String(r[catKey]==null?"":r[catKey])!=posSel)return false;
    if(lvlSel&&r.lvl!=lvlSel)return false;
    if(!isNaN(minFit)&&!(r.fit>=minFit))return false;
    if(!isNaN(minLik)&&!(r.lik>=minLik))return false;
    if(!isNaN(minSamp)&&!(splitVal(r,sampKey)>=minSamp))return false;
    if(q){const s=`${r.name} ${r.school} ${r.city||""} ${r.st||""}`.toLowerCase(); if(!s.includes(q))return false;}
    return true;});
  rows.sort(cmp);
  visibleRows=rows;
  // per-column heat range (5th/95th pct of the filtered set) for every non-text column
  const rng={};
  cols.forEach(c=>{if(!c[2]){const v=rows.map(r=>splitVal(r,c[0])).filter(x=>typeof x=="number"); if(v.length)rng[c[0]]=[pct(v,.05),pct(v,.95)];}});
  // section header band: walk visible cols, span each run of same-group columns
  let gh="", gi=0;
  while(gi<cols.length){
    const key=cols[gi][0], g=(GROUP[tab]||{})[key]||"";
    let gj=gi+1; while(gj<cols.length && ((GROUP[tab]||{})[cols[gj][0]]||"")===g) gj++;
    const isNm=(gj-gi===1 && key==="name");
    gh+=`<th class="grp${isNm?' gnm':''}" colspan="${gj-gi}">${esc(g)}</th>`; gi=gj;
  }
  const colrow=cols.map((c,i)=>{
    const arrow=sortK==c[0]?(sortDir<0?" ▾":" ▴"):"";
    // select-all checkbox rides inside the frozen Name header (no extra column → no sticky reflow)
    if(c[0]=="name")return `<th class="l nm" data-k="name"><input type="checkbox" id="selAll" title="Select all in view" onclick="event.stopPropagation()">${c[1]}${arrow}</th>`;
    return `<th class="${c[2]?'l':''}${c[0]=="st"?' st':''}" data-k="${c[0]}">${c[1]}${arrow}</th>`;
  }).join("");
  document.querySelector("#tbl thead").innerHTML=`<tr class="grp-row">${gh}</tr><tr>${colrow}</tr>`;
  document.querySelector("#tbl tbody").innerHTML=rows.map((r,idx)=>`<tr data-i="${idx}" data-pid="${r.pid}" class="${String(r.pid)==String(selectedPid)?'sel':''}">`+cols.map((c,i)=>{
    let v=splitVal(r,c[0]), cls=c[2]?'l':'', sty='';
    if(c[0]=="name"){cls='nm'; v=`<span class="nmwrap"><input type="checkbox" class="rowsel" data-pid="${r.pid}"${picked.has(String(r.pid))?' checked':''} onclick="event.stopPropagation()">${ovStar(r.pid)}<span class="nmtxt">${esc(r.name)}</span>${tiePill(r)}</span>`;}
    else if(c[0]=="lead"){cls='leadcell'; v=ovInlineLead(r.pid);}
    else if(c[0]=="notes"){cls='l notescell'; v=ovInlineNotes(r.pid);}
    else if(c[0]=="st"){cls='st';}
    else if(c[0]=="city"){v=esc(r.city||'');}
    else{ if(rng[c[0]])sty=heat(v,rng[c[0]][0],rng[c[0]][1],dirOf(tab,c[0])); v=fmt(v);}
    return `<td class="${cls}" style="${sty}">${v==null?'':(c[2]&&c[0]!="name"&&c[0]!="city"&&c[0]!="notes"&&c[0]!="lead"?esc(v):v)}</td>`;}).join("")+"</tr>").join("");
  document.getElementById("count").textContent=rows.length+" rows";
  document.querySelectorAll("#tbl thead th[data-k]").forEach(th=>th.onclick=()=>{const k=th.dataset.k;
    if(sortK==k)sortDir*=-1; else{sortK=k;sortDir=(typeof (rows[0]||{})[k]=="string")?1:-1;} render();});
  document.querySelectorAll("#tbl tbody tr").forEach(tr=>tr.onclick=()=>showCard(visibleRows[Number(tr.dataset.i)]));
  document.querySelectorAll("#tbl tbody .inline-note").forEach(autoGrowNote);
  // selection: per-row checkboxes + the Name-header select-all (scoped to the current view)
  document.querySelectorAll("#tbl tbody .rowsel").forEach(cb=>cb.onchange=()=>{
    const p=String(cb.dataset.pid); if(cb.checked)picked.add(p); else picked.delete(p); syncSel();});
  const sa=document.getElementById("selAll");
  if(sa)sa.onchange=()=>{const vis=visibleRows.map(r=>String(r.pid));
    if(sa.checked)vis.forEach(p=>picked.add(p)); else vis.forEach(p=>picked.delete(p));
    document.querySelectorAll("#tbl tbody .rowsel").forEach(cb=>cb.checked=picked.has(String(cb.dataset.pid)));
    syncSel();};
  syncSel();
}
// contextual category select (POS / Throws / Pitch) + sample label, repopulated per tab
function populateCat(){
  const [key,label]=CAT[tab];
  document.getElementById("posLbl").textContent=label;
  document.getElementById("sampLbl").textContent=SAMP[tab][1];
  const vals=[...new Set(D[tab].map(r=>r[key]).filter(v=>v!=null&&v!==""))].map(String).sort();
  document.getElementById("posSel").innerHTML='<option value="">All</option>'+vals.map(v=>`<option value="${v}">${v}</option>`).join("");
  posSel="";
  document.getElementById("yrGrp").style.display=(tab=="ars")?"none":"";
  // platoon splits only exist for hitters; hide the toggle (and reset it) elsewhere
  document.getElementById("splitGrp").style.display=(tab=="hit")?"":"none";
  if(tab!="hit"){splitMode="all"; document.querySelectorAll("#splitSeg button").forEach((x,i)=>x.classList.toggle("on",i==0));}
}
// proximity segmented control (single-select; "at least this close")
document.querySelectorAll("#prox button").forEach(b=>b.onclick=()=>{
  document.querySelectorAll("#prox button").forEach(x=>x.classList.remove("on")); b.classList.add("on");
  prox=b.dataset.v; render();});
// "USD only" toggle — show just our own players who are in the portal
document.getElementById("usdChip").onclick=function(){usdOnly=!usdOnly; this.classList.toggle("on",usdOnly); render();};
// platoon-split segmented control (hitters; swaps stat columns to vs-LHP / vs-RHP)
document.querySelectorAll("#splitSeg button").forEach(b=>b.onclick=()=>{
  document.querySelectorAll("#splitSeg button").forEach(x=>x.classList.remove("on")); b.classList.add("on");
  splitMode=b.dataset.v; render();});
// class-year chips (multi-select)
document.querySelectorAll("#yrChips .chip").forEach(b=>b.onclick=()=>{
  const v=b.dataset.v; if(years.has(v)){years.delete(v);b.classList.remove("on");}else{years.add(v);b.classList.add("on");} render();});
document.getElementById("posSel").addEventListener("change",e=>{posSel=e.target.value;render();});
document.getElementById("lvlSel").addEventListener("change",e=>{lvlSel=e.target.value;render();});
["minFit","minLik","minSamp","q","allcols"].forEach(id=>document.getElementById(id).addEventListener("input",render));
document.getElementById("reset").onclick=()=>{
  ["q","minFit","minLik","minSamp"].forEach(id=>document.getElementById(id).value="");
  prox="any"; document.querySelectorAll("#prox button").forEach((x,i)=>x.classList.toggle("on",i==0));
  usdOnly=false; document.getElementById("usdChip").classList.remove("on");
  if(ovEnabled()){leadFilter="any"; document.querySelectorAll("#leadSeg button").forEach((x,i)=>x.classList.toggle("on",i==0));
    favOnly=false; document.getElementById("favChip").classList.remove("on");}
  years.clear(); document.querySelectorAll("#yrChips .chip").forEach(x=>x.classList.remove("on"));
  posSel=""; document.getElementById("posSel").value="";
  lvlSel=""; document.getElementById("lvlSel").value="";
  splitMode="all"; document.querySelectorAll("#splitSeg button").forEach((x,i)=>x.classList.toggle("on",i==0));
  picked.clear(); render();};
document.querySelectorAll(".tabs button").forEach(b=>b.onclick=()=>{
  document.querySelectorAll(".tabs button").forEach(x=>x.classList.remove("on")); b.classList.add("on");
  // selection columns differ per tab → scope the picks to one tab; clear on switch
  tab=b.dataset.t; picked.clear(); sortK=(tab=="ars")?"stuff":"fit"; sortDir=-1; populateCat(); render();});
document.getElementById("ft").textContent="Coverage is partial: ~"+D.sum.home+" players have a mapped hometown and school placement is state-level — an empty cell or missing dot is unknown data, not a true zero.";
populateCat(); render(); ovInit();
</script></body></html>"""


if __name__ == "__main__":
    main()
