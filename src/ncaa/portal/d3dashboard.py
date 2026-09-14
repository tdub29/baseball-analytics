"""d3-dashboard.com enrichment client.

Confirmed live API (probed): base https://d3-dashboard.com/api , auth via
`X-API-Key: <key>` or `Authorization: Bearer <token>`. Real endpoints:
    /api/players  /api/teams  /api/games  /api/batting  /api/pitching  /api/conferences

Covers D1-D3, 2021+ — fills the current-season gap that collegebaseball (2012-2023)
leaves. Live calls need an API key (config: enrichment.d3dashboard.api_key); without
one, calls raise a clear message. Field names are mapped flexibly (we tune the alias
maps once a real response is seen — use `probe()` with a key to dump the JSON keys).
"""
from __future__ import annotations

import logging
import sqlite3

import requests
from tenacity import retry, stop_after_attempt, wait_exponential

from .db import now_iso
from .enrich import HITTING_ALIASES, PITCHING_ALIASES, NAME_ALIASES, _norm_header
from .resolve import Resolver
from .util import clean_str, to_float, to_int

log = logging.getLogger(__name__)
BASE = "https://d3-dashboard.com/api"
_INT_FIELDS = {"pa", "hr", "sb"}


class D3DashboardClient:
    def __init__(self, api_key: str = "", base_url: str = BASE, bearer: str = ""):
        self.base = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "portal-eval/0.1 (internal)"
        if api_key:
            self.session.headers["X-API-Key"] = api_key
        if bearer:
            self.session.headers["Authorization"] = f"Bearer {bearer}"
        self._authed = bool(api_key or bearer)

    def get(self, path: str, params: dict | None = None) -> dict | list:
        if not self._authed:  # fail fast — don't retry a missing key
            raise RuntimeError(
                "d3-dashboard needs an API key (enrichment.d3dashboard.api_key). "
                "Auth: X-API-Key or Authorization: Bearer. Docs: https://d3-dashboard.com/docs"
            )
        return self._request(path, params or {})

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, max=20))
    def _request(self, path: str, params: dict) -> dict | list:
        r = self.session.get(f"{self.base}/{path.lstrip('/')}", params=params, timeout=30)
        r.raise_for_status()
        return r.json()

    @staticmethod
    def _records(payload) -> list[dict]:
        """Normalize common response envelopes to a list of dicts."""
        if isinstance(payload, list):
            return payload
        for key in ("data", "results", "players", "rows", "items"):
            if isinstance(payload, dict) and isinstance(payload.get(key), list):
                return payload[key]
        return []

    def batting(self, **params) -> list[dict]:
        return self._records(self.get("batting", params))

    def pitching(self, **params) -> list[dict]:
        return self._records(self.get("pitching", params))

    def probe(self, endpoint: str = "batting") -> list[str]:
        recs = self._records(self.get(endpoint, {"limit": 1, "perPage": 1}))
        return sorted(recs[0].keys()) if recs else []


def _map_record(rec: dict, aliases: dict) -> dict:
    """Map a response dict to schema fields via normalized-key aliases."""
    norm_to_actual = {_norm_header(k): k for k in rec.keys()}
    out: dict = {}
    for field, opts in aliases.items():
        for o in opts:
            if o in norm_to_actual:
                raw = rec[norm_to_actual[o]]
                if field in ("team", "level"):
                    out[field] = clean_str(raw)
                elif field in _INT_FIELDS:
                    out[field] = to_int(raw)
                else:
                    out[field] = to_float(raw)
                break
    # name
    for o in NAME_ALIASES:
        if o in norm_to_actual:
            out["__name__"] = clean_str(rec[norm_to_actual[o]])
            break
    return out


def enrich_from_d3dashboard(con: sqlite3.Connection, config: dict) -> dict:
    cfg = (config.get("enrichment", {}) or {}).get("d3dashboard", {}) or {}
    if not cfg.get("enabled"):
        return {"skipped": "d3dashboard disabled in config"}
    client = D3DashboardClient(api_key=cfg.get("api_key", ""),
                               base_url=cfg.get("base_url", BASE),
                               bearer=cfg.get("bearer", ""))
    seasons = cfg.get("seasons") or ["2025"]
    divisions = cfg.get("divisions") or [1]
    resolver = Resolver(con)
    totals = {"batting_rows": 0, "pitching_rows": 0, "matched": 0, "unmatched": 0}

    for season in seasons:
        for div in divisions:
            for endpoint, aliases, table in [
                ("batting", HITTING_ALIASES, "stats_hitting"),
                ("pitching", PITCHING_ALIASES, "stats_pitching"),
            ]:
                recs = client._records(client.get(endpoint, {"season": season, "division": div}))
                for rec in recs:
                    mapped = _map_record(rec, aliases)
                    name = mapped.pop("__name__", None)
                    if not name:
                        continue
                    cand = resolver.resolve(name, mapped.get("team"))
                    if not cand:
                        totals["unmatched"] += 1
                        continue
                    totals["matched"] += 1
                    srow = {"player_id": cand.player_id, "season": str(season),
                            "source": "d3dashboard",
                            "source_file": f"{endpoint}:division={div}",
                            "observed_at": now_iso(),
                            **{k: v for k, v in mapped.items() if v is not None}}
                    cols = list(srow)
                    ph = ", ".join("?" for _ in cols)
                    con.execute(
                        f"INSERT OR REPLACE INTO {table} ({', '.join(cols)}) VALUES ({ph})",
                        [srow[c] for c in cols],
                    )
                    totals[f"{endpoint}_rows"] += 1
    con.commit()
    return totals
