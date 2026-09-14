"""Unit tests for the pure-logic pipeline pieces (no network)."""
import json
import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.enrich import HITTING_ALIASES, _build_map, detect_kind  # noqa: E402
from ncaa.portal.evaluate import _pos_matches, level_factor, normalize_pos  # noqa: E402
from ncaa.portal.resolve import Resolver  # noqa: E402
from ncaa.portal.sources.twitter import TwitterAdapter  # noqa: E402
from ncaa.portal.util import clean_str, eligibility_from_class, name_key, to_float, to_int  # noqa: E402


# ── util ─────────────────────────────────────────────────────────────────────
@pytest.mark.parametrize("a,b", [
    ("Jake Smith", "Jacob Smith"),          # nickname
    ("José Ramírez", "Jose Ramirez"),       # accents
    ("Smith, John", "John Smith"),          # order
    ("A.J. Puk Jr.", "AJ Puk"),             # punctuation + suffix
])
def test_name_key_equivalence(a, b):
    assert name_key(full=a) == name_key(full=b)


def test_name_key_distinguishes():
    assert name_key(full="John Smith") != name_key(full="Jane Smith")


@pytest.mark.parametrize("v,exp", [("0.371", 0.371), (".53", 0.53), ("12%", 12.0),
                                   ("-", None), ("nan", None), ("", None), (None, None)])
def test_to_float(v, exp):
    assert to_float(v) == exp


def test_to_int_and_clean():
    assert to_int("17.0") == 17
    assert clean_str("  Junior ") == "Junior"
    assert clean_str("N/A") is None
    assert eligibility_from_class("Junior") == 1
    assert eligibility_from_class("Sophomore") == 2


# ── resolve ──────────────────────────────────────────────────────────────────
@pytest.fixture
def con():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.execute("CREATE TABLE players (player_id INTEGER PRIMARY KEY, full_name TEXT, from_school TEXT)")
    c.executemany("INSERT INTO players (full_name, from_school) VALUES (?,?)",
                  [("Cider Canon", "Davidson College"),
                   ("Jack Gurevitch", "University of San Diego"),
                   ("John Smith", "Texas A&M")])
    c.commit()
    return c


def test_resolver_exact_and_fuzzy(con):
    r = Resolver(con)
    assert r.resolve("cider canon").reason == "exact-key"
    assert r.resolve("Cider Cannon", "Davidson").full_name == "Cider Canon"   # misspelled
    assert r.resolve("J. Gurevitch", "San Diego").full_name == "Jack Gurevitch"
    assert r.resolve("Totally Unknown Person", "Nowhere") is None


# ── enrich header auto-mapping ───────────────────────────────────────────────
def test_detect_kind():
    assert detect_kind(["Name", "IP", "FIP"]) == "pitching"
    assert detect_kind(["Name", "PA", "OBP", "SLG"]) == "hitting"
    assert detect_kind(["Player", "FB - stuff+"]) == "pitching"


def test_build_map_tolerates_spacing():
    cols = ["Player", "School", "PA", "AVG", "OBP", "HardHit %", "K %", "Chase%"]
    m = _build_map(cols, HITTING_ALIASES)
    assert m["ba"] == "AVG" and m["hardhit_pct"] == "HardHit %" and m["k_pct"] == "K %"


# ── evaluate scoring helpers ─────────────────────────────────────────────────
def test_level_factor_and_pos():
    assert level_factor("BBC", None) == 1.0
    assert level_factor("ND2", "II") == 0.80
    assert level_factor(None, "III") < level_factor(None, "I")
    assert _pos_matches("RHP", "RHP")
    assert _pos_matches("P", "RHP")        # pitcher need matches generic P
    assert _pos_matches("LHP", "P")
    assert not _pos_matches("C", "SS")
    assert normalize_pos("rhp") == "RHP"


# ── twitter parsing ──────────────────────────────────────────────────────────
def test_tweet_parse():
    ev = TwitterAdapter.parse_tweet("Cooper Walls has entered the transfer portal from Coastal Carolina.")
    assert ev and ev.player_name == "Cooper Walls" and ev.event_type == "ENTERED"
    assert ev.from_school.startswith("Coastal")
    assert TwitterAdapter.parse_tweet("nice weather today, great game") is None


