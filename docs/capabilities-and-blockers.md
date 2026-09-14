# What I can do right now vs. what's blocked

_Snapshot of the current environment + access. Probed 2026-05-29._

**Environment is good:** Python 3.12/3.13, Node 24, **pip + git + Docker all present**,
**network is live** (`stats.ncaa.org` → HTTP 200). Installed: pandas, openpyxl, pyyaml,
bs4, requests, lxml. Not yet installed (but installable): rapidfuzz, gspread, tenacity,
collegebaseball.

---

## ✅ Can do RIGHT NOW — zero extra access

| # | Capability | Why it's unblocked |
|---|---|---|
| 1 | **Import your `2025 Transfer Portal Main Database.xlsx` into the DB** | I have the local file; pandas/openpyxl installed. Seeds players + hot boards + call assignments. |
| 2 | **Build & run the DB / schema / init** | Done — `scripts/init_db.py` creates all 9 tables. |
| 3 | **Entity resolution + dedup engine** (rapidfuzz) | `pip install rapidfuzz` (net up); runs on imported data. |
| 4 | **Fit-scoring engine + need profiles** | Pure logic over the DB; no external access. |
| 5 | **Pull FREE live NCAA stats** via `collegebaseball` / `stats.ncaa.org` | Network reachable (200); `pip install` works. No login needed. |
| 6 | **Stand up `henrygd/ncaa-api`** for ncaa.com team context | Docker present. |
| 7 | **Fetch PUBLIC tracker pages** (static HTML) | WebFetch works on public pages (e.g., free portions of trackers). ToS-limited — internal use only. |
| 8 | **Write all pipeline code** (adapters, Sheet-sync, alerts) | Code authoring needs nothing; *running* some pieces needs creds (below). |
| 9 | **Web research** (sources, vendors, rules, windows) | — |

## 🟡 Can do, but need ONE input from you first

| Capability | What I need |
|---|---|
| **6-4-3 Charts advanced metrics** (STUFF+, xwOBA, SEAGER, per-pitch shapes) | A **CSV export** dropped in `data/643_exports/` — 6-4-3 has no public API. |
| **Google Sheet sync (run it)** | Share the sheet to a service account + the `*-service-account.json` (the sheet `…lskrac` is private → 401). |
| **D1Baseball / 64 Analytics subscriber data** | Your **logged-in session cookie** (you hold the subscription). |
| **X/Twitter real-time entry listener** | An X API **bearer token**. |
| **Teams / Slack / email alerts** | A **webhook URL**. |

## ❌ Cannot do (hard blockers)

| Capability | Why |
|---|---|
| **Pull official NCAA portal data** (`sso.ncaa.org`) | Needs USD login **+ a 2FA code a coach sends you**. I won't automate a 2FA/auth bypass — that's the whole reason the pipeline routes around it. |
| **Read any paywalled source I have no credentials for** | No cookie/token = no access; and I won't scrape behind a login without your credentials. |

> **Google Sheet — resolved:** the private Sheet (`…lskrac`) is the **same workbook** as the
> `2025 Transfer Portal Main Database.xlsx`, which I already imported — so its schema/content is
> known, not a blocker. Only *pushing* the auto board back into it needs a service-account JSON
> (writes a separate `Hot Board (auto)` tab; never touches your existing tabs). Reading the *live*
> sheet directly (vs. the static .xlsx) also needs the service account or a link-viewable share.

---

## Status: the pipeline is built

The chain **import → resolve → enrich → evaluate → board/alert** runs end-to-end on the real
2025 data (23,194 players · 18,621 pitcher lines · 1,586 fit-scored · 21 tests passing). See
[transfer-portal-pipeline.md](transfer-portal-pipeline.md) and the repo README. What's left is
wiring live feeds, each gated only on a credential/input you provide (d3-dashboard key, 6-4-3 CSV,
D1Baseball cookie, X token, Google service account, alert webhook).

---

## Re-verified + live-feed readiness prep — 2026-06-30

**Verified built state** (system Python 3.12 — not the Polymarket `.venv`, which lacks
`rapidfuzz`): **125 tests passing**, no network. DB (`db/baseball.db`, refreshed 2026-06-27) is
current and populated: 35,034 players · 11,001 portal_events (10,147 ENTERED / 854 COMMITTED /
**0 WITHDRAWN** — withdrawals await the 64 Analytics feed) · 1,706 currently-ENTERED · 39,770
hitting + 32,864 pitching stat lines · 35,069 pitch-arsenal rows · 49,408 bio rows · 1,336
evaluations. Offline `python run.py board` produces a ranked CSV with `google_sheet: skipped`
(correct — disabled). No fabricated data; every row traces to an imported source.

**Input-free prep completed this run** (all scoped to `baseball/`, no external calls):
- **Env-var secrets support** — `src/portal/config.py` now expands `${ENV_VAR}` /
  `${ENV_VAR:-fallback}` at load time (backward-compatible; unset ⇒ `""` ⇒ adapters no-op). So
  the D1Baseball/64 Analytics cookies, X bearer token, and alert webhook can be supplied via env
  vars — **no secret is hardcoded**. Five credential fields annotated in `config.example.yaml`.
