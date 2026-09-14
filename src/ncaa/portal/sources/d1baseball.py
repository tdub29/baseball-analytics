"""D1Baseball transfer-tracker adapter (subscriber).

Best baseball coverage (powered by Verified Athletics). Two paths:

1. **Paste mode (runnable today, no cookie):** the live page is double-walled, but
   a logged-in human can copy the rendered tracker table and save it to a .txt.
   `parse_tracker_text()` turns that paste into PortalEvents. Use it via
   `ingest --source d1baseball --path <paste.txt>` (or `paste_path:` in config).
2. **Live fetch (needs a cookie):** two walls, confirmed by probing the live 2026
   tracker — a Cloudflare-style *bot* wall (plain requests gets HTTP 403, cleared by
   CloakBrowser; `stealth: true`) and a *subscriber* paywall (the TablePress table is
   rendered server-side only for logged-in subscribers, so a session cookie is required).

For INTERNAL evaluation use only — respect ToS, rate-limit, do not redistribute.

fetch() is defensive: paste mode returns [] if the file is missing; live mode returns []
if disabled or cookieless — so the rest of the pipeline always runs.
"""
from __future__ import annotations

import logging
import re
from pathlib import Path

from ..util import clean_str, name_key
from .base import BaseAdapter, PortalEvent

log = logging.getLogger(__name__)
TRACKER_URL = "https://d1baseball.com/stories/2026-transfer-tracker/"

# ── paste-parsing constants ──────────────────────────────────────────────────
CLASS_YEARS = {"FR", "SO", "JR", "SR", "GR"}
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_YEAR_RE = re.compile(r"^(?:19|20)\d{2}$")
_HEADER_RE = re.compile(r"^Player\b", re.I)
# NB: the live footer is "Showing 1 to 1,715 of 1,715 entriesPrevious1Next" — no word
# boundary after "entries", so don't anchor a trailing \b (it would never match).
_FOOTER_RE = re.compile(r"^Showing\s+\d.*\bentries", re.I)
_NO_DEST = {"--", "—", "–", "-"}


def _anchor_fields(cells: list[str]) -> tuple[str | None, str] | None:
    """If this is a 'Position<TAB>Class' anchor row, return (position, class_year).

    The rendered table copies each record as: name, then this Pos/Class line,
    then the school, then the Season/Destination/Date tail. Names and school names
    carry no tab and the Season line's cells are '--'/year/date — so a class-year
    in the first TWO cells uniquely marks an anchor with no false hits. We scan
    both cells (not just cell[1]) because a few rows have a blank Position, which
    shifts the class into cell[0] (e.g. "JR<TAB>"); missing that drops the record
    AND lets the previous one swallow this name as a bogus destination.
    """
    for i in range(min(2, len(cells))):
        if cells[i].upper() in CLASS_YEARS:
            position = next((c for j, c in enumerate(cells[:2]) if j != i and c), None)
            return position, cells[i].upper()
    return None


def _is_anchor(cells: list[str]) -> bool:
    return _anchor_fields(cells) is not None


def parse_tracker_text(text: str, source_url: str | None = None) -> list[PortalEvent]:
    """Parse a copy-paste of the D1Baseball transfer tracker into PortalEvents.

    The rendered TablePress table copies as a flat run of lines. Two record
    shapes share one structure, keyed on whether a destination has committed:

        Uncommitted (4 lines)        Committed (6 lines)
        --------------------         -------------------
        Diego Ortiz                  Jake Wagoner
        2B<TAB>JR<TAB>               C<TAB>JR<TAB>
        SIUE                         Lamar
        2026<TAB>--<TAB>2026-06-02   2026
                                     Houston
                                     2026-06-01

    The Season/Destination/Date group is ONE tab-joined line when there's no
    destination but splits onto THREE lines once a school commits, so we read the
    whole tail between the school and the next record and pull fields by *pattern*
    (year / ISO-date / "the leftover token"), not by fixed offset. Header and the
    "Showing N of N entries" footer are trimmed; exact duplicate rows are dropped.
    """
    lines = [ln.rstrip("\r") for ln in text.splitlines()]
    split = [ln.split("\t") for ln in lines]

    # ── trim to the table region: after the "Player ... Date Entered" header,
    #    up to (not including) the "Showing N of N entries" footer ──
    start = 0
    for i, ln in enumerate(lines):
        if _HEADER_RE.match(ln) and "Date Entered" in ln:
            start = i + 1
            break
    end = len(lines)
    for i in range(start, len(lines)):
        if _FOOTER_RE.match(lines[i].strip()):
            end = i
            break

    # ── anchors are our record markers; everything else is read relative to them ──
    anchors = [i for i in range(start, end)
               if "\t" in lines[i] and _is_anchor([c.strip() for c in split[i]])]

    events: list[PortalEvent] = []
    seen: set[tuple] = set()
    for n, k in enumerate(anchors):
        cells = [c.strip() for c in split[k]]
        position, class_year = _anchor_fields(cells)  # anchors filtered to these already
        name = lines[k - 1].strip() if k - 1 >= start else ""
        if not name:
            continue
        school = clean_str(lines[k + 1]) if k + 1 < end else None

        # tail = lines between the school and the NEXT record's name line
        tail_end = (anchors[n + 1] - 1) if n + 1 < len(anchors) else end
        tokens: list[str] = []
        for j in range(k + 2, tail_end):
            tokens += [t.strip() for t in split[j] if t.strip()]

        season = next((t for t in tokens if _YEAR_RE.match(t)), None)
        date = next((t for t in tokens if _DATE_RE.match(t)), None)
        dest = next((t for t in tokens
                     if t not in _NO_DEST and not _YEAR_RE.match(t)
                     and not _DATE_RE.match(t)), None)

        ev = PortalEvent(
            player_name=name,
            event_type="COMMITTED" if dest else "ENTERED",
            from_school=school,
            to_school=dest,
            position=position,
            class_year=class_year,
            event_date=date,
            source_url=source_url,
            raw={"season": season, "latest_team": school,
                 "destination": dest, "date_entered": date},
        )
        dedup = (name_key(full=name), ev.event_type,
                 (school or "").lower(), date, (dest or "").lower())
        if dedup in seen:
            continue
        seen.add(dedup)
        events.append(ev)

    log.info("d1baseball paste parsed %d events (%d anchors, region %d-%d)",
             len(events), len(anchors), start, end)
    return events


