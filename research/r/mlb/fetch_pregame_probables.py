"""Archived pregame probable starters from MLB StatsAPI, 2017-2025 regular season.

For each game, asks the live feed for a timecode before any snapshot exists; StatsAPI answers with
its earliest archived snapshot (Pre-Game status, roughly two hours before first pitch). Records the
probables listed there. Resumable: rows already in the jsonl cache are skipped. 2016 is left out:
its earliest snapshots are already In Progress, so they hold the actual starters, not the probables.

    python research/r/mlb/fetch_pregame_probables.py            # writes data/mlb/raw/statsapi/

2017-2025 games: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.
"""
import csv, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = "data/mlb/raw/statsapi"
CACHE = os.path.join(OUT, "pregame-probables.jsonl")
FIELDS = "gameData,status,detailedState,datetime,dateTime,probablePitchers,away,home,id,metaData,timeStamp"
WORKERS = int(os.environ.get("WORKERS", "12"))


def get(url, tries=4):
    for k in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry any network error, then surface it
            if k == tries - 1:
                raise
            time.sleep(2 ** k)


def schedule(season):
    d = get(f"https://statsapi.mlb.com/api/v1/schedule?sportId=1&season={season}&gameType=R")
    return [((g["gamePk"], season, g["officialDate"]),
             {"home_team": g["teams"]["home"]["team"]["id"], "away_team": g["teams"]["away"]["team"]["id"],
              "home_score": g["teams"]["home"].get("score"), "away_score": g["teams"]["away"].get("score"),
              "game_number": g.get("gameNumber")})
            for day in d["dates"] for g in day["games"] if g["status"]["codedGameState"] == "F"]


def probe(item):
    pk, season, date = item
    d = get(f"https://statsapi.mlb.com/api/v1.1/game/{pk}/feed/live?timecode=19000101_000000&fields={FIELDS}")
    gd, pp = d.get("gameData", {}), d.get("gameData", {}).get("probablePitchers", {})
    return {"game_pk": pk, "season": season, "date": date, "snapshot": d.get("metaData", {}).get("timeStamp"),
            "status": gd.get("status", {}).get("detailedState"), "first_pitch": gd.get("datetime", {}).get("dateTime"),
            "away_prob": pp.get("away", {}).get("id"), "home_prob": pp.get("home", {}).get("id")}


def main():
    os.makedirs(OUT, exist_ok=True)
    done = set()
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            done = {r["game_pk"] for r in map(_parse, f) if r}
    games, extra = {}, {}
    for s in range(2017, 2026):
        for g, x in schedule(s):
            games[g[0]] = g; extra[g[0]] = x
    todo = [g for pk, g in sorted(games.items()) if pk not in done]
    print(f"{len(games)} final regular-season games, {len(todo)} to fetch", flush=True)
    fails = 0
    with open(CACHE, "a") as f, ThreadPoolExecutor(WORKERS) as ex:
        for i, row in enumerate(ex.map(lambda g: _safe(g), todo), 1):
            if row is None:
                fails += 1
                continue
            f.write(json.dumps(row) + "\n"); f.flush()
            if i % 1000 == 0:
                print(f"{i}/{len(todo)}", flush=True)
    with open(CACHE) as f:
        rows = {r["game_pk"]: {**r, **extra.get(r["game_pk"], {})} for r in map(_parse, f) if r}
    cols = ["game_pk", "season", "date", "snapshot", "status", "first_pitch", "away_prob", "home_prob",
            "home_team", "away_team", "home_score", "away_score", "game_number"]
    with open(os.path.join(OUT, "pregame-probables.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, cols); w.writeheader(); w.writerows(sorted(rows.values(), key=lambda r: r["game_pk"]))
    print(f"wrote {len(rows)} rows; {fails} failed this run", flush=True)
    sys.exit(1 if fails else 0)


def _parse(line):
    try:
        return json.loads(line)
    except ValueError:  # a line cut short by an interrupted run: refetched
        return None


def _safe(g):
    try:
        return probe(g)
    except Exception as e:  # noqa: BLE001
        print(f"fail {g[0]}: {e}", file=sys.stderr, flush=True)
        return None


if __name__ == "__main__":
    main()
