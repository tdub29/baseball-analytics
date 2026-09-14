# Supabase RLS + overlay sync — reference recipe

**Status (2026-08-06):** static verification is now **enforced by tests**
(`tests/test_overlay_rls_schema.py`, 14 assertions, offline, no credentials) rather than
being a one-time read, so the security posture cannot be loosened silently.

**Re-verified 2026-08-08:** the 14 assertions still pass (`python -m pytest
tests/test_overlay_rls_schema.py -q` = 14 passed) and every recipe claim was re-checked
against `src/portal/overlay.py`, `scripts/build_html.py`, and `config.example.yaml` —
browser upsert uses `Prefer: resolution=merge-duplicates,return=minimal`, the board
re-polls both tables every 25 s (`sbFetch`), and both browser + server-side reads use the
anon key only (service_role/secret keys rejected by `_looks_like_service_key`). Static
posture holds; the live check below is still the one blocked step (host unresolved).

**Re-checked 2026-08-18 (4th probe):** the 14 offline assertions still pass (`python -m pytest tests/test_overlay_rls_schema.py -q` = 14 passed in 0.18s) and `bqmvpxpcihkiljxednbd.supabase.co` **still does not resolve** (DNS gaierror). Four failures across 2026-07-22, 07-30, 08-06 and 08-18 is not a transient outage: treat the project as gone until a human says otherwise. Static posture is enforced and holding; the live probe is the only open step.

