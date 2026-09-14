"""
Fetch NCAA contest Situational Stats (hitting only) and extract team ``leadoff pct``
totals. The site uses ``X-Y`` where **X = leadoff successes** (what we compare to B1).

Example:
  python ncaa_situational_stats_playwright.py https://stats.ncaa.org/contests/6535305/situational_stats
  python ncaa_situational_stats_playwright.py URL --battle-report contest_6535305_battle_calc_output.txt
  python ncaa_situational_stats_playwright.py --batch-contests

B1 table (PBP): ``B1a`` / ``B1b`` display is ``count/goal`` — the **first number**
is leadoff innings with a baserunner (USD bat / USD pitch). That lines up with
using NCAA’s **first number** as the cross-check, not the denominator ``Y``.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from bs4 import BeautifulSoup

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    raise SystemExit("pip install playwright && playwright install chromium")

DEFAULT_URL = "https://stats.ncaa.org/contests/6535305/situational_stats"
SCRIPT_DIR = Path(__file__).resolve().parent


def extract_contest_id(url: str) -> int | None:
    m = re.search(r"/contests/(\d+)/", url)
    if not m:
        return None
    return int(m.group(1))


def fetch_html(url: str, *, headless: bool = False, wait_ms: int = 4000) -> str:
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"] if headless else [],
        )
        try:
            context = browser.new_context(
                viewport={"width": 1400, "height": 900},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
                locale="en-US",
            )
            context.add_init_script(
                "Object.defineProperty(navigator, 'webdriver', { get: () => undefined })"
            )
            page = context.new_page()
            page.goto(url, wait_until="domcontentloaded", timeout=45000)
            page.wait_for_timeout(wait_ms)
            return page.content()
        finally:
            browser.close()


def _situational_url(contest_id: int) -> str:
    return f"https://stats.ncaa.org/contests/{contest_id}/situational_stats"


def discover_contest_ids_from_battle_reports(directory: Path) -> list[int]:
    ids: list[int] = []
    for p in sorted(directory.glob("contest_*_battle_calc_output.txt")):
        m = re.match(r"contest_(\d+)_battle_calc_output\.txt$", p.name, re.I)
        if m:
            ids.append(int(m.group(1)))
    return sorted(set(ids))


def parse_matchup_from_battle_report(text: str, contest_id: int) -> str:
    for line in text.splitlines():
        m = re.match(rf"^Game\s+{contest_id}\s+\((.+)\)\s*$", line.strip())
        if m:
            return m.group(1).strip()
    return ""


def ncaa_leadoff_succ_usd_and_opp(
    rows: list[tuple[str, int, int, str]],
) -> tuple[int | None, int | None]:
    """From situational hitting rows: (usd_succ, opp_succ)."""
    usd_s: int | None = None
    opp_s: int | None = None
    for team, succ, _opp, _raw in rows:
        if _is_usd_team_name(team):
            usd_s = succ
        else:
            opp_s = succ
    return usd_s, opp_s


def _fmt_ncaa_b1(ncaa: int | None, b1: int | None) -> str:
    if ncaa is None and b1 is None:
        return "-"
    if ncaa is None:
        return f"- / {b1}"
    if b1 is None:
        return f"{ncaa} / -"
    return f"{ncaa} / {b1}"


def batch_situational_vs_b1_verbose(
    contest_ids: list[int],
    *,
    headless: bool = False,
    wait_ms: int = 4000,
) -> None:
    """One browser session: per-contest expanded markdown (legacy)."""
    if not contest_ids:
        print("No contest IDs given.", file=sys.stderr)
        return

    print("# NCAA situational leadoff (1st #) vs Battles B1 - batch")
    print()
    print("For each contest: `Leadoff succ` = first number in NCAA `leadoff pct` total; ")
    print("B1a/B1b first number = PBP leadoff-inning counts from `contest_*_battle_calc_output.txt`.")
    print()

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"] if headless else [],
        )
        try:
            context = browser.new_context(
                viewport={"width": 1400, "height": 900},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
                locale="en-US",
            )
            context.add_init_script(
                "Object.defineProperty(navigator, 'webdriver', { get: () => undefined })"
            )
            page = context.new_page()

            for cid in contest_ids:
                br_path = SCRIPT_DIR / f"contest_{cid}_battle_calc_output.txt"
                b1a_val, b1b_val = None, None
                br_txt = ""
                if br_path.is_file():
                    br_txt = br_path.read_text(encoding="utf-8")
                    b1a_val, b1b_val = parse_b1_from_battle_report(br_txt, cid)

                print(f"## Contest {cid}")
                url = _situational_url(cid)
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=45000)
                    page.wait_for_timeout(wait_ms)
                    html = page.content()
                except Exception as e:
                    print(f"**Fetch failed:** {e}")
                    print()
                    continue

                rows = parse_hitting_leadoff_totals(html)
                if not rows:
                    print("*(No hitting situational tables parsed; try non-headless.)*")
                    print()
                    continue

                print()
                print("| Team (hitting) | Leadoff succ | Opp. | raw |")
                print("|----------------|-------------:|-----:|:----|")
                for team, succ, opp, raw in rows:
                    print(f"| {team} | {succ} | {opp} | {raw} |")

                if b1a_val is not None or b1b_val is not None:
                    print()
                    print("| Side | NCAA succ | B1 (PBP) |")
                    print("|------|----------:|:---------|")
                    for team, succ, opp, raw in rows:
                        if _is_usd_team_name(team):
                            b1 = f"B1a {b1a_val}" if b1a_val is not None else "B1a -"
                            role = "USD offense"
                        else:
                            b1 = f"B1b {b1b_val}" if b1b_val is not None else "B1b -"
                            role = f"Opp ({team})"
                        print(f"| {role} | {succ} | {b1} |")
                else:
                    print()
                    print(f"*(No B1 file: {br_path.name})*")
                print()
        finally:
            browser.close()


def _sources_full_match(
    usd_ncaa: int | None,
    b1a: int | None,
    opp_ncaa: int | None,
    b1b: int | None,
) -> str:
    """Yes when NCAA equals B1 for both sides; otherwise No."""
    if usd_ncaa is None or b1a is None or opp_ncaa is None or b1b is None:
        return "No"
    return "Yes" if (usd_ncaa == b1a and opp_ncaa == b1b) else "No"


def batch_situational_vs_b1_consolidated(
    contest_ids: list[int],
    *,
    headless: bool = False,
    wait_ms: int = 4000,
) -> str:
    """
    One browser session; returns markdown for a single table:
    Contest ID | Matchup | USD (NCAA succ / B1a) | Opp (NCAA succ / B1b) | Matches.
    """
    if not contest_ids:
        return ""

    lines: list[str] = []
    lines.append("# NCAA situational leadoff vs Battles B1 (consolidated)")
    lines.append("")
    lines.append(
        "NCAA **leadoff succ** = first number in situational **leadoff pct** total; "
        "**B1a / B1b** = first number in battle report PBP counts (`count`/`goal`)."
    )
    lines.append("")
    lines.append(
        "**Matches** = `Yes` only when NCAA equals B1 for **both** USD (`B1a`) "
        "and opponent (`B1b`); otherwise `No` (including missing NCAA fetch)."
    )
    lines.append("")
    lines.append(
        "| Contest | Matchup | USD (NCAA succ / B1a) | Opp (NCAA succ / B1b) | Matches |"
    )
    lines.append(
        "|--------:|---------|----------------------:|-----------------------:|:-------:|"
    )

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"] if headless else [],
        )
        try:
            context = browser.new_context(
                viewport={"width": 1400, "height": 900},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
                locale="en-US",
            )
            context.add_init_script(
                "Object.defineProperty(navigator, 'webdriver', { get: () => undefined })"
            )
            page = context.new_page()

            for cid in contest_ids:
                br_path = SCRIPT_DIR / f"contest_{cid}_battle_calc_output.txt"
                b1a_val, b1b_val = None, None
                matchup = ""
                if br_path.is_file():
                    br_txt = br_path.read_text(encoding="utf-8")
                    b1a_val, b1b_val = parse_b1_from_battle_report(br_txt, cid)
                    matchup = parse_matchup_from_battle_report(br_txt, cid)

                matchup_esc = matchup.replace("|", "/")
                url = _situational_url(cid)
                usd_ncaa: int | None = None
                opp_ncaa: int | None = None
                usd_cell = "-"
                opp_cell = "-"
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=45000)
                    page.wait_for_timeout(wait_ms)
                    html = page.content()
                    hit_rows = parse_hitting_leadoff_totals(html)
                    usd_ncaa, opp_ncaa = ncaa_leadoff_succ_usd_and_opp(hit_rows)
                    usd_cell = _fmt_ncaa_b1(usd_ncaa, b1a_val)
                    opp_cell = _fmt_ncaa_b1(opp_ncaa, b1b_val)
                except Exception:
                    usd_cell = _fmt_ncaa_b1(None, b1a_val)
                    opp_cell = _fmt_ncaa_b1(None, b1b_val)

                match_cell = _sources_full_match(usd_ncaa, b1a_val, opp_ncaa, b1b_val)
                lines.append(
                    f"| {cid} | {matchup_esc} | {usd_cell} | {opp_cell} | {match_cell} |"
                )
        finally:
            browser.close()

    return "\n".join(lines) + "\n"


def _first_slash_int(cell: str) -> int | None:
    """First integer in a ``'3 / 2'`` or ``'- / 2'`` style table cell (= NCAA side)."""
    if not cell or not cell.strip():
        return None
    left = cell.split("/", 1)[0].strip()
    if left == "-" or left == "":
        return None
    try:
        return int(left)
    except ValueError:
        return None


def parse_ncaa_leadoff_from_situational_md(md_text: str) -> dict[int, tuple[int | None, int | None]]:
    """From ``situational_vs_b1_batch.md`` table, read (USD NCAA succ, Opp NCAA succ) per contest.

    Second number in each cell is B1 from PBP — ignored here; refreshed from battle reports.
    """
    out: dict[int, tuple[int | None, int | None]] = {}
    for line in md_text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        if "Contest" in line or line.startswith("|--") or "Matchup" in line:
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 6:
            continue
        try:
            cid = int(parts[1])
        except (ValueError, IndexError):
            continue
        usd_cell = parts[3] if len(parts) > 3 else ""
        opp_cell = parts[4] if len(parts) > 4 else ""
        out[cid] = (_first_slash_int(usd_cell), _first_slash_int(opp_cell))
    return out


def batch_situational_vs_b1_consolidated_battle_refresh(
    contest_ids: list[int],
    *,
    previous_md_path: Path,
    script_dir: Path | None = None,
) -> str:
    """Rebuild consolidated table: **NCAA columns unchanged** (from ``previous_md_path``), B1 from battle txt.

    No Playwright / situational fetch. Use after PBP or battle-logic changes.
    """
    if not contest_ids:
        return ""

    sd = script_dir or SCRIPT_DIR
    md_prev = ""
    if previous_md_path.is_file():
        md_prev = previous_md_path.read_text(encoding="utf-8")
    ncaa_map = parse_ncaa_leadoff_from_situational_md(md_prev)

    lines: list[str] = []
    lines.append("# NCAA situational leadoff vs Battles B1 (consolidated)")
    lines.append("")
    lines.append(
        "NCAA **leadoff succ** = first number in situational **leadoff pct** total; "
        "**B1a / B1b** = first number in battle report PBP counts (`count`/`goal`)."
    )
    lines.append("")
    lines.append(
        "**Matches** = `Yes` only when NCAA equals B1 for **both** USD (`B1a`) "
        "and opponent (`B1b`); otherwise `No` (including missing NCAA fetch)."
    )
    lines.append("")
    lines.append(
        "| Contest | Matchup | USD (NCAA succ / B1a) | Opp (NCAA succ / B1b) | Matches |"
    )
    lines.append(
        "|--------:|---------|----------------------:|-----------------------:|:-------:|"
    )

    for cid in contest_ids:
        br_path = sd / f"contest_{cid}_battle_calc_output.txt"
        b1a_val, b1b_val = None, None
        matchup = ""
        if br_path.is_file():
            br_txt = br_path.read_text(encoding="utf-8")
            b1a_val, b1b_val = parse_b1_from_battle_report(br_txt, cid)
            matchup = parse_matchup_from_battle_report(br_txt, cid)

        matchup_esc = matchup.replace("|", "/")
        usd_ncaa, opp_ncaa = ncaa_map.get(cid, (None, None))
        usd_cell = _fmt_ncaa_b1(usd_ncaa, b1a_val)
        opp_cell = _fmt_ncaa_b1(opp_ncaa, b1b_val)
        match_cell = _sources_full_match(usd_ncaa, b1a_val, opp_ncaa, b1b_val)
        lines.append(f"| {cid} | {matchup_esc} | {usd_cell} | {opp_cell} | {match_cell} |")

    return "\n".join(lines) + "\n"


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip()).lower()


def _leadoff_col_index(thead_tr) -> int | None:
    ths = thead_tr.find_all("th")
    for i, th in enumerate(ths):
        t = _norm(th.get_text())
        if "leadoff" in t and "pct" in t:
            return i
    return None


def _cell_stat_text(td) -> str:
    for a in td.select("a"):
        t = a.get_text(strip=True)
        if t:
            return t
    return td.get_text(strip=True)


def parse_hitting_leadoff_totals(html: str) -> list[tuple[str, int, int, str]]:
    """
    Per Hitting card: (team_short_name, successes, opportunities, raw ``X-Y``).
    """
    soup = BeautifulSoup(html, "html.parser")
    out: list[tuple[str, int, int, str]] = []

    for card in soup.select("div.card"):
        hdr = card.select_one(".card-header")
        if hdr is None:
            continue
        htxt = hdr.get_text(" ", strip=True)
        if not _norm(htxt).endswith("hitting") and " hitting" not in _norm(htxt):
            continue

        team = re.sub(r"\s+hitting\s*$", "", htxt, flags=re.I).strip()
        if not team:
            continue

        table = card.select_one("table")
        if table is None:
            continue
        thead = table.find("thead")
        if thead is None:
            continue
        head_tr = thead.find("tr")
        if head_tr is None:
            continue

        lo_i = _leadoff_col_index(head_tr)
        if lo_i is None:
            continue

        tbody = table.find("tbody")
        if tbody is None:
            continue

        total_tr = None
        for tr in tbody.find_all("tr"):
            first = tr.find(["td", "th"])
            if first is None:
                continue
            st = first.get("style") or ""
            if "grey_heading" in st.lower() or first.find("b") is not None:
                txt = first.get_text(strip=True)
                if txt and "," not in txt and len(txt) < 40:
                    total_tr = tr

        if total_tr is None:
            continue

        cells = total_tr.find_all("td")
        if lo_i >= len(cells):
            continue
        raw = _cell_stat_text(cells[lo_i])
        m = re.match(r"^(\d+)-(\d+)$", raw)
        if not m:
            continue
        succ, opp = int(m.group(1)), int(m.group(2))
        out.append((team, succ, opp, raw))

    return out


def parse_b1_from_battle_report(text: str, contest_id: int) -> tuple[int | None, int | None]:
    """Return (B1a value, B1b value) numerators for ``Game {contest_id}`` block."""
    lines = text.splitlines()
    in_block = False
    b1a_val: int | None = None
    b1b_val: int | None = None
    for line in lines:
        if re.match(rf"^Game\s+{contest_id}\s+", line.strip()):
            in_block = True
            b1a_val, b1b_val = None, None
            continue
        if in_block and line.strip().startswith("Game ") and not line.strip().startswith(f"Game {contest_id}"):
            break
        if not in_block:
            continue
        m1 = re.search(r"B1a Leadoff Runners \(Off\):\s*(\d+)/", line)
        if m1:
            b1a_val = int(m1.group(1))
        m2 = re.search(r"B1b Leadoff Runners \(Def\):\s*(\d+)/", line)
        if m2:
            b1b_val = int(m2.group(1))
    return b1a_val, b1b_val


def _is_usd_team_name(name: str) -> bool:
    n = name.strip().lower()
    return n.startswith("san diego") or n == "usd"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("url", nargs="?", default=DEFAULT_URL)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--dump-html", type=Path, default=None)
    parser.add_argument(
        "--battle-report",
        type=Path,
        default=None,
        help="Battle calc .txt; default contest_{id}_battle_calc_output.txt next to this script",
    )
    parser.add_argument("--no-b1-compare", action="store_true")
    parser.add_argument(
        "--batch-contests",
        action="store_true",
        help="All contest_*_battle_calc_output.txt in this folder (one browser session)",
    )
    parser.add_argument(
        "--batch-verbose",
        action="store_true",
        help="With --batch-contests: per-contest expanded tables instead of one consolidated table",
    )
    args = parser.parse_args()

    if args.batch_contests:
        ids = discover_contest_ids_from_battle_reports(SCRIPT_DIR)
        if args.batch_verbose:
            batch_situational_vs_b1_verbose(ids, headless=args.headless)
        else:
            print(batch_situational_vs_b1_consolidated(ids, headless=args.headless), end="")
        return

    html = fetch_html(args.url, headless=args.headless)
    if args.dump_html:
        args.dump_html.write_text(html, encoding="utf-8")
        print(f"Saved {args.dump_html}", file=sys.stderr)

    rows = parse_hitting_leadoff_totals(html)
    if not rows:
        print("No Hitting situational tables parsed.", file=sys.stderr)
        sys.exit(2)

    cid = extract_contest_id(args.url)
    b1a_val: int | None = None
    b1b_val: int | None = None
    br_path = args.battle_report
    if br_path is None and cid is not None and not args.no_b1_compare:
        br_path = SCRIPT_DIR / f"contest_{cid}_battle_calc_output.txt"
    if br_path and br_path.is_file() and cid is not None:
        b1a_val, b1b_val = parse_b1_from_battle_report(
            br_path.read_text(encoding="utf-8"), cid
        )

    print("NCAA situational - leadoff pct first number = leadoff successes (NCAA table)")
    print()
    print("| Team (hitting) | Leadoff succ | Opp. (2nd #) | raw |")
    print("|----------------|-------------:|-------------:|:----|")
    for team, succ, opp, raw in rows:
        print(f"| {team} | {succ} | {opp} | {raw} |")

    if b1a_val is None and b1b_val is None:
        print()
        print("(No B1 comparison: pass `--battle-report` or add `contest_{id}_battle_calc_output.txt`.)")
        return

    print()
    print("Compare to Battles B1 (first value = PBP leadoff-inning counts; B1 display is `count/goal`)")
    print()
    print("| Side | NCAA situational succ | B1 (PBP) |")
    print("|------|----------------------:|:---------|")

    for team, succ, opp, raw in rows:
        if _is_usd_team_name(team):
            b1 = f"B1a {b1a_val}" if b1a_val is not None else "B1a -"
            role = "USD offense (this team hitting)"
        else:
            b1 = f"B1b {b1b_val}" if b1b_val is not None else "B1b -"
            role = f"Opponent offense ({team} hitting)"
        print(f"| {role} | {succ} | {b1} |")


if __name__ == "__main__":
    main()