# ── d3-dashboard client ──────────────────────────────────────────────────────
def test_d3_records_envelopes():
    from ncaa.portal.d3dashboard import D3DashboardClient as C
    assert len(C._records([{"a": 1}])) == 1
    assert len(C._records({"data": [{"a": 1}]})) == 1
    assert len(C._records({"players": [{"a": 1}, {"a": 2}]})) == 2
    assert C._records({"nope": 1}) == []


def test_d3_no_key_fails_fast():
    from ncaa.portal.d3dashboard import D3DashboardClient
    with pytest.raises(RuntimeError, match="API key"):
        D3DashboardClient().get("players")


def test_d3_map_record():
    from ncaa.portal.d3dashboard import _map_record
    rec = {"playerName": "Test Guy", "school": "USD", "PA": 100,
           "AVG": .350, "OBP": .450, "HardHitPct": .55, "KPct": .18}
    m = _map_record(rec, HITTING_ALIASES)
    assert m["__name__"] == "Test Guy" and m["team"] == "USD"
    assert m["ba"] == .350 and m["pa"] == 100 and m["hardhit_pct"] == .55


def test_d1b_stats_parse():
    from ncaa.portal.d1b_stats import parse_d1b_stats
    txt = "\n".join([
        "Subscribe Now", "Search",
        "Player\tTeam\tClass\tPOS\tBA\tOBP\tSLG\tOPS\tGP\tPA\tAB\tR\tH\t2B\t3B\tHR\tRBI\tHBP\tBB\tK\tSB\tCS",
        "Jack Cannon", "Le Moyne",
        "JR\tRF\t.439\t.504\t.699\t1.203\t47\t225\t196\t61\t86\t19\t1\t10\t64\t2\t25\t28\t51\t4",
        "Test Guy", "Florida A&#038;M",
        "SO\tCF\t.300\t.400\t.500\t.900\t50\t200\t180\t40\t54\t10\t2\t5\t30\t3\t15\t40\t12\t3",
    ])
    recs = parse_d1b_stats(txt)
    assert len(recs) == 2
    jc = recs[0]
    assert jc["__name__"] == "Jack Cannon" and jc["team"] == "Le Moyne"
    assert jc["ba"] == 0.439 and jc["h"] == 86 and jc["hr"] == 10 and jc["sb"] == 51
    assert jc["ops"] == 1.203 and jc["bb"] == 25 and jc["so"] == 28
    assert jc["doubles"] == 19 and jc["triples"] == 1 and jc["rbi"] == 64
    assert recs[1]["team"] == "Florida A&M"   # HTML entity unescaped


# ── trackman scoring (pure logic; models/network not required) ───────────────
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from ncaa.portal import trackman as tm  # noqa: E402


def test_pitch_flags_and_zone():
    df = pd.DataFrame({
        "pitchcall": ["StrikeSwinging", "StrikeCalled", "InPlay", "BallCalled", "FoulBall"],
        "platelocside": [0.0, 0.0, 0.0, 2.0, 0.0],
        "platelocheight": [2.5, 2.5, 2.5, 2.5, 0.5],
        "exitspeed": [None, None, 95.0, None, None],
    })
    f = tm._pitch_flags(df)
    assert list(f["whiff"]) == [True, False, False, False, False]
    assert list(f["swing"]) == [True, False, True, False, True]      # swing/inplay/foul
    assert list(f["strike"]) == [True, True, True, False, True]
    assert list(f["inzone"]) == [True, True, True, False, False]     # last is low/out


def test_scale_20_80_clamped():
    assert tm._scale_20_80(-0.0032, -0.0032, 0.0130) == 50.0          # at mean → 50
    assert tm._scale_20_80(99, 0, 0.01) == 80.0                       # clamps high
    assert tm._scale_20_80(-99, 0, 0.01) == 20.0                      # clamps low
    assert tm._scale_20_80(None, 0, 1) is None