**Still NOT live-verified.** A third live probe on 2026-08-06 ran
`scripts/verify-supabase-rls.ps1` and the host `bqmvpxpcihkiljxednbd.supabase.co` again
failed to resolve, matching 2026-07-22 and 2026-07-30. The free-tier project is
paused or deleted. The newer `sb_publishable_…` key in `config.yaml` did **not** indicate
a re-provisioned project. **This step is blocked on a human un-pausing (or
re-provisioning) the Supabase project** — see
[Live verification](#live-verification-the-remaining-blocked-step) for the one command
that closes it once the project is up.

The single canonical doc for how the **Supabase** board-overlay backend is secured and how
coach edits round-trip into the pipeline. Setup lives in
[board-interaction-setup.md](board-interaction-setup.md); the schema you run once is
[`../supabase/overlay_schema.sql`](../supabase/overlay_schema.sql).

## What this covers

The coach-board overlay (Path A, `board_overlay.backend: supabase`) lets coaches edit lead
temperature / favorites / notes directly on the published board, with **no login**. The
browser talks to Supabase PostgREST using the **public anon key**, and the only thing
stopping that key from touching the rest of the project is **row-level security on two
tables**. This doc is the reference for what those policies are and how the data round-trips
back into the pipeline.

Source of truth: [`../supabase/overlay_schema.sql`](../supabase/overlay_schema.sql) (run once
in the Supabase SQL Editor). Client read + round-trip:
[`../src/portal/overlay.py`](../src/portal/overlay.py). Browser write path:
[`../scripts/build_html.py`](../scripts/build_html.py) (the baked-in board JS).

## The two tables

| Table | Grain / PK | Columns | Mirrors |
|---|---|---|---|
| `public.board_overlay` | one row per player — PK `player_id` (= `players.player_id`) | `lead_temp` (`'1'`–`'5'`, 5 = hottest, CHECK-constrained, NULL = untagged), `favorite` (bool, default false), `updated_by` (coach name), `updated_at` (timestamptz) | `call_assignments.lead_temp` / `favorite` |
| `public.board_notes` | one row per (player, coach) — PK `(player_id, author)` | `body` (text), `updated_at` | per-coach `call_assignments.scout_notes` JSON |

`player_id` is stable across nightly rebuilds (entity-resolution guarantees it), so a coach's
tags re-attach to the right player every refresh
(`overlay.py::sync_overlay_to_db`, keyed on `int(player_id)`).

## The RLS policies (verbatim from the schema)

Both tables have RLS **enabled**, then exactly six policies — read + insert + update for the
`anon` role on each table. Insert **and** update are both required because PostgREST upsert is
`INSERT … ON CONFLICT DO UPDATE`; without the update policy an edit to an existing row fails.
(`overlay_schema.sql` lines 29–46.)

```sql
alter table public.board_overlay enable row level security;
alter table public.board_notes   enable row level security;

-- board_overlay: anon may read + upsert, nothing else
create policy "overlay anon select" on public.board_overlay for select to anon using (true);
create policy "overlay anon insert" on public.board_overlay for insert to anon with check (true);
create policy "overlay anon update" on public.board_overlay for update to anon using (true) with check (true);

-- board_notes: same
create policy "notes anon select" on public.board_notes for select to anon using (true);
create policy "notes anon insert" on public.board_notes for insert to anon with check (true);
create policy "notes anon update" on public.board_notes for update to anon using (true) with check (true);
```

**Security model.** `using (true)` / `with check (true)` = the anon key can freely read and
upsert *these two tables*. It cannot touch any other table because no other table grants a
policy to `anon`, and RLS defaults to deny. The gate is: RLS scoping + the unguessable
Netlify board link + the anon key. Attribution is by the coach-picked name (`updated_by` /
`author`), not auth. **No DELETE policy exists** — anon can retag or clear (`lead_temp = NULL`)
but cannot drop rows.

### Residual risks (accepted, by design)

- **Anyone with the board link can read + write ALL overlay rows and impersonate any coach
  name.** No per-row or per-author auth. This is the explicit "no-login, pick your name"
  decision — fine for a small trusted staff on an unguessable link, not a public board.
- **Optional hardening is present but commented out** in `overlay_schema.sql` (lines 54–56):
  lock inserts to a known staff allowlist —
  `create policy "notes named authors only" on public.board_notes for insert to anon with check (author in ('Trevor','Coach K', …))`.
  Add the same `with check` to the overlay insert/update to bound writes. It stops name
  spoofing, not link sharing.
- **Rotating exposure**: the anon key lives in the published HTML. If the link leaks beyond
  staff, rotate the anon key in Supabase and republish; the old board stops working.

**Migration note (already in the schema).** The overlay was originally hot/warm/cold; it was
switched to a 1–5 rating. If a project still has the old CHECK, run the three migration lines
at the bottom of `overlay_schema.sql` (delete non-1–5 rows + test rows, drop the old
constraint, add the 1–5 constraint).

## Why the anon key is safe to embed

`overlay.py::_sb()` refuses to use a service key: `_looks_like_service_key()` (lines 131–148)
rejects both the `sb_secret_…` format and any legacy JWT whose payload decodes to
`role=service_role`. The board build and the server-side read both use **only** the anon key,
so there is no path for a service_role key to leak into the published HTML. The
current `config.yaml` uses a `sb_publishable_…` key (the newer public-key format) — public by
design; RLS is what makes it harmless. `verify-supabase-rls.ps1` mirrors the same guard before
it will run.

## The sync recipe (end to end)

```
supabase/overlay_schema.sql  ──run once──▶  board_overlay + board_notes  (RLS on)
        │                                            ▲            │
   config.yaml                                       │ upsert     │ GET (anon key,
   board_overlay.backend: supabase                   │ (anon key, │ server-side)
   board_overlay.supabase.{url, anon_key}            │ in browser)│
        │                                            │            ▼
   scripts/build_html.py ──embeds anon key──▶  published board  read_overlay_from_supabase()
        │                                       (coach edits)         │
   publish-board.ps1 ──▶ Netlify (unguessable link)                   │
                                                                      ▼
                            run.py sync-overlay ──▶ call_assignments (lead_temp,
                                                     favorite, scout_notes)  keyed by player_id
```

1. **Schema (one-time).** Supabase → SQL Editor → paste `supabase/overlay_schema.sql` → Run.
   Creates both tables, enables RLS, creates the six anon policies. Idempotent
   (`create table if not exists`, `drop policy if exists` before each `create policy`).
2. **Config.** In `config.yaml`, set `board_overlay.backend: supabase` and
   `board_overlay.supabase.url` + `.anon_key` (the **public** key — the service-key guard
   rejects a service_role/secret key). Set `board_overlay.coaches: [...]` once.
3. **Write path (browser → Supabase).** `build_html.py` bakes the anon key + table names into
   the board HTML. A coach clicks a 1–5 lead / star / types a note; the page upserts directly
   to `…/rest/v1/board_overlay` and `…/board_notes` via `POST` with header
   `Prefer: resolution=merge-duplicates,return=minimal` (`build_html.py` `persistOverlay` /
   `persistNote`, lines 758–768). RLS admits it (anon, these two tables). The board re-polls
   both tables every 25 s (`sbFetch`, line 815), so every coach converges on the same state.
4. **Read/sync path (Supabase → pipeline).** `run.py sync-overlay` calls
   `overlay.read_overlay_from_supabase()` — a server-side `GET /rest/v1/<table>?select=*` of
   both tables with the **same anon key** (RLS already permits the read, so no service key is
   needed) — and merges them into `{player_id: {temp, fav, by, notes:{author:body}}}`.
5. **Round-trip into `call_assignments`.** `sync_overlay_to_db()` writes the merged state into
   `call_assignments.lead_temp / favorite / scout_notes` keyed by `int(player_id)`.
   `ensure_overlay_columns()` adds those columns to an older DB if missing, so `sync-overlay`
   never fails on a fresh DB. It fills a NULL `priority` from the lead rating but never
   clobbers a manual one, and skips any `player_id` no longer in `players` (never FK-inserts a
   stale/test row). Because `player_id` is stable across rebuilds, the next `run-all`
   re-attaches every tag to the right player.
6. **First paint.** `build_overlay_payload()` seeds the baked HTML from a live Supabase read so
   the board matches what the browser fetches on load; it falls back to the DB snapshot
   (`seed_from_db`) if the read fails (e.g. an offline build).

`push-overlay-sheet` / `read_overlay_from_sheet` are the parallel **sheet** backend — same
round-trip target (`call_assignments`), a Google Sheet instead of Supabase, per-coach note
columns instead of a `board_notes` table.

Commands: `python run.py sync-overlay` (pull edits in), `python run.py run-all` (full refresh,
includes sync), `scripts/publish-board.ps1` (daily: refresh → sync → rebuild → publish).

## Reproducing this on a NEW table (the reusable pattern)

To add another anon-writable overlay table (say `board_flags`), copy the same three-part
pattern:

1. **Create the table with a stable PK** that maps to `players.player_id` (or a
   `(player_id, author)` composite for per-coach rows):
   ```sql
   create table if not exists public.board_flags (
     player_id bigint primary key,
     flag      text,
     updated_by text,
     updated_at timestamptz not null default now()
   );
   ```
2. **Enable RLS + grant anon the upsert triad** (select + insert + update; add a `with check`
   allowlist only if you want to bound writers; deliberately no delete):
   ```sql
   alter table public.board_flags enable row level security;
   create policy "flags anon select" on public.board_flags for select to anon using (true);
   create policy "flags anon insert" on public.board_flags for insert to anon with check (true);
   create policy "flags anon update" on public.board_flags for update to anon using (true) with check (true);
   ```
3. **Client upsert + subscribe pattern** (mirror `overlay.py` + the board JS):
   - **Browser write:** `POST {url}/rest/v1/board_flags` with headers
     `apikey`/`Authorization: Bearer <anon>`, `Content-Type: application/json`, and
     `Prefer: resolution=merge-duplicates,return=minimal`; body keyed on the PK.
   - **Poll for others' edits:** `GET {url}/rest/v1/board_flags?select=*` on an interval
     (the board uses 25 s), merge into local state, re-render unless a field is being edited.
   - **Server-side read + round-trip:** `GET …?select=*` with the anon key, then upsert into
     the pipeline DB keyed by the stable `player_id`. Never embed a service_role key.

## Static verification (enforced by tests, no live DB, no credentials)

`tests/test_overlay_rls_schema.py` asserts the posture below against
`supabase/overlay_schema.sql` on every test run, so widening a policy later fails CI
instead of going unnoticed:

```powershell
python -m pytest tests/test_overlay_rls_schema.py -q     # 14 passed
```

It checks RLS enabled on both tables, the full anon select+insert+update triad on each
(the upsert triad — PostgREST upsert needs update as well as insert), **no** DELETE
policy anywhere, no policy on any non-overlay table, no policy targeting `public`, no
bare `GRANT` that would bypass RLS, the 1–5 `lead_temp` domain, and the stable
`player_id` / `(player_id, author)` primary keys. Comment lines are stripped first so the
commented-out hardening block cannot satisfy or trip an assertion.

Also confirmed by reading `overlay.py`, `build_html.py`, `config.yaml`:

- [x] RLS `enable`d on `board_overlay` and `board_notes` (`overlay_schema.sql:29–30`).
- [x] anon `select` + `insert` + `update` policies on both (upsert-complete); no `delete` grant.
- [x] No policy on any other table → the anon key is scoped to just these two.
- [x] Server-side read uses the anon key (`_sb`, `_sb_get`); service_role/secret keys are
      rejected before any request (`_looks_like_service_key`).
- [x] Browser writes use `Prefer: resolution=merge-duplicates` upsert; 25 s re-poll.
- [x] Sync keys on the stable `players.player_id`; overlay columns auto-added to
      `call_assignments`.
- [x] `config.yaml` backend = `supabase` with a `sb_publishable_…` (public) key, not a secret key.

## Live verification (the remaining BLOCKED step)

Static review cannot confirm the **live** project actually ran the schema with RLS on (a
schema file in the repo is not proof it was applied). That is the one open item and needs the
project reachable + an outward call — both out of scope for a read-only pass.

**One command (once the project is up):**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-supabase-rls.ps1        # add -TestUpsert to also exercise the write policy
```

It reads `url` + the public `anon_key` from `config.yaml`, refuses a service_role/secret key,
DNS-pre-checks the host (fails clearly if the free-tier project is paused), then checks:

1. `board_overlay` + `board_notes` return `200` (anon SELECT policy works).
2. A non-overlay table (`players`) is **not** readable with the anon key (RLS scoping holds).
3. (`-TestUpsert`) upsert to `board_overlay` succeeds (anon INSERT/UPDATE). anon has **no**
   delete policy, so remove the throwaway row from the dashboard afterward.

Equivalent manual SQL (Supabase SQL Editor) to confirm RLS is on + list the policies:

```sql
select relname, relrowsecurity
from pg_class where relname in ('board_overlay','board_notes');   -- both relrowsecurity = true

select tablename, policyname, cmd, roles
from pg_policies where tablename in ('board_overlay','board_notes')
order by tablename, cmd;                                          -- 3 rows each: SELECT/INSERT/UPDATE to {anon}
```

If (1)–(3) pass and a non-overlay table is denied, the live RLS matches this recipe. If
`players` (or any non-overlay table) returns rows to the anon key, RLS is misconfigured —
anon is over-granted — and the fix is to re-run the schema and check no broad `to anon` /
`to public` policy or a stray `GRANT` bypasses RLS.
