"""
USD Baseball Battle Logic — Standalone Module
============================================

This module implements the "Offense Battles" (Battles 1–5) used to evaluate
USD team performance. All calculations assume a pandas DataFrame of play-by-play
(or inning-level) data with columns: battingTeam, pitchingTeam, inn, inning_leadoff,
Runs Scored, event_category, pitchResult, total_bases, any_adv, gameDate, totalRuns,
opponentRuns, opponent, gameId. Data is filtered to battingTeam == "USD" for offense
and pitchingTeam == "USD" for defense.

--------------------------------------------------------------------------------
BATTLE 1: Leadoff Baserunners
--------------------------------------------------------------------------------
  • Offense goal: Get a baserunner in 4+ different innings in the leadoff spot.
  • Defense goal: Allow a leadoff baserunner in 3 or fewer innings.

  Calculation:
    - Offense: Sum of inning_leadoff over all rows where battingTeam == "USD".
      Each inning counts at most once (inning_leadoff is 1 if that inning had a
      leadoff runner). Goal met if count >= 4.
    - Defense: Same sum over rows where pitchingTeam == "USD". Goal met if count <= 3.

--------------------------------------------------------------------------------
BATTLE 2: Score the Leadoff Baserunners
--------------------------------------------------------------------------------
  • Offense goal: When we get a leadoff runner, score in at least 67% of those innings.
  • Defense goal: When the opponent gets a leadoff runner, strand them (no run) in
    at least 70% of those innings.

  Calculation:
    - Offense: Group batting data by inn; for innings where inning_leadoff == 1,
      count how many have Runs Scored > 0. Percentage = (innings with run) / (innings
      with leadoff runner) * 100. Goal met if pct >= 67.
    - Defense: Same grouping for pitching; count innings where leadoff reached and
      Runs Scored > 0 (runs allowed). Stranded = (innings with leadoff) - (innings
      with run). Percentage = stranded / (innings with leadoff) * 100. Goal met if
      pct >= 70.

--------------------------------------------------------------------------------
BATTLE 3: Total Baserunners
--------------------------------------------------------------------------------
  • Offense goals: (a) 16+ total baserunners, (b) Total bases + extra-base advances
    (any_adv) + BB+HBP sum to 24+.
  • Defense goal: Allow 13 or fewer total baserunners.

  Calculation:
    - Baserunner events: single, double, triple, home_run, walk, hit_by_pitch
      (event_category in that set).
    - Offense BR: Count of such events when battingTeam == "USD". Goal (a) met if >= 16.
    - Defense BR: Count when pitchingTeam == "USD". Goal met if <= 13.
    - Total bases + XBs: Sum of total_bases + any_adv + (walk + hit_by_pitch count) for
      batting rows. Goal (b) met if sum >= 24.

--------------------------------------------------------------------------------
BATTLE 4: Clean Defense
--------------------------------------------------------------------------------
  • Goal: Zero defensive errors (when USD is pitching).

  Calculation:
    - Count rows where pitchingTeam == "USD" and pitchResult contains "error"
      (case-insensitive). Goal met if count == 0.

--------------------------------------------------------------------------------
BATTLE 5: Free 90s (Walks + HBP)
--------------------------------------------------------------------------------
  • Offense goal: More walks + HBP than strikeouts.
  • Defense goal: Allow 4 or fewer walks + HBP.

  Calculation:
    - Offense: Count event_category in {"walk", "hit_by_pitch"} for batting;
      count pitchResult containing "Strikeout" for batting. Goal met if
      (walk + HBP) > strikeouts.
    - Defense: Count event_category in {"walk", "hit_by_pitch"} when pitching.
      Goal met if count <= 4.
"""

from __future__ import annotations

import os
from textwrap import fill

import numpy as np
import pandas as pd