def test_aggregate_pitching_maps_schema():
    scored = pd.DataFrame({
        "pitcher": ["A, B"] * 4,
        "autopitchtype": ["Four-Seam", "Four-Seam", "Slider", "Slider"],
        "pitchcall": ["StrikeSwinging", "InPlay", "BallCalled", "StrikeSwinging"],
        "platelocside": [0.0, 0.0, 2.0, 1.0],
        "platelocheight": [2.5, 2.5, 2.5, 1.0],
        "exitspeed": [None, 95.0, None, None],
        "angle": [None, 10.0, None, None],
        "stuff_plus": [110.0, 100.0, 90.0, 95.0],
        "xwhiff": [0.3, 0.1, 0.2, 0.25],
    })
    row = tm.aggregate_pitching(scored)[0]
    assert row["__name__"] == "A, B" and row["pitches"] == 4
    assert row["t2_stuff"] == 98.8                       # mean(110,100,90,95)
    assert row["fb_stuff"] == 105.0 and row["sl_stuff"] == 92.5
    assert row["inzone_whiff_pct"] == 50.0               # 1 of 2 in-zone swings
    assert row["chase_pct"] == 50.0                      # 1 of 2 out-of-zone pitches swung


def test_aggregate_hitting_maps_schema():
    scored = pd.DataFrame({
        "batter": ["X, Y"] * 3,
        "swing": [True, False, True],
        "contact": [True, False, True],
        "inzone": [True, True, False],
        "exitspeed": [100.0, None, 80.0],
        "angle": [28.0, None, -5.0],
        "direction": [0.0, 0.0, 0.0],
        "xslg": [0.8, None, 0.2],
        "decision_rv": [0.01, -0.02, 0.0],
        "korbb": ["", "Strikeout", ""],
        "batterside": ["Right", "Right", "Right"],
        "date": ["2025-03-01"] * 3, "pitcher": ["P"] * 3,
        "paofinning": [1, 1, 2], "inning": [1, 1, 1],
    })
    row = tm.aggregate_hitting(scored)[0]
    assert row["__name__"] == "X, Y" and row["pa"] == 2 and row["pitches"] == 3
    assert row["avg_ev"] == 90.0                         # mean(100,80)
    assert row["xslg"] == 0.5                            # mean over swings(0.8,0.2)
    assert row["k_pct"] == 50.0                          # 1 K / 2 PA


def test_enrich_trackman_disabled_is_skip():
    out = tm.enrich_from_trackman(None, {"enrichment": {"trackman": {"enabled": False}}})
    assert "skipped" in out


def test_perf_percentile_uses_available_metrics():
    from ncaa.portal.evaluate import _perf_percentile
    df = pd.DataFrame({
        "role": ["pitcher", "pitcher", "hitter", "hitter"],
        "t2_stuff": [110.0, 90.0, None, None],     # higher better
        "xslg": [None, None, 0.6, 0.3],
    })
    p = _perf_percentile(df)
    assert p.iloc[0] > p.iloc[1]                   # 110 Stuff+ ranks above 90
    assert p.iloc[2] > p.iloc[3]                   # .600 xSLG ranks above .300


def test_scale_20_80_population():
    from ncaa.portal.evaluate import _scale_20_80
    s = pd.Series(np.linspace(0.0, 100.0, 101))
    g = _scale_20_80(s)
    assert g.iloc[50] == 50.0                        # mean of a symmetric pool → 50
    assert g.is_monotonic_increasing                 # rank-preserving
    assert g.min() >= 20 and g.max() <= 80           # clamped to the scouting scale
    # reflects SDs: the value nearest +1 SD above the mean grades ≈ 60, -1 SD ≈ 40
    hi = (s - (s.mean() + s.std(ddof=0))).abs().idxmin()
    lo = (s - (s.mean() - s.std(ddof=0))).abs().idxmin()
    assert 57.0 <= g.iloc[hi] <= 63.0 and 37.0 <= g.iloc[lo] <= 43.0
    # degenerate pool → everyone average; all-missing stays ungraded
    assert (_scale_20_80(pd.Series([7.0, 7.0])) == 50.0).all()
    assert pd.isna(_scale_20_80(pd.Series([float("nan"), float("nan")])).iloc[0])


