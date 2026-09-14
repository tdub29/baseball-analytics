# Netlify setup — publishing the hot board to coaches

One-time setup so `scripts/publish-board.ps1` can push the board to a single, unguessable
link you share with the staff. Do this **once**; after that the daily command just works.

Current live board URL: `https://usd-portal-3p176b.netlify.app/`

> Already covered, with the daily workflow + gotchas, in
> [scripts/README-publish.md](../scripts/README-publish.md). This file is the trimmed,
> copy-paste **setup checklist**.

## Prerequisites (already done on this machine)

- Node.js — installed (`node -v`)
- Netlify CLI — installed (`netlify --version` → `netlify-cli/26.x`)

If you ever need to reinstall the CLI: `npm i -g netlify-cli`

## One-time setup (run these in order)

```powershell
# 1. Sign in (opens a browser; a free Netlify account is fine)
netlify login

# 2. Move into the project
cd "C:\Users\TrevorWhite\Downloads\Big Projects\baseball"

# 3. Create the site — let it AUTO-GENERATE the name
netlify sites:create
#    When prompted:
#      • Team: pick your team (or the only one shown)
#      • Site name: press Enter to accept the random name
#        (the randomness IS the privacy — see note below)

# 4. Link this folder to the site you just made
netlify link --name usd-portal-3p176b
#    This writes .netlify/state.json so every deploy hits the SAME url.
```

That's it. Confirm it worked:

```powershell
netlify status
#  → shows the linked site + its URL (https://<random-name>.netlify.app)
```

## Publish (every time you want coaches to see the latest)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-board.ps1
```

…or double-click `scripts/publish-board.cmd`. It prints `Website URL: https://….netlify.app`.
**Send that link to the coaches once** — the same link always shows the latest board.

## Notes

- **Keep the name random.** Don't rename the site to `usd-baseball-portal` or anything
  guessable. The default name (e.g. `clever-otter-4f2a1c.netlify.app`) is what keeps the
  board from being found. The link is the only gate — see below.
- **It's an unguessable link, not a login.** Anyone the link is forwarded to can open it,
  and you can't revoke per-person. Fine for a small trusted staff. If you ever need real
  access control, the upgrade is Netlify password protection (paid plan) or **Cloudflare
  Access** (free — coaches sign in with an email code; can be limited to `@sandiego.edu`).
- **Only one file ships.** `publish-board.ps1` deploys `data/portal_board.html` (staged as
  `dist/index.html`) and nothing else — never the `data/` folder or the database.
- **The map needs internet.** Player data is embedded in the file, but the map and fonts
  load from a CDN, so coaches need a connection for the map (the tables always work).
