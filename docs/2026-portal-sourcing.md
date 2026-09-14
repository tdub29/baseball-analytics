# 2026 portal sourcing — paths explored (2026-05-30)

Goal: get **live 2026 NCAA DI baseball transfer-portal entries** flowing into the pipeline.
Window opens **June 1, 2026**. Probed every path with CloakBrowser (stealth Chromium that
clears Cloudflare bot walls) + direct HTTP. Verdict: **D1Baseball + your cookie is the best
(realistically only solid) baseball path** — now wired and waiting on the cookie.

## Findings

| Source | Baseball? | Walls | CloakBrowser beats it? | Verdict |
|---|---|---|---|---|
| **D1Baseball 2026 tracker** | ✅ best coverage | Cloudflare **bot** wall + **server-side paywall** | bot wall: ✅ · paywall: ❌ (needs cookie) | **BEST — wired, needs cookie** |
| Verbal Commits | ❌ basketball only | bot wall (403) | ✅ (but wrong sport) | dead end for baseball |
| Wikipedia | ❌ no list exists | none | n/a | no 2026 baseball transfer list |
| Search engines (DDG/etc.) | n/a | bot challenge | flaky | not a feed |
| On3 portal wire | ❌ | SPA | loads shell only | **dead end** — baseball route fires NO data API and renders 0 entries (On3 portal = football/basketball only) |
| X/Twitter (x.com) | ~ signal | login + JS wall | renders no tweets logged-out | not viable free |
| Nitter mirrors | ~ | "verifying browser" / defunct | ❌ | not viable |
| 6-4-3 Portal HQ / 64 Analytics | ✅ | subscription login | likely (cookie pattern) | secondary — Trevor already has 6-4-3 access |

## Key evidence

- **D1Baseball paywall is server-side.** The public WP REST post
  `https://d1baseball.com/wp-json/wp/v2/posts/946960` returns only a 1,073-byte
  "Become an insider… SUBSCRIBE NOW" stub — the TablePress transfer table is rendered
  only for logged-in subscribers. So there is **no free backdoor**; a session cookie is required.
- The tracker is **WordPress + TablePress** → the data is an HTML `<table>`, which the
  d1baseball adapter's `_parse()` already scans (`table tr`).
- CloakBrowser got a clean **200 with no Cloudflare challenge** on both D1Baseball and
  Verbal Commits — it reliably clears the *bot* wall. It does **not** clear *auth* walls.

## What's wired

- `src/portal/stealth.py` — `stealth_get(url, cookie=…, wait_selector=…, cache_as=…)` reusable
  CloakBrowser fetcher (lazy import; falls back cleanly if cloakbrowser absent).
- `src/portal/sources/d1baseball.py` — fetches via `stealth_get` (clears bot wall) with the
  configured cookie (clears paywall); plain-requests fallback. Guards: no cookie → skips.
- `config.example.yaml` → `sources.d1baseball`: `stealth: true`, `cookie: ""`.

## To go live for June 1 — the one input needed

Paste a logged-in **d1baseball.com session Cookie** into `config.yaml`
(`sources.d1baseball.cookie`), then:

```powershell
python run.py ingest --source d1baseball     # pulls 2026 entries via CloakBrowser+cookie
python run.py run-all                          # ingest + enrich + evaluate + board
```

Get the cookie from browser devtools while logged in (Application → Cookies → copy the
`Cookie:` request header, esp. the `wordpress_logged_in_*` value). Tune `_parse()` cell order
against the real table once it renders.

## Secondary path worth trying

**6-4-3 Portal HQ** (`643charts.com`) — Trevor already has 6-4-3 access for stats. Same
CloakBrowser+cookie pattern could pull its portal-recruit list; would also tie directly to the
existing 6-4-3 stat enrichment. Not yet wired (an account session limit cut the deep probe short).

## Not worth pursuing for baseball

Verbal Commits (basketball), Wikipedia (no list), open web search (bot-walled), X/Twitter &
nitter (login/JS walls, mirrors defunct), On3 (baseball route renders no entries — portal is
football/basketball only; no data API fires for baseball).
