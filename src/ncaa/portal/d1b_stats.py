"""D1Baseball "National Statistics" box-score paste -> stats_hitting.

The 6-4-3 exports carry advanced/Stuff+ data but not box-score season totals (AB/H/R/RBI/
BB/K/SB...), and stats.ncaa.org is Akamai-walled. D1Baseball's National Statistics
leaderboard has the full box score and a logged-in subscriber can copy the rendered table
to a .txt — the same no-cookie paste path the transfer-tracker adapter uses.

The page copies as a flat run of lines; each hitter is three lines:

    Tanner Mally                                   <- player
    Western Michigan                               <- team
    JR<TAB>CF<TAB>.446<TAB>.554<TAB>...<TAB>6       <- Class, POS, then the 18 stat columns

stat columns (after Class, POS):
    BA OBP SLG OPS GP PA AB R H 2B 3B HR RBI HBP BB K SB CS

The leaderboard is all of D1, so by default we attach only players already in OUR portal
pool (current_status='ENTERED') — resolve each name+team, skip anyone not in the pool.
Upserts source='d1baseball' on UNIQUE(player_id, season, source); re-runs are idempotent.
"""
from __future__ import annotations

import html
import logging
import sqlite3

from .db import now_iso
from .resolve import Resolver
from .util import to_float, to_int

log = logging.getLogger(__name__)

CLASS_YEARS = {"FR", "SO", "JR", "SR", "GR"}
# batting stat columns, after the leading Class + POS cells; (schema_col, kind)
_HIT_COLS = [
    ("ba", "f"), ("obp", "f"), ("slg", "f"), ("ops", "f"), ("gp", "i"), ("pa", "i"),
    ("ab", "i"), ("r", "i"), ("h", "i"), ("doubles", "i"), ("triples", "i"), ("hr", "i"),
    ("rbi", "i"), ("hbp", "i"), ("bb", "i"), ("so", "i"), ("sb", "i"), ("cs", "i"),
]
# pitching stat columns, after the leading Class cell (NB: pitching has no POS column).
# Header: Class W L ERA APP GS CG SHO SV IP H R ER BB K HBP BA. No HR-allowed -> no FIP.
_PITCH_COLS = [
    ("w", "i"), ("l", "i"), ("era", "f"), ("app", "i"), ("gs", "i"), ("cg", "i"),
    ("sho", "i"), ("sv", "i"), ("ip", "f"), ("h", "i"), ("r", "i"), ("er", "i"),
    ("bb", "i"), ("k", "i"), ("hbp", "i"), ("ba_against", "f"),
]
# batted-ball view (NB: no POS column — lead is just Class). Header: Class GB% LD% FB% PU% HR/FB%.
_BBALL_COLS = [
    ("gb_pct", "f"), ("ld_pct", "f"), ("fb_pct", "f"), ("pu_pct", "f"), ("hr_fb_pct", "f"),
]
# advanced-batting view (lead = Class only). Header: Class K% BB% K:BB ISO BABIP wOBA wRC wRAA wRC+.
_ADVBAT_COLS = [
    ("k_pct", "f"), ("bb_pct", "f"), ("k_bb_ratio", "f"), ("iso", "f"), ("babip", "f"),
    ("woba", "f"), ("wrc", "i"), ("wraa", "i"), ("wrc_plus", "i"),
]

# kind -> (column spec, leading non-stat cells, target table). One D1Baseball export per view;
# rows are matched by EXACT cell count (batting=20, pitching=17, batted-ball=6, adv-batting=10)
# so the views never collide even when two tables share one paste.
_VIEWS = {
    "hitting":     (_HIT_COLS, 2, "stats_hitting"),
    "pitching":    (_PITCH_COLS, 1, "stats_pitching"),
    "batted_ball": (_BBALL_COLS, 1, "stats_hitting"),
    "adv_batting": (_ADVBAT_COLS, 1, "stats_hitting"),
}


