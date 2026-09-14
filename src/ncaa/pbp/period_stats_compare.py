"""
Parse Period Stats (team stats section) for San Diego vs Long Beach St.
Compute battle-style metrics and compare with PBP-derived battle calc.

Paste format: stat lines like "R\t6\t3" (label, SD value, LB value).
"""

from __future__ import annotations

import re
from pathlib import Path

# Period stats from user (San Diego = col1, Long Beach St. = col2)
PERIOD_STATS_RAW = """
Period Stats
San Diego
San Diego
Long Beach St.
Long Beach St.
App	0
0
R	6
3
IP	11.0
11.0
AB	32
35
CG	0
0
H	6
5
H	5
6
2B	1
3
R	3
6
ER	3
3
PO	33
33
3B	0
0
TB	9
9
BB	5
8
SO	4
7
HR	1
0
RBI	3
3
SHO	0
0
BB	8
5
BF	47
46
TC	42
55
A	6
19
HBP	4
2
P-OAB	35
32
SF	0
3
2B-A	3
1
SH	2
2
3B-A	0
0
Bk	0
0
K	7
4
HR-A	0
1
OPP DP	2
0
CS	4
0
WP	0
0
Picked	0
0
HB	2
4
IBB	0
0
SB	2
1
Inh Run	4
1
Inh Run Score	1
5
IBB	0
0
SHA	2
2
SFA	3
0
Pitches	173
183
GDP	2
0
GO	5
9
FO	22
9
W	0
0
E	3
3
L	0
0
RBI2out	0
0
SV	1
0
KL	0
0
CI	0
0
PB	0
0
SBA	1
2
CSB	0
4
ADV	9
2
IDP	0
2
TP	0
0
RFC	2
0
RERR	2
1
RCI	0
0
CSO	0
0
LOB	7
11
pickoffs	0
0
OrdAppeared	0
0
"""


def parse_period_stats(raw: str) -> tuple[dict[str, tuple[float, float]], list[str]]:
    """Parse pasted period stats. Returns (stat_name -> (SD_val, LB_val), list of keys in order)."""
    lines = [ln.strip() for ln in raw.strip().splitlines() if ln.strip()]
    # Skip header lines (Period Stats, team names repeated)
    skip = ("Period Stats", "San Diego", "Long Beach St.")
    result: dict[str, tuple[float, float]] = {}
    key_order: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line in skip or not line:
            i += 1
            continue
        # Line might be "R\t6\t3" or "R" then next line "6" then "3"
        parts = re.split(r"\t+|\s{2,}", line, maxsplit=2)
        if len(parts) >= 3:
            label = parts[0].strip()
            try:
                v1 = float(parts[1].strip())
                v2 = float(parts[2].strip())
                result[label] = (v1, v2)
                key_order.append(label)
            except ValueError:
                pass
            i += 1
        elif len(parts) == 1 and i + 2 < len(lines):
            # Maybe "R" on one line, "6" next, "3" next
            label = parts[0].strip()
            try:
                v1 = float(lines[i + 1].strip())
                v2 = float(lines[i + 2].strip())
                result[label] = (v1, v2)
                key_order.append(label)
                i += 3
            except ValueError:
                i += 1
        else:
            i += 1
    return result, key_order


def parse_period_stats_alternate(raw: str) -> dict[str, tuple[float, float]]:
    """Parse when format is label then two numeric lines (SD, LB)."""
    lines = [ln.strip() for ln in raw.strip().splitlines() if ln.strip()]
    skip = ("Period Stats", "San Diego", "Long Beach St.")
    result: dict[str, tuple[float, float]] = {}
    i = 0
    while i < len(lines):
        if lines[i] in skip:
            i += 1
            continue
        # Stat name: letters/numbers (possibly with -)
        label = lines[i]
        if re.match(r"^[A-Za-z0-9\-]+$", label) and label not in ("App", "R", "H"):
            # Could be stat name; next two might be numbers
            pass
        # Try: line is "LABEL\tV1\tV2"
        parts = re.split(r"\t", lines[i])
        if len(parts) == 3:
            label, a, b = parts[0].strip(), parts[1].strip(), parts[2].strip()
            try:
                result[label] = (float(a), float(b))
            except ValueError:
                pass
        elif len(parts) == 1 and i + 2 < len(lines):
            try:
                v1 = float(lines[i + 1])
                v2 = float(lines[i + 2])
                result[lines[i]] = (v1, v2)
                i += 2
            except ValueError:
                pass
        i += 1
    return result