# Define performance goals based on the 2025 OFFENSE BATTLES document
GOALS = {
    "Battle 1: Leadoff Baserunners": {
        "Leadoff Runners (Offense)": 4,   # Offense goal: get to 4+ leadoff runners
        "Leadoff Runners (Defense)": 3    # Defense goal: 3 or fewer allowed
    },
    "Battle 2: Score the Leadoff Baserunners": {
        "Leadoff Runs % (Offense)": 67,     # Offense goal: 67% or higher
        "Leadoff Stranded % (Defense)": 70  # Defense goal: 70% or higher
    },
    "Battle 3: Total Baserunners": {
        "Total Baserunners (Offense)": 16,  # Offense goal: get to 16+ baserunners
        "Total BR + Extra Bases (Offense)": 24,
        "Total Baserunners (Defense)": 13   # Defense goal: 13 or fewer allowed
    },
    "Battle 4: Clean Defense": {
        "Defensive Errors (Pitching)": 0   # Goal: 0 USD errors
    },
    "Battle 5: Free 90s": {
        "BB + HBP (Offense)": "More than K",  # Offense goal: more walks/HBP than strikeouts
        "BB + HBP (Defense)": 4              # Defense goal: 4 or fewer allowed
    }
}


def compute_battle_performance(df: pd.DataFrame) -> dict:
    """
    Computes battle metrics for USD, separating batting and pitching performances.
    Includes numerator and denominator for percentage calculations and
    compares actual values to defined goals.
    """
    batting_df = df[df["battingTeam"] == "USD"].copy()
    pitching_df = df[df["pitchingTeam"] == "USD"].copy()

    # Battle 1: Leadoff Baserunners
    leadoff_success_bat = batting_df["inning_leadoff"].sum()
    leadoff_success_pitch = pitching_df["inning_leadoff"].sum()

    # Battle 2: Score the Leadoff Baserunners (Offense)
    if leadoff_success_bat > 0:
        grouped_inn_bat = batting_df.groupby("inn").agg({
            "inning_leadoff": "max",
            "Runs Scored": "max"
        }).reset_index()
        innings_with_runs = grouped_inn_bat[
            (grouped_inn_bat["inning_leadoff"] == 1) & (grouped_inn_bat["Runs Scored"] > 0)
        ].shape[0]
        leadoff_runs_pct = (innings_with_runs / leadoff_success_bat) * 100
        leadoff_runs_text = f"{innings_with_runs}/{leadoff_success_bat} ({leadoff_runs_pct:.1f}%)"
        leadoff_runs_met = leadoff_runs_pct >= GOALS["Battle 2: Score the Leadoff Baserunners"]["Leadoff Runs % (Offense)"]
    else:
        leadoff_runs_text, leadoff_runs_met = "0/0 (0.0%)", False

    # Battle 2: Score the Leadoff Baserunners (Defense)
    if leadoff_success_pitch > 0:
        grouped_inn_pitch = pitching_df.groupby("inn").agg({
            "inning_leadoff": "max",
            "Runs Scored": "max"
        }).reset_index()
        innings_with_runs_allowed = grouped_inn_pitch[
            (grouped_inn_pitch["inning_leadoff"] == 1) & (grouped_inn_pitch["Runs Scored"] > 0)
        ].shape[0]
        innings_leadoff_stranded = leadoff_success_pitch - innings_with_runs_allowed
        leadoff_stranded_pct = (innings_leadoff_stranded / leadoff_success_pitch) * 100
        leadoff_stranded_text = f"{innings_leadoff_stranded}/{leadoff_success_pitch} ({leadoff_stranded_pct:.1f}%)"
        leadoff_stranded_met = leadoff_stranded_pct >= GOALS["Battle 2: Score the Leadoff Baserunners"]["Leadoff Stranded % (Defense)"]
    else:
        leadoff_stranded_text, leadoff_stranded_met = "0/0 (0.0%)", False

    # Battle 3: Total Baserunners
    baserunner_events = {"single", "double", "triple", "home_run", "walk", "hit_by_pitch"}
    total_baserunners_off = batting_df[batting_df["event_category"].isin(baserunner_events)].shape[0]
    total_baserunners_def = pitching_df[pitching_df["event_category"].isin(baserunner_events)].shape[0]
    tb_off = int(batting_df["total_bases"].fillna(0).sum()) if "total_bases" in batting_df.columns else 0
    xb_off = int(batting_df["any_adv"].fillna(0).sum()) if "any_adv" in batting_df.columns else 0
    bb_hbp_off = int(batting_df[batting_df["event_category"].isin(["walk", "hit_by_pitch"])].shape[0]) if "event_category" in batting_df.columns else 0
    tb_plus_xb_off = tb_off + xb_off + bb_hbp_off

    # Battle 4: Clean Defense
    defensive_errors = pitching_df["pitchResult"].str.contains("error", case=False, na=False).sum()

    # Battle 5: Free 90s
    free_90s_off = batting_df[batting_df["event_category"].isin(["walk", "hit_by_pitch"])].shape[0]
    strikeouts_off = batting_df["pitchResult"].str.contains("Strikeout", na=False).sum()
    free_90s_def = pitching_df[pitching_df["event_category"].isin(["walk", "hit_by_pitch"])].shape[0]

    return {
        "Battle 1: Leadoff Baserunners": {
            "Leadoff Runners (Offense)": f"{leadoff_success_bat} (Goal: 4+) {'✔' if leadoff_success_bat >= 4 else '✘'}",
            "Leadoff Runners (Defense)": f"{leadoff_success_pitch} (Goal: ≤3) {'✔' if leadoff_success_pitch <= 3 else '✘'}"
        },
        "Battle 2: Score the Leadoff Baserunners": {
            "Leadoff Runs % (Offense)": f"{leadoff_runs_text} (Goal: 67%+) {'✔' if leadoff_runs_met else '✘'}",
            "Leadoff Stranded % (Defense)": f"{leadoff_stranded_text} (Goal: 70%+) {'✔' if leadoff_stranded_met else '✘'}"
        },
        "Battle 3: Total Baserunners": {
            "Total Baserunners (Offense)": f"{total_baserunners_off} (Goal: 16+) {'✔' if total_baserunners_off >= 16 else '✘'}",
            "Total BR + Extra Bases (Offense)": f"{tb_plus_xb_off} (Goal: 24+) {'✔' if tb_plus_xb_off >= 24 else '✘'}",
            "Total Baserunners (Defense)": f"{total_baserunners_def} (Goal: ≤13) {'✔' if total_baserunners_def <= 13 else '✘'}"
        },
        "Battle 4: Clean Defense": {
            "Defensive Errors (Pitching)": f"{defensive_errors} (Goal: 0) {'✔' if defensive_errors == 0 else '✘'}"
        },
        "Battle 5: Free 90s": {
            "BB + HBP (Offense)": f"{free_90s_off} (Goal: More than K ({strikeouts_off})) {'✔' if free_90s_off > strikeouts_off else '✘'}",
            "BB + HBP (Defense)": f"{free_90s_def} (Goal: ≤4) {'✔' if free_90s_def <= 4 else '✘'}"
        }
    }


