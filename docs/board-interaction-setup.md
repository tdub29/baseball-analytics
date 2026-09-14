# Coach interaction: lead rating (1–5, 5 = hot) + favorites + notes

Lets coaches mark players on the published hot board. Both paths are built; pick one by
setting `board_overlay.backend` in `config.yaml`. Everything round-trips into
`call_assignments` (`lead_temp`, `favorite`, `scout_notes`), keyed by the stable
`players.player_id`, so a coach's tags re-attach to the right player on every daily rebuild.

> For the Supabase security/RLS model + the full write→read→round-trip sync path (and the
> live-verification SQL/curl), see [supabase-rls-sync-recipe.md](supabase-rls-sync-recipe.md).

| | **A — Supabase (edit on the board)** | **B — Google Sheet (edit in the sheet)** |
|---|---|---|
| `backend:` | `supabase` | `sheet` |
| Coach does | Clicks a 1–5 lead rating, stars, types notes on the board; shared + live | Edits a Lead dropdown / Favorite / notes columns in a Sheet; board shows them read-only |
| New service | Free Supabase project | None (reuses your Google service account) |
| Attribution | "pick your name" dropdown (no login) | per-coach note columns in the Sheet |

Common to both: no login. Set the staff names once in config:

```yaml
board_overlay:
  backend: supabase            # or: sheet  (or: none to turn it off)
  coaches: ["Trevor", "Coach K", "Coach M"]
```

---

## Path A — Supabase (edit on the board)

**1. Create the project** — sign in at <https://supabase.com> → New project (free tier).
Wait ~2 min for it to provision.

**2. Create the tables** — left sidebar → **SQL Editor** → New query → paste all of
[`supabase/overlay_schema.sql`](../supabase/overlay_schema.sql) → **Run**. (Creates the two
tables + the row-level-security policies that let the public anon key read/write *only*
these two tables.)

**3. Grab the URL + anon key** — left sidebar → **Project Settings → API**:
- **Project URL** → `https://<ref>.supabase.co`
- **anon public** key (the long `eyJ...` one — *not* the `service_role` key)

**4. Put them in `config.yaml`:**

```yaml
board_overlay:
  backend: supabase
  coaches: ["Trevor", "Coach K"]
  supabase:
    url: "https://<ref>.supabase.co"
    anon_key: "eyJ...your anon public key..."
```

**5. Build + publish** — `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-board.ps1`. On the board, coaches:
- pick their name (top, **You** dropdown — remembered on their device),
- click a player → a **1–5 lead rating** (5 = hot), **☆ Favorite**, and a note,
- filter the table by **Lead** and **★ only**.

Changes save to Supabase instantly and other coaches see them within ~25 s (the board
re-polls). `run-all` / `sync-overlay` pull them back into `call_assignments` for your CSV,
Excel, and records.

> **Privacy:** the anon key is meant to be public (it's embedded in the page); RLS is the
> real gate and limits it to the two overlay tables. The unguessable Netlify link is still
> the front door. Anyone with the link can edit — fine for a trusted staff. To lock writes
> to known names, uncomment the "named authors only" policy in the SQL file.

---

## Path B — Google Sheet (edit in the sheet)

Reuses the Google service account from the `google_sheet:` block (set that up first if you
haven't — same `service_account_json` + `spreadsheet_id`).

**1. Configure:**

```yaml
board_overlay:
  backend: sheet
  coaches: ["Trevor", "Coach K"]       # becomes the per-coach note columns
  sheet:
    tab: "Coach Board"
    limit: 300                          # how many top-fit players to list for tagging
    edit_url: "https://docs.google.com/spreadsheets/d/<id>/edit#gid=<tab-gid>"   # optional deep link on the board
```

**2. Build the editable tab** — `python run.py push-overlay-sheet`. Creates/refreshes a
**Coach Board** tab with `player_id | Player | School | Pos | Rating | Lead | Favorite | <coach> notes…`
and a **1–5** dropdown on the Lead column (5 = hot). Re-runs preserve existing edits and add
new portal entries (this also happens automatically inside `run-all`).

**3. Coaches edit the sheet** — set Lead (1–5, 5 = hot), put anything (`x`, `TRUE`) in
Favorite, type in their notes column.

**4. Publish** — `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-board.ps1`. The board reads the sheet at build
time and shows each player's lead chip / ★ / notes read-only, filterable, with an
"Edit in the team sheet →" link (if `edit_url` is set). `sync-overlay` writes the edits back
into `call_assignments`.

---

## Turn it off

```yaml
board_overlay:
  backend: none
```

The board renders exactly as before — no overlay UI, no external calls.

## Commands

| Command | What it does |
|---|---|
| `python run.py sync-overlay` | Pull coach edits from the active backend → `call_assignments` |
| `python run.py push-overlay-sheet` | (sheet only) (re)build the coach-editable tab, preserving edits |
| `python run.py run-all` | Full refresh — includes the two above when a backend is set |
| `scripts/publish-board.ps1` | Daily: refresh → sync overlay → rebuild → publish to Netlify |
