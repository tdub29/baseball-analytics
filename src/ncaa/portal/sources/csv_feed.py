"""CSV feed adapter — runnable today.

Paste portal entries from anywhere into a CSV and ingest them. Flexible
headers (case/space-insensitive):
    name (required), event/event_type, from/from_school, to/to_school,
    position/pos, class/year, date, url
"""
from __future__ import annotations

from pathlib import Path

import pandas as pd

from ..util import clean_str
from .base import BaseAdapter, PortalEvent

_ALIASES = {
    "player_name": ["name", "player", "playername", "fullname"],
    "event_type": ["event", "eventtype", "type", "status"],
    "from_school": ["from", "fromschool", "school", "currentschool"],
    "to_school": ["to", "toschool", "destination", "commit"],
    "position": ["position", "pos"],
    "class_year": ["class", "year", "classyear"],
    "event_date": ["date", "eventdate"],
    "source_url": ["url", "link", "source", "sourceurl"],
}


def _norm(h: str) -> str:
    return "".join(c for c in str(h).lower() if c.isalnum())


class CsvFeedAdapter(BaseAdapter):
    source_id = "csv"

    def __init__(self, path: str | Path, config: dict | None = None):
        super().__init__(config)
        self.path = Path(path)

    def fetch(self) -> list[PortalEvent]:
        if not self.path.exists():
            return []
        df = pd.read_csv(self.path)
        norm_to_actual = {_norm(c): c for c in df.columns}
        colmap = {}
        for field, opts in _ALIASES.items():
            for o in opts:
                if o in norm_to_actual:
                    colmap[field] = norm_to_actual[o]
                    break
        if "player_name" not in colmap:
            raise ValueError(f"CSV needs a name column; got {list(df.columns)}")

        events: list[PortalEvent] = []
        for _, r in df.iterrows():
            name = clean_str(r.get(colmap["player_name"]))
            if not name:
                continue
            events.append(PortalEvent(
                player_name=name,
                event_type=clean_str(r.get(colmap.get("event_type", "_"))) or "ENTERED",
                from_school=clean_str(r.get(colmap.get("from_school", "_"))),
                to_school=clean_str(r.get(colmap.get("to_school", "_"))),
                position=clean_str(r.get(colmap.get("position", "_"))),
                class_year=clean_str(r.get(colmap.get("class_year", "_"))),
                event_date=clean_str(r.get(colmap.get("event_date", "_"))),
                source_url=clean_str(r.get(colmap.get("source_url", "_"))),
            ))
        return events
