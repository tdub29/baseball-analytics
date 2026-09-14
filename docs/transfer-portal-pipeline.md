# NCAA Baseball Transfer Portal — Scout/Coach Evaluation Pipeline

A DIY data pipeline that maintains a fresh, queryable database of players in the
NCAA baseball transfer portal, **enriched with performance stats and scored for fit**
against a program's roster needs.

> **Scope & intent:** internal scout/coach evaluation (private use). This design
> scrapes public trackers and monitors public social posts. That is generally fine
> for internal evaluation; it is **not** licensed for building a public/commercial
> product. See [Legal / ToS](#legal--tos) before any redistribution.

---

## 1. Why a pipeline (the provenance problem)

There is **no public NCAA API**. The portal is a private compliance database; entries
are made by school compliance officers (updated multiple times/day) after an athlete
files written notice. Everyone downstream taps one of two paths:

- **Source-of-truth path** — vendors with institutional/licensed access (Verified
  Athletics, Verbal Commits, Synergy). Clean, slightly lagged.
- **Reporting/announcement path** — insider reporters + the athletes themselves on
  X/Twitter. Fastest, noisiest.

This pipeline fuses **both** so you get speed (social) *and* reliability (curated
trackers), then layers the thing coaches actually need: **stat enrichment + fit scoring**.

---

## 1b. Working WITHOUT the official NCAA login (the key constraint)

USD has an `sso.ncaa.org` login — the literal source of truth — but each session needs a
**2FA code a coach has to send**, so it's not reliably self-serve. **The pipeline is
designed to run with zero dependence on it.** Here's exactly what you gain/lose:

| Capability | With official login | **Without it (this pipeline)** |
|---|---|---|
| List of who's in the portal | Authoritative, immediate | D1Baseball + Verbal Commits + 64 Analytics + X, ~minutes–hours lag |
| Withdrawals (left portal) | Authoritative | 64 Analytics flags removals; X confirms; some lag |
| Contact info / compliance fields | Yes | **No** — not public; this is the main thing you lose |
| Eligibility/class details | Yes | Partial (from trackers + roster scrape) |
| Player stats / advanced metrics | n/a (portal isn't stats) | **Full** — via `collegebaseball` + 6-4-3 Charts |
| Fit scoring / hot board | Manual | **Automated** |

**Verdict:** ~90% of the evaluation workflow (who entered, their stats, fit ranking, call
board) is doable **without** the login. The login mainly adds *authoritative confirmation*
and *contact fields*. Recommended flow: run the pipeline daily without the login to build
the board, then use a (rare) logged-in session only to **confirm/grab contacts** for the
top-N players you actually want to call — turning a per-access bottleneck into a once-a-week task.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  INGESTION (source adapters, scheduled)                               │
│                                                                       │
│  D1Baseball   64 Analytics   Verbal Commits   FieldLevel   X/Twitter  │
│      │             │              │               │            │      │
│      └─────────────┴──────────────┴───────────────┴────────────┘      │
│                              ▼                                        │
│                   normalized PortalEvent[]                            │
└──────────────────────────────┬────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ENTITY RESOLUTION  — fuzzy-match name+school+pos+class → player_id    │
│                       dedupe across sources, idempotent upsert         │
│                       event types: ENTERED / WITHDRAWN / COMMITTED     │
└──────────────────────────────┬────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ENRICHMENT — NCAA.com stats (self-hosted ncaa-api), school stat       │
│               pages; compute normalized/level-adjusted metrics         │
└──────────────────────────────┬────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  EVALUATION — position-need match · eligibility filter · percentile    │
│               ranks · level-of-competition adj · configurable FIT score │
└──────────────────────────────┬────────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STORAGE (SQLite→Postgres)   +   OUTPUT (Google Sheet sync, CSV, CLI)  │
│                              +   ALERTS (new entry matches a need)      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data sources (ingestion adapters)

Each adapter is a small module that fetches its source and yields normalized
`PortalEvent` rows. Add/remove freely — the rest of the pipeline doesn't care which
sources are on.

| Adapter | Type | Gives you | Notes / freshness |
|---|---|---|---|
| **D1Baseball** | HTML scrape (subscription) | Baseball-specific entries + destinations, reporter-curated | Best baseball coverage; powered by Verified Athletics. Needs a logged-in session cookie. |
| **64 Analytics** | HTML / email-alert parse (subscription) | Additions, **removals**, commitments + stat filters | Only source here that explicitly flags **removals** (withdrawals). Portal Pass = $2,000/yr. |
| **Verbal Commits** | HTML scrape | Cross-division entries; structured | Powers Synergy's men's transfer data — closest to a structured feed. |
| **FieldLevel** | HTML scrape | Baseball portal announcements | Recruiting-network feed. |
| **X/Twitter** | API v2 filtered stream / list timeline | **Speed** — entries hours before they post elsewhere | Watchlist of insiders (@d1baseball, Kendall Rogers, beat writers, @VerbalCommitsD2…) + keyword rule `("transfer portal") (baseball OR commits OR entered)`. Requires NLP extraction. |

**Recommended minimum viable set:** D1Baseball (coverage) + X/Twitter (speed) +
64 Analytics (withdrawals & stats). The others are redundancy/cross-checks.

### Normalized event contract

```jsonc
{
  "source": "d1baseball",            // adapter id
  "source_url": "https://…",         // permalink for audit
  "observed_at": "2026-06-02T14:11Z",// when WE saw it
  "event_type": "ENTERED",           // ENTERED | WITHDRAWN | COMMITTED
  "player_name": "Jake Smith",
  "from_school": "Coastal Carolina",
  "to_school": null,                 // set on COMMITTED
  "position": "RHP",
  "class_year": "JR",                // FR/SO/JR/SR/GR
  "eligibility_remaining": null,     // years, if reported
  "raw": { /* original parsed blob for re-processing */ }
}
```

---

## 4. Entity resolution

The hard part. The same player shows up as "Jake Smith", "Jacob Smith (Coastal)",
"J. Smith RHP" across sources, and announcements precede official entry.

**Matching key:** normalized(name) + from_school + position, with class_year as a
tiebreaker. Use:

- Name normalization (lowercase, strip punctuation/suffixes, nickname map: Jake↔Jacob).
- `rapidfuzz` token-set ratio ≥ 90 on name **and** an exact/fuzzy school match → same player.
- On match, keep a stable `player_id`; append the event to that player's timeline.
- **Idempotency:** dedupe on `(player_id, event_type, source, date)` so re-running an
  adapter never double-inserts.
- **State machine per player:** `ENTERED → (WITHDRAWN | COMMITTED)`. A later COMMITTED
  supersedes ENTERED for "current status" but the full event log is retained.

---

## 5. Enrichment (the scout value-add, part 1)

Portal entry tells you *who*; enrichment tells you *how good*. Three tiers, cheapest first:

**Tier 1 — free code packages that scrape `stats.ncaa.org` (no login, no cost):**

- **`collegebaseball`** (Python, [nathanblumenfeld](https://github.com/nathanblumenfeld/collegebaseball)) —
  **primary enrichment engine.** Wraps stats.ncaa.org with an intuitive API *and computes
  advanced metrics*. Install: `pip install git+https://github.com/nathanblumenfeld/collegebaseball`.
  Also [CodeMateo15/CollegeBaseballStatsPackage](https://github.com/CodeMateo15/CollegeBaseballStatsPackage)
  (DI/II/III team stats 2002–2025, player stats 2021–2025, MLB-draft 1965–2025).
- **`baseballr`** (R, [Bill Petti](https://billpetti.github.io/baseballr/reference/ncaa.html)) —
  the most mature option if you prefer R. `ncaa_team_player_stats()`, `ncaa_roster()`,
  `ncaa_pbp()`, `ncaa_game_logs()`, `ncaa_lineups()`, `ncaa_park_factor()`,
  `ncaa_schedule_info()` (DI/II/III). Call from Python via `subprocess`/`rpy2` if needed.
- **[henrygd/ncaa-api](https://github.com/henrygd/ncaa-api)** (Docker) — ncaa.com
  scores/standings/rankings for team context. No player stats depth; complements the above.
- ⚠️ **`pybaseball` does NOT work here** — it's MLB-only (Statcast/FanGraphs/Baseball-Reference).
  Don't reach for it for college data.

**Tier 2 — 6-4-3 Charts (the advanced metrics USD actually uses, replaces TruMedia):**

- [6-4-3 Charts](https://643charts.com/) integrates **Synergy + Trackman + AWRE** and is the
  source of the batted-ball / pitch-shape metrics on the hot boards (STUFF+, xWOBA, SEAGER,
  Perceived Value, per-pitch stuff+/strike%, HardHit%, Chase%, etc.).
- **[Portal HQ](https://643charts.com/portal-hq/)** organizes portal recruits and links them to
  these metrics + video, with a **cross-school Player ID** for accurate transfer career data.
- **Integration path: CSV export.** 6-4-3 exports stat tables to CSV/PDF; there's no public
  self-serve API (they do custom data solutions via [643charts.com/api](https://643charts.com/api/)).
  So the pipeline **ingests 6-4-3 CSV drops** into `stats_hitting`/`stats_pitching` rather than
  calling an API. Ask 6-4-3 whether a scheduled export / data feed is available for USD.

**Tier 2.5 — d3-dashboard.com developer API (current-season D1–D3, 2021+):**

- Confirmed live API: base `https://d3-dashboard.com/api`, auth `X-API-Key` or
  `Authorization: Bearer`. Real endpoints: `/api/players`, `/api/teams`, `/api/games`,
  `/api/batting`, `/api/pitching`, `/api/conferences`.
- **Fills the gap collegebaseball leaves** (which stops at 2023) with a real *current-season*
  API across D1–D3. Adapter built: `src/portal/d3dashboard.py` → `python run.py enrich-d3`
  (needs `enrichment.d3dashboard.api_key` in config). Docs: https://d3-dashboard.com/docs.

**Tier 3 — Synergy / Verbal Commits direct** if you keep an institutional license (raw advanced data).

**Derived metrics** (compute when not provided, don't just store raw):
- Hitters: AVG/OBP/SLG, **ISO**, **BB%**, **K%**, SB success, BABIP.
- Pitchers: **FIP-ish**, **K/9**, **BB/9**, **WHIP**, K-BB%, GB% if available.
- **Level adjustment:** z-score each metric *within position × division × conference*,
  then apply a strength-of-schedule / conference factor so a .320 hitter in the SEC
  isn't compared flat against a .320 hitter in a low-D2 league. This is what makes the
  evaluation defensible across the wildly different competition levels in the portal.

---

## 6. Evaluation / fit scoring (the scout value-add, part 2)

Driven by a **roster-need profile** you define (see `config.example.yaml`):

```yaml
needs:
  - position: RHP
    priority: 1
    min_eligibility: 1          # years remaining
    min_class: JR
    target_metrics: { k_per_9: ">=9.5", bb_per_9: "<=3.5", innings: ">=40" }
  - position: SS
    priority: 2
    min_eligibility: 2
    target_metrics: { obp: ">=.380", k_pct: "<=18", iso: ">=.150" }
filters:
  divisions: [D1, D2]
  conferences_exclude: []
```

**Rating** — an overall future-value grade on the **20-80 scouting scale**, in **true
standard-deviation units against the full college population** (every player we have stats
for, *not* just the portal, and *not* an MLB yardstick): 50 = the all-college mean, every
10 pts = 1 SD (60 = +1 SD, 70 = +2 SD, 80 = +3 SD), clamped to 20-80. Grading against all
of college — not the portal subset — is what makes a high grade mean something, and since
portal players aren't +3 SD above the all-college mean, **an 80 stays a true outlier** (in
the current pool the best bats top out in the high 70s; nobody hits 80). It is the 20-80
rescaling of a talent composite:

```
composite = w1 * performance_percentile    // level-adjusted, within role, sample-weighted
          + w2 * level_of_competition       // SOS / conference factor
          + w3 * seniority                   // USD favors older transfers
Rating    = clamp(50 + 10 * z(composite vs all college), 20, 80)   // OFP, true-SD z
```

The composite is **sample-confidence-weighted**, so tiny-sample junk (a .700+ wOBA over a
few batted balls — common in the full-college dump, which has no PA to filter on) sinks to
the bottom rather than the top. Hitters also carry two **position-relative 20-80 tool
grades** — **Hit** (contact / on-base / swing decisions) and **Power** (slug + exit velocity
+ batted-ball authority), each graded against all college hitters *at the same position*
(the recruiting-board lens; thin position groups fall back to the whole pool). Tool z-scores
are **winsorized** (each metric clipped to its [1st, 99th] pctile before mean/SD) so junk
lines can't mint spurious 80s. A **Speed** grade is deferred until stolen-base data is
populated (the 6-4-3 metric exports don't carry SB). Pitchers carry no tool grades.
Canonical implementation: [`../src/portal/evaluate.py`](../src/portal/evaluate.py)
(positional need is recorded but carries zero weight; gettability is a separate **Get%**).

Outputs a **ranked board** per need, plus **alerts**: when a newly-ENTERED player
clears a need profile's thresholds, fire a notification (email/Teams/Slack) the same hour.

---

## 7. Storage & schema

Start with **SQLite** (zero-setup, file-based, perfect for one analyst); migrate to
Postgres only if multiple users/concurrent writes. Full DDL in
[`../db/schema.sql`](../db/schema.sql). Tables:

- `players` — canonical identity (player_id, name, position, class, eligibility).
- `portal_events` — full event log (ENTERED/WITHDRAWN/COMMITTED) w/ source + url + observed_at.
- `stats_hitting` / `stats_pitching` / `stats_fielding` — per season, raw + derived.
- `evaluations` — computed fit scores per (player, need_profile, run).
- `need_profiles` — your roster needs (mirrors config).
- `source_runs` — ingestion audit log (what ran, when, rows, errors).
- `watchlist` — players flagged for manual follow.

---

## 8. Output: Google Sheet sync

Since the working board is a Google Sheet, the pipeline treats Sheets as a **first-class
output**:

- `gspread` + a Google **service account** (share the sheet with the service-account
  email as Editor) → push the ranked evaluation board to a tab, one row per player.
- Two-way option: read a "manual notes / coach grade" column back into `players` so
  human grades persist across runs.
- Idempotent: key rows by `player_id`; update in place, append new, mark
  WITHDRAWN/COMMITTED with status + strikethrough formatting.

> **To match your existing sheet's columns exactly**, share it (Anyone-with-link →
> Viewer) or paste the header row — the schema and the Sheets writer will be aligned to it.

---

## 9. Scheduling / orchestration

Windows-native options (pick one):

- **Windows Task Scheduler** → `python -m portal.run --all`
  - **During the window (June 1–30):** hourly.
  - **Off-window:** once daily (late portal/grad-transfer trickle).
- **GitHub Actions cron** if you'd rather run it in the cloud (commit DB to a private
  repo or push to a managed Postgres). Cron `0 * 1-30 6 *` for hourly in June.
- X/Twitter filtered stream can run as a **always-on** lightweight listener for true
  real-time alerts, separate from the batch scrapers.

The 2026 DI baseball primary transfer window is **June 1–30**
([NCAA DI windows](http://fs.ncaa.org/Docs/eligibility_center/Transfer/DIUG_Windows.pdf)) —
that's the period to crank cadence up.

---

## 10. Build phases

1. **Walking skeleton** — SQLite schema + one adapter (D1Baseball) + manual run → rows land. ✅ proves the spine.
2. **Resolution + multi-source** — add X listener + Verbal Commits; entity resolution + dedupe.
3. **Enrichment** — stand up self-hosted ncaa-api; join stats; compute derived/level-adjusted metrics.
4. **Evaluation** — need profiles + fit score + ranked board.
5. **Delivery** — Google Sheet sync + alerts + scheduled cadence.

---

## 11. Legal / ToS

- Scraping + internal evaluation use: generally low-risk, **but** D1Baseball / 64 Analytics
  / On3 / 247 Terms prohibit scraping and redistribution. Respect `robots.txt`, rate-limit,
  cache, and **do not redistribute** their data outside your program.
- A subscription (D1Baseball / 64 Analytics) you log into is the cleanest legal basis for
  reading those sources programmatically for internal use.
- X/Twitter: use the official API per its developer terms; don't scrape the site.
- If this ever becomes a public/commercial product, replace scraping with a **licensed
  feed** (On3 or Verbal Commits) — see the research report.

---

## 12. Sources

- [henrygd/ncaa-api](https://github.com/henrygd/ncaa-api) · [D1Baseball tracker](https://d1baseball.com/stories/2026-transfer-tracker/) · [Verified Athletics](https://verifiedathletics.com/) · [Verbal Commits](https://verbalcommits.com/transfers) · [64 Analytics Portal Pass](https://www.64analytics.com/portal-pass) · [Synergy portal docs](https://support.synergysports.com/support/solutions/articles/77000565953-transfer-portal) · [NCAA DI transfer windows](http://fs.ncaa.org/Docs/eligibility_center/Transfer/DIUG_Windows.pdf)
