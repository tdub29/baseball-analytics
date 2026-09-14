"""Coach-board interaction overlay: lead temperature / favorites / notes.

Coaches mark players **Hot / Warm / Cold**, star favorites, and leave notes on top of
the published hot board. Two interchangeable backends, chosen by `board_overlay.backend`
in config.yaml:

  - "supabase"  — coaches edit ON the board (in-page). The browser reads+writes Supabase
                  PostgREST directly (public anon key, gated by row-level security on just
                  the two overlay tables). This module reads the same tables back for the
                  round-trip into the pipeline DB. No login: writes carry a coach name the
                  user picked from a dropdown.
  - "sheet"     — coaches edit in a linked Google Sheet tab. This module pushes the player
                  list to that tab (`push_overlay_to_sheet`) and reads the edits back.
  - "none"/absent — overlay disabled; the board renders read-only exactly as before.

Everything round-trips into call_assignments (lead_temp, favorite, scout_notes), keyed by
the stable players.player_id that entity-resolution guarantees. So tomorrow's rebuild
re-attaches a coach's tags to the right player even as the stats refresh.

Contract shared by both backends and the HTML board (build_html.py embeds this):
    overlay[pid] = {
        "temp":  "hot" | "warm" | "cold" | None,
        "fav":   0 | 1,
        "by":    "<coach name>" | None,          # who last set temp/fav
        "at":    "<iso ts>" | None,
        "notes": { "<coach name>": "<body>", ... },   # per-coach, mirrors scout_notes JSON
    }
"""
from __future__ import annotations

import json
import logging
import sqlite3
from typing import Any

from .db import now_iso

log = logging.getLogger("portal.overlay")

LEAD_TEMPS = ("1", "2", "3", "4", "5")   # coach lead rating; 5 = hottest, 1 = coldest
# When a lead is tagged and no manual Priority exists yet, mirror it into priority so the
# legacy CRM ordering (1 = highest) stays sensible. We only fill a NULL priority — never
# clobber a manually set one.
LEAD_TO_PRIORITY = {"5": 1, "4": 2, "3": 3, "2": 4, "1": 5}   # rating 5 (hot) -> priority 1 (top)

# Default Supabase table names (overridable in config).
DEF_OVERLAY_TABLE = "board_overlay"
DEF_NOTES_TABLE = "board_notes"
DEF_SHEET_TAB = "Coach Board"


# ── config helpers ───────────────────────────────────────────────────────────
def overlay_cfg(cfg: dict | None) -> dict:
    return (cfg or {}).get("board_overlay") or {}


def backend_of(cfg: dict | None) -> str:
    b = str(overlay_cfg(cfg).get("backend") or "none").strip().lower()
    return b if b in ("supabase", "sheet") else "none"


def _coaches(cfg: dict | None) -> list[str]:
    names = overlay_cfg(cfg).get("coaches") or []
    return [str(n).strip() for n in names if str(n).strip()]


def _clean_temp(v: Any) -> str | None:
    s = str(v or "").strip().lower()
    return s if s in LEAD_TEMPS else None


def _truthy(v: Any) -> int:
    s = str(v).strip().lower()
    return 1 if s in ("1", "true", "yes", "y", "x", "★", "star", "fav") else 0


# ── schema migration (idempotent) ────────────────────────────────────────────
def ensure_overlay_columns(con: sqlite3.Connection) -> None:
    """Add the overlay columns to an existing call_assignments table if missing.

    Fresh DBs get them from db/schema.sql; this brings older DBs up to date so
    sync-overlay never fails on a missing column. Safe to call every run.
    """
    have = {r["name"] for r in con.execute("PRAGMA table_info(call_assignments)")}
    adds = {
        "lead_temp": "TEXT",
        "favorite": "INTEGER DEFAULT 0",
        "overlay_updated_by": "TEXT",
        "overlay_updated_at": "TEXT",
    }
    for col, decl in adds.items():
        if col not in have:
            con.execute(f"ALTER TABLE call_assignments ADD COLUMN {col} {decl}")
    con.execute("CREATE INDEX IF NOT EXISTS idx_calls_lead_temp ON call_assignments(lead_temp)")
    con.commit()


