"""
Build combined battle text + PBP for battle_pdf/generate-pdf.mjs (full season).

Merges:
  - real5_battle_calc_output.txt (early-season games in real5 pipeline)
  - contest_*_battle_calc_output.txt (newer per-contest runs)

Per contest_id, **contest_* overrides** real5 when both exist (updated PBP/scrape).

Usage (from battles/):
  python merge_season_pdf_inputs.py --pdf

Writes ``season_pdf_battle_input.txt`` and ``season_pdf_pbp_input.csv``, then runs Node to refresh
``battle_pdf/season_battle_report.pdf`` and all per-game PDFs. Omit ``--pdf`` to only write the two inputs.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent

HEADER = """USD Baseball — Battle calculation output
Source: baseballr-style PBP via battles/baseballr_battle_calc.py (merged: real5 + contest_*)
============================================================
"""


def _parse_game_blocks(text: str) -> dict[int, str]:
    """Split on 'Game {id} ...' lines; return id -> block including the Game line through following blank-line-separated section."""
    lines = text.splitlines()
    blocks: dict[int, str] = {}
    i = 0
    while i < len(lines):
        m = re.match(r"^Game\s+(\d+)\s+", lines[i])
        if not m:
            i += 1
            continue
        gid = int(m.group(1))
        start = i
        i += 1
        if i < len(lines) and re.match(r"^-+$", lines[i].strip()):
            i += 1
        while i < len(lines) and lines[i].strip() != "":
            i += 1
        end = i
        block = "\n".join(lines[start:end]).rstrip()
        blocks[gid] = block
        while i < len(lines) and lines[i].strip() == "":
            i += 1
    return blocks


def _load_contest_battle_blocks() -> dict[int, str]:
    out: dict[int, str] = {}
    pat = re.compile(r"^contest_(\d+)_battle_calc_output\.txt$", re.I)
    for p in sorted(SCRIPT_DIR.glob("contest_*_battle_calc_output.txt")):
        m = pat.match(p.name)
        if not m:
            continue
        expected_gid = int(m.group(1))
        blocks = _parse_game_blocks(p.read_text(encoding="utf-8"))
        if expected_gid in blocks:
            out[expected_gid] = blocks[expected_gid]
        elif len(blocks) == 1:
            out[expected_gid] = next(iter(blocks.values()))
    return out


def merge_battle_text() -> dict[int, str]:
    real5_path = SCRIPT_DIR / "real5_battle_calc_output.txt"
    if not real5_path.is_file():
        print("Warning: real5_battle_calc_output.txt not found; using contest_* only.", file=sys.stderr)
        merged = {}
    else:
        raw = real5_path.read_text(encoding="utf-8")
        merged = _parse_game_blocks(raw)
    contest_blocks = _load_contest_battle_blocks()
    for gid, block in contest_blocks.items():
        merged[gid] = block
    return merged


def merge_pbp_csv() -> pd.DataFrame:
    """All PBP play rows: real5, with any game_id that has contest_*_pbp.csv replaced in full by the contest file."""
    real5_path = SCRIPT_DIR / "real5_pbp_baseballr_style.csv"
    contest_paths = sorted(
        p
        for p in SCRIPT_DIR.glob("contest_*_pbp.csv")
        if re.match(r"^contest_(\d+)_pbp\.csv$", p.name, re.I)
    )
    contest_frames = [pd.read_csv(p) for p in contest_paths]
    override_ids: set[int] = set()
    for df in contest_frames:
        if "game_pbp_id" not in df.columns:
            continue
        g = pd.to_numeric(df["game_pbp_id"], errors="coerce").dropna().astype(int)
        override_ids.update(g.unique().tolist())

    if not real5_path.is_file():
        if not contest_frames:
            return pd.DataFrame()
        return pd.concat(contest_frames, ignore_index=True)

    real5 = pd.read_csv(real5_path)
    if "game_pbp_id" not in real5.columns:
        return pd.concat([real5] + contest_frames, ignore_index=True)
    r = real5.copy()
    r["game_pbp_id"] = pd.to_numeric(r["game_pbp_id"], errors="coerce")
    r = r[~r["game_pbp_id"].isin(list(override_ids))]
    if not contest_frames:
        return r
    return pd.concat([r] + contest_frames, ignore_index=True)


def _game_sort_key(
    merged_blocks: dict[int, str],
    pbp: pd.DataFrame,
) -> list[int]:
    """Contest IDs sorted by first-seen game_date in pbp, then id."""
    dates: dict[int, str] = {}
    if not pbp.empty and "game_pbp_id" in pbp.columns and "game_date" in pbp.columns:
        for gid, grp in pbp.groupby(pbp["game_pbp_id"].astype(int)):
            d = grp["game_date"].iloc[0]
            if pd.notna(d):
                dates[int(gid)] = str(d).strip()
    gids = sorted(merged_blocks.keys())

    def key(g: int) -> tuple:
        d = dates.get(g, "")
        return (d, g)

    return sorted(gids, key=key)


def main() -> None:
    merged = merge_battle_text()
    if not merged:
        print("No battle data found.", file=sys.stderr)
        sys.exit(1)
    pbp = merge_pbp_csv()
    order = _game_sort_key(merged, pbp)
    lines = [HEADER.rstrip(), ""]
    for gid in order:
        lines.append(merged[gid])
        lines.append("")
    battle_out = SCRIPT_DIR / "season_pdf_battle_input.txt"
    battle_out.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"Wrote {battle_out.name} ({len(merged)} games)")

    pbp_out = SCRIPT_DIR / "season_pdf_pbp_input.csv"
    pbp.to_csv(pbp_out, index=False)
    ng = int(pbp["game_pbp_id"].nunique()) if not pbp.empty and "game_pbp_id" in pbp.columns else 0
    print(f"Wrote {pbp_out.name} ({len(pbp)} rows, {ng} games)")

    pdf_dir = SCRIPT_DIR / "battle_pdf"
    mjs = pdf_dir / "generate-pdf.mjs"
    if "--pdf" in sys.argv or "--run-pdf" in sys.argv:
        cmd = [
            "node",
            str(mjs),
            str(battle_out),
            str(pdf_dir / "season_battle_report.pdf"),
            str(pbp_out),
            str(pdf_dir / "sd_logo.png"),
        ]
        subprocess.run(cmd, check=True, cwd=str(SCRIPT_DIR))
        print("Wrote battle_pdf/season_battle_report.pdf + per-game PDFs")


if __name__ == "__main__":
    main()
