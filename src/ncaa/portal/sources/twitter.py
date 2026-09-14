"""X/Twitter adapter — fastest portal signal.

Watches insider accounts + a keyword stream and extracts portal events from
tweet text. Needs an X API bearer token (sources.twitter.bearer_token). Without
tweepy or a token, fetch() returns []. Uses the official API per its terms.
"""
from __future__ import annotations

import logging
import re

from .base import BaseAdapter, PortalEvent

log = logging.getLogger(__name__)

# Light heuristics; replace with a stronger NER pass if you want higher recall.
_ENTER = re.compile(r"\b(enter(?:ed|ing)?|in)\s+the\s+(?:transfer\s+)?portal\b", re.I)
_COMMIT = re.compile(r"\b(commit(?:s|ted|ting)?|pledg|announc)\w*\b", re.I)
_NAME = re.compile(r"\b([A-Z][a-z]+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b")
_FROM = re.compile(r"\bfrom\s+([A-Z][\w&.\-' ]+?)(?:\.|,|\s+(?:has|is|will|enters)|$)")


class TwitterAdapter(BaseAdapter):
    source_id = "twitter"

    def __init__(self, config: dict | None = None):
        super().__init__(config)
        self.token = (config or {}).get("bearer_token") or ""
        self.accounts = (config or {}).get("watch_accounts") or []
        self.keywords = (config or {}).get("keywords") or ["transfer portal"]

    def fetch(self) -> list[PortalEvent]:
        if not self.config.get("enabled", False) or not self.token:
            return []
        try:
            import tweepy
        except ImportError:
            log.warning("tweepy not installed; `pip install tweepy`")
            return []
        client = tweepy.Client(bearer_token=self.token)
        events: list[PortalEvent] = []
        query = "(" + " OR ".join(f'"{k}"' for k in self.keywords) + ") (baseball) -is:retweet lang:en"
        try:
            resp = client.search_recent_tweets(query=query, max_results=50,
                                                tweet_fields=["created_at", "author_id"])
        except Exception as e:  # pragma: no cover
            log.error("twitter search failed: %s", e)
            return []
        for tw in (resp.data or []):
            ev = self.parse_tweet(tw.text)
            if ev:
                ev.source_url = f"https://x.com/i/web/status/{tw.id}"
                if getattr(tw, "created_at", None):
                    ev.event_date = str(tw.created_at.date())
                events.append(ev)
        return events

    @staticmethod
    def parse_tweet(text: str) -> PortalEvent | None:
        """Pull a (player, event, from_school) guess out of a tweet."""
        is_enter, is_commit = bool(_ENTER.search(text)), bool(_COMMIT.search(text))
        if not (is_enter or is_commit):
            return None
        name_m = _NAME.search(text)
        if not name_m:
            return None
        from_m = _FROM.search(text)
        return PortalEvent(
            player_name=name_m.group(1).strip(),
            event_type="COMMITTED" if is_commit and not is_enter else "ENTERED",
            from_school=from_m.group(1).strip() if from_m else None,
            raw={"text": text},
        )
