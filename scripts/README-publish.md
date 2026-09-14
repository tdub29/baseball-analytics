# Publishing the hot board to coaches (Netlify, one link)

`scripts/publish-board.ps1` is the **one command you run each morning**. It refreshes the
data, rebuilds the dashboard, and pushes it to a single Netlify URL you share with the
staff. The link is **unguessable** (a random `*.netlify.app`) and **stays the same every
day**, so you only send it once.

Current live board URL: `https://usd-portal-3p176b.netlify.app/`

## One-time setup (do this once)

```powershell
# 1. Install the CLI (Node is already on this machine)
npm i -g netlify-cli

# 2. Sign in (opens a browser; free account is fine)
netlify login

# 3. Create the site and link this folder to it
cd "C:\Users\TrevorWhite\Downloads\Big Projects\baseball"
netlify link --name usd-portal-3p176b
```

`netlify link` writes `.netlify/state.json`, so every future deploy hits the **same URL**.

> Privacy note: don't rename the site to something guessable like `usd-baseball-portal`.
> The default random name (e.g. `clever-otter-4f2a1c.netlify.app`) is what keeps the board
> from being found. Anyone you give the link to can open it — see "Gotchas" below.

## Every morning

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-board.ps1
```

…or just double-click **`scripts/publish-board.cmd`**.

It prints `Website URL: https://….netlify.app`. Send that to the coaches the first time;
after that, the same link always shows the latest board.

## Gotchas

- **Expired D1Baseball cookie:** if `run-all` errors on D1Baseball, the script **warns and
  still rebuilds + publishes** from the current DB + free sources (VerbalCommits, the 6-4-3
  CSVs in `data/643_exports`). Paste a fresh cookie into `config.yaml`
  (`sources.d1baseball.cookie`) when convenient.
- **Only one file ships.** The script deploys `data/portal_board.html` (staged as
  `dist/index.html`) and nothing else — never the `data/` folder or the DB, which hold
  scraped, not-for-redistribution cache.
- **Rebuild + publish without re-pulling data:** `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-board.ps1 -SkipRefresh`
- **It's an unguessable link, not real auth.** Fine for a small trusted staff, but anyone
  the link is forwarded to can open it, and you can't revoke per-person. If you ever need
  true access control, the upgrades are Netlify password protection (paid) or **Cloudflare
  Access** (free — coaches sign in with an email code; you can allow only `@sandiego.edu`).
- **The map needs internet.** The board embeds all player data inline, but the Leaflet map
  and fonts load from a CDN, so coaches need a connection for the map to render (the tables
  always work).