def create_battle_report_text(df: pd.DataFrame) -> str:
    """
    Computes the battle performance report and returns it as a formatted string.
    """
    battle_results = compute_battle_performance(df)
    game_date = df["gameDate"].iloc[0].strftime("%Y-%m-%d")

    report_lines = [f"=== USD Battle Performance Report (Battles 1–5) - {game_date} ===\n"]
    for battle_name, metrics in battle_results.items():
        report_lines.append(battle_name)
        for metric_label, metric_value in metrics.items():
            report_lines.append(f"   {metric_label}: {metric_value}")
        report_lines.append("")
    return "\n".join(report_lines)


def compute_battle_metrics_table(df: pd.DataFrame) -> dict:
    """
    Returns per-metric display strings (e.g. '3/4'), met flags for coloring,
    and vs_goal_pct for season summaries. Output keys are canonical metric
    codes used in table columns.
    """
    batting_df = df[df["battingTeam"] == "USD"].copy()
    pitching_df = df[df["pitchingTeam"] == "USD"].copy()

    out = {}

    # Battle 1: Leadoff Runners
    leadoff_off = int(batting_df["inning_leadoff"].sum())
    leadoff_def = int(pitching_df["inning_leadoff"].sum())
    goal_1a, goal_1b = 4, 3
    out["B1a Leadoff Runners (Off)"] = {
        "display": f"{leadoff_off}/{goal_1a}",
        "met": leadoff_off >= goal_1a,
        "value": leadoff_off,
        "goal": goal_1a,
        "vs_goal_pct": (leadoff_off / goal_1a * 100.0) if goal_1a else np.nan
    }
    out["B1b Leadoff Runners (Def)"] = {
        "display": f"{leadoff_def}/{goal_1b}",
        "met": leadoff_def <= goal_1b,
        "value": leadoff_def,
        "goal": goal_1b,
        "vs_goal_pct": (goal_1b / leadoff_def * 100.0) if leadoff_def > 0 else 100.0
    }

    # Battle 2: Leadoff scored / stranded
    if leadoff_off > 0:
        grp_b = batting_df.groupby("inn").agg({"inning_leadoff": "max", "Runs Scored": "max"}).reset_index()
        innings_with_runs = grp_b[(grp_b["inning_leadoff"] == 1) & (grp_b["Runs Scored"] > 0)].shape[0]
        pct_off = (innings_with_runs / leadoff_off) * 100.0
        display_off = f"{innings_with_runs}/{leadoff_off}"
    else:
        innings_with_runs, pct_off, display_off = 0, 0.0, "0/0"

    if leadoff_def > 0:
        grp_p = pitching_df.groupby("inn").agg({"inning_leadoff": "max", "Runs Scored": "max"}).reset_index()
        runs_allowed = grp_p[(grp_p["inning_leadoff"] == 1) & (grp_p["Runs Scored"] > 0)].shape[0]
        stranded = leadoff_def - runs_allowed
        pct_def = (stranded / leadoff_def) * 100.0
        display_def = f"{stranded}/{leadoff_def}"
    else:
        stranded, pct_def, display_def = 0, 0.0, "0/0"

    out["B2a Leadoff Runs % (Off)"] = {
        "display": display_off,
        "met": pct_off >= 67.0,
        "value": pct_off,
        "goal": 67.0,
        "vs_goal_pct": (pct_off / 67.0 * 100.0) if 67.0 else np.nan
    }
    out["B2b Leadoff Stranded % (Def)"] = {
        "display": display_def,
        "met": pct_def >= 70.0,
        "value": pct_def,
        "goal": 70.0,
        "vs_goal_pct": (pct_def / 70.0 * 100.0) if 70.0 else np.nan
    }

    # Battle 3: Total Baserunners
    baserunner_events = {"single", "double", "triple", "home_run", "walk", "hit_by_pitch"}
    tot_off = int(batting_df[batting_df["event_category"].isin(baserunner_events)].shape[0])
    tot_def = int(pitching_df[pitching_df["event_category"].isin(baserunner_events)].shape[0])
    goal_3a, goal_3b = 16, 13
    out["B3a Total Baserunners (Off)"] = {
        "display": f"{tot_off}/{goal_3a}",
        "met": tot_off >= goal_3a,
        "value": tot_off,
        "goal": goal_3a,
        "vs_goal_pct": (tot_off / goal_3a * 100.0)
    }
    out["B3b Total Baserunners (Def)"] = {
        "display": f"{tot_def}/{goal_3b}",
        "met": tot_def <= goal_3b,
        "value": tot_def,
        "goal": goal_3b,
        "vs_goal_pct": (goal_3b / tot_def * 100.0) if tot_def > 0 else 100.0
    }
    tb_off = int(batting_df["total_bases"].fillna(0).sum()) if "total_bases" in batting_df.columns else 0
    xb_off = int(batting_df["any_adv"].fillna(0).sum()) if "any_adv" in batting_df.columns else 0
    bb_hbp_off = int(batting_df[batting_df["event_category"].isin(["walk", "hit_by_pitch"])].shape[0]) if "event_category" in batting_df.columns else 0
    tb_plus_xb_off = tb_off + xb_off + bb_hbp_off
    out["B3c Total Bases + XBs (Off)"] = {
        "display": f"{tb_plus_xb_off}/24",
        "met": tb_plus_xb_off >= 24,
        "value": tb_plus_xb_off,
        "goal": 24,
        "vs_goal_pct": (tb_plus_xb_off / 24 * 100.0)
    }

    # Makeup for B3c: 1B/2B/3B/HR and XB (SB vs WP/PB vs other)
    n1b = int((batting_df["event_category"] == "single").sum()) if "event_category" in batting_df.columns else 0
    n2b = int((batting_df["event_category"] == "double").sum()) if "event_category" in batting_df.columns else 0
    n3b = int((batting_df["event_category"] == "triple").sum()) if "event_category" in batting_df.columns else 0
    nhr = int((batting_df["event_category"] == "home_run").sum()) if "event_category" in batting_df.columns else 0
    xb_sb = int(batting_df["any_adv_sb"].fillna(0).sum()) if "any_adv_sb" in batting_df.columns else 0
    xb_wp_pb = int(batting_df["any_adv_wp_pb"].fillna(0).sum()) if "any_adv_wp_pb" in batting_df.columns else 0
    xb_other = int(batting_df["any_adv_other"].fillna(0).sum()) if "any_adv_other" in batting_df.columns else 0
    out["_makeup"] = {
        "tb": {"1b": n1b, "2b": n2b, "3b": n3b, "hr": nhr},
        "xb": {"sb": xb_sb, "wp_pb": xb_wp_pb, "other": xb_other},
    }

    # Battle 4: Errors
    errors = int(pitching_df["pitchResult"].str.contains("error", case=False, na=False).sum())
    out["B4 Defensive Errors (Pitch)"] = {
        "display": f"{errors}/0",
        "met": errors == 0,
        "value": errors,
        "goal": 0.0,
        "vs_goal_pct": 100.0 if errors == 0 else 0.0
    }

    # Battle 5: Free 90s
    free90_off = int(batting_df[batting_df["event_category"].isin(["walk", "hit_by_pitch"])].shape[0])
    ks_off = int(batting_df["pitchResult"].str.contains("Strikeout", na=False).sum())
    free90_def = int(pitching_df[pitching_df["event_category"].isin(["walk", "hit_by_pitch"])].shape[0])
    out["B5a BB+HBP (Off) vs K"] = {
        "display": f"{free90_off}/{ks_off}",
        "met": free90_off > ks_off,
        "value": free90_off,
        "goal": float(ks_off),
        "vs_goal_pct": (free90_off / max(ks_off, 1) * 100.0)
    }
    out["B5b BB+HBP (Def)"] = {
        "display": f"{free90_def}/4",
        "met": free90_def <= 4,
        "value": free90_def,
        "goal": 4.0,
        "vs_goal_pct": (4.0 / free90_def * 100.0) if free90_def > 0 else 100.0
    }

    return out


