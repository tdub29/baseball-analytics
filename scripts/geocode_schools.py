#!/usr/bin/env python
"""Geocode every portal school to real campus coordinates (OpenStreetMap / Nominatim).

    python scripts/geocode_schools.py

Reads the distinct from_school values of ENTERED players, geocodes each to a real
lat/lon (cached + resumable in data/cache/school_coords.json), so the dashboard map
plots schools at their actual campus, not a state centroid. Polite: 1 req/sec, a
descriptive User-Agent, on-disk cache so re-runs only fetch the misses.
"""
from __future__ import annotations

import json
import sqlite3
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "data" / "cache" / "school_coords.json"
UA = {"User-Agent": "usd-baseball-portal-eval/1.0 (internal scouting; contact trevor@good360.org)"}
URL = "https://nominatim.openstreetmap.org/search"


def schools() -> list[str]:
    con = sqlite3.connect(ROOT / "db" / "baseball.db")
    rows = con.execute("""SELECT DISTINCT from_school FROM players
                          WHERE current_status='ENTERED' AND from_school IS NOT NULL""").fetchall()
    con.close()
    return sorted({r[0].strip() for r in rows if r[0] and r[0].strip()})


def geocode(name: str):
    """Nominatim → (lat, lon) or None. Tries the name, then name + ' baseball'."""
    for q in (name, f"{name} university" if "univ" not in name.lower() and "college" not in name.lower() else None):
        if not q:
            continue
        try:
            r = requests.get(URL, params={"q": q, "format": "jsonv2", "countrycodes": "us", "limit": 1},
                             headers=UA, timeout=20)
            if r.status_code == 200 and r.json():
                d = r.json()[0]
                return [round(float(d["lat"]), 4), round(float(d["lon"]), 4)]
        except Exception:
            pass
        time.sleep(1.1)
    return None


def main() -> None:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    todo = [s for s in schools() if s not in cache]
    print(f"{len(cache)} cached, {len(todo)} to geocode")
    for i, name in enumerate(todo, 1):
        cache[name] = geocode(name)
        if i % 10 == 0 or i == len(todo):
            CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=0), encoding="utf-8")
            print(f"  [{i}/{len(todo)}] {name} -> {cache[name]}")
        time.sleep(1.1)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=0), encoding="utf-8")
    hit = sum(1 for v in cache.values() if v)
    print(f"done: {hit}/{len(cache)} schools geocoded -> {CACHE}")


if __name__ == "__main__":
    main()
