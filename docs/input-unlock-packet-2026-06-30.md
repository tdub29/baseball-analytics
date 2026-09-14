# Live-feed input-unlock packet — 2026-06-30

The pipeline is **built and verified** (see bottom of this doc + `capabilities-and-blockers.md`).
The offline chain (import → resolve → enrich → evaluate → board) runs end-to-end with zero
external access. What remains is **wiring the live feeds** — each gated only on one input from
Trevor. This is the exact, ordered checklist: what to provide, where it goes, and what it unblocks.

**Secrets never go in code.** As of this date the config loader expands `${ENV_VAR}` (and
`${ENV_VAR:-fallback}`) at load time — set the value in the environment and reference it in
`config.yaml`. File-based secrets live in the gitignored `secrets/` folder. Nothing is hardcoded.

**Interpreter note (important):** run with **system Python 3.12**
(`C:\Users\TrevorWhite\AppData\Local\Programs\Python\Python312\python.exe`), which has the
project deps (rapidfuzz, pandas, gspread). The plain `python` alias in some shells resolves to
the **Polymarket** `.venv` (the `uv`/`VIRTUAL_ENV` gotcha), which is missing `rapidfuzz` and will
fail collection. Either call the full path or activate a baseball-local venv.

---

## The unlock checklist

### 1. 6-4-3 Charts advanced-metrics CSV — the #1 unlock (current-season stats)
- **What to provide:** a CSV export from 643charts.com (Portal HQ + hitter metrics + pitcher
  metrics; ideally also raw pitch-by-pitch — see `docs/643-pull-checklist.md`).
- **Where it goes:** drop into `data/643_exports/`.
  - Hitters → `hitters_2026_overall.csv` (and optionally `_vlhp` / `_vrhp` splits)
  - Pitchers → `pitchers_2026.csv`
  - Portal HQ entry list → `portal_hq_entries.csv`
  - Raw pitch data (for Stuff+/xSLG on non-USD players) → `raw_trackman_<x>.csv`
- **Schema:** only a **name column** is required (`Name`/`Player`/`FullName` — case/`%`/spaces
  don't matter). Season + split are read from the filename. Full accepted-column list is in
  `data/643_exports/README.md`. Hitting vs. pitching is auto-detected.
- **Next step:** `python run.py enrich-643 --dir data/643_exports` → `evaluate` → `board`.
- **Unblocks:** current-season (2026) advanced metrics on the board (`collegebaseball` stops at
  2023). Raw pitch data additionally unblocks **your** Stuff+ / xSLG / xWhiff / decision-value
  models via `enrich-trackman` — the numbers 6-4-3 itself never provides.

### 2. Google service-account JSON — push the board to the Sheet
- **What to provide:** a Google Cloud **service-account JSON key** (Sheets API enabled), **and**
  share the target sheet to that service account's email as **Editor**.
- **Where it goes:** `secrets/google-service-account.json` (gitignored; path already referenced by
  `google_sheet.service_account_json` in config).
- **Service-account email:** not discoverable until the key is created — it's the `client_email`
  field inside the downloaded JSON (`…@<project>.iam.gserviceaccount.com`). Copy it from the file,
  then Share → add as Editor. Full steps in `secrets/README.md`.
- **Target sheet id (already known):** `1oYJcLKUFpPOvE8690SxsKfnPZXlWzqrGIRfT5lskrac` — the same
  workbook as `2025 Transfer Portal Main Database.xlsx`. The board writes a **separate**
  `Hot Board (auto)` tab; it never touches existing tabs.
- **Next step:** set `google_sheet.enabled: true`, then `python run.py board` (or `run-all`).
- **Unblocks:** the ranked hot board auto-published into the live Google Sheet (and the `sheet`
  overlay backend if you choose it over Supabase).

### 3. D1Baseball / 64 Analytics session cookie — subscriber entry feeds (only if needed)
- **What to provide:** your logged-in session **Cookie header** from the browser devtools of a
  subscription you already hold (internal USD evaluation only — respect ToS, don't redistribute).
- **Where it goes (preferred):** env var, referenced in config —
  - D1Baseball: `$env:D1BASEBALL_COOKIE = "..."` → `sources.d1baseball.cookie: ${D1BASEBALL_COOKIE}`
  - 64 Analytics: `$env:ANALYTICS64_COOKIE = "..."` → `sources.64analytics.cookie: ${ANALYTICS64_COOKIE}`
- **No-cookie fallback (already works today):** copy the rendered tracker table into a `.txt` and
  run `python run.py ingest --source d1baseball --path <paste.txt>` — no credential needed.
- **Next step:** set the cookie (and `stealth: true` needs `pip install cloakbrowser` for the bot
  wall), then `python run.py ingest --source d1baseball`.
- **Unblocks:** automated live D1Baseball entries/destinations; 64 Analytics is the only source
  that flags **removals/withdrawals**.

### 4. X (Twitter) API bearer token — real-time entry listener
- **What to provide:** an X API v2 **bearer token**.
- **Where it goes:** `$env:X_BEARER_TOKEN = "..."` → `sources.twitter.bearer_token: ${X_BEARER_TOKEN}`,
  and set `sources.twitter.enabled: true`. Needs `pip install tweepy`.
- **Next step:** `python run.py ingest --source twitter` (or it runs inside `run-all`).
- **Unblocks:** the fastest signal — portal entries hours before curated trackers post them
  (watch-account + keyword search, parsed to PortalEvents).

### 5. Alert webhook — new-high-fit-entry notifications
- **What to provide:** a **Teams / Slack / email** incoming-webhook URL.
- **Where it goes:** `$env:ALERT_WEBHOOK_URL = "..."` → `alerts.webhook_url: ${ALERT_WEBHOOK_URL}`,
  set `alerts.enabled: true` and `alerts.channel: teams|slack|email`.
- **Next step:** `python run.py alert --min-fit 85`.
- **Unblocks:** same-hour push when a newly-ENTERED player clears the fit threshold. Until then,
  `alert` prints a dry-run to the console (no webhook = no send, by design).

---

## Out of scope (do NOT attempt)
- **Official NCAA portal (`sso.ncaa.org`).** Needs USD login **plus a 2FA code a coach sends** —
  interactive, per-access. The pipeline is deliberately designed to route around it; treat it as
  rare manual confirmation for contacts on top-N call targets only. Not automatable here.

## Verified built state (2026-06-30)
- **Tests:** `125 passed` (system Python 3.12, no network).
- **DB (`db/baseball.db`, refreshed 2026-06-27):** 35,034 players · 11,001 portal_events
  (10,147 ENTERED / 854 COMMITTED / 0 WITHDRAWN — withdrawals await the 64 Analytics feed) ·
  1,706 currently-ENTERED · 39,770 hitting + 32,864 pitching stat lines · 35,069 pitch-arsenal
  rows · 49,408 bio rows · 1,336 evaluations · 3,146 call assignments.
- **Offline board export:** `python run.py board` produces a ranked CSV; `google_sheet: skipped`
  (correctly, since disabled). No fabricated data anywhere — all rows trace to imported sources.
- **Readiness prep done this run (no inputs needed):** env-var interpolation added to
  `src/portal/config.py`; five credential fields annotated in `config.example.yaml`;
  `data/643_exports/README.md` (exact CSV schema) + `secrets/README.md` (service-account setup)
  created; `secrets/` folder created.
