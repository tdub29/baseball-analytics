# Ask the coach: how should the board work for marking players?

Quick decision to relay to the coach. He's picking **where** he wants to mark players
(Hot/Warm/Cold lead, favorites, notes). Everything else is already decided.

---

## The question to send him

> Quick one on the portal board — when you're looking at a player, how would you rather
> mark him?
>
> **Option A — all on the board:** tap his name right on the site and set him **Hot /
> Warm / Cold**, star your favorites, and type a quick note — all in one place, works on
> your phone.
>
> **Option B — board to look, sheet to mark:** use the board just to view the players and
> stats, but do your hot/cold tags and notes in our **team spreadsheet** like we do now.
>
> Whatever's easier in the moment — no wrong answer.

### Shorter version (one line)

> For the portal board: want to mark guys **Hot/Warm/Cold + notes right on the site**, or
> keep doing that in **our spreadsheet** and use the site just to look?

---

## What's the same either way

- Coaches mark players **Hot / Warm / Cold**, **favorite** them, and leave **notes**.
- It all flows back into the database (the existing CRM layer — `call_assignments`).
- **No login.** The board stays on the unguessable link; coaches just **pick their name
  from a dropdown** so notes show who wrote them.

## What his answer triggers (for Trevor)

| He picks | What I build |
|---|---|
| **A — on the board** | In-page editing (free Supabase backend, shared + live for all coaches). I'll need a 2-minute Supabase signup from you. |
| **B — in the sheet** | Board displays each player's lead chip / star / notes (color-coded, filterable) read-only; he edits via a dropdown in the linked Google Sheet. No new service. |