def render_season_summary_pdf(rows_df: pd.DataFrame, summary_df: pd.DataFrame, out_path: str) -> None:
    """
    Renders a two-page PDF: Page 1 = game-by-game battle table, Page 2 = season
    totals summary. rows_df and summary_df are produced by the notebook loop that
    calls compute_battle_metrics_table and aggregates Games_Met / Avg_Vs_Goal_Pct.
    """
    import matplotlib.pyplot as plt
    from matplotlib import colors
    from matplotlib.backends.backend_pdf import PdfPages

    metric_cols = [
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
    display_cols = ["GameDate", "Opponent", "Score"] + metric_cols
    wrapped_headers = [fill(h, width=14) for h in display_cols]

    disp = rows_df[display_cols].copy()

    def get_color_for_pct(pct, met, is_error_metric=False):
        if pct is None or (isinstance(pct, float) and np.isnan(pct)):
            return "white"
        if met:
            norm = min(max(pct, 0), 100) / 100.0
            cmap = colors.LinearSegmentedColormap.from_list("", ["#eafaf1", "#6fcf97"])
            return colors.to_hex(cmap(norm))
        else:
            norm = min(max(pct, 0), 100) / 100.0
            cmap = colors.LinearSegmentedColormap.from_list("", ["#fdeaea", "#eb5757"])
            return colors.to_hex(cmap(norm))

    cell_colours = [["white"] * len(display_cols) for _ in range(len(disp))]
    for r_idx, (_, row) in enumerate(rows_df.iterrows()):
        for c_idx, col in enumerate(display_cols):
            if col in ("GameDate", "Opponent", "Score"):
                cell_colours[r_idx][c_idx] = "white"
            else:
                vs_goal_col = col + "__vs_goal_pct"
                met_col = col + "__met"
                is_error_metric = col == "B4 Defensive Errors (Pitch)"
                pct = row.get(vs_goal_col, None)
                met = row.get(met_col, False)
                if pct is None and met_col in row:
                    cell_colours[r_idx][c_idx] = "#c6efce" if met else "#ffc7ce"
                else:
                    cell_colours[r_idx][c_idx] = get_color_for_pct(pct, met, is_error_metric=is_error_metric)

    table_data = [wrapped_headers] + disp.values.tolist()
    colours = [["#d9d9d9"] * len(display_cols)] + cell_colours

    fig1 = plt.figure(figsize=(17, 11))
    fig1.patch.set_facecolor("white")
    plt.suptitle("USD Battles Season Summary - Game by Game", fontsize=18, y=0.98)
    ax1 = plt.axes([0.02, 0.08, 0.96, 0.86])
    ax1.axis("off")

    table = ax1.table(
        cellText=table_data,
        cellLoc="center",
        cellColours=colours,
        loc="upper left"
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1.0, 1.4)
    for c in range(len(display_cols)):
        cell = table[0, c]
        cell.set_text_props(fontweight="bold")
        cell.set_height(0.08)

    # Page 2: totals summary
    fig2 = plt.figure(figsize=(14, 8))
    fig2.patch.set_facecolor("white")
    plt.suptitle("USD Battles Season Totals Summary", fontsize=18, y=0.95)
    ax2 = plt.axes([0.02, 0.08, 0.96, 0.85])
    ax2.axis("off")

    sum_headers = ["Metric", "Games Met", "Avg % of Goal"]
    sum_rows = []
    for metric in metric_cols:
        row = summary_df.loc[summary_df["Metric"] == metric]
        if not row.empty:
            games = int(row["Games"].values[0])
            met = int(row["Games_Met"].values[0])
            avg_pct = row["Avg_Vs_Goal_Pct"].values[0]
            sum_rows.append([fill(metric, width=25), f"{met}/{games}", f"{avg_pct:.1f}%"])
        else:
            sum_rows.append([fill(metric, width=25), "0/0", "—"])

    sum_table_data = [sum_headers] + sum_rows
    sum_colours = [["#d9d9d9", "#d9d9d9", "#d9d9d9"]] + [["white"] * 3 for _ in sum_rows]
    sum_table = ax2.table(
        cellText=sum_table_data,
        cellLoc="center",
        cellColours=sum_colours,
        loc="upper left"
    )
    sum_table.auto_set_font_size(False)
    sum_table.set_fontsize(10)
    sum_table.scale(1.0, 1.4)
    for r in range(len(sum_table_data)):
        for c in range(len(sum_headers)):
            cell = sum_table[r, c]
            if r == 0:
                cell.set_text_props(fontweight="bold")
                cell.set_height(0.08)
            else:
                cell.set_height(0.06)

    with PdfPages(out_path) as pdf:
        pdf.savefig(fig1, bbox_inches="tight", facecolor="white")
        pdf.savefig(fig2, bbox_inches="tight", facecolor="white")
    plt.close(fig1)
    plt.close(fig2)