# ── reading the current overlay out of the pipeline DB ────────────────────────
def seed_from_db(con: sqlite3.Connection) -> dict[str, dict]:
    """Overlay state already stored in call_assignments, keyed by str(player_id).

    Used to seed the board's first paint (so tags show instantly, before the live
    Supabase fetch) and as the read side for exports.
    """
    ensure_overlay_columns(con)
    out: dict[str, dict] = {}
    for r in con.execute(
        """SELECT player_id, lead_temp, favorite, scout_notes,
                  overlay_updated_by, overlay_updated_at
           FROM call_assignments
           WHERE lead_temp IS NOT NULL OR favorite=1
              OR (scout_notes IS NOT NULL AND scout_notes!='' AND scout_notes!='{}')"""
    ):
        notes = {}
        if r["scout_notes"]:
            try:
                notes = {k: v for k, v in json.loads(r["scout_notes"]).items() if v}
            except Exception:
                notes = {}
        out[str(r["player_id"])] = {
            "temp": _clean_temp(r["lead_temp"]),
            "fav": 1 if r["favorite"] else 0,
            "by": r["overlay_updated_by"],
            "at": r["overlay_updated_at"],
            "notes": notes,
        }
    return out


# ── Supabase backend (PostgREST over plain HTTP) ─────────────────────────────
def _looks_like_service_key(key: str) -> bool:
    """True if `key` is a Supabase service_role key (must NEVER reach the browser).

    Catches both the new `sb_secret_…` format and a legacy JWT whose decoded payload
    carries role=service_role. Conservative: unknown formats return False.
    """
    if key.startswith("sb_secret_"):
        return True
    parts = key.split(".")
    if len(parts) == 3:  # JWT: header.payload.signature
        import base64
        try:
            pad = parts[1] + "=" * (-len(parts[1]) % 4)
            payload = json.loads(base64.urlsafe_b64decode(pad))
            return str(payload.get("role", "")) == "service_role"
        except Exception:
            return False
    return False


def _sb(cfg: dict) -> dict:
    # The overlay uses ONLY the public anon key — for both the browser and our server-side
    # read — because RLS already lets `anon` read+upsert the two overlay tables. We never
    # read a service_role key here, so there is no way to embed one in the published HTML.
    sb = overlay_cfg(cfg).get("supabase") or {}
    url = str(sb.get("url") or "").rstrip("/")
    key = str(sb.get("anon_key") or "").strip()
    if not url or not key:
        raise RuntimeError("board_overlay.supabase needs `url` and `anon_key`")
    if _looks_like_service_key(key):
        raise RuntimeError("board_overlay.supabase.anon_key looks like a SERVICE_ROLE key — "
                           "use the PUBLIC anon key (it gets embedded in the board).")
    return {
        "url": url,
        "key": key,
        "anon_key": key,   # browser + server both use the anon key
        "overlay_table": sb.get("overlay_table") or DEF_OVERLAY_TABLE,
        "notes_table": sb.get("notes_table") or DEF_NOTES_TABLE,
    }


def _sb_get(url: str, table: str, key: str) -> list[dict]:
    import requests
    r = requests.get(
        f"{url}/rest/v1/{table}",
        params={"select": "*"},
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"},
        timeout=25,
    )
    r.raise_for_status()
    return r.json() or []


def read_overlay_from_supabase(cfg: dict) -> dict[str, dict]:
    sb = _sb(cfg)
    overlay_rows = _sb_get(sb["url"], sb["overlay_table"], sb["key"])
    note_rows = _sb_get(sb["url"], sb["notes_table"], sb["key"])
    out: dict[str, dict] = {}
    for row in overlay_rows:
        pid = str(row.get("player_id"))
        if pid in (None, "None", ""):
            continue
        out[pid] = {
            "temp": _clean_temp(row.get("lead_temp")),
            "fav": 1 if row.get("favorite") else 0,
            "by": row.get("updated_by"),
            "at": row.get("updated_at"),
            "notes": {},
        }
    for row in note_rows:
        pid = str(row.get("player_id"))
        author = str(row.get("author") or "").strip()
        body = str(row.get("body") or "").strip()
        if not pid or not author or not body:
            continue
        out.setdefault(pid, {"temp": None, "fav": 0, "by": None, "at": None, "notes": {}})
        out[pid]["notes"][author] = body
    return out


# ── Google Sheet backend ─────────────────────────────────────────────────────
def _sheet_cfg(cfg: dict) -> dict:
    sh = overlay_cfg(cfg).get("sheet") or {}
    # fall back to the existing google_sheet block for creds + spreadsheet
    gs = (cfg or {}).get("google_sheet") or {}
    sa = sh.get("service_account_json") or gs.get("service_account_json")
    sid = sh.get("spreadsheet_id") or gs.get("spreadsheet_id")
    if not sa or not sid:
        raise RuntimeError(
            "board_overlay.sheet needs service_account_json + spreadsheet_id "
            "(or set them under google_sheet)")
    return {"service_account_json": sa, "spreadsheet_id": sid,
            "tab": sh.get("tab") or DEF_SHEET_TAB, "limit": int(sh.get("limit") or 300)}


