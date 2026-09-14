#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Daily one-shot: refresh portal data, rebuild the dashboard, publish it to Netlify,
  and print the link to send the coaching staff.

.DESCRIPTION
  Run this each morning. It:
    1. Refreshes the data      (python run.py run-all). Continues even if a source errors
                               (e.g. an expired D1Baseball cookie) — the board still
                               rebuilds from the current DB + free sources.
    2. Rebuilds the dashboard  (python scripts/build_html.py -> data/portal_board.html)
    3. Stages ONLY that one file into dist/index.html. It never deploys data/, which holds
       the SQLite DB and scraped/not-for-redistribution cache.
    4. Publishes dist/ to your linked Netlify site (same unguessable *.netlify.app URL
       every day).

  One-time setup is in scripts/README-publish.md
  (npm i -g netlify-cli ; netlify login ; netlify sites:create ; netlify link).

.PARAMETER SkipRefresh
  Skip the data pull and just rebuild + publish whatever is already in the DB.
#>
param([switch]$SkipRefresh)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# 1/4 — refresh the data. run-all catches most per-source errors itself, but an expired
# D1Baseball cookie can still surface a non-zero exit; warn and carry on so the daily
# board always publishes from whatever is current.
if (-not $SkipRefresh) {
  Step "1/5  Refreshing portal data (run-all)"
  python run.py run-all
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "run-all exited $LASTEXITCODE (often an expired D1Baseball cookie). Rebuilding from the current DB anyway."
  }
} else {
  Write-Host "Skipping data refresh (-SkipRefresh)."
}

# 2/5 — pull coach overlay edits (lead temp / favorites / notes) into the DB so the
# rebuilt board + CSV reflect the latest tags. No-ops if board_overlay.backend = none.
# (Redundant after a full run-all, which already syncs — but cheap, and it covers the
# -SkipRefresh path where run-all didn't run.)
Step "2/5  Syncing coach overlay"
python run.py sync-overlay
if ($LASTEXITCODE -ne 0) { Write-Warning "sync-overlay exited $LASTEXITCODE - continuing; the board still reads live." }

# 3/5 — rebuild the self-contained HTML. This MUST succeed; if it doesn't, publish nothing.
Step "3/5  Rebuilding dashboard HTML"
python scripts/build_html.py
if ($LASTEXITCODE -ne 0) { throw "build_html.py failed (exit $LASTEXITCODE) - nothing published." }

$src = Join-Path $root 'data/portal_board.html'
if (-not (Test-Path $src)) { throw "Expected $src but it does not exist." }

# 4/5 — stage exactly one file. Rebuild dist/ from scratch so nothing stale or extra
# (and never the data/ folder) can leak into the public deploy.
Step "4/5  Staging the single file for deploy"
$pub = Join-Path $root 'dist'
if (Test-Path $pub) { Remove-Item $pub -Recurse -Force }
New-Item -ItemType Directory -Path $pub | Out-Null
Copy-Item $src (Join-Path $pub 'index.html') -Force
$sizeMB = [math]::Round((Get-Item $src).Length / 1MB, 1)
Write-Host "Staged dist/index.html ($sizeMB MB)."

# 5/5 — publish to the linked Netlify site (keeps the same URL each day).
Step "5/5  Publishing to Netlify"
$netlify = Get-Command netlify -ErrorAction SilentlyContinue
if (-not $netlify) {
  throw "netlify CLI not found. One-time setup: npm i -g netlify-cli ; netlify login ; netlify sites:create ; netlify link  (see scripts/README-publish.md)."
}
# --no-build: we upload the prebuilt dist/ as-is; without it the CLI tries to run a
# (nonexistent) site build and errors.
netlify deploy --prod --dir dist --no-build
if ($LASTEXITCODE -ne 0) {
  throw "netlify deploy failed (exit $LASTEXITCODE). If it said 'Not linked to a site', run: netlify link"
}

Write-Host "`nDone. Copy the 'Website URL' printed above and send it to the coaches." -ForegroundColor Green
Write-Host "Same link every day - after the first send, they just refresh to see the latest board." -ForegroundColor Green
