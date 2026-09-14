<# 
One-time helper for moving the board to a new Netlify account/site.

Run from the repo root:
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-new-netlify-site.ps1

This links the repo to the new manually-created Netlify site, then deploys the
current prebuilt board as a single static file.
#>

$ErrorActionPreference = 'Stop'

$SiteName = 'usd-portal-3p176b'
$SiteUrl = 'https://usd-portal-3p176b.netlify.app/'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$netlify = Get-Command netlify -ErrorAction SilentlyContinue
if (-not $netlify) {
  throw "Netlify CLI not found. Install it with: npm i -g netlify-cli"
}

Write-Host "Checking Netlify login..."
netlify status
if ($LASTEXITCODE -ne 0) {
  Write-Host "`nLog into the NEW Netlify account, then rerun this script:" -ForegroundColor Yellow
  Write-Host "  netlify login"
  exit 1
}

$state = Join-Path $root '.netlify/state.json'
if (-not (Test-Path $state)) {
  Write-Host "`nNo linked site found. Linking this folder to $SiteName..." -ForegroundColor Yellow
  netlify link --name $SiteName
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`nCould not link by name. Confirm the new account owns $SiteUrl, then run:" -ForegroundColor Yellow
    Write-Host "  netlify link --name $SiteName"
    throw "netlify link failed."
  }
}

python scripts/build_html.py
if ($LASTEXITCODE -ne 0) { throw "Board build failed." }

$src = Join-Path $root 'data/portal_board.html'
if (-not (Test-Path $src)) { throw "Missing $src" }

$dist = Join-Path $root 'dist'
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Path $dist | Out-Null
Copy-Item $src (Join-Path $dist 'index.html') -Force

Write-Host "`nDeploying one production upload to the linked NEW Netlify site..."
netlify deploy --prod --dir dist --no-build
if ($LASTEXITCODE -ne 0) { throw "Netlify deploy failed." }

Write-Host "`nNew site status:" -ForegroundColor Green
netlify status