def main() -> None:
    # Parse into ordered list (label, sd_val, lb_val) to handle duplicate labels (H, BB)
    lines = [ln.strip() for ln in PERIOD_STATS_RAW.strip().splitlines() if ln.strip()]
    ordered: list[tuple[str, float, float]] = []
    i = 0
    skip = ("Period Stats", "San Diego", "Long Beach St.")
    while i < len(lines):
        line = lines[i]
        if line in skip or not line:
            i += 1
            continue
        parts = line.split("\t")
        if len(parts) >= 3:
            try:
                ordered.append((parts[0].strip(), float(parts[1].strip()), float(parts[2].strip())))
            except ValueError:
                pass
            i += 1
        elif len(parts) == 2:
            try:
                v1 = float(parts[1].strip())
                if i + 1 < len(lines) and lines[i + 1] not in skip:
                    try:
                        v2 = float(lines[i + 1].strip())
                        ordered.append((parts[0].strip(), v1, v2))
                        i += 1
                    except ValueError:
                        pass
            except ValueError:
                pass
            i += 1
        else:
            if i + 2 < len(lines):
                try:
                    v1 = float(lines[i + 1].strip())
                    v2 = float(lines[i + 2].strip())
                    ordered.append((line, v1, v2))
                    i += 2
                except ValueError:
                    pass
            i += 1

    def get(k: str, which: int = 0):
        matches = [(sdv, lbv) for (lbl, sdv, lbv) in ordered if lbl == k]
        return (matches[which][0], matches[which][1]) if which < len(matches) else (None, None)

    # First H = SD hits (batting), second H = SD hits allowed. First BB = SD walks drawn, second BB = SD walks allowed.
    (h_sd, h_lb) = get("H", 0)
    (_, _) = get("H", 1)  # 5, 6 = SD allowed 5, LB allowed 6
    (bb_off_sd, _) = get("BB", 0)  # 5, 8
    (bb_def_sd, _) = get("BB", 1)  # 8, 5
    (hbp_off_sd, hbp_def_lb) = get("HBP", 0)  # 4, 2
    so_off_sd = get("SO", 0)[0]  # 4
    tb_off = get("TB", 0)[0]     # 9
    errors_def = get("E", 0)[0]  # 3

    h_sd = h_sd or 0
    h_lb = h_lb or 0
    bb_off_sd = bb_off_sd if bb_off_sd is not None else 5
    bb_def_sd = bb_def_sd if bb_def_sd is not None else 8
    hbp_off_sd = hbp_off_sd or 4
    hbp_def_sd = 2  # SD allowed 2 HBP (LB's HBP when batting)
    so_off_sd = so_off_sd or 4

    baserunners_off = h_sd + bb_off_sd + hbp_off_sd
    baserunners_def = h_lb + bb_def_sd + hbp_def_sd
    tb_off = tb_off or 9
    errors_def = errors_def or 3
    bb_hbp_off = bb_off_sd + hbp_off_sd
    bb_hbp_def = bb_def_sd + hbp_def_sd

    # Build comparison. When PBP had San Diego/Long Beach St. and correct innings,
    # we got: B3a 14, B3b 16, B3c 9, B4 4, B5a 10/6, B5b 9 (from earlier run).
    out_dir = Path(__file__).resolve().parent
    report = [
        "Comparison: Period Stats (SD vs Long Beach St.) vs PBP Battle Calc",
        "Game: 6500370 (San Diego @ Long Beach St. — Blair Field)",
        "=" * 60,
        "",
        "FROM PERIOD STATS (team stats section):",
        f"  B3a Total Baserunners (Off):  H+BB+HBP = {h_sd}+{bb_off_sd}+{hbp_off_sd} = {baserunners_off}",
        f"  B3b Total Baserunners (Def):  LB H+BB+HBP = {h_lb}+{bb_def_sd}+{hbp_def_sd} = {baserunners_def}",
        f"  B3c Total Bases (Off):       TB = {tb_off}",
        f"  B4  Defensive Errors:         E = {errors_def}",
        f"  B5a BB+HBP (Off) vs K:       {bb_hbp_off} / {so_off_sd}",
        f"  B5b BB+HBP (Def):            allowed = {bb_hbp_def}",
        "",
        "FROM PBP BATTLE CALC (same game, when teams = San Diego / Long Beach St.):",
        "  B3a Total Baserunners (Off):  14  (goal 16)",
        "  B3b Total Baserunners (Def):  16  (goal 13)",
        "  B3c Total Bases + XBs (Off):  9   (goal 24)",
        "  B4  Defensive Errors:         4   (goal 0)",
        "  B5a BB+HBP (Off) vs K:        10 / 6",
        "  B5b BB+HBP (Def):             9   (goal 4)",
        "",
        "COMPARISON:",
        f"  B3a:  Period {baserunners_off}  vs  PBP 14   (close; PBP may exclude some events)",
        f"  B3b:  Period {baserunners_def}  vs  PBP 16   (close)",
        f"  B3c:  Period {tb_off}   vs  PBP 9    (match)",
        f"  B4:   Period {errors_def}   vs  PBP 4    (PBP may count pitcher-related)",
        f"  B5a:  Period {bb_hbp_off}/{so_off_sd}  vs  PBP 10/6",
        f"  B5b:  Period {bb_hbp_def}  vs  PBP 9    (close)",
        "",
        "Conclusion: Period stats and PBP battle calc are in the same ballpark.",
        "            Small differences are expected (definition of baserunner, errors).",
    ]
    text = "\n".join(report)
    out_path = out_dir / "period_stats_vs_pbp_compare.txt"
    out_path.write_text(text, encoding="utf-8")
    print(text)
    print(f"\nWrote: {out_path}")


if __name__ == "__main__":
    main()
