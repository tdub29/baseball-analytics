"""Seed the DB from the existing '2025 Transfer Portal Main Database.xlsx'.

Usage:
    python scripts/import_excel.py "C:\\path\\to\\2025 Transfer Portal Main Database.xlsx"
    python scripts/import_excel.py            # uses default Downloads path

Idempotent-ish: re-running merges players by normalized name and relies on the
UNIQUE constraints on stats/events to avoid dupes.
"""
from __future__ import annotations

import json
import sqlite3
import sys
import warnings
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.db import PlayerIndex, add_portal_event, connect, now_iso  # noqa: E402
from ncaa.portal.util import clean_str, eligibility_from_class, to_float, to_int  # noqa: E402

warnings.simplefilter("ignore")

DEFAULT_XLSX = Path.home() / "Downloads" / "2025 Transfer Portal Main Database.xlsx"
SEASON = "2025"


def _insert_stats(con: sqlite3.Connection, table: str, row: dict) -> bool:
    cols = [k for k, v in row.items() if v is not None]
    if not cols:
        return False
    ph = ", ".join("?" for _ in cols)
    try:
        con.execute(
            f"INSERT OR IGNORE INTO {table} ({', '.join(cols)}) VALUES ({ph})",
            [row[c] for c in cols],
        )
        return con.total_changes > 0
    except sqlite3.IntegrityError:
        return False


def import_names_notes(con, idx, xlsx) -> dict:
    df = pd.read_excel(xlsx, sheet_name="Names + Notes")
    note_cols = list(df.columns[list(df.columns).index("Notes") + 1:])  # scout columns
    players_new = events = calls = 0
    for _, r in df.iterrows():
        first, last = clean_str(r.get("First")), clean_str(r.get("Last"))
        if not first and not last:
            continue
        pid, created = idx.get_or_create(
            first=first, last=last,
            defaults={
                "position": clean_str(r.get("Pos")),
                "class_year": clean_str(r.get("Year")),
                "division": clean_str(r.get("Div")),
                "from_school": clean_str(r.get("School")),
                "summer_team": clean_str(r.get("Summer Team")),
                "eligibility_remaining": eligibility_from_class(r.get("Year")),
                "current_status": "ENTERED",
            },
        )
        players_new += created
        edate_parsed = pd.to_datetime(r.get("DATE"), errors="coerce")
        edate = str(edate_parsed.date()) if pd.notna(edate_parsed) else None
        if add_portal_event(con, player_id=pid, event_type="ENTERED",
                            source="excel:names+notes", event_date=edate):
            events += 1
        scout_notes = {c: clean_str(r.get(c)) for c in note_cols if clean_str(r.get(c))}
        if clean_str(r.get("Contact")) or clean_str(r.get("Notes")) or scout_notes \
           or clean_str(r.get("Priority")) is not None:
            con.execute(
                """INSERT INTO call_assignments
                     (player_id, assigned_date, priority, contact, notes, scout_notes, updated_at)
                   VALUES (?,?,?,?,?,?,?)""",
                (pid, edate, to_int(r.get("Priority")), clean_str(r.get("Contact")),
                 clean_str(r.get("Notes")),
                 json.dumps(scout_notes) if scout_notes else None, now_iso()),
            )
            calls += 1
    return {"players_new": players_new, "events": events, "calls": calls}


