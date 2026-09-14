"""
Build real 5-game dual-style play-by-play outputs and an exact-only battle
feasibility report.

This script extends the workflow documented in:
  Baseball/battles/cursor_battle_logic_migration_and_docum.md

It pulls real NCAA play-by-play data for University of San Diego games from:
  https://ncaa-api.henrygd.me

Deliverables:
  - real5_pbp_baseballr_style.csv
  - real5_pbp_retrosheet_style.csv
  - real5_battle_feasibility.md
  - real5_selected_games.csv
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import requests

API_BASE = "https://ncaa-api.henrygd.me"
SPORT = "baseball"
DIVISION = "d1"

BASERUNNER_EVENTS = {"single", "double", "triple", "home_run", "walk", "hit_by_pitch"}

METRIC_ORDER = [
    "B1a Leadoff Runners (Off)",
    "B1b Leadoff Runners (Def)",
    "B2a Leadoff Runs % (Off)",
    "B2b Leadoff Stranded % (Def)",
    "B3a Total Baserunners (Off)",
    "B3b Total Baserunners (Def)",
    "B3c Total Bases + XBs (Off)",
    "B4 Defensive Errors (Pitch)",
    "B5a BB+HBP (Off) vs K",
    "B5b BB+HBP (Def)",
]

RUNS_OUTS_DESC = {
    "0": "No out recorded on this play",
    "1": "One out recorded on this play",
    "2": "Two outs recorded on this play (e.g. double play)",
    "3": "Three outs recorded on this play",
}

NON_PA_PATTERNS = [
    r"^no play\.?$",
    r"staff day",
    r"mound visit",
    r"\bto p for\b",
    r"\bpinch hit for\b",
    r"\bpinch ran for\b",
    r"\badvanced to\b",
    r"\bstole\b",
    r"\bcaught stealing\b",
    r"\bpicked off\b",
    r"\bwild pitch\b",
    r"\bpassed ball\b",
    r"\bdefensive indifference\b",
    r"\bexit velo\b",
    r"\blaunch angle\b",
]


@dataclass
class GameSelection:
    contest_id: str
    game_date: str
    source_url: str
    away_short: str
    home_short: str
    title: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build real 5-game dual-style PBP outputs and battle feasibility report."
    )
    parser.add_argument("--team-short", type=str, default="San Diego")
    parser.add_argument("--games", type=int, default=5)
    parser.add_argument("--start-date", type=str, default="2026-02-15")
    parser.add_argument("--max-days-back", type=int, default=450)
    parser.add_argument("--year", type=int, default=None, help="Only include games in this calendar year (e.g. 2026). If set, returns all such games found, even if fewer than --games.")
    parser.add_argument("--out-dir", type=str, default="Baseball")
    return parser.parse_args()


def fetch_json(session: requests.Session, url: str, retries: int = 3, timeout: int = 25) -> dict[str, Any] | None:
    for attempt in range(1, retries + 1):
        try:
            response = session.get(url, timeout=timeout)
            content_type = response.headers.get("content-type", "")
            if response.status_code == 200 and "application/json" in content_type:
                payload = response.json()
                if isinstance(payload, dict):
                    return payload
                return {"_payload": payload}
            if response.status_code in (429, 500, 502, 503, 504):
                time.sleep(0.5 * attempt)
                continue
            return None
        except requests.RequestException:
            time.sleep(0.5 * attempt)
    return None


def extract_contest_id(game_url: str) -> str | None:
    match = re.search(r"/game/(\d+)", game_url or "")
    if not match:
        return None
    return match.group(1)


def select_games(
    session: requests.Session,
    team_short: str,
    games_needed: int,
    start_dt: date,
    max_days_back: int,
    year_filter: int | None = None,
) -> tuple[list[GameSelection], dict[str, dict[str, Any]]]:
    selected: list[GameSelection] = []
    pbp_cache: dict[str, dict[str, Any]] = {}
    seen_ids: set[str] = set()

    for day_offset in range(max_days_back):
        scan_dt = start_dt - timedelta(days=day_offset)
        if year_filter is not None and scan_dt.year != year_filter:
            if scan_dt.year < year_filter:
                break
            continue
        scoreboard_url = (
            f"{API_BASE}/scoreboard/{SPORT}/{DIVISION}/{scan_dt:%Y/%m/%d}/all-conf"
        )
        scoreboard = fetch_json(session, scoreboard_url, retries=2, timeout=18)
        if not scoreboard:
            continue

        games = scoreboard.get("games", [])
        if not isinstance(games, list):
            continue

        for wrapper in games:
            if not isinstance(wrapper, dict):
                continue
            game = wrapper.get("game", {})
            if not isinstance(game, dict):
                continue

            if str(game.get("gameState", "")).lower() != "final":
                continue

            away_short = (game.get("away", {}).get("names", {}).get("short") or "").strip()
            home_short = (game.get("home", {}).get("names", {}).get("short") or "").strip()
            if away_short != team_short and home_short != team_short:
                continue

            contest_id = extract_contest_id(str(game.get("url", "")))
            if not contest_id or contest_id in seen_ids:
                continue

            pbp_url = f"{API_BASE}/game/{contest_id}/play-by-play"
            pbp_payload = fetch_json(session, pbp_url, retries=3, timeout=20)
            if not pbp_payload:
                continue
            if "periods" not in pbp_payload or "teams" not in pbp_payload:
                continue

            seen_ids.add(contest_id)
            pbp_cache[contest_id] = pbp_payload
            source_url = str(game.get("url", "")).strip() or f"/game/{contest_id}"
            selected.append(
                GameSelection(
                    contest_id=contest_id,
                    game_date=str(scan_dt),
                    source_url=source_url,
                    away_short=away_short,
                    home_short=home_short,
                    title=str(game.get("title", "")),
                )
            )

            if len(selected) >= games_needed and year_filter is None:
                return selected, pbp_cache
        if year_filter is not None and scan_dt.year < year_filter:
            break

    if year_filter is not None:
        return selected, pbp_cache
    raise RuntimeError(
        f"Only found {len(selected)} valid game(s) with play-by-play for team '{team_short}' "
        f"within {max_days_back} days from {start_dt}."
    )


def classify_event(text: str) -> dict[str, Any]:
    raw = (text or "").strip()
    lower = raw.lower()

    if not lower:
        return {
            "is_plate_appearance": False,
            "event_category": None,
            "event_cd": pd.NA,
            "event_tx": "",
            "event_desc": "",
            "runs_outs": pd.NA,
            "is_error_text": False,
            "is_strikeout_text": False,
        }

    if any(re.search(pat, lower) for pat in NON_PA_PATTERNS):
        return {
            "is_plate_appearance": False,
            "event_category": None,
            "event_cd": pd.NA,
            "event_tx": "",
            "event_desc": "",
            "runs_outs": pd.NA,
            "is_error_text": "error" in lower,
            "is_strikeout_text": "struck out" in lower,
        }

    event_category: str | None = None
    event_cd: int | pd._libs.missing.NAType = pd.NA
    event_tx = ""
    event_desc = ""
    runs_outs: str | pd._libs.missing.NAType = pd.NA

    if "homered" in lower or "home run" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "home_run", 23, "H", "Homerun", "0"
    elif re.search(r"\btripled\b", lower):
        event_category, event_cd, event_tx, event_desc, runs_outs = "triple", 22, "T", "Triple", "0"
    elif re.search(r"\bdoubled\b", lower):
        event_category, event_cd, event_tx, event_desc, runs_outs = "double", 21, "D", "Double", "0"
    elif re.search(r"\bsingled\b", lower):
        event_category, event_cd, event_tx, event_desc, runs_outs = "single", 20, "S", "Single", "0"
    elif "intentionally walked" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "walk", 15, "I", "Intentional Walk", "0"
    elif re.search(r"\bwalked\b", lower):
        event_category, event_cd, event_tx, event_desc, runs_outs = "walk", 14, "W", "Nonintentional Walk", "0"
    elif "hit by pitch" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "hit_by_pitch", 16, "H", "Hit By Pitch", "0"
    elif "struck out" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "strikeout", 3, "K", "Strikeout", "1"
    elif "reached on" in lower and "error" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "reached_on_error", 18, "E", "Error", "0"
    elif "fielder's choice" in lower or "fielders choice" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "fielders_choice", 19, "FC", "Fielder's Choice", pd.NA
    elif "double play" in lower:
        if "lined into double play" in lower:
            event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "L", "Line out", "2"
        elif "flied into double play" in lower:
            event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "F", "Fly out", "2"
        else:
            event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "G", "Ground out", "2"
    elif "triple play" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "G", "Ground out", "3"
    elif "grounded out" in lower or "out at first" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "G", "Ground out", "1"
    elif "flied out" in lower or "fly out" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "F", "Fly out", "1"
    elif "lined out" in lower or "line out" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "L", "Line out", "1"
    elif "popped up" in lower or "pop out" in lower or "fouled out" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "P", "Pop out", "1"
    elif "sac" in lower or "sacrifice" in lower:
        event_category, event_cd, event_tx, event_desc, runs_outs = "field_out", 2, "G", "Generic Out", "1"

    is_pa = event_category is not None
    if not is_pa:
        return {
            "is_plate_appearance": False,
            "event_category": None,
            "event_cd": pd.NA,
            "event_tx": "",
            "event_desc": "",
            "runs_outs": pd.NA,
            "is_error_text": "error" in lower,
            "is_strikeout_text": "struck out" in lower,
        }

    return {
        "is_plate_appearance": True,
        "event_category": event_category,
        "event_cd": event_cd,
        "event_tx": event_tx,
        "event_desc": event_desc,
        "runs_outs": runs_outs,
        "is_error_text": "error" in lower,
        "is_strikeout_text": "struck out" in lower,
    }


def flatten_canonical_game(selection: GameSelection, pbp_payload: dict[str, Any], team_short: str) -> pd.DataFrame:
    teams = pbp_payload.get("teams", [])
    team_map: dict[Any, dict[str, Any]] = {}
    for team in teams:
        if isinstance(team, dict):
            team_map[team.get("teamId")] = {
                "name_short": str(team.get("nameShort", "")),
                "is_home": bool(team.get("isHome", False)),
            }

    rows: list[dict[str, Any]] = []
    event_order = 0
    periods = pbp_payload.get("periods", [])
    for period in periods:
        if not isinstance(period, dict):
            continue
        inning_number = period.get("periodNumber")
        inning_display = period.get("periodDisplay")
        stats = period.get("playbyplayStats", [])
        if not isinstance(stats, list):
            continue
        for stat in stats:
            if not isinstance(stat, dict):
                continue
            batting_team_id = stat.get("teamId")
            batting_team_info = team_map.get(batting_team_id, {})
            batting_team = str(batting_team_info.get("name_short", ""))
            batting_is_home = bool(batting_team_info.get("is_home", False))

            other_teams = [t for tid, t in team_map.items() if tid != batting_team_id]
            fielding_team = str(other_teams[0].get("name_short", "")) if other_teams else ""

            plays = stat.get("plays", [])
            if not isinstance(plays, list):
                continue
            for play in plays:
                if not isinstance(play, dict):
                    continue
                text = str(play.get("playText") or "").strip()
                parsed = classify_event(text)
                rows.append(
                    {
                        "contest_id": selection.contest_id,
                        "game_date": selection.game_date,
                        "source_url": selection.source_url,
                        "inning_number": pd.to_numeric(inning_number, errors="coerce"),
                        "inning_display": str(inning_display or ""),
                        "event_order": event_order,
                        "batting_team_raw": batting_team,
                        "batting_is_home": batting_is_home,
                        "fielding_team_raw": fielding_team,
                        "inning_top_bot": "bot" if batting_is_home else "top",
                        "play_text": text,
                        "home_score_raw": play.get("homeScore"),
                        "visitor_score_raw": play.get("visitorScore"),
                        **parsed,
                    }
                )
                event_order += 1

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows).sort_values(["contest_id", "event_order"]).reset_index(drop=True)
    df["inning_number"] = pd.to_numeric(df["inning_number"], errors="coerce").astype("Int64")

    df["home_score"] = pd.to_numeric(df["home_score_raw"], errors="coerce")
    df["visitor_score"] = pd.to_numeric(df["visitor_score_raw"], errors="coerce")
    df["home_score"] = df.groupby("contest_id")["home_score"].ffill().fillna(0).astype(int)
    df["visitor_score"] = df.groupby("contest_id")["visitor_score"].ffill().fillna(0).astype(int)
    df["home_delta"] = df.groupby("contest_id")["home_score"].diff().fillna(df["home_score"]).clip(lower=0).astype(int)
    df["visitor_delta"] = (
        df.groupby("contest_id")["visitor_score"].diff().fillna(df["visitor_score"]).clip(lower=0).astype(int)
    )

    df["runs_for_batting"] = np.where(df["batting_is_home"], df["home_delta"], df["visitor_delta"]).astype(int)
    df["batting_runs_after"] = np.where(df["batting_is_home"], df["home_score"], df["visitor_score"]).astype(int)
    df["fielding_runs_after"] = np.where(df["batting_is_home"], df["visitor_score"], df["home_score"]).astype(int)

    df["batting_team_label"] = np.where(df["batting_team_raw"] == team_short, "USD", "OPP")
    df["fielding_team_label"] = np.where(df["fielding_team_raw"] == team_short, "USD", "OPP")
    df["is_baserunner_event"] = df["event_category"].isin(BASERUNNER_EVENTS)
    return df


def build_baseballr_style(canonical_df: pd.DataFrame) -> pd.DataFrame:
    out = pd.DataFrame(
        {
            "game_date": canonical_df["game_date"],
            "location": "",
            "attendance": pd.NA,
            "inning": canonical_df["inning_number"],
            "inning_top_bot": canonical_df["inning_top_bot"],
            "score": canonical_df["batting_runs_after"].astype(str)
            + "-"
            + canonical_df["fielding_runs_after"].astype(str),
            "batting": canonical_df["batting_team_raw"],
            "fielding": canonical_df["fielding_team_raw"],
            "description": canonical_df["play_text"],
            "game_pbp_url": canonical_df["source_url"].apply(
                lambda value: f"https://www.ncaa.com{value}" if str(value).startswith("/") else str(value)
            ),
            "game_pbp_id": canonical_df["contest_id"],
        }
    )
    return out.reset_index(drop=True)


def build_retrosheet_style(canonical_df: pd.DataFrame) -> pd.DataFrame:
    pa_df = canonical_df[canonical_df["is_plate_appearance"]].copy()
    pa_df["runs_outs"] = pa_df["runs_outs"].astype("string")
    pa_df["runs_outs_desc"] = pa_df["runs_outs"].map(RUNS_OUTS_DESC).fillna("")
    pa_df["pit_id"] = (
        "pit_" + pa_df["contest_id"].astype(str) + "_" + pa_df["event_order"].astype(int).astype(str).str.zfill(4)
    )
    pa_df["bat_id"] = (
        "bat_" + pa_df["contest_id"].astype(str) + "_" + pa_df["event_order"].astype(int).astype(str).str.zfill(4)
    )

    out = pd.DataFrame(
        {
            "game_id": pa_df["contest_id"],
            "inning": pa_df["inning_number"],
            "bat_home_id": pa_df["batting_is_home"].astype(int),
            "bat_team_id": pa_df["batting_team_label"],
            "fld_team_id": pa_df["fielding_team_label"],
            "bat_id": pa_df["bat_id"],
            "pit_id": pa_df["pit_id"],
            "event_cd": pa_df["event_cd"].astype("Int64"),
            "event_tx": pa_df["event_tx"],
            "event_desc": pa_df["event_desc"],
            "runs_outs": pa_df["runs_outs"],
            "runs_outs_desc": pa_df["runs_outs_desc"],
        }
    )
    return out.reset_index(drop=True)


def assign_leadoff_flags(df: pd.DataFrame, half_keys: list[str], order_col: str, event_col: str) -> pd.Series:
    flags = pd.Series(0, index=df.index, dtype="int64")
    grouped = df.sort_values(order_col).groupby(half_keys, dropna=False, sort=False)
    for _, group in grouped:
        if group.empty:
            continue
        first_idx = group.index[0]
        if df.loc[first_idx, event_col] in BASERUNNER_EVENTS:
            flags.loc[first_idx] = 1
    return flags


def event_to_total_bases(event_category: str | None) -> int:
    if event_category == "single":
        return 1
    if event_category == "double":
        return 2
    if event_category == "triple":
        return 3
    if event_category == "home_run":
        return 4
    if event_category in {"walk", "hit_by_pitch"}:
        return 1
    return 0


def summarize_baseballr_exact(game_df: pd.DataFrame) -> tuple[dict[str, Any], dict[str, str]]:
    metric_values: dict[str, Any] = {}
    metric_reasons: dict[str, str] = {}

    pa_df = game_df[game_df["is_plate_appearance"]].copy()
    half_keys = ["contest_id", "inning_number", "batting_team_label"]
    half_all = game_df.groupby(half_keys, dropna=False).size().reset_index(name="rows")
    half_pa = pa_df.groupby(half_keys, dropna=False).size().reset_index(name="rows")
    half_merged = half_all.merge(half_pa, on=half_keys, how="left", suffixes=("_all", "_pa"))
    missing_first_pa = half_merged["rows_pa"].isna().any()

    if missing_first_pa:
        metric_reasons["B1a Leadoff Runners (Off)"] = "AMBIGUOUS_LEADOFF_NO_PARSED_PA"
        metric_reasons["B1b Leadoff Runners (Def)"] = "AMBIGUOUS_LEADOFF_NO_PARSED_PA"
    else:
        first_pa = pa_df.sort_values("event_order").groupby(half_keys, as_index=False).first()
        leadoff_success = first_pa[first_pa["event_category"].isin(BASERUNNER_EVENTS)]
        metric_values["B1a Leadoff Runners (Off)"] = int((leadoff_success["batting_team_label"] == "USD").sum())
        metric_values["B1b Leadoff Runners (Def)"] = int((leadoff_success["batting_team_label"] == "OPP").sum())

    metric_reasons["B2a Leadoff Runs % (Off)"] = "MISSING_EXACT_INNING_RUN_ATTRIBUTION"
    metric_reasons["B2b Leadoff Stranded % (Def)"] = "MISSING_EXACT_INNING_RUN_ATTRIBUTION"

    unknown_pa = pa_df["event_category"].isna().any()
    if unknown_pa:
        metric_reasons["B3a Total Baserunners (Off)"] = "UNKNOWN_PA_EVENT_CATEGORY"
        metric_reasons["B3b Total Baserunners (Def)"] = "UNKNOWN_PA_EVENT_CATEGORY"
        metric_reasons["B5a BB+HBP (Off) vs K"] = "UNKNOWN_PA_EVENT_CATEGORY"
        metric_reasons["B5b BB+HBP (Def)"] = "UNKNOWN_PA_EVENT_CATEGORY"
    else:
        metric_values["B3a Total Baserunners (Off)"] = int(
            pa_df[(pa_df["batting_team_label"] == "USD") & (pa_df["event_category"].isin(BASERUNNER_EVENTS))].shape[0]
        )
        metric_values["B3b Total Baserunners (Def)"] = int(
            pa_df[(pa_df["batting_team_label"] == "OPP") & (pa_df["event_category"].isin(BASERUNNER_EVENTS))].shape[0]
        )
        off_bb_hbp = int(
            pa_df[(pa_df["batting_team_label"] == "USD") & (pa_df["event_category"].isin({"walk", "hit_by_pitch"}))].shape[0]
        )
        off_ks = int(pa_df[(pa_df["batting_team_label"] == "USD") & (pa_df["is_strikeout_text"])].shape[0])
        def_bb_hbp = int(
            pa_df[(pa_df["batting_team_label"] == "OPP") & (pa_df["event_category"].isin({"walk", "hit_by_pitch"}))].shape[0]
        )
        metric_values["B5a BB+HBP (Off) vs K"] = f"{off_bb_hbp}/{off_ks}"
        metric_values["B5b BB+HBP (Def)"] = def_bb_hbp

    metric_reasons["B3c Total Bases + XBs (Off)"] = "MISSING_ANY_ADV_RUNNER_STATE"
    metric_values["B4 Defensive Errors (Pitch)"] = int(
        game_df[(game_df["fielding_team_label"] == "USD") & (game_df["is_error_text"])].shape[0]
    )
    return metric_values, metric_reasons


def summarize_retrosheet_exact(game_df: pd.DataFrame, retrosheet_df: pd.DataFrame) -> tuple[dict[str, Any], dict[str, str]]:
    metric_values: dict[str, Any] = {}
    metric_reasons: dict[str, str] = {}

    retro_game = retrosheet_df[retrosheet_df["game_id"] == str(game_df["contest_id"].iloc[0])].copy()
    if retro_game.empty:
        for metric in METRIC_ORDER:
            metric_reasons[metric] = "NO_RETROSHEET_ROWS"
        return metric_values, metric_reasons

    retro_game["event_cd"] = pd.to_numeric(retro_game["event_cd"], errors="coerce").astype("Int64")
    has_unknown_cd = retro_game["event_cd"].isna().any()

    half_all = game_df.groupby(["contest_id", "inning_number", "batting_team_label"], dropna=False).size().reset_index(name="rows")
    half_retro = (
        retro_game.groupby(["game_id", "inning", "bat_team_id"], dropna=False)
        .size()
        .reset_index(name="rows")
        .rename(
            columns={
                "game_id": "contest_id",
                "inning": "inning_number",
                "bat_team_id": "batting_team_label",
            }
        )
    )
    half_merged = half_all.merge(half_retro, on=["contest_id", "inning_number", "batting_team_label"], how="left")
    missing_first_pa = half_merged["rows_y"].isna().any()

    if missing_first_pa:
        metric_reasons["B1a Leadoff Runners (Off)"] = "AMBIGUOUS_LEADOFF_NO_RETROSHEET_EVENT"
        metric_reasons["B1b Leadoff Runners (Def)"] = "AMBIGUOUS_LEADOFF_NO_RETROSHEET_EVENT"
    else:
        first_pa = (
            retro_game.sort_values(["inning", "bat_id"])
            .groupby(["inning", "bat_team_id"], as_index=False)
            .first()
        )
        reached_mask = first_pa["event_cd"].isin([14, 16, 20, 21, 22, 23])
        metric_values["B1a Leadoff Runners (Off)"] = int((first_pa[reached_mask]["bat_team_id"] == "USD").sum())
        metric_values["B1b Leadoff Runners (Def)"] = int((first_pa[reached_mask]["bat_team_id"] == "OPP").sum())

    metric_reasons["B2a Leadoff Runs % (Off)"] = "MISSING_EXACT_INNING_RUN_ATTRIBUTION"
    metric_reasons["B2b Leadoff Stranded % (Def)"] = "MISSING_EXACT_INNING_RUN_ATTRIBUTION"
    metric_reasons["B3c Total Bases + XBs (Off)"] = "MISSING_TOTAL_BASES_PLUS_ANY_ADV_FIELDS"
    metric_reasons["B4 Defensive Errors (Pitch)"] = "RETROSHEET_STYLE_NO_FULL_ERROR_TEXT_CONTEXT"

    if has_unknown_cd:
        metric_reasons["B3a Total Baserunners (Off)"] = "UNKNOWN_RETROSHEET_EVENT_CODE"
        metric_reasons["B3b Total Baserunners (Def)"] = "UNKNOWN_RETROSHEET_EVENT_CODE"
        metric_reasons["B5a BB+HBP (Off) vs K"] = "UNKNOWN_RETROSHEET_EVENT_CODE"
        metric_reasons["B5b BB+HBP (Def)"] = "UNKNOWN_RETROSHEET_EVENT_CODE"
    else:
        metric_values["B3a Total Baserunners (Off)"] = int(
            retro_game[(retro_game["bat_team_id"] == "USD") & (retro_game["event_cd"].isin([14, 16, 20, 21, 22, 23]))].shape[0]
        )
        metric_values["B3b Total Baserunners (Def)"] = int(
            retro_game[(retro_game["bat_team_id"] == "OPP") & (retro_game["event_cd"].isin([14, 16, 20, 21, 22, 23]))].shape[0]
        )
        off_bb_hbp = int(
            retro_game[(retro_game["bat_team_id"] == "USD") & (retro_game["event_cd"].isin([14, 16]))].shape[0]
        )
        off_ks = int(retro_game[(retro_game["bat_team_id"] == "USD") & (retro_game["event_cd"] == 3)].shape[0])
        def_bb_hbp = int(
            retro_game[(retro_game["bat_team_id"] == "OPP") & (retro_game["event_cd"].isin([14, 16]))].shape[0]
        )
        metric_values["B5a BB+HBP (Off) vs K"] = f"{off_bb_hbp}/{off_ks}"
        metric_values["B5b BB+HBP (Def)"] = def_bb_hbp

    return metric_values, metric_reasons


def try_import_battle_logic() -> Any:
    try:
        from .battle_logic import compute_battle_metrics_table

        return compute_battle_metrics_table
    except ImportError:
        script_dir = Path(__file__).resolve().parent
        if str(script_dir) not in sys.path:
            sys.path.insert(0, str(script_dir))
        from ncaa.pbp.battle_logic import compute_battle_metrics_table

        return compute_battle_metrics_table


def build_normalized_for_battle(game_df: pd.DataFrame) -> pd.DataFrame:
    norm = game_df.copy()
    norm["battingTeam"] = norm["batting_team_label"]
    norm["pitchingTeam"] = norm["fielding_team_label"]
    norm["inn"] = norm["inning_number"].astype(str)
    norm["pitchResult"] = norm["play_text"]
    norm["event_category"] = norm["event_category"].fillna("unknown")
    norm["Runs Scored"] = norm["runs_for_batting"].astype(int)
    norm["total_bases"] = norm["event_category"].apply(event_to_total_bases).astype(int)
    norm["any_adv"] = pd.NA
    norm["gameDate"] = pd.to_datetime(norm["game_date"])
    norm["inning_leadoff"] = 0

    pa_norm = norm[norm["is_plate_appearance"]].copy()
    if not pa_norm.empty:
        leadoff_flags = assign_leadoff_flags(
            pa_norm,
            ["contest_id", "inning_number", "battingTeam"],
            "event_order",
            "event_category",
        )
        norm.loc[leadoff_flags[leadoff_flags == 1].index, "inning_leadoff"] = 1

    return norm[
        [
            "battingTeam",
            "pitchingTeam",
            "inn",
            "inning_leadoff",
            "Runs Scored",
            "event_category",
            "pitchResult",
            "total_bases",
            "any_adv",
            "gameDate",
        ]
    ].copy()


def compute_battle_integration_status(canonical_df: pd.DataFrame) -> dict[str, dict[str, str]]:
    compute_battle_metrics_table = try_import_battle_logic()
    integration: dict[str, dict[str, str]] = {"baseballr": {}, "retrosheet": {}}

    for contest_id, game_df in canonical_df.groupby("contest_id", sort=False):
        normalized = build_normalized_for_battle(game_df)
        try:
            _ = compute_battle_metrics_table(normalized)
            integration["baseballr"][str(contest_id)] = "ok"
        except Exception as exc:
            integration["baseballr"][str(contest_id)] = f"error: {exc}"

        retrosheet_norm = normalized[normalized["event_category"] != "unknown"].copy()
        try:
            _ = compute_battle_metrics_table(retrosheet_norm)
            integration["retrosheet"][str(contest_id)] = "ok"
        except Exception as exc:
            integration["retrosheet"][str(contest_id)] = f"error: {exc}"

    return integration


def build_metric_records(
    canonical_df: pd.DataFrame,
    retrosheet_df: pd.DataFrame,
) -> dict[str, dict[str, dict[str, dict[str, Any]]]]:
    records: dict[str, dict[str, dict[str, dict[str, Any]]]] = {"baseballr": {}, "retrosheet": {}}

    for contest_id, game_df in canonical_df.groupby("contest_id", sort=False):
        game_key = str(contest_id)
        b_values, b_reasons = summarize_baseballr_exact(game_df)
        r_values, r_reasons = summarize_retrosheet_exact(game_df, retrosheet_df)
        records["baseballr"][game_key] = {}
        records["retrosheet"][game_key] = {}

        for metric in METRIC_ORDER:
            records["baseballr"][game_key][metric] = {
                "status": "Exact-Computed" if metric in b_values else "Not-Computable-Exact",
                "value": b_values.get(metric, ""),
                "reason": "" if metric in b_values else b_reasons.get(metric, "UNSPECIFIED"),
            }
            records["retrosheet"][game_key][metric] = {
                "status": "Exact-Computed" if metric in r_values else "Not-Computable-Exact",
                "value": r_values.get(metric, ""),
                "reason": "" if metric in r_values else r_reasons.get(metric, "UNSPECIFIED"),
            }

    return records


def aggregate_matrix(records: dict[str, dict[str, dict[str, dict[str, Any]]]]) -> list[dict[str, str]]:
    total_games = len(records["baseballr"])
    rows: list[dict[str, str]] = []
    for metric in METRIC_ORDER:
        row = {"Metric": metric}
        for style in ["baseballr", "retrosheet"]:
            statuses = [payload[metric]["status"] for payload in records[style].values()]
            computed = sum(status == "Exact-Computed" for status in statuses)
            not_computed = total_games - computed
            row[style] = (
                f"{computed}/{total_games} Exact-Computed; "
                f"{not_computed}/{total_games} Not-Computable-Exact"
            )
        rows.append(row)
    return rows


def collect_reason_notes(records: dict[str, dict[str, dict[str, dict[str, Any]]]]) -> dict[str, dict[str, list[str]]]:
    notes: dict[str, dict[str, list[str]]] = {"baseballr": {}, "retrosheet": {}}
    for style in ["baseballr", "retrosheet"]:
        for metric in METRIC_ORDER:
            reasons: set[str] = set()
            for game_payload in records[style].values():
                cell = game_payload[metric]
                if cell["status"] == "Not-Computable-Exact":
                    reasons.add(str(cell["reason"]))
            notes[style][metric] = sorted(reasons)
    return notes


def first_computed_samples(records: dict[str, dict[str, dict[str, dict[str, Any]]]]) -> dict[str, list[tuple[str, str, Any]]]:
    samples: dict[str, list[tuple[str, str, Any]]] = {"baseballr": [], "retrosheet": []}
    for style in ["baseballr", "retrosheet"]:
        for game_id, metric_payload in records[style].items():
            values = []
            for metric in METRIC_ORDER:
                cell = metric_payload[metric]
                if cell["status"] == "Exact-Computed":
                    values.append((game_id, metric, cell["value"]))
            if values:
                samples[style] = values
                break
    return samples


def build_markdown_report(
    selections: list[GameSelection],
    matrix_rows: list[dict[str, str]],
    reason_notes: dict[str, dict[str, list[str]]],
    samples: dict[str, list[tuple[str, str, Any]]],
    integration: dict[str, dict[str, str]],
) -> str:
    lines: list[str] = []
    lines.append("# Real 5-Game Battle Feasibility (Exact-Only)")
    lines.append("")
    lines.append("Built from the workflow in `Baseball/battles/cursor_battle_logic_migration_and_docum.md`.")
    lines.append("")
    lines.append("## Selected Games")
    lines.append("")
    lines.append("| Game Date | Contest ID | Away | Home | Source |")
    lines.append("|---|---:|---|---|---|")
    for s in selections:
        lines.append(
            f"| {s.game_date} | {s.contest_id} | {s.away_short} | {s.home_short} | `https://www.ncaa.com{s.source_url}` |"
        )

    lines.append("")
    lines.append("## Battle Input Checklist (Exact-Only)")
    lines.append("")
    lines.append("| Metric | Required Inputs | Baseballr-style Exact Rule | Retrosheet-style Exact Rule | Hard Failure Condition |")
    lines.append("|---|---|---|---|---|")
    lines.append(
        "| B1a/B1b | inning side + first PA event + on-base type | Identify first parsed PA each half-inning and check on-base event set | Use first coded event each half-inning and event_cd in {14,16,20,21,22,23} | Missing first PA event for any relevant half-inning |"
    )
    lines.append(
        "| B2a/B2b | leadoff success + inning run/no-run outcome | Requires exact inning run attribution after leadoff event | Same requirement plus inning-level run attribution from coded feed | Missing exact inning run attribution by half-inning |"
    )
    lines.append(
        "| B3a/B3b | event-level baserunner outcomes | Count parsed events in {single,double,triple,home_run,walk,hit_by_pitch} | Count event_cd in {14,16,20,21,22,23} | Unknown event classification/code in relevant PA rows |"
    )
    lines.append(
        "| B3c | total_bases and any_adv | Needs exact runner-state advancement (`any_adv`) | Needs exact runner-state advancement and total-bases+adv fields | Missing runner-state advancement fields |"
    )
    lines.append(
        "| B4 | defensive error events | Count `error` text while USD is fielding | Requires full error context beyond limited coded-event rows | Missing full defensive error context in style |"
    )
    lines.append(
        "| B5a/B5b | BB+HBP and strikeout counts | Parse walk/HBP and strikeout events from text | Use event_cd {14,16} for BB/HBP and 3 for K | Unknown event classification/code in relevant rows |"
    )

    lines.append("")
    lines.append("## Main Matrix")
    lines.append("")
    lines.append("| Metric | baseballr | retrosheet |")
    lines.append("|---|---|---|")
    for row in matrix_rows:
        lines.append(f"| {row['Metric']} | {row['baseballr']} | {row['retrosheet']} |")

    lines.append("")
    lines.append("## Style Notes")
    lines.append("")
    for style in ["baseballr", "retrosheet"]:
        lines.append(f"### {style}")
        notes_written = False
        for metric in METRIC_ORDER:
            reasons = reason_notes[style][metric]
            if reasons:
                notes_written = True
                lines.append(f"- `{metric}`: {', '.join(reasons)}")
        if not notes_written:
            lines.append("- All metrics exact-computable.")
        lines.append("")

    lines.append("## Exact-Computed Samples")
    lines.append("")
    for style in ["baseballr", "retrosheet"]:
        lines.append(f"### {style}")
        if not samples[style]:
            lines.append("- No exact-computed metric samples available.")
            lines.append("")
            continue
        lines.append("| Game ID | Metric | Value |")
        lines.append("|---|---|---|")
        for game_id, metric, value in samples[style]:
            lines.append(f"| {game_id} | {metric} | {value} |")
        lines.append("")

    lines.append("## Battle Logic Integration Check")
    lines.append("")
    lines.append("| Style | Game ID | `compute_battle_metrics_table` |")
    lines.append("|---|---|---|")
    for style in ["baseballr", "retrosheet"]:
        for game_id, status in integration[style].items():
            lines.append(f"| {style} | {game_id} | {status} |")
    lines.append("")
    return "\n".join(lines)


def write_selected_games_csv(selections: list[GameSelection], out_path: Path) -> None:
    rows = [
        {
            "game_date": s.game_date,
            "contest_id": s.contest_id,
            "away_short": s.away_short,
            "home_short": s.home_short,
            "source_url": f"https://www.ncaa.com{s.source_url}",
            "title": s.title,
        }
        for s in selections
    ]
    pd.DataFrame(rows).to_csv(out_path, index=False)


def main() -> None:
    args = parse_args()
    start_dt = datetime.strptime(args.start_date, "%Y-%m-%d").date()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    session.headers.update({"User-Agent": "Mozilla/5.0 (compatible; pbp-battle-feasibility/1.0)"})

    selections, pbp_cache = select_games(
        session=session,
        team_short=args.team_short,
        games_needed=args.games,
        start_dt=start_dt,
        max_days_back=args.max_days_back,
        year_filter=args.year,
    )

    battles_dir = out_dir / "battles"
    battles_dir.mkdir(parents=True, exist_ok=True)
    baseballr_path = battles_dir / "real5_pbp_baseballr_style.csv"
    retrosheet_path = battles_dir / "real5_pbp_retrosheet_style.csv"
    report_path = battles_dir / "real5_battle_feasibility.md"
    selected_games_path = battles_dir / "real5_selected_games.csv"

    if not selections:
        baseballr_cols = [
            "game_date", "location", "attendance", "inning", "inning_top_bot", "score",
            "batting", "fielding", "description", "game_pbp_url", "game_pbp_id",
        ]
        pd.DataFrame(columns=baseballr_cols).to_csv(baseballr_path, index=False)
        retrosheet_cols = [
            "game_id", "inning", "bat_home_id", "bat_team_id", "fld_team_id",
            "bat_id", "pit_id", "event_cd", "event_tx", "event_desc", "runs_outs", "runs_outs_desc",
        ]
        pd.DataFrame(columns=retrosheet_cols).to_csv(retrosheet_path, index=False)
        report_path.write_text("# No games found\n\nNo play-by-play data for the given criteria.\n", encoding="utf-8")
        pd.DataFrame(columns=["game_date", "contest_id", "away_short", "home_short", "source_url", "title"]).to_csv(
            selected_games_path, index=False
        )
        print("Wrote (empty):")
        print(f"- {baseballr_path}")
        print(f"- {retrosheet_path}")
        print(f"- {report_path}")
        print(f"- {selected_games_path}")
        print("")
        print(f"No games found for team '{args.team_short}' (year_filter={args.year}).")
        return

    canonical_frames = [
        flatten_canonical_game(selection, pbp_cache[selection.contest_id], args.team_short)
        for selection in selections
    ]
    canonical_df = pd.concat(canonical_frames, ignore_index=True)
    canonical_df = canonical_df.sort_values(["contest_id", "event_order"]).reset_index(drop=True)

    baseballr_df = build_baseballr_style(canonical_df)
    retrosheet_df = build_retrosheet_style(canonical_df)

    records = build_metric_records(canonical_df, retrosheet_df)
    matrix_rows = aggregate_matrix(records)
    reason_notes = collect_reason_notes(records)
    samples = first_computed_samples(records)
    integration = compute_battle_integration_status(canonical_df)

    report_md = build_markdown_report(
        selections=selections,
        matrix_rows=matrix_rows,
        reason_notes=reason_notes,
        samples=samples,
        integration=integration,
    )

    baseballr_df.to_csv(baseballr_path, index=False)
    retrosheet_df.to_csv(retrosheet_path, index=False)
    report_path.write_text(report_md, encoding="utf-8")
    write_selected_games_csv(selections, selected_games_path)

    print("Wrote:")
    print(f"- {baseballr_path}")
    print(f"- {retrosheet_path}")
    print(f"- {report_path}")
    print(f"- {selected_games_path}")
    print("")
    print(f"Selected {len(selections)} games for team '{args.team_short}'.")


if __name__ == "__main__":
    main()