def _open_sheet(sc: dict):
    import gspread
    from google.oauth2.service_account import Credentials
    scopes = ["https://www.googleapis.com/auth/spreadsheets"]
    creds = Credentials.from_service_account_file(sc["service_account_json"], scopes=scopes)
    return gspread.authorize(creds).open_by_key(sc["spreadsheet_id"])


def _note_cols(headers: list[str]) -> dict[str, str]:
    """Map a header like 'TW notes' / 'Coach K Notes' -> coach name 'TW' / 'Coach K'."""
    out = {}
    for h in headers:
        hl = str(h).strip()
        if hl.lower().endswith("notes") and hl.lower() not in ("notes",):
            out[hl] = hl[: -len("notes")].strip(" -:·")
    return out


def read_overlay_from_sheet(cfg: dict) -> dict[str, dict]:
    sc = _sheet_cfg(cfg)
    sh = _open_sheet(sc)
    try:
        ws = sh.worksheet(sc["tab"])
    except Exception:
        return {}
    records = ws.get_all_records()
    if not records:
        return {}
    headers = list(records[0].keys())
    note_map = _note_cols(headers)
    # tolerant header lookups
    def pick(row, *names):
        for n in names:
            for k in row:
                if str(k).strip().lower() == n:
                    return row[k]
        return None
    out: dict[str, dict] = {}
    for row in records:
        pid = pick(row, "player_id", "pid")
        if pid in (None, ""):
            continue
        pid = str(pid).strip()
        notes = {}
        for col, coach in note_map.items():
            body = str(row.get(col) or "").strip()
            if body:
                notes[coach] = body
        out[pid] = {
            "temp": _clean_temp(pick(row, "lead", "lead_temp", "temp")),
            "fav": _truthy(pick(row, "favorite", "fav", "star")),
            "by": None, "at": None, "notes": notes,
        }
    return out


def push_overlay_to_sheet(con: sqlite3.Connection, cfg: dict) -> str:
    """(Re)build the coach-editable tab with the current ENTERED player list, PRESERVING
    any lead/favorite/notes coaches already entered. Run on each refresh so new portal
    entries appear and committed/withdrawn players drop off — without wiping edits."""
    sc = _sheet_cfg(cfg)
    sh = _open_sheet(sc)
    try:
        ws = sh.worksheet(sc["tab"])
        prior = {str(r.get("player_id") or r.get("pid")): r for r in ws.get_all_records()}
        prior_headers = list(next(iter(prior.values())).keys()) if prior else []
    except Exception:
        ws = sh.add_worksheet(title=sc["tab"], rows="400", cols="20")
        prior, prior_headers = {}, []

    note_headers = [h for h in prior_headers if h.lower().endswith("notes") and h.lower() != "notes"]
    if not note_headers:
        note_headers = [f"{c} notes" for c in _coaches(cfg)] or ["Notes"]
    headers = ["player_id", "Player", "School", "Pos", "Rating", "Lead", "Favorite", *note_headers]

    players = con.execute(
        """SELECT pl.player_id pid, pl.full_name name, pl.from_school school, pl.position pos,
                  (SELECT ROUND(MAX(fit_score),1) FROM evaluations e WHERE e.player_id=pl.player_id) fit
           FROM players pl WHERE pl.current_status='ENTERED'
           ORDER BY fit IS NULL, fit DESC""",
    ).fetchall()
    players = players[: sc["limit"]]

    rows = [headers]
    for p in players:
        pid = str(p["pid"])
        prev = prior.get(pid, {})
        rows.append([
            pid, p["name"], p["school"] or "", p["pos"] or "", p["fit"] if p["fit"] is not None else "",
            prev.get("Lead", prev.get("lead", "")), prev.get("Favorite", prev.get("favorite", "")),
            *[prev.get(h, "") for h in note_headers],
        ])
    ws.clear()
    ws.update(rows, value_input_option="USER_ENTERED")
    _try_set_lead_validation(sh, ws, header_row=headers, n_rows=len(rows))
    return f"pushed {len(players)} players to '{sc['tab']}' (preserved {len(prior)} prior rows)"


def _try_set_lead_validation(sh, ws, header_row: list[str], n_rows: int) -> None:
    """Best-effort Cold/Warm/Hot dropdown on the Lead column. Guarded — never fatal."""
    try:
        col = header_row.index("Lead")
        body = {"requests": [{
            "setDataValidation": {
                "range": {"sheetId": ws.id, "startRowIndex": 1, "endRowIndex": n_rows,
                          "startColumnIndex": col, "endColumnIndex": col + 1},
                "rule": {
                    "condition": {"type": "ONE_OF_LIST", "values": [
                        {"userEnteredValue": "5"}, {"userEnteredValue": "4"},
                        {"userEnteredValue": "3"}, {"userEnteredValue": "2"},
                        {"userEnteredValue": "1"}]},
                    "showCustomUi": True, "strict": False},
            }}]}
        sh.batch_update(body)
    except Exception as e:  # noqa: BLE001
        log.info("lead-column data validation skipped: %s", e)


