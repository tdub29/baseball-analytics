"""Verbal Commits adapter — structured cross-division portal entries.

Verbal Commits powers Synergy's men's transfer data. Public transfers page at
verbalcommits.com/transfers. Defensive fetch + adjustable parser, same pattern
as the D1Baseball adapter. Internal use only; respect ToS / rate limits.
"""
from __future__ import annotations

import logging

import requests
from bs4 import BeautifulSoup
from tenacity import retry, stop_after_attempt, wait_exponential

from ..util import clean_str
from .base import BaseAdapter, PortalEvent

log = logging.getLogger(__name__)
URL = "https://verbalcommits.com/transfers"


class VerbalCommitsAdapter(BaseAdapter):
    source_id = "verbalcommits"

    def __init__(self, config: dict | None = None):
        super().__init__(config)
        self.url = (config or {}).get("url") or URL

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, max=20))
    def _get(self) -> str:
        resp = requests.get(
            self.url, headers={"User-Agent": "Mozilla/5.0 (portal-eval; internal)"}, timeout=30
        )
        resp.raise_for_status()
        return resp.text

    def fetch(self) -> list[PortalEvent]:
        if not self.config.get("enabled", False):
            return []
        try:
            return self._parse(self._get())
        except Exception as e:
            log.error("verbalcommits fetch failed: %s", e)
            return []

    def _parse(self, html: str) -> list[PortalEvent]:
        soup = BeautifulSoup(html, "lxml")
        events: list[PortalEvent] = []
        for tr in soup.select("table tr"):
            cells = [clean_str(td.get_text(" ", strip=True)) for td in tr.find_all("td")]
            cells = [c for c in cells if c]
            if len(cells) < 2:
                continue
            events.append(PortalEvent(
                player_name=cells[0],
                from_school=cells[1] if len(cells) > 1 else None,
                position=cells[2] if len(cells) > 2 else None,
                source_url=self.url,
            ))
        return events