- **Input folders + schema docs** — `data/643_exports/README.md` (exact 6-4-3 CSV schema:
  required name column, accepted headers, filename→season/split inference, hitting/pitching
  auto-detect) and `secrets/README.md` (Google service-account setup + env-var table);
  `secrets/` folder created. Both READMEs gitignored (guidance only).

**The input-unlock packet** (exactly what to provide + where): see
[input-unlock-packet-2026-06-30.md](input-unlock-packet-2026-06-30.md).

**Still blocked (each on ONE Trevor input):**
| Feed | Input needed | Lands at |
|---|---|---|
| 6-4-3 current-season metrics | CSV export | `data/643_exports/` (schema in its README) |
| Google Sheet push | service-account JSON + share sheet to `client_email` as Editor | `secrets/google-service-account.json` |
| D1Baseball / 64 Analytics | logged-in session cookie (or paste `.txt` — cookie-free) | `${D1BASEBALL_COOKIE}` / `${ANALYTICS64_COOKIE}` |
| X real-time listener | X API bearer token | `${X_BEARER_TOKEN}` |
| New-entry alerts | Teams/Slack/email webhook | `${ALERT_WEBHOOK_URL}` |

**Out of scope:** official NCAA portal (`sso.ncaa.org`) — interactive login + coach-sent 2FA;
the pipeline routes around it by design.

---

- **2026-08-05** — Supabase board overlay/notes RLS **static-verified** against
  `supabase/overlay_schema.sql` + `src/portal/overlay.py` + `scripts/build_html.py` +
  `config.yaml` (RLS enabled on `board_overlay`/`board_notes`; 6 anon select/insert/update
  policies, no delete; anon key scoped to just those two tables). Consolidated the reference
  into a single canonical doc [supabase-rls-sync-recipe.md](supabase-rls-sync-recipe.md)
  (removed the duplicate `-and-` variant; repointed the setup-doc link). **Live RLS still
  UNVERIFIED** — needs one outward run of `scripts/verify-supabase-rls.ps1` against a reachable
  project (config now carries a newer `sb_publishable_…` key vs. the paused host seen 07-22/07-30;
  outward calls were out of scope this pass). That live run is the only thing left to unblock t-1784628475334.

- **2026-08-08** — Supabase overlay/notes RLS **re-verified statically** (no credentials, no
  outward calls). Ran `python -m pytest tests/test_overlay_rls_schema.py -q` → **14 passed**;
  re-checked every claim in the reference doc against `src/portal/overlay.py`,
  `scripts/build_html.py`, and `config.example.yaml` (anon-key-only reads/writes,
  `Prefer: resolution=merge-duplicates,return=minimal` upsert, 25 s re-poll, service-key guard).
  Canonical reference: [supabase-rls-sync-recipe.md](supabase-rls-sync-recipe.md). **Live RLS
  still UNVERIFIED** — `bqmvpxpcihkiljxednbd.supabase.co` still does not resolve (paused/deleted
  free-tier project). Only outstanding step: a human un-pauses/re-provisions the project, then
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-supabase-rls.ps1` from `baseball/` closes t-1784628475334.

- **2026-08-09**. Fourth blocked check, same result. DNS on
  `bqmvpxpcihkiljxednbd.supabase.co` fails (`getaddrinfo` / `EAI_NONAME`), so the project is
  still paused or deleted; the live probe cannot run and the task stays Blocked. Static
  posture re-confirmed the same pass: `python -m pytest tests/test_overlay_rls_schema.py -q`
  → **14 passed**. Nothing further is doable from this side. Note the command in the two
  entries above uses `pwsh`, which is **not installed on this machine** (Windows PowerShell
  5.1 only); the runnable form is
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-supabase-rls.ps1`.

- **2026-08-16**. Fifth blocked check, same DNS failure (`socket.getaddrinfo` on
  `bqmvpxpcihkiljxednbd.supabase.co` → `gaierror: [Errno 11001] getaddrinfo failed`), so the
  project is still paused or deleted. Static posture re-confirmed: `python -m pytest
  tests/test_overlay_rls_schema.py -q` → **14 passed**. Two defects in the probe itself were
  fixed this pass, both of which would have produced a wrong answer the first time it finally ran:
  - `scripts/verify-supabase-rls.ps1` sent `player_id = "zzz-rls-test-<timestamp>"`, a **string**,
    into a `bigint primary key`. PostgREST rejects that on type before RLS is consulted, so
    `-TestUpsert` would have printed `FAIL POST board_overlay upsert` against a perfectly healthy
    write policy. It now sends the fixed id `-999999`, which cannot collide with a real NCAA
    player id and is trivial to delete from the dashboard afterward (anon has no DELETE policy).
  - Every `pwsh -File` invocation across this project's docs, scripts and `CLAUDE.md` is now
    `powershell -NoProfile -ExecutionPolicy Bypass -File`. The 08-09 entry flagged this and only
    corrected the one command it quoted; nine others were still unrunnable on this machine.

  Nothing else is doable from this side. The task is one un-pause away from closing.
