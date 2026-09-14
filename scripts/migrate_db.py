"""Additive, non-destructive migration of db/baseball.db to the current schema.

Creates any missing tables (player_bio, pitch_arsenal, ...) via the schema's
`CREATE TABLE IF NOT EXISTS`, and ALTERs in any new columns on existing tables —
preserving all existing rows. Safe to run repeatedly.

Usage: python scripts/migrate_db.py
"""
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.db import now_iso  # noqa: E402

DB = ROOT / "db" / "baseball.db"
SCHEMA = ROOT / "db" / "schema.sql"

# Columns added to existing tables after their initial creation.
NEW_COLS = {
    "stats_hitting": [("xslg", "REAL"), ("decision_value", "REAL"), ("pitches", "INTEGER"),
                      ("max_ev", "REAL"), ("xba", "REAL"), ("swspot_pct", "REAL"), ("la", "REAL"),
                      ("fb_pct", "REAL"), ("ld_pct", "REAL"), ("swing_pct", "REAL"),
                      ("zswing_pct", "REAL"), ("sd_plus", "REAL"), ("barrels", "INTEGER"), ("bbe", "INTEGER"),
                      ("source_file", "TEXT"), ("observed_at", "TEXT"),
                      # D1Baseball box-score season totals
                      ("gp", "INTEGER"), ("ab", "INTEGER"), ("h", "INTEGER"), ("r", "INTEGER"),
                      ("rbi", "INTEGER"), ("bb", "INTEGER"), ("so", "INTEGER"), ("doubles", "INTEGER"),
                      ("triples", "INTEGER"), ("hbp", "INTEGER"), ("cs", "INTEGER"), ("ops", "REAL"),
                      ("pu_pct", "REAL"), ("hr_fb_pct", "REAL"),
                      ("bb_pct", "REAL"), ("k_bb_ratio", "REAL"), ("iso", "REAL"), ("babip", "REAL"),
                      ("wrc", "INTEGER"), ("wraa", "INTEGER"), ("wrc_plus", "INTEGER")],
    "stats_pitching": [("xwhiff_pct", "REAL"), ("pitches", "INTEGER"),
                       ("fb_velo", "REAL"), ("fb_ivb", "REAL"), ("fb_hb", "REAL"),
                       ("source_file", "TEXT"), ("observed_at", "TEXT"),
                       # D1Baseball box-score season totals
                       ("era", "REAL"), ("w", "INTEGER"), ("l", "INTEGER"), ("sv", "INTEGER"),
                       ("app", "INTEGER"), ("gs", "INTEGER"), ("cg", "INTEGER"), ("sho", "INTEGER"),
                       ("h", "INTEGER"), ("r", "INTEGER"), ("er", "INTEGER"), ("bb", "INTEGER"),
                       ("k", "INTEGER"), ("hbp", "INTEGER"), ("ba_against", "REAL")],
    "pitch_arsenal": [("source_file", "TEXT"), ("observed_at", "TEXT")],
    # geographic layer: canonical hometown + CA/San Diego tie flags on players,
    # per-season hometown landing columns on player_bio.
    "players": [("hometown_city", "TEXT"), ("hometown_state", "TEXT"),
                ("high_school", "TEXT"), ("height_in", "INTEGER"), ("weight_lb", "INTEGER"),
                ("ca_tie", "INTEGER DEFAULT 0"),
                ("socal_tie", "INTEGER DEFAULT 0"),
                ("sd_tie", "INTEGER DEFAULT 0"), ("ca_tie_reasons", "TEXT")],
    "player_bio": [("hometown_city", "TEXT"), ("hometown_state", "TEXT"),
                   ("high_school", "TEXT"), ("position", "TEXT")],
}


def main() -> None:
    if not DB.exists():
        raise SystemExit(f"{DB} not found — run `python run.py init` first")
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    # 1) Add new columns to PRE-EXISTING tables first, so schema indexes that
    #    reference them (e.g. idx_players_ca_tie) can be created below. Skip
    #    tables that don't exist yet — executescript creates those fresh with
    #    the new columns already in place.
    existing_tables = {r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    for tbl, cols in NEW_COLS.items():
        if tbl not in existing_tables:
            continue
        existing = {r[1] for r in con.execute(f"PRAGMA table_info({tbl})")}
        for col, typ in cols:
            if col not in existing:
                con.execute(f"ALTER TABLE {tbl} ADD COLUMN {col} {typ}")
                print(f"  + {tbl}.{col} {typ}")
    # 2) Create any missing tables + indexes (incl. ones on the new columns).
    con.executescript(SCHEMA.read_text(encoding="utf-8"))
    if "player_bio" in existing_tables:
        _backfill_bio_evidence(con)
    con.commit()
    tables = [r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    print("tables:", ", ".join(tables))
    con.close()


def _backfill_bio_evidence(con: sqlite3.Connection) -> None:
    """Seed granular evidence from existing canonical player_bio rows.

    Legacy rows do not know the original file/URL, but keeping them in the same
    evidence table preserves player/season/source/team/value provenance before
    future reloads add source_file-level citations.
    """
    existing = con.execute("SELECT COUNT(*) AS n FROM player_bio_evidence").fetchone()["n"]
    if existing:
        return
    now = now_iso()
    rows = con.execute(
        """SELECT id, player_id, season, source, team, height_in, weight_lb,
                  bats, throws, class_year, position, hometown_city,
                  hometown_state, high_school
           FROM player_bio"""
    ).fetchall()
    inserted = 0
    for r in rows:
        row_hash = f"legacy-player_bio:{r['id']}"
        cur = con.execute(
            """INSERT OR IGNORE INTO player_bio_evidence
               (player_id, season, source, source_file, observed_at, row_hash,
                team, height_in, weight_lb, bats, throws, class_year, position,
                hometown_city, hometown_state, high_school)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (r["player_id"], r["season"], r["source"] or "unknown",
             "legacy:player_bio", now, row_hash, r["team"], r["height_in"],
             r["weight_lb"], r["bats"], r["throws"], r["class_year"],
             r["position"], r["hometown_city"], r["hometown_state"],
             r["high_school"]),
        )
        inserted += cur.rowcount
    if inserted:
        print(f"  + player_bio_evidence backfill rows: {inserted}")


if __name__ == "__main__":
    main()
