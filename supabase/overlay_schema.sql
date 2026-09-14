-- Coach-board interaction overlay — Supabase (Postgres) schema.
-- Run this ONCE in your Supabase project: SQL Editor → paste → Run.
-- Backs the "supabase" board_overlay backend (coaches edit Hot/Warm/Cold, favorites,
-- and notes directly on the published board). See docs/board-interaction-setup.md.
--
-- No login: the board uses the project's PUBLIC anon key from the browser. Row-level
-- security below means that key can read + upsert ONLY these two tables and nothing
-- else in the project. The unguessable board link + anon key are the gate (matches the
-- "no-login, pick-your-name" decision). Attribution is by the coach-picked name.

-- One row per player: the shared lead temperature + favorite star.
create table if not exists public.board_overlay (
  player_id   bigint primary key,                                   -- = players.player_id (stable across rebuilds)
  lead_temp   text check (lead_temp in ('1','2','3','4','5')),      -- coach rating, 5 = hottest; NULL = untagged
  favorite    boolean not null default false,
  updated_by  text,                                                 -- coach name (dropdown); attribution without login
  updated_at  timestamptz not null default now()
);

-- One note per (player, coach) — mirrors the pipeline's per-scout scout_notes JSON.
create table if not exists public.board_notes (
  player_id   bigint not null,
  author      text   not null,                                      -- coach name (dropdown)
  body        text,
  updated_at  timestamptz not null default now(),
  primary key (player_id, author)
);

alter table public.board_overlay enable row level security;
alter table public.board_notes   enable row level security;

-- anon may read + upsert these two tables only. (PostgREST upsert = INSERT ... ON
-- CONFLICT DO UPDATE, so both insert and update policies are required.)
drop policy if exists "overlay anon select" on public.board_overlay;
drop policy if exists "overlay anon insert" on public.board_overlay;
drop policy if exists "overlay anon update" on public.board_overlay;
create policy "overlay anon select" on public.board_overlay for select to anon using (true);
create policy "overlay anon insert" on public.board_overlay for insert to anon with check (true);
create policy "overlay anon update" on public.board_overlay for update to anon using (true) with check (true);

drop policy if exists "notes anon select" on public.board_notes;
drop policy if exists "notes anon insert" on public.board_notes;
drop policy if exists "notes anon update" on public.board_notes;
create policy "notes anon select" on public.board_notes for select to anon using (true);
create policy "notes anon insert" on public.board_notes for insert to anon with check (true);
create policy "notes anon update" on public.board_notes for update to anon using (true) with check (true);

-- ── Migration: if you already created board_overlay with the old hot/warm/cold check,
-- run THIS once to switch it to the 1-5 rating (also clears the setup-test row) ──────
--   delete from public.board_overlay where lead_temp not in ('1','2','3','4','5') or player_id < 0;
--   alter table public.board_overlay drop constraint if exists board_overlay_lead_temp_check;
--   alter table public.board_overlay add  constraint board_overlay_lead_temp_check check (lead_temp in ('1','2','3','4','5'));

-- Optional hardening (uncomment if you ever want to lock writes to a known staff list):
-- create policy "notes named authors only" on public.board_notes for insert to anon
--   with check (author in ('Trevor','Coach K','...'));