def _parse(text: str, cols: list, lead: int) -> list[dict]:
    """Shared 3-line-record parser (name / team / Class<TAB>...stats). A stat row is matched
    by EXACT cell count = lead + len(cols) once trailing empties are dropped — robust across
    the standard-batting / pitching / batted-ball layouts (which differ in width) even when a
    single paste contains two tables."""
    lines = text.splitlines()
    out: list[dict] = []
    want = lead + len(cols)
    for j, ln in enumerate(lines):
        cells = ln.split("\t")
        while cells and cells[-1].strip() == "":   # drop trailing empty cells
            cells.pop()
        cells = [c.strip() for c in cells]
        if len(cells) != want or cells[0].upper() not in CLASS_YEARS:
            continue
        if j < 2 or "\t" in lines[j - 1] or "\t" in lines[j - 2]:
            continue  # name/team lines carry no tab; guard against misalignment
        name = html.unescape(lines[j - 2].strip())
        team = html.unescape(lines[j - 1].strip())
        if not name or not team:
            continue
        vals = cells[lead:]
        rec = {"__name__": name, "team": team}
        for idx, (col, kind) in enumerate(cols):
            rec[col] = (to_float if kind == "f" else to_int)(vals[idx])
        out.append(rec)
    return out


def parse_d1b_stats(text: str) -> list[dict]:
    """Parse the D1Baseball batting leaderboard paste into per-player stat dicts."""
    return _parse(text, _HIT_COLS, lead=2)


def parse_d1b_pitching(text: str) -> list[dict]:
    """Parse the D1Baseball pitching leaderboard paste into per-player stat dicts."""
    return _parse(text, _PITCH_COLS, lead=1)


def enrich_from_d1b_stats(con: sqlite3.Connection, paste_path: str, *,
                          season: str = "2026", kind: str = "hitting",
                          portal_only: bool = True, create_missing: bool = False) -> dict:
    """Ingest a D1Baseball box-score paste for the portal pool. kind='hitting' ->
    stats_hitting; kind='pitching' -> stats_pitching (and derive K/BB)."""
    try:
        with open(paste_path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except FileNotFoundError:
        return {"error": f"paste not found: {paste_path}"}
    if kind not in _VIEWS:
        return {"error": f"unknown kind '{kind}'; expected one of {sorted(_VIEWS)}"}
    cols, lead, table = _VIEWS[kind]
    recs = _parse(text, cols, lead)
    pitching = table == "stats_pitching"

    status = {r["player_id"]: r["current_status"]
              for r in con.execute("SELECT player_id, current_status FROM players")}
    resolver = Resolver(con)
    from .db import PlayerIndex
    idx = PlayerIndex(con) if create_missing else None

    totals = {"parsed": len(recs), "matched": 0, "skipped_non_portal": 0,
              "unmatched": 0, "rows": 0}
    now = now_iso()
    src_file = paste_path.replace("\\", "/").rsplit("/", 1)[-1]
    for rec in recs:
        name = rec.pop("__name__")
        team = rec.get("team")
        cand = resolver.resolve(name, team)
        if cand:
            pid = cand.player_id
            if portal_only and status.get(pid) != "ENTERED":
                totals["skipped_non_portal"] += 1
                continue
            totals["matched"] += 1
        elif create_missing and idx is not None:
            pid, _ = idx.get_or_create(full=name, defaults={"from_school": team})
        else:
            totals["unmatched"] += 1
            continue
        if pitching and rec.get("k") is not None and rec.get("bb"):  # derive K/BB
            rec["k_bb"] = round(rec["k"] / rec["bb"], 2)
        srow = {"player_id": pid, "season": str(season), "source": "d1baseball",
                "source_file": src_file, "observed_at": now,
                **{k: v for k, v in rec.items() if v is not None}}
        cols = list(srow)
        ph = ", ".join("?" for _ in cols)
        # MERGE, don't replace: standard / advanced / batted-ball are separate D1Baseball
        # views of the same (player, season, source) row, so each ingest must ADD its
        # columns without nulling the others. ON CONFLICT updates only the columns present.
        upd = ", ".join(f"{c}=excluded.{c}" for c in cols
                        if c not in ("player_id", "season", "source"))
        con.execute(f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({ph}) "
                    f"ON CONFLICT(player_id, season, source) DO UPDATE SET {upd}",
                    [srow[c] for c in cols])
        totals["rows"] += 1
    con.commit()
    return totals