class D1BaseballAdapter(BaseAdapter):
    source_id = "d1baseball"

    def __init__(self, config: dict | None = None):
        super().__init__(config)
        cfg = config or {}
        self.cookie = cfg.get("cookie") or ""
        self.url = cfg.get("url") or TRACKER_URL
        # A saved copy-paste of the rendered tracker — the no-cookie path.
        self.paste_path = cfg.get("paste_path") or ""
        # The live tracker sits behind Cloudflare-style bot protection that 403s a
        # plain requests.get, so default the live path to a stealth browser.
        self.stealth = cfg.get("stealth", True)

    def fetch(self) -> list[PortalEvent]:
        # Paste mode short-circuits the cookie/stealth walls entirely.
        if self.paste_path:
            return self._fetch_paste()
        if not self.config.get("enabled", False):
            log.info("d1baseball disabled in config")
            return []
        if not self.cookie:
            log.warning("d1baseball enabled but no session cookie and no paste_path; skipping")
            return []
        try:
            return self._parse_html(self._get())
        except Exception as e:  # never crash the whole run on one source
            log.error("d1baseball fetch failed: %s", e)
            return []

    # ── paste path (no network) ──────────────────────────────────────────────
    def _fetch_paste(self) -> list[PortalEvent]:
        p = Path(self.paste_path)
        if not p.exists():
            log.error("d1baseball paste_path not found: %s", p)
            return []
        text = p.read_text(encoding="utf-8", errors="replace")
        return parse_tracker_text(text, source_url=self.url)

    # ── live path (needs cookie + stealth) ─────────────────────────────────────
    def _get(self) -> str:
        # CloakBrowser clears the bot wall; the cookie (a logged-in session) clears
        # the paywall — the transfer table renders server-side ONLY for subscribers.
        import requests
        from tenacity import retry, stop_after_attempt, wait_exponential

        @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, max=20))
        def _do() -> str:
            if self.stealth:
                try:
                    from ..stealth import stealth_get
                    return stealth_get(self.url, cookie=self.cookie or None,
                                       wait_selector="table",
                                       cache_as="d1baseball_tracker.html")
                except RuntimeError as e:  # cloakbrowser not installed → fall back
                    log.warning("stealth fetch unavailable (%s); using plain requests", e)
            headers = {"User-Agent": "Mozilla/5.0 (portal-eval; internal use)"}
            if self.cookie:
                headers["Cookie"] = self.cookie
            resp = requests.get(self.url, headers=headers, timeout=30)
            resp.raise_for_status()
            return resp.text

        return _do()

    def _parse_html(self, html: str) -> list[PortalEvent]:
        """Extract entries from the live TablePress HTML.

        Rows render as [player, position, class, latest_team, season, destination,
        date]. We scan table rows; a destination cell (not '--') marks a commit.
        """
        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "lxml")
        events: list[PortalEvent] = []
        for tr in soup.select("table tr"):
            cells = [clean_str(td.get_text(" ", strip=True)) for td in tr.find_all(["td", "th"])]
            cells = [c for c in cells if c]
            if len(cells) < 2 or cells[0].lower() in {"player", "name"}:
                continue
            dest = cells[5] if len(cells) > 5 and cells[5] not in _NO_DEST else None
            events.append(PortalEvent(
                player_name=cells[0],
                position=cells[1] if len(cells) > 1 else None,
                class_year=cells[2] if len(cells) > 2 else None,
                from_school=cells[3] if len(cells) > 3 else None,
                to_school=dest,
                event_type="COMMITTED" if dest else "ENTERED",
                event_date=cells[6] if len(cells) > 6 else None,
                source_url=self.url,
            ))
        log.info("d1baseball parsed %d candidate rows", len(events))
        return events
