"""One-off: USD roster surnames on opponent batting rows; outs column vs _outs_on_play resim."""
from __future__ import annotations

import re
import sys
from pathlib import Path

import pandas as pd
from ncaa_pbp_playwright import _effective_outs_added, _outs_on_play

from ncaa.pbp.baseballr_description_mappings import has_pa_action

SCRIPT_DIR = Path(__file__).resolve().parent


def roster_surnames(path: Path) -> set[str]:
    s: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if parts[-1] in ("Jr.", "Sr.", "II", "III", "IV") and len(parts) >= 2:
            s.add(parts[-2])
        else:
            s.add(parts[-1])
    return s


def lead_batter_last(desc: str) -> str | None:
    m = re.match(r"^([A-Za-zÀ-ž'\-]+),", str(desc).strip())
    return m.group(1) if m else None


SUR_LOWER = {x.lower() for x in roster_surnames(SCRIPT_DIR / "usd_roster_names.txt")}


def diagnose(cid: int) -> None:
    p = SCRIPT_DIR / f"contest_{cid}_pbp.csv"
    df = pd.read_csv(p)
    print(f"=== contest {cid}  ({len(df)} rows)")

    wrong_batter_side: list[tuple] = []
    mism_team: list[tuple] = []

    for i, row in df.iterrows():
        desc = str(row.get("description", ""))
        bat = str(row.get("batting", ""))
        if not has_pa_action(desc):
            continue
        last = lead_batter_last(desc)
        if not last:
            continue
        if last.lower() not in SUR_LOWER:
            continue
        if "San Francisco" in bat:
            wrong_batter_side.append((i, bat, desc[:120]))
        if "San Diego" not in bat and "Torero" not in bat:
            mism_team.append((i, bat, last, desc[:100]))

    if wrong_batter_side:
        print("USD roster surname as LEAD batter but batting column = San Francisco:")
        for x in wrong_batter_side:
            print(" ", x)
    else:
        print("No plays: lead batter matches USD roster while batting=San Francisco.")

    if mism_team:
        print(f"USD roster lead batter, batting not San Diego ({len(mism_team)} rows):")
        for x in mism_team[:15]:
            print(" ", x)
        if len(mism_team) > 15:
            print(f"  ... +{len(mism_team) - 15} more")

    outs_issues: list[tuple] = []
    for (inn, tb), g in df.groupby(["inning", "inning_top_bot"], sort=False):
        o_half = 0
        for j, row in g.iterrows():
            desc = str(row["description"])
            scr = int(row["outs"]) if pd.notna(row["outs"]) else 0
            raw_o = _outs_on_play(desc)
            add = _effective_outs_added(o_half, raw_o)
            o_half += add
            exp = o_half
            if scr != exp:
                outs_issues.append((inn, tb, j, scr, exp, desc[:100]))
            if o_half >= 3:
                o_half = 0

    if outs_issues:
        print("Outs column vs _outs_on_play resim mismatch:")
        for u in outs_issues[:25]:
            print(" ", u)
        if len(outs_issues) > 25:
            print(f"  ... +{len(outs_issues) - 25} more")
    else:
        print("Outs: scraped column matches _outs_on_play resim for every row (by half).")


def main() -> None:
    cids = [int(x) for x in sys.argv[1:]] if len(sys.argv) > 1 else [6522573, 6522574]
    for cid in cids:
        diagnose(cid)
        print()


if __name__ == "__main__":
    main()