def test_rating_separates_by_level_of_competition():
    """Two hitters with IDENTICAL stats but different conferences must NOT tie —
    the SEC bat outrates the SWAC bat once conference strength drives the level term."""
    from ncaa.portal.evaluate import evaluate
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript((ROOT / "db" / "schema.sql").read_text())
    # spread players so the pool z-score isn't degenerate
    seed = [("Spread A", "Vanderbilt", 0.300), ("Spread B", "Vanderbilt", 0.350),
            ("Spread C", "Vanderbilt", 0.420),
            ("SEC Bat", "LSU", 0.380), ("SWAC Bat", "Alcorn State", 0.380)]
    for name, school, xwoba in seed:
        cur = con.execute(
            "INSERT INTO players (full_name, position, division, current_status, class_year, from_school)"
            " VALUES (?,?,?,?,?,?)", (name, "OF", "I", "ENTERED", "JR", school))
        con.execute(
            "INSERT INTO stats_hitting (player_id, season, pa, xwoba, source)"
            " VALUES (?,?,?,?,?)", (cur.lastrowid, "2026", 200, xwoba, "test"))
    con.commit()
    evaluate(con, {})
    r = dict(con.execute(
        """SELECT p.full_name, e.fit_score FROM evaluations e
           JOIN players p ON p.player_id=e.player_id""").fetchall())
    assert r["SEC Bat"] > r["SWAC Bat"]            # same stats, stronger league → higher rating


def test_usd_outbound_player_gets_no_local_tie_pull():
    """USD's OWN portal entrants must not be inflated by the San Diego 'pull toward USD'
    tie — a player leaving USD vs an identical UCSD player (same SD ties) should score a
    LOWER Likelihood, and carry the outbound_usd flag."""
    from ncaa.portal.evaluate import evaluate
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript((ROOT / "db" / "schema.sql").read_text())
    for name, school in [("Leaving USD", "San Diego"), ("Leaving UCSD", "UC San Diego")]:
        cur = con.execute(
            "INSERT INTO players (full_name, position, division, current_status, class_year,"
            " from_school, ca_tie, socal_tie, sd_tie) VALUES (?,?,?,?,?,?,1,1,1)",
            (name, "OF", "I", "ENTERED", "JR", school))
        con.execute("INSERT INTO stats_hitting (player_id, season, pa, xwoba, source)"
                    " VALUES (?,?,?,?,?)", (cur.lastrowid, "2026", 150, 0.350, "test"))
    con.commit()
    evaluate(con, {})
    comp = {r["full_name"]: json.loads(r["components"]) for r in con.execute(
        "SELECT p.full_name, e.components FROM evaluations e JOIN players p ON p.player_id=e.player_id")}
    assert comp["Leaving USD"]["outbound_usd"] == 1
    assert comp["Leaving UCSD"]["outbound_usd"] == 0
    # identical SD ties + stats, but USD's own departing player isn't "gettable home"
    assert comp["Leaving USD"]["likelihood"] < comp["Leaving UCSD"]["likelihood"]


def test_local_tie_is_performance_scaled():
    """A weak local player must not ride the hometown bonus to a high Get% — the applied
    tie scales with performance, so a strong local target gets more local pull than a weak
    one (same SD tie), and the weak one's Likelihood is lower."""
    from ncaa.portal.evaluate import evaluate
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript((ROOT / "db" / "schema.sql").read_text())
    # spread for a non-degenerate pool, plus two UCSD locals: one weak, one strong
    seed = [("Spread Lo", "Vanderbilt", 0.20, 0, 0, 0), ("Spread Mid", "Vanderbilt", 0.40, 0, 0, 0),
            ("Spread Hi", "Vanderbilt", 0.60, 0, 0, 0),
            ("Weak Local", "UC San Diego", 0.10, 1, 1, 1),
            ("Strong Local", "UC San Diego", 0.55, 1, 1, 1)]
    for name, school, xwoba, ca, socal, sd in seed:
        cur = con.execute(
            "INSERT INTO players (full_name, position, division, current_status, class_year,"
            " from_school, ca_tie, socal_tie, sd_tie) VALUES (?,?,?,?,?,?,?,?,?)",
            (name, "OF", "I", "ENTERED", "JR", school, ca, socal, sd))
        con.execute("INSERT INTO stats_hitting (player_id, season, pa, xwoba, source)"
                    " VALUES (?,?,?,?,?)", (cur.lastrowid, "2026", 150, xwoba, "test"))
    con.commit()
    evaluate(con, {})
    comp = {r["full_name"]: json.loads(r["components"]) for r in con.execute(
        "SELECT p.full_name, e.components FROM evaluations e JOIN players p ON p.player_id=e.player_id")}
    # the applied (scaled) tie is smaller for the weak local than the strong local
    assert comp["Weak Local"]["tie"] < comp["Strong Local"]["tie"]
    # and a perf≈0.1 local bat no longer reads as a strong Get
    assert comp["Weak Local"]["likelihood"] < 50.0