# ── unified read + payload + write-back ──────────────────────────────────────
def read_overlay(cfg: dict) -> dict[str, dict]:
    b = backend_of(cfg)
    if b == "supabase":
        return read_overlay_from_supabase(cfg)
    if b == "sheet":
        return read_overlay_from_sheet(cfg)
    return {}


def build_overlay_payload(con: sqlite3.Connection, cfg: dict) -> dict:
    """The object build_html.py embeds. Shape is backend-tagged so the board JS knows
    whether to render editable controls (supabase) or read-only chips (sheet)."""
    b = backend_of(cfg)
    if b == "none":
        return {"backend": "none"}
    coaches = _coaches(cfg)
    if b == "supabase":
        sb = _sb(cfg)
        # Seed first paint from the LIVE Supabase tables so the baked HTML matches what the
        # browser fetches on load (no flash of stale DB notes). Fall back to the DB's
        # last-synced snapshot only if the read fails (e.g. an offline build).
        try:
            data = read_overlay_from_supabase(cfg)
        except Exception as e:  # noqa: BLE001
            log.warning("supabase seed read failed (%s); using DB snapshot", e)
            data = seed_from_db(con)
        return {"backend": "supabase", "coaches": coaches, "data": data,
                "supabase": {"url": sb["url"], "anonKey": sb["anon_key"] or sb["key"],
                             "overlayTable": sb["overlay_table"], "notesTable": sb["notes_table"]}}
    # sheet: read live + bake (board is read-only for this backend)
    try:
        data = read_overlay_from_sheet(cfg)
    except Exception as e:  # noqa: BLE001
        log.warning("sheet overlay read failed (%s); board will render without overlay", e)
        data = {}
    return {"backend": "sheet", "coaches": coaches, "data": data,
            "sheetUrl": (overlay_cfg(cfg).get("sheet") or {}).get("edit_url", "")}


def sync_overlay_to_db(con: sqlite3.Connection, cfg: dict) -> dict:
    """Pull the live overlay from the active backend and write it into call_assignments.

    One overlay-carrying call_assignments row per player (the lowest-id existing row, or a
    new one). Notes merge into the per-coach scout_notes JSON. Idempotent."""
    b = backend_of(cfg)
    if b == "none":
        return {"backend": "none", "synced": 0}
    ensure_overlay_columns(con)
    overlay = read_overlay(cfg)
    valid = {r[0] for r in con.execute("SELECT player_id FROM players")}
    upd = ins = note_writes = skipped = 0
    for pid, ov in overlay.items():
        try:
            pid_i = int(pid)
        except (TypeError, ValueError):
            continue
        if pid_i not in valid:   # stale/test row (e.g. a player since removed) — never FK-insert it
            skipped += 1
            continue
        temp = _clean_temp(ov.get("temp"))
        fav = 1 if ov.get("fav") else 0
        notes = {k: v for k, v in (ov.get("notes") or {}).items() if v}
        row = con.execute(
            "SELECT id, scout_notes, priority FROM call_assignments WHERE player_id=? ORDER BY id LIMIT 1",
            (pid_i,)).fetchone()
        merged = {}
        if row and row["scout_notes"]:
            try:
                merged = json.loads(row["scout_notes"]) or {}
            except Exception:
                merged = {}
        merged.update(notes)
        if notes:
            note_writes += len(notes)
        scout_json = json.dumps(merged) if merged else None
        ts = ov.get("at") or now_iso()
        by = ov.get("by")
        if row:
            sets = ["lead_temp=?", "favorite=?", "scout_notes=?",
                    "overlay_updated_by=?", "overlay_updated_at=?", "updated_at=?"]
            vals = [temp, fav, scout_json, by, ts, now_iso()]
            if temp and row["priority"] is None:        # fill, don't clobber
                sets.append("priority=?"); vals.append(LEAD_TO_PRIORITY[temp])
            vals.append(row["id"])
            con.execute(f"UPDATE call_assignments SET {', '.join(sets)} WHERE id=?", vals)
            upd += 1
        else:
            con.execute(
                """INSERT INTO call_assignments
                     (player_id, priority, lead_temp, favorite, scout_notes,
                      overlay_updated_by, overlay_updated_at, updated_at)
                   VALUES (?,?,?,?,?,?,?,?)""",
                (pid_i, LEAD_TO_PRIORITY.get(temp), temp, fav, scout_json, by, ts, now_iso()))
            ins += 1
    con.commit()
    return {"backend": b, "players": len(overlay), "updated": upd,
            "inserted": ins, "note_writes": note_writes, "skipped_unknown": skipped}