def import_pitchers(con, idx, xlsx) -> dict:
    df = pd.read_excel(xlsx, sheet_name="All Divisions Pitcher Data")
    new = stats = 0
    for _, r in df.iterrows():
        full = clean_str(r.get("playerFullName"))
        if not full:
            continue
        playerid = clean_str(r.get("playerid"))
        pid, created = idx.get_or_create(
            first=clean_str(r.get("playerFirstName")), last=clean_str(r.get("player")),
            full=full,
            defaults={
                "position": clean_str(r.get("pos")),
                "bats": clean_str(r.get("batsHand")),
                "throws": clean_str(r.get("throwsHand")),
                "current_status": None,        # stats universe; portal truth = Names+Notes
                "external_ids": {"trumedia": playerid} if playerid else None,
            },
        )
        new += created
        portal_flag = clean_str(r.get("Trumedia Portal Yes"))
        if portal_flag:
            add_portal_event(con, player_id=pid, event_type="ENTERED",
                             source="excel:pitcher-data", source_url=clean_str(r.get("Link")))
        srow = {
            "player_id": pid, "season": SEASON, "source": "excel:643",
            "team": clean_str(r.get("newestTeamName")),
            "level": clean_str(r.get("newestTeamLevel")),
            "ip": to_float(r.get("IP")), "fip": to_float(r.get("FIP")),
            "slg_against": to_float(r.get("SLG")), "k_bb": to_float(r.get("K/BB")),
            "perceived_value": to_float(r.get("Perceived Value")),
            "hardhit_pct": to_float(r.get("HardHit%")), "ground_pct": to_float(r.get("Ground%")),
            "strike_pct": to_float(r.get("Strike%")), "miss_pct": to_float(r.get("Miss%")),
            "inzone_whiff_pct": to_float(r.get("InZoneWhiff%")), "chase_pct": to_float(r.get("Chase%")),
            "t2_stuff": to_float(r.get("T2 Stuff")),
            "cb_stuff": to_float(r.get("CB - stuff+")), "ch_stuff": to_float(r.get("CH - stuff+")),
            "ct_stuff": to_float(r.get("CT - stuff+")), "fb_stuff": to_float(r.get("FB - stuff+")),
            "si_stuff": to_float(r.get("SI - stuff+")), "sl_stuff": to_float(r.get("SL - stuff+")),
            "cb_strike_pct": to_float(r.get("CB - strike%")), "ch_strike_pct": to_float(r.get("CH - strike%")),
            "ct_strike_pct": to_float(r.get("CT - strike%")), "fb_strike_pct": to_float(r.get("FB - strike%")),
            "si_strike_pct": to_float(r.get("SI - strike%")), "sl_strike_pct": to_float(r.get("SL - strike%")),
        }
        before = con.total_changes
        _insert_stats(con, "stats_pitching", srow)
        stats += con.total_changes - before
    return {"players_new": new, "stats_rows": stats}


def import_hitters(con, idx, xlsx) -> dict:
    df = pd.read_excel(xlsx, sheet_name="Hitter Hot Board Data")
    new = stats = 0
    for _, r in df.iterrows():
        full = clean_str(r.get("Name"))
        if not full:
            continue
        pid, created = idx.get_or_create(
            full=full,
            defaults={
                "position": clean_str(r.get("POS")), "bats": clean_str(r.get("B")),
                "throws": clean_str(r.get("T")), "current_status": None,
            },
        )
        new += created
        srow = {
            "player_id": pid, "season": SEASON, "source": "excel:643",
            "team": clean_str(r.get("Team")),
            "pa": to_int(r.get("PA")), "ba": to_float(r.get("BA")), "obp": to_float(r.get("OBP")),
            "slg": to_float(r.get("SLG")), "xwoba": to_float(r.get("xWOBA")), "woba": to_float(r.get("wOBA")),
            "hr": to_int(r.get("HR")), "sb": to_int(r.get("SB")),
            "avg_ev": to_float(r.get("AVG EV")), "ev90": to_float(r.get("90EV")),
            "hardhit_pct": to_float(r.get("HardHit%")), "barrel_pct": to_float(r.get("Barrel%")),
            "gb_pct": to_float(r.get("GB%")), "pull_pct": to_float(r.get("Pull%")),
            "k_pct": to_float(r.get("K%")), "zcon_pct": to_float(r.get("Z-Con%")),
            "chase_pct": to_float(r.get("Chase%")), "swstr_pct": to_float(r.get("SwStrk%")),
            "seager": to_float(r.get("SEAGER")),
        }
        before = con.total_changes
        _insert_stats(con, "stats_hitting", srow)
        stats += con.total_changes - before
    return {"players_new": new, "stats_rows": stats}


def import_roster(con, xlsx) -> dict:
    df = pd.read_excel(xlsx, sheet_name="RosterInfo")
    n = 0
    for _, r in df.iterrows():
        fn = clean_str(r.get("FULLNAME"))
        if not fn:
            continue
        con.execute(
            "INSERT INTO roster_info (full_name, pos_season_concat) VALUES (?,?)",
            (fn, clean_str(r.get("pos_season_concat"))),
        )
        n += 1
    return {"roster_rows": n}


def main() -> None:
    xlsx = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_XLSX
    if not xlsx.exists():
        sys.exit(f"workbook not found: {xlsx}")

    con = connect()
    try:
        idx = PlayerIndex(con)
        print("importing Names + Notes ...");           a = import_names_notes(con, idx, xlsx)
        print("importing All Divisions Pitcher Data ..."); b = import_pitchers(con, idx, xlsx)
        print("importing Hitter Hot Board Data ...");    c = import_hitters(con, idx, xlsx)
        print("importing RosterInfo ...");               d = import_roster(con, xlsx)
        con.commit()
    finally:
        con.close()

    con = connect()
    counts = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ["players", "portal_events", "call_assignments",
                        "stats_hitting", "stats_pitching", "roster_info"]}
    con.close()
    print("\n--- import summary (per stage) ---")
    for label, res in [("names+notes", a), ("pitchers", b), ("hitters", c), ("roster", d)]:
        print(f"  {label}: {res}")
    print("\n--- table totals ---")
    for k, v in counts.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