def test_winsorized_z_caps_junk():
    from ncaa.portal.evaluate import _winsorized_z
    # a tiny-sample junk line (e.g. a .999 wOBA over a few batted balls) is clipped to the
    # 99th-pctile bound, so it can't inflate the SD or earn an absurd z — without the clip
    # its z would be enormous; winsorized it lands just above the realistic top.
    base = list(np.linspace(0.25, 0.40, 99))         # realistic wOBA spread
    z = _winsorized_z(pd.Series(base + [9.99]))
    assert z.iloc[-1] == z.max() and z.max() < 5.0


def test_tool_grade_20_80():
    from ncaa.portal.evaluate import POWER_TOOL, _tool_grade
    # small pool (< POS_GROUP_MIN) → falls back to the whole-hitter pool
    sub = pd.DataFrame({"xslg": [0.7, 0.5, 0.3, 0.2], "avg_ev": [95.0, 90.0, 85.0, 80.0],
                        "position": ["OF", "OF", "OF", "OF"]})
    g = _tool_grade(sub, POWER_TOOL)               # uses the two present POWER metrics
    assert g.iloc[0] > g.iloc[3]                    # more power → higher grade
    assert g.between(20, 80).all()
    # no usable metric present → ungraded (pitchers, missing data)
    none = _tool_grade(pd.DataFrame({"unrelated": [1.0, 2.0], "position": ["OF", "OF"]}), POWER_TOOL)
    assert none.isna().all()


def test_tool_grade_is_position_relative():
    """A tool is graded against same-position peers: a SS with mid power outranks a 1B with
    the SAME raw line, because SS as a group hit for less power."""
    from ncaa.portal.evaluate import POS_GROUP_MIN, POWER_TOOL, _tool_grade
    n = POS_GROUP_MIN + 5
    rng = np.random.default_rng(0)
    ss = pd.DataFrame({"xslg": rng.normal(0.35, 0.03, n), "avg_ev": rng.normal(86, 2, n), "position": ["SS"] * n})
    fb = pd.DataFrame({"xslg": rng.normal(0.50, 0.03, n), "avg_ev": rng.normal(92, 2, n), "position": ["1B"] * n})
    ss.loc[0, ["xslg", "avg_ev"]] = [0.45, 90.0]   # elite power FOR A SHORTSTOP
    fb.loc[0, ["xslg", "avg_ev"]] = [0.45, 90.0]   # below-average power FOR A FIRST BASEMAN
    df = pd.concat([ss, fb], ignore_index=True)
    g = _tool_grade(df, POWER_TOOL)
    assert g.iloc[0] > g.iloc[n]                    # identical raw line, SS graded higher


def test_hit_tool_groups_average_contact_and_zone():
    """A strong BA/xBA line should not be dragged below average just because the source has
    several whiff/discipline columns but no OBP/K% line."""
    import numpy as np

    from ncaa.portal.evaluate import HIT_TOOL, POS_GROUP_MIN, _tool_grade

    n = POS_GROUP_MIN + 10
    rng = np.random.default_rng(4)
    df = pd.DataFrame({
        "position": ["DH"] * n,
        "ba": rng.normal(0.255, 0.025, n),
        "xba": rng.normal(0.255, 0.025, n),
        "zcon_pct": rng.normal(79, 4, n),
        "swstr_pct": rng.normal(27, 4, n),
        "chase_pct": rng.normal(30, 3, n),
    })
    # Hollis Porter-like shape: very strong average/xBA, poor whiff/contact.
    df.loc[0, ["ba", "xba", "zcon_pct", "swstr_pct", "chase_pct"]] = [0.309, 0.309, 73.2, 36.5, 33.7]
    g = _tool_grade(df, HIT_TOOL)
    assert g.iloc[0] > 50
