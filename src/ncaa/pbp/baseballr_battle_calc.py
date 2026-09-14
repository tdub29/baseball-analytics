"""
Convert baseballr-style PBP CSV to battle-ready DataFrame and run full battle
calculations (B1–B5) for every game in the PBP data.

Uses baseballr_description_mappings for description → reached_base, out,
total_bases, any_adv, event_category, errors, walk, HBP, strikeout.
Games lookup: from selected_games CSV when present, else inferred from PBP; all games in the PBP are processed.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pandas as pd

from ncaa.pbp.baseballr_description_mappings import (
    count_any_adv,
    count_any_adv_breakdown,
    defensive_error_in_description,
    has_pa_action,
    is_non_pa,
    is_hit_by_pitch,
    is_strikeout,
    is_walk,
    reached_base,
    total_bases_from_description,
)

try:
    from ncaa_pbp_playwright import _effective_outs_added
    from ncaa_pbp_playwright import _outs_on_play as _parser_outs_on_play
except ImportError:
    _effective_outs_added = None
    _parser_outs_on_play = None


# Validation/troubleshoot columns added to PBP CSV; order before 'description'
PBP_VALIDATION_COLUMNS = [
    "batting_team_norm",
    "pitching_team_norm",
    "inning_leadoff",
    "is_pa",
    "reached_base",
    "runs_scored_half",
    "event_category",
    "total_bases",
    "any_adv",
    "is_walk",
    "is_hbp",
    "is_k",
    "defensive_error",
]


def _reorder_pbp_with_validation_before_description(raw: pd.DataFrame) -> pd.DataFrame:
    """Put validation columns immediately before 'description'."""
    all_cols = list(raw.columns)
    if "description" not in all_cols:
        return raw
    valid = [c for c in PBP_VALIDATION_COLUMNS if c in raw.columns]
    before = [c for c in all_cols if c not in valid and all_cols.index(c) < all_cols.index("description")]
    after = [c for c in all_cols if c not in valid and all_cols.index(c) > all_cols.index("description")]
    return raw[before + valid + ["description"] + after]


def add_validation_columns_to_pbp(
    raw: pd.DataFrame,
    games_lookup: dict[int, tuple[str, str]] | None = None,
) -> pd.DataFrame:
    """Add all battle-calc-derived columns to raw PBP for troubleshooting/validation.
    Same logic as battle calc: is_pa, reached_base, runs_scored_half, event_category,
    total_bases, any_adv, is_walk, is_hbp, is_k, defensive_error, inning_leadoff.
    If games_lookup is provided, adds batting_team_norm and pitching_team_norm (USD/other).
    Validation columns are placed immediately before the description column.
    """
    raw = raw.copy()
    if "description" not in raw.columns:
        return raw

    desc = raw["description"].fillna("").astype(str)
    raw["game_pbp_id"] = pd.to_numeric(raw["game_pbp_id"], errors="coerce")
    raw["_inning"] = pd.to_numeric(raw["inning"], errors="coerce")

    # --- When we have games_lookup: resolve batting/fielding (half + batter-majority vote) ---
    votes_by_gid: dict[int, dict[str, dict[str, int]]] = {}
    if games_lookup is not None:
        raw["_vote_bat_cell"] = raw["batting"].astype(str)

        def _votes_for_gid(gid_i: int, grp: pd.DataFrame) -> dict[str, dict[str, int]]:
            away, home = games_lookup.get(gid_i, ("?", "?"))
            scraped = grp.loc[:, "_vote_bat_cell"]
            return _build_batter_team_votes_for_game(grp, away, home, scraped)

        for gid_val, grp in raw.groupby("game_pbp_id", dropna=False):
            if pd.isna(gid_val):
                continue
            votes_by_gid[int(gid_val)] = _votes_for_gid(int(gid_val), grp)

        def _bat_fld(row: pd.Series) -> pd.Series:
            gid = row.get("game_pbp_id")
            if pd.isna(gid):
                return pd.Series(["?", "?"])
            gid_i = int(gid)
            away, home = games_lookup.get(gid_i, ("?", "?"))
            votes = votes_by_gid.get(gid_i, {})
            b, p = _resolve_batting_pitching_names(
                away,
                home,
                str(row.get("inning_top_bot", "")),
                str(row.get("description", "")),
                votes,
            )
            return pd.Series([b, p])

        bf = raw.apply(_bat_fld, axis=1)
        raw["batting"] = bf[0].values
        raw["fielding"] = bf[1].values

        def _bat_norm(row: pd.Series) -> str:
            return _normalize_to_usd(row["batting"])

        def _pit_norm(row: pd.Series) -> str:
            return _normalize_to_usd(row["fielding"])

        raw["batting_team_norm"] = raw.apply(_bat_norm, axis=1)
        raw["pitching_team_norm"] = raw.apply(_pit_norm, axis=1)
    # else: leave batting_team_norm / pitching_team_norm out; keep original batting/fielding

    # --- Runs scored in half-inning (same as battle "Runs Scored") ---
    raw["_away"] = raw["score"].apply(lambda s: _parse_score(s)[0])
    raw["_home"] = raw["score"].apply(lambda s: _parse_score(s)[1])
    raw["runs_scored_half"] = 0
    for gid, grp in raw.groupby("game_pbp_id", dropna=False):
        grp = grp.sort_values(["_inning", "inning_top_bot"], ascending=[True, False])
        prev_away, prev_home = 0, 0
        for (_inn, top_bot), sub in grp.groupby(["_inning", "inning_top_bot"], sort=False):
            curr_away = sub["_away"].max()
            curr_home = sub["_home"].max()
            if str(top_bot).strip().lower() == "top":
                runs = max(0, int(curr_away) - prev_away)
                prev_away = int(curr_away)
            else:
                runs = max(0, int(curr_home) - prev_home)
                prev_home = int(curr_home)
            raw.loc[sub.index, "runs_scored_half"] = runs

    # --- Description-derived (same as battle calc) ---
    raw["is_pa"] = (~desc.apply(is_non_pa)).astype(int)
    raw["reached_base"] = desc.apply(lambda d: 1 if reached_base(d) else 0)
    raw["event_category"] = desc.apply(_description_to_event_category)
    raw["total_bases"] = desc.apply(total_bases_from_description)
    raw["any_adv"] = desc.apply(count_any_adv)
    raw["is_walk"] = desc.apply(lambda d: 1 if is_walk(d) else 0)
    raw["is_hbp"] = desc.apply(lambda d: 1 if is_hit_by_pitch(d) else 0)
    raw["is_k"] = desc.apply(lambda d: 1 if is_strikeout(d) else 0)
    raw["defensive_error"] = desc.apply(lambda d: 1 if defensive_error_in_description(d) else 0)

    # --- Leadoff: first PA of half-inning reached base ---
    raw["_is_pa"] = ~desc.apply(is_non_pa)
    raw["inning_leadoff"] = 0
    for (_gid, _inn, _top_bot), sub in raw.groupby(
        ["game_pbp_id", "_inning", "inning_top_bot"], dropna=False
    ):
        pa_rows = sub.loc[sub["_is_pa"]]
        if len(pa_rows) == 0:
            continue
        if games_lookup is not None and "batting_team_norm" in raw.columns:
            gid_i = int(_gid) if not pd.isna(_gid) else 0
            away, home = games_lookup.get(gid_i, ("?", "?"))
            tb = str(_top_bot).strip().lower()
            half_bat_expect = away if tb == "top" else home
            expect_team = _normalize_to_usd(half_bat_expect)
            aligned = pa_rows.loc[pa_rows["batting_team_norm"] == expect_team]
            candidate = aligned if len(aligned) > 0 else pa_rows
        else:
            candidate = pa_rows
        first_idx = candidate.index[0]
        if reached_base(raw.at[first_idx, "description"]):
            raw.at[first_idx, "inning_leadoff"] = 1

    # Drop temps and reorder
    raw.drop(
        columns=["_is_pa", "_inning", "_away", "_home", "_vote_bat_cell"],
        inplace=True,
        errors="ignore",
    )
    return _reorder_pbp_with_validation_before_description(raw)


def add_leadoff_column_to_pbp(
    raw: pd.DataFrame,
    games_lookup: dict[int, tuple[str, str]] | None = None,
) -> pd.DataFrame:
    """Add all validation/troubleshoot columns to raw PBP (leadoff + full set).
    Validation columns are placed immediately before the description column.
    Pass games_lookup to include batting_team_norm and pitching_team_norm (USD/other).
    """
    return add_validation_columns_to_pbp(raw, games_lookup=games_lookup)

# Game ID -> (away_team, home_team) for real5 games (feasibility doc); fallback when no CSV
REAL5_GAMES: dict[int, tuple[str, str]] = {
    6419683: ("San Diego", "Santa Clara"),
    6419807: ("Pacific", "San Diego"),
    6419874: ("Pacific", "San Diego"),
    6419937: ("Pacific", "San Diego"),
    6455090: ("San Diego", "Saint Mary's (CA)"),
}

USD_ALIASES = ("San Diego", "San Diego Toreros", "USD")
# San Diego State (SDSU) — do not map to USD; e.g. "San Diego St. Aztecs", "San Diego State"
SDSU_NAME_PREFIX = "San Diego St"

# One-time: this sac bunt should not count as an out; fix that row and recompute
# (inning, inning_top_bot, outs) for the rest of the game so inning switches are correct.
_MEIDROTH_SAC_BUNT_NO_OUT_DESC = (
    "Meidroth,Connor sacrifice bunt in front of the plate, unassisted (1-1 BF); Mestas,Gage advanced to third base."
)


def _correct_sac_bunt_no_out_in_pbp(raw: pd.DataFrame) -> pd.DataFrame:
    """If the Meidroth sac-bunt row exists, set its outs to 0 and recompute inning/outs for that game."""
    if "description" not in raw.columns or "outs" not in raw.columns or "game_pbp_id" not in raw.columns:
        return raw
    mask = raw["description"].astype(str).str.strip() == _MEIDROTH_SAC_BUNT_NO_OUT_DESC
    if not mask.any():
        return raw
    gid = int(raw.loc[mask, "game_pbp_id"].iloc[0])
    game_idx = raw.index[raw["game_pbp_id"] == gid].tolist()
    if not game_idx:
        return raw
    # Play order = row order for that game. Use parser's _outs_on_play(description) so
    # every play gets correct outs (including sac-bunt exception and non-out plays like "advanced on error").
    game_df = raw.loc[game_idx].copy()
    game_df = game_df.sort_index()
    desc_col = game_df["description"].astype(str).fillna("")
    if _parser_outs_on_play is not None:
        prev_d = ""
        inn, tb = 1, "top"
        run = 0
        new_inn, new_tb, new_outs = [], [], []
        for d in desc_col:
            if d.strip() == _MEIDROTH_SAC_BUNT_NO_OUT_DESC:
                o = 0
            else:
                o = _parser_outs_on_play(d)
            if (
                run == 0
                and o > 0
                and "out caught stealing" in d.lower()
                and prev_d
                and "under review" in prev_d.lower()
            ):
                o = 0
            adj = _effective_outs_added(run, o) if _effective_outs_added else o
            run += adj
            new_inn.append(inn)
            new_tb.append(tb)
            new_outs.append(run)
            if run >= 3:
                run = 0
                if tb == "top":
                    tb = "bot"
                else:
                    inn += 1
                    tb = "top"
            prev_d = d
    else:
        inning_col = game_df["inning"].astype(int)
        top_bot = game_df["inning_top_bot"].astype(str).str.strip().str.lower()
        outs_col = game_df["outs"].astype(int)
        outs_on_play = []
        prev_inn, prev_tb, prev_outs = None, None, 0
        for inn, tb, out, desc in zip(inning_col, top_bot, outs_col, desc_col):
            if prev_inn is not None and inn == prev_inn and tb == prev_tb:
                op = out - prev_outs
            else:
                op = out
            if desc.strip() == _MEIDROTH_SAC_BUNT_NO_OUT_DESC:
                op = 0
            outs_on_play.append(op)
            prev_inn, prev_tb, prev_outs = inn, tb, out
        inn, tb = 1, "top"
        run = 0
        new_inn, new_tb, new_outs = [], [], []
        for op in outs_on_play:
            adj = _effective_outs_added(run, op) if _effective_outs_added else op
            run += adj
            new_inn.append(inn)
            new_tb.append(tb)
            new_outs.append(run)
            if run >= 3:
                run = 0
                if tb == "top":
                    tb = "bot"
                else:
                    inn += 1
                    tb = "top"
    raw = raw.copy()
    ordered_idx = sorted(game_idx)
    for k, idx in enumerate(ordered_idx):
        raw.at[idx, "inning"] = new_inn[k]
        raw.at[idx, "inning_top_bot"] = new_tb[k]
        raw.at[idx, "outs"] = new_outs[k]
    return raw


# Games where outs/inning should be recomputed from description text (IFR, odd DP rows, etc.).
_RECOMPUTE_OUTS_GAME_IDS = (6548823, 6514969, 6507273, 6507956, 6437867, 6522574)


def _recompute_outs_for_game(raw: pd.DataFrame, game_id: int) -> pd.DataFrame:
    """Recompute outs and inning/outs for one game from _outs_on_play(description). Only used for specific game IDs."""
    if _parser_outs_on_play is None or "description" not in raw.columns or "outs" not in raw.columns or "game_pbp_id" not in raw.columns:
        return raw
    raw["game_pbp_id"] = pd.to_numeric(raw["game_pbp_id"], errors="coerce")
    game_idx = raw.index[raw["game_pbp_id"] == game_id].tolist()
    if not game_idx:
        return raw
    game_df = raw.loc[game_idx].copy().sort_index()
    desc_col = game_df["description"].astype(str).fillna("")
    outs_col = pd.to_numeric(game_df["outs"], errors="coerce").fillna(0).astype(int)
    prev_d = ""
    inn, tb = 1, "top"
    run = 0
    new_inn, new_tb, new_outs = [], [], []
    for d, ncaa_o in zip(desc_col, outs_col):
        o = _parser_outs_on_play(d)
        if (
            run == 0
            and o > 0
            and "out caught stealing" in d.lower()
            and prev_d
            and "under review" in prev_d.lower()
        ):
            o = 0
        adj = _effective_outs_added(run, o) if _effective_outs_added else o
        run += adj
        cap_ncaa = min(int(ncaa_o), 3)
        # NCAA HTML often duplicates the caught-stealing third out across half boundaries so pure text
        # inference can finish a half with two outs while the scraped outs column shows three (6507273).
        # Snap only when we're one short of closing the half but NCAA reports three outs on this row.
        if run == 2 and cap_ncaa >= 3:
            run = 3
        new_inn.append(inn)
        new_tb.append(tb)
        new_outs.append(run)
        if run >= 3:
            run = 0
            if tb == "top":
                tb = "bot"
            else:
                inn += 1
                tb = "top"
        prev_d = d
    raw = raw.copy()
    for k, idx in enumerate(sorted(game_idx)):
        raw.at[idx, "inning"] = new_inn[k]
        raw.at[idx, "inning_top_bot"] = new_tb[k]
        raw.at[idx, "outs"] = new_outs[k]
    return raw


def _normalize_to_usd(team: str) -> str:
    """Map USD (Toreros) to 'USD'; leave SDSU and others unchanged for battle logic."""
    if pd.isna(team):
        return team
    s = str(team).strip()
    if s.startswith(SDSU_NAME_PREFIX):
        return s  # San Diego St. Aztecs / San Diego State — not USD
    if s in USD_ALIASES or s.startswith("San Diego"):
        return "USD"
    return s


def load_games_from_csv(path: str | Path) -> dict[int, tuple[str, str]]:
    """Load game_id -> (away_short, home_short) from selected_games CSV (contest_id, away_short, home_short)."""
    path = Path(path)
    if not path.is_file():
        return {}
    df = pd.read_csv(path)
    for col in ("contest_id", "away_short", "home_short"):
        if col not in df.columns:
            return {}
    out: dict[int, tuple[str, str]] = {}
    for _, row in df.iterrows():
        cid = pd.to_numeric(row["contest_id"], errors="coerce")
        if pd.isna(cid):
            continue
        out[int(cid)] = (str(row["away_short"]).strip(), str(row["home_short"]).strip())
    return out


def infer_games_lookup_from_pbp(raw: pd.DataFrame) -> dict[int, tuple[str, str]]:
    """Infer game_id -> (away_short, home_short) from PBP rows."""
    raw = raw.copy()
    if "game_pbp_id" not in raw.columns:
        return {}
    raw["game_pbp_id"] = pd.to_numeric(raw["game_pbp_id"], errors="coerce")
    raw = raw.dropna(subset=["game_pbp_id"])
    raw["_gid"] = raw["game_pbp_id"].astype(int)
    if "inning_top_bot" not in raw.columns or "fielding" not in raw.columns:
        return {}
    raw["_top_bot"] = raw["inning_top_bot"].astype(str).str.strip().str.lower()
    raw["_bat"] = raw.get("batting", pd.Series(dtype=object)).fillna("").astype(str).str.strip()
    raw["_fld"] = raw["fielding"].fillna("").astype(str).str.strip()

    out: dict[int, tuple[str, str]] = {}
    for gid, grp in raw.groupby("_gid", dropna=False):
        away, home = "", ""
        for _, row in grp.iterrows():
            tb = row["_top_bot"]
            bat, fld = row["_bat"], row["_fld"]
            if tb == "top":
                if bat and fld:
                    away, home = bat, fld
                    break
                if fld:
                    home = fld
            else:
                if bat and fld:
                    away, home = fld, bat
                    break
                if fld:
                    away = fld
        if away and home:
            out[int(gid)] = (away, home)
            continue
        teams = set()
        for _, row in grp.iterrows():
            for v in (row["_bat"], row["_fld"]):
                if v and str(v).strip():
                    teams.add(str(v).strip())
        if len(teams) == 2:
            t1, t2 = sorted(teams)
            home_cand = next((row["_fld"] for _, row in grp.iterrows() if row["_top_bot"] == "top" and row["_fld"]), "")
            home = home_cand if home_cand in teams else t2
            away = t1 if home == t2 else t2
            out[int(gid)] = (away, home)
    return out


def build_complete_games_lookup(
    raw: pd.DataFrame,
    pbp_csv_path: str | Path,
    selected_games_path: str | Path | None = None,
) -> dict[int, tuple[str, str]]:
    """Build a games lookup that includes every game_pbp_id in raw."""
    path = Path(pbp_csv_path)
    sel_path = selected_games_path or path.parent / "real5_selected_games.csv"
    lookup = load_games_from_csv(sel_path) if Path(sel_path).is_file() else {}
    raw_gids = set()
    if "game_pbp_id" in raw.columns:
        for v in raw["game_pbp_id"].dropna().unique():
            try:
                raw_gids.add(int(float(v)))
            except (ValueError, TypeError):
                pass
    inferred = infer_games_lookup_from_pbp(raw)
    for gid in raw_gids:
        if gid not in lookup and gid in inferred:
            lookup[gid] = inferred[gid]
        elif gid not in lookup:
            lookup[gid] = ("?", "?")
    return lookup


def _description_to_event_category(desc: str) -> str:
    """Map description to battle event_category."""
    if not desc or not isinstance(desc, str):
        return "other"
    t = desc.strip().lower()
    if "homered" in t:
        return "home_run"
    if "tripled" in t:
        return "triple"
    if "doubled" in t:
        return "double"
    if "singled" in t:
        return "single"
    if is_walk(desc):
        return "walk"
    if is_hit_by_pitch(desc):
        return "hit_by_pitch"
    return "other"


def _parse_score(score_str: str) -> tuple[int, int]:
    """Parse 'A-H' format to (away_runs, home_runs)."""
    if pd.isna(score_str) or not str(score_str).strip():
        return 0, 0
    s = str(score_str).strip()
    m = re.match(r"^(\d+)\s*-\s*(\d+)$", s)
    if m:
        return int(m.group(1)), int(m.group(2))
    return 0, 0


def _build_pitch_result(desc: str) -> str:
    """Ensure pitchResult contains 'Strikeout' and 'error' when applicable."""
    if not desc or not isinstance(desc, str):
        return ""
    out = desc
    if is_strikeout(desc) and "strikeout" not in out.lower():
        out = out + " Strikeout"
    if defensive_error_in_description(desc) and "error" not in out.lower():
        out = out + " error"
    return out


def _align_to_game_team(raw_batting: str, away: str, home: str) -> str | None:
    """Return away or home full string if raw batting cell matches one lineup."""
    if not raw_batting or not away or not home:
        return None
    n = str(raw_batting).strip().lower()
    if not n:
        return None
    for full in (away, home):
        f = full.strip().lower()
        if not f:
            continue
        if n == f or n in f or f in n:
            return full
        first = f.split()[0]
        if len(first) > 2 and first in n:
            return full
    return None


def _looks_like_dense_player_stub(tok: str) -> bool:
    """True for tokens like GonzalezD — unique compact batter label without comma (NCAA shorthand)."""
    if not tok or "," in tok:
        return False
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9']{1,}", tok):
        return False
    # All-upper last names ("HARRIES") are shout-case PBP formatting, not GonzalezD-style stubs.
    letters_only = "".join(c for c in tok if c.isalpha())
    if len(letters_only) >= 2 and letters_only == letters_only.upper():
        return False
    lower = tok[1:]
    return tok[0].isupper() and (not lower.islower() and any(c.isupper() for c in lower))


def _leading_batter_token_dense_or_none(desc: str) -> str | None:
    """If first word is GonzalezD-style stub, return lowercase token; else None."""
    s = (desc or "").strip()
    m3 = re.match(
        r"^([A-Za-z][A-Za-z'\-]{0,24}[A-Za-z]?)\s+"
        r"(?:singled|doubled|tripled|homered|walked|struck|flied|grounded|lined|popped|fouled"
        r"|reached|hit by|sacrifice|out at|was called)",
        s,
        re.I,
    )
    if not m3:
        return None
    stub = m3.group(1)
    if _looks_like_dense_player_stub(stub):
        return stub.lower()
    return None


def _batter_vote_key(desc: str, lineup_team_aligned: str | None = None) -> str | None:
    """Stable key per batter for majority vote (NCAA 'Last, Fi' or leading token + verb)."""
    s = (desc or "").strip()
    if len(s) < 4:
        return None
    m = re.match(
        r"^([^\s,]+)\s*,\s*([^\s:]+)\s+",
        s,
    )
    if m:
        last_raw, fi_word = m.group(1).strip(), m.group(2).strip()
        letters_last = "".join(c for c in last_raw if c.isalpha())
        letters_f = "".join(c for c in fi_word if c.isalpha())
        if letters_last and letters_f:
            last, fi = letters_last.lower(), letters_f.lower()
            return f"{last},{fi[0]}"
    m3 = re.match(
        r"^([A-Za-z][A-Za-z'\-]{0,24}[A-Za-z]?)\s+"
        r"(?:singled|doubled|tripled|homered|walked|struck|flied|grounded|lined|popped|fouled"
        r"|reached|hit by|sacrifice|out at|was called)",
        s,
        re.I,
    )
    if m3:
        stub = m3.group(1)
        if _looks_like_dense_player_stub(stub):
            return stub.lower()
        return None
    return None


def _vote_keys_for_desc_lookup(desc: str, away: str, home: str) -> list[str]:
    keys: list[str] = []
    s = (desc or "").strip()
    if len(s) < 4:
        return keys
    m = re.match(
        r"^([^\s,]+)\s*,\s*([^\s:]+)\s+",
        s,
    )
    if m:
        last_raw, fi_word = m.group(1).strip(), m.group(2).strip()
        letters_last = "".join(c for c in last_raw if c.isalpha())
        letters_f = "".join(c for c in fi_word if c.isalpha())
        if letters_last and letters_f:
            last, fi = letters_last.lower(), letters_f.lower()
            keys.append(f"{last},{fi[0]}")
            return keys
    d = _leading_batter_token_dense_or_none(s)
    if d:
        keys.append(d)
    return keys


def _build_batter_team_votes_for_game(
    grp: pd.DataFrame,
    away: str,
    home: str,
    scraped_bat: pd.Series | None = None,
) -> dict[str, dict[str, int]]:
    """Majority vote: which lineup each batter appears under in scraped ``batting`` column."""
    votes: dict[str, dict[str, int]] = {}
    if not away or not home:
        return votes
    use_scraped = scraped_bat is not None and not scraped_bat.empty
    bat_col_present = grp.get("batting") is not None
    if not use_scraped and not bat_col_present:
        return votes
    for idx, row in grp.iterrows():
        desc = str(row.get("description", ""))
        if not has_pa_action(desc):
            continue
        if use_scraped:
            try:
                cell = scraped_bat.loc[idx]
            except (KeyError, TypeError):
                cell = row.get("batting", "")
        else:
            cell = row.get("batting", "")
        side = _align_to_game_team(str(cell), away, home)
        if side is None:
            continue
        key = _batter_vote_key(desc, lineup_team_aligned=side)
        if not key:
            continue
        votes.setdefault(key, {})
        votes[key][side] = votes[key].get(side, 0) + 1
    return votes


def _resolve_batting_pitching_names(
    away: str,
    home: str,
    top_bot: str,
    description: str,
    votes: dict[str, dict[str, int]],
) -> tuple[str, str]:
    """Use half-inning + batter majority to fix mis-tagged NCAA rows (wrong team, right half)."""
    tb = str(top_bot or "").strip().lower()
    half_bat = away if tb == "top" else home
    half_pit = home if tb == "top" else away
    if (
        not away
        or not home
        or away == "?"
        or home == "?"
        or not has_pa_action(str(description))
    ):
        return half_bat, half_pit
    keys_try = _vote_keys_for_desc_lookup(str(description), away, home)
    if not keys_try:
        return half_bat, half_pit

    tally = None
    for k in keys_try:
        if k in votes:
            tally = votes[k]
            break
    if tally is None:
        return half_bat, half_pit
    if not tally:
        return half_bat, half_pit
    best_side = max(tally, key=lambda t: tally[t])
    best_n = tally[best_side]
    exp_n = tally.get(half_bat, 0)
    if best_n >= 2 and best_n > exp_n:
        bat = best_side
        pit = home if bat == away else away
        return bat, pit
    return half_bat, half_pit


def baseballr_to_battle_df(raw: pd.DataFrame, games_lookup: dict[int, tuple[str, str]] | None = None) -> pd.DataFrame:
    """Convert baseballr-style PBP DataFrame to battle_logic-ready format."""
    games = games_lookup if games_lookup is not None else {}
    raw = raw.copy()
    if len(raw) == 0:
        return pd.DataFrame(columns=[
            "battingTeam", "pitchingTeam", "inn", "inning_leadoff", "Runs Scored",
            "event_category", "pitchResult", "total_bases", "any_adv",
            "gameDate", "totalRuns", "opponentRuns", "opponent", "gameId",
        ])
    raw["game_pbp_id"] = pd.to_numeric(raw["game_pbp_id"], errors="coerce").astype("Int64")

    votes_by_gid: dict[int, dict[str, dict[str, int]]] = {}
    for gid_val, grp in raw.groupby("game_pbp_id", dropna=False):
        if pd.isna(gid_val):
            continue
        gid_i = int(gid_val)
        away, home = games.get(gid_i, ("?", "?"))
        votes_by_gid[gid_i] = _build_batter_team_votes_for_game(grp, away, home)

    def _batpit_row(row: pd.Series) -> pd.Series:
        gid = row.get("game_pbp_id")
        if pd.isna(gid):
            return pd.Series(["?", "?"])
        gid_i = int(gid)
        away, home = games.get(gid_i, ("?", "?"))
        votes = votes_by_gid.get(gid_i, {})
        b, p = _resolve_batting_pitching_names(
            away, home, str(row.get("inning_top_bot", "")), str(row.get("description", "")), votes
        )
        return pd.Series([b, p])

    _bp = raw.apply(_batpit_row, axis=1)
    raw["_batting_team"] = _bp[0]
    raw["_pitching_team"] = _bp[1]
    raw["battingTeam"] = raw["_batting_team"].apply(_normalize_to_usd)
    raw["pitchingTeam"] = raw["_pitching_team"].apply(_normalize_to_usd)

    raw["inn"] = pd.to_numeric(raw["inning"], errors="coerce").fillna(0).astype(int)
    raw["description"] = raw["description"].fillna("").astype(str)

    raw["_away"] = raw["score"].apply(lambda s: _parse_score(s)[0])
    raw["_home"] = raw["score"].apply(lambda s: _parse_score(s)[1])

    run_dfs = []
    for gid, grp in raw.groupby("game_pbp_id", dropna=False):
        grp = grp.copy()
        grp = grp.sort_values(["inn", "inning_top_bot"], ascending=[True, False])
        prev_away, prev_home = 0, 0
        runs_list = []
        for (inn, top_bot), sub in grp.groupby(["inn", "inning_top_bot"], sort=False):
            sub = sub.copy()
            curr_away = sub["_away"].max()
            curr_home = sub["_home"].max()
            if str(top_bot).strip().lower() == "top":
                runs = max(0, curr_away - prev_away)
                prev_away = curr_away
            else:
                runs = max(0, curr_home - prev_home)
                prev_home = curr_home
            sub["Runs Scored"] = runs
            runs_list.append(sub)
        run_dfs.append(pd.concat(runs_list, ignore_index=True))
    if not run_dfs:
        return pd.DataFrame(columns=[
            "battingTeam", "pitchingTeam", "inn", "inning_leadoff", "Runs Scored",
            "event_category", "pitchResult", "total_bases", "any_adv",
            "gameDate", "totalRuns", "opponentRuns", "opponent", "gameId",
        ])
    raw = pd.concat(run_dfs, ignore_index=True)

    raw["_is_pa"] = ~raw["description"].apply(is_non_pa)
    raw["inning_leadoff"] = 0
    for (gid, inn, top_bot), sub in raw.groupby(["game_pbp_id", "inn", "inning_top_bot"], dropna=False):
        pa_rows = sub.loc[sub["_is_pa"]]
        if len(pa_rows) == 0:
            continue
        gid_i = int(gid) if not pd.isna(gid) else 0
        away, home = games.get(gid_i, ("?", "?"))
        tb = str(top_bot).strip().lower()
        half_bat_expect = away if tb == "top" else home
        expect_team = _normalize_to_usd(half_bat_expect)
        aligned = pa_rows.loc[pa_rows["battingTeam"] == expect_team]
        candidate = aligned if len(aligned) > 0 else pa_rows
        first_idx = candidate.index[0]
        if reached_base(raw.at[first_idx, "description"]):
            raw.at[first_idx, "inning_leadoff"] = 1

    # Ensure "Kern walked." (top 7, game 6548823) gets leadoff when manually added
    _gid = raw["game_pbp_id"].astype(str).str.strip()
    _desc = raw["description"].astype(str).str.strip().str.lower()
    kern_walk_mask = (
        (_gid == "6548823")
        & (raw["inn"] == 7)
        & (raw["inning_top_bot"].astype(str).str.strip().str.lower() == "top")
        & (_desc.str.contains("kern walked", na=False))
    )
    if kern_walk_mask.any():
        raw.loc[kern_walk_mask, "inning_leadoff"] = 1

    raw["event_category"] = raw["description"].apply(_description_to_event_category)
    raw["pitchResult"] = raw["description"].apply(_build_pitch_result)
    raw["total_bases"] = raw["description"].apply(total_bases_from_description)
    raw["any_adv"] = raw["description"].apply(count_any_adv)
    _adv_breakdown = raw["description"].apply(count_any_adv_breakdown)
    raw["any_adv_sb"] = _adv_breakdown.apply(lambda d: d["sb"])
    raw["any_adv_wp_pb"] = _adv_breakdown.apply(lambda d: d["wp_pb"])
    raw["any_adv_other"] = _adv_breakdown.apply(lambda d: d["other"])

    def game_meta(row: pd.Series) -> pd.Series:
        gid = row["game_pbp_id"]
        gid_int = int(gid) if not pd.isna(gid) else 0
        away, home = games.get(gid_int, ("?", "?"))
        last = raw[raw["game_pbp_id"] == gid].iloc[-1] if not raw[raw["game_pbp_id"] == gid].empty else row
        away_runs = last["_away"] if "_away" in last else 0
        home_runs = last["_home"] if "_home" in last else 0
        _away_s = (away.strip() if isinstance(away, str) else "") or ""
        is_usd_away = (
            away in USD_ALIASES
            or (_away_s.startswith("San Diego") and not _away_s.startswith(SDSU_NAME_PREFIX))
        )
        usd_runs = away_runs if is_usd_away else home_runs
        opp_runs = home_runs if is_usd_away else away_runs
        opp_name = home if is_usd_away else away
        return pd.Series({
            "totalRuns": int(usd_runs),
            "opponentRuns": int(opp_runs),
            "opponent": opp_name,
            "gameDate": pd.to_datetime(row["game_date"], errors="coerce"),
        })

    meta = raw.apply(game_meta, axis=1)
    raw["totalRuns"] = meta["totalRuns"]
    raw["opponentRuns"] = meta["opponentRuns"]
    raw["opponent"] = meta["opponent"]
    raw["gameDate"] = meta["gameDate"]
    raw["gameId"] = raw["game_pbp_id"].astype(str)

    out = raw[[
        "battingTeam", "pitchingTeam", "inn",
        "inning_leadoff", "Runs Scored",
        "event_category", "pitchResult", "total_bases", "any_adv",
        "any_adv_sb", "any_adv_wp_pb", "any_adv_other",
        "gameDate", "totalRuns", "opponentRuns", "opponent", "gameId",
    ]].copy()
    return out


def load_and_convert(
    csv_path: str | Path,
    games_lookup: dict[int, tuple[str, str]] | None = None,
    games_csv_path: str | Path | None = None,
) -> pd.DataFrame:
    """Load baseballr CSV and return battle-ready DataFrame."""
    path = Path(csv_path)
    if not path.is_file():
        raise FileNotFoundError(f"CSV not found: {path}")
    raw = pd.read_csv(path)
    raw = _correct_sac_bunt_no_out_in_pbp(raw)
    for gid in _RECOMPUTE_OUTS_GAME_IDS:
        raw = _recompute_outs_for_game(raw, gid)
    if games_lookup is not None:
        lookup = games_lookup
    else:
        lookup = build_complete_games_lookup(raw, path, games_csv_path)
    # Recompute leadoff (and apply Kern walked fix) so battle df has correct inning_leadoff even if CSV was not written
    raw = add_leadoff_column_to_pbp(raw, games_lookup=lookup)
    return baseballr_to_battle_df(raw, games_lookup=lookup)


def run_battle_calc_for_all_games(
    csv_path: str | Path,
    games_lookup: dict[int, tuple[str, str]] | None = None,
    games_csv_path: str | Path | None = None,
) -> tuple[dict, pd.DataFrame]:
    """Load PBP CSV, convert, run compute_battle_metrics_table for every game.
    Returns (results, full_battle_df) so callers can order by game date."""
    from ncaa.pbp.battle_logic import compute_battle_metrics_table

    path = Path(csv_path)
    if not path.is_file():
        return {}, pd.DataFrame()
    raw = pd.read_csv(path)
    lookup = games_lookup if games_lookup is not None else build_complete_games_lookup(raw, path, games_csv_path)

    full = load_and_convert(csv_path, games_lookup=lookup, games_csv_path=None)
    results = {}
    for gid in full["gameId"].dropna().unique():
        try:
            gid_int = int(float(gid))
        except (ValueError, TypeError):
            continue
        game_df = full[full["gameId"] == str(gid_int)].copy()
        game_df["gameDate"] = pd.to_datetime(game_df["gameDate"], errors="coerce")
        try:
            results[gid_int] = compute_battle_metrics_table(game_df)
        except Exception as e:
            results[gid_int] = {"_error": str(e)}
    return results, full


def write_battle_report(
    results: dict,
    out_path: str | Path,
    games_lookup: dict[int, tuple[str, str]] | None = None,
    full_battle_df: pd.DataFrame | None = None,
) -> None:
    """Write battle results for all games to a text file. Games are ordered by date when full_battle_df is provided."""
    path = Path(out_path)
    lookup = games_lookup if games_lookup is not None else {}
    # Order by game date (ascending) when we have the full df; else by contest id
    if full_battle_df is not None and not full_battle_df.empty and "gameId" in full_battle_df.columns and "gameDate" in full_battle_df.columns:
        order_df = full_battle_df.assign(gameDate=pd.to_datetime(full_battle_df["gameDate"], errors="coerce")).groupby("gameId", as_index=False)["gameDate"].min()
        order_df = order_df.sort_values("gameDate", na_position="last")
        game_order = []
        for gid_val in order_df["gameId"].tolist():
            try:
                gid_int = int(float(gid_val))
                if gid_int in results:
                    game_order.append(gid_int)
            except (ValueError, TypeError):
                pass
        for gid in sorted(results.keys()):
            if gid not in game_order:
                game_order.append(gid)
    else:
        game_order = sorted(results.keys())
    lines = [
        "USD Baseball — Battle calculation output",
        "Source: baseballr-style PBP via battles/baseballr_battle_calc.py",
        "=" * 60,
        "",
    ]
    for gid in game_order:
        tab = results[gid]
        away, home = lookup.get(gid, REAL5_GAMES.get(gid, ("?", "?")))
        lines.append(f"Game {gid}  ({away} @ {home})")
        lines.append("-" * 40)
        if isinstance(tab, dict) and "_error" in tab:
            lines.append(f"  ERROR: {tab['_error']}")
            lines.append("")
            continue
        for metric, data in tab.items():
            if metric == "_makeup" or not isinstance(data, dict) or "display" not in data:
                continue
            met = "✓" if data.get("met") else "✗"
            lines.append(f"  {metric}: {data['display']}  (goal met: {met})")
        if isinstance(tab, dict) and "_makeup" in tab:
            m = tab["_makeup"]
            tb = m.get("tb", {})
            xb = m.get("xb", {})
            tb_str = f"1B {tb.get('1b', 0)}, 2B {tb.get('2b', 0)}, 3B {tb.get('3b', 0)}, HR {tb.get('hr', 0)}"
            xb_total = (xb.get("sb", 0) or 0) + (xb.get("wp_pb", 0) or 0) + (xb.get("other", 0) or 0)
            xb_str = f"XB: {xb_total} (SB {xb.get('sb', 0)}, WP/PB {xb.get('wp_pb', 0)})"
            lines.append(f"  Makeup B3c: {tb_str} | {xb_str}")
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


# Metric column order used by battle_logic.render_season_summary_pdf
PDF_METRIC_COLS = [
    "B1a Leadoff Runners (Off)",
    "B1b Leadoff Runners (Def)",
    "B2a Leadoff Runs % (Off)",
    "B2b Leadoff Stranded % (Def)",
    "B3a Total Baserunners (Off)",
    "B3c Total Bases + XBs (Off)",
    "B3b Total Baserunners (Def)",
    "B4 Defensive Errors (Pitch)",
    "B5a BB+HBP (Off) vs K",
    "B5b BB+HBP (Def)",
]


def build_rows_df_and_summary_df(
    results: dict,
    full_battle_df: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Build rows_df (one row per game) and summary_df for render_season_summary_pdf."""
    rows = []
    for gid in sorted(results.keys()):
        tab = results[gid]
        if not isinstance(tab, dict) or "_error" in tab:
            continue
        grp = full_battle_df[full_battle_df["gameId"] == str(gid)]
        if grp.empty:
            continue
        first = grp.iloc[0]
        gdate = pd.to_datetime(first.get("gameDate"), errors="coerce")
        game_date_str = gdate.strftime("%Y-%m-%d") if pd.notna(gdate) else str(gid)
        opponent = str(first.get("opponent", "?"))
        usd_runs = int(first.get("totalRuns", 0))
        opp_runs = int(first.get("opponentRuns", 0))
        score_str = f"{usd_runs}-{opp_runs}"
        row = {"GameId": gid, "GameDate": game_date_str, "Opponent": opponent, "Score": score_str}
        for col in PDF_METRIC_COLS:
            data = tab.get(col)
            if isinstance(data, dict):
                row[col] = data.get("display", "")
                row[col + "__met"] = data.get("met", False)
                row[col + "__vs_goal_pct"] = data.get("vs_goal_pct")
            else:
                row[col] = ""
                row[col + "__met"] = False
                row[col + "__vs_goal_pct"] = None
        rows.append(row)
    rows_df = pd.DataFrame(rows)
    if not rows_df.empty and "GameDate" in rows_df.columns:
        rows_df = rows_df.sort_values("GameDate", na_position="last").reset_index(drop=True)

    summary_rows = []
    for metric in PDF_METRIC_COLS:
        met_col = metric + "__met"
        pct_col = metric + "__vs_goal_pct"
        if met_col not in rows_df.columns:
            summary_rows.append({"Metric": metric, "Games": 0, "Games_Met": 0, "Avg_Vs_Goal_Pct": 0.0})
            continue
        n = len(rows_df)
        met_count = int(rows_df[met_col].fillna(False).sum())
        pcts = rows_df[pct_col].dropna()
        avg_pct = float(pcts.mean()) if len(pcts) > 0 else 0.0
        summary_rows.append({"Metric": metric, "Games": n, "Games_Met": met_count, "Avg_Vs_Goal_Pct": avg_pct})
    summary_df = pd.DataFrame(summary_rows)
    return rows_df, summary_df


def main() -> None:
    """Load PBP CSV, run battle calc for all games, print and write output."""
    battles_dir = Path(__file__).resolve().parent
    csv_path = battles_dir / "real5_pbp_baseballr_style.csv"
    games_csv = battles_dir / "real5_selected_games.csv"
    out_path = battles_dir / "real5_battle_calc_output.txt"
    if not csv_path.is_file():
        print(f"CSV not found: {csv_path}")
        return
    raw = pd.read_csv(csv_path)
    raw = _correct_sac_bunt_no_out_in_pbp(raw)
    for gid in _RECOMPUTE_OUTS_GAME_IDS:
        raw = _recompute_outs_for_game(raw, gid)
    lookup = build_complete_games_lookup(raw, csv_path, games_csv)
    raw = add_leadoff_column_to_pbp(raw, games_lookup=lookup)
    try:
        raw.to_csv(csv_path, index=False)
    except OSError as e:
        print(f"Note: could not update PBP CSV ({e}); report will use current CSV.")
    results, full = run_battle_calc_for_all_games(csv_path, games_lookup=lookup)
    write_battle_report(results, out_path, games_lookup=lookup, full_battle_df=full)
    out_abs = out_path.resolve()
    print(f"Report written: {out_abs}")

    # Node PDFs: season_battle_report.pdf + per-game {date}_{opponent}_{id}_Battle_report.pdf
    pdf_dir = battles_dir / "battle_pdf"
    mjs = pdf_dir / "generate-pdf.mjs"
    if mjs.is_file():
        out_pdf = pdf_dir / "season_battle_report.pdf"
        pbp_csv = battles_dir / "real5_pbp_baseballr_style.csv"
        logo = pdf_dir / "sd_logo.png"
        cmd = ["node", str(mjs), str(out_path), str(out_pdf), str(pbp_csv), str(logo)]
        try:
            subprocess.run(cmd, check=True, cwd=str(battles_dir))
            print(f"Wrote PDFs: {out_pdf} + per-game in battle_pdf/")
        except (FileNotFoundError, subprocess.CalledProcessError) as e:
            print(f"Node PDF step skipped: {e}")
    else:
        print("battle_pdf/generate-pdf.mjs not found; PDF step skipped.")
    print()
    print("=== Battle calculation — all games ===\n")
    for gid in sorted(results.keys()):
        tab = results[gid]
        if isinstance(tab, dict) and "_error" in tab:
            print(f"Game {gid}: ERROR — {tab['_error']}\n")
            continue
        print(f"Game {gid}")
        for metric, data in tab.items():
            if isinstance(data, dict) and "display" in data:
                met = "Y" if data.get("met") else "N"
                print(f"  {metric}: {data['display']}  (goal met: {met})")
        print()
    print("Done.")


if __name__ == "__main__":
    main()
