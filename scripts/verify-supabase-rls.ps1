<#
.SYNOPSIS
  Live-verify the coach-board Supabase RLS (board_overlay + board_notes) using ONLY the
  public anon key from config.yaml. Read-only by default. Turns the manual probe in
  docs/supabase-rls-sync-recipe.md into one command.

.DESCRIPTION
  Task t-1784628475334. On 2026-07-22 and again 2026-07-30 the project host did not
  resolve (free-tier paused/deleted), so this could not be run live. Un-pause the project
  in the Supabase dashboard (or point config.yaml at the current project), then run:

      powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-supabase-rls.ps1

  Pass criteria (from the recipe doc):
    1. board_overlay + board_notes return 200 (anon SELECT policy works).
    2. A non-overlay table (players) is NOT readable with the anon key (RLS scoping holds).
    3. (opt, -TestUpsert) upsert to board_overlay with a throwaway player_id succeeds
       (anon INSERT/UPDATE). anon has NO delete policy, so remove the test row from the
       dashboard afterward. Off by default so no test row is left behind.

  Safety: refuses to run if the configured key looks like a service_role/secret key.
#>
[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config.yaml'),
  [switch]$TestUpsert
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path $ConfigPath)) { Write-Error "config.yaml not found at $ConfigPath"; exit 2 }
$cfg = Get-Content -Raw -Path $ConfigPath

# Pull url + anon_key from the board_overlay.supabase block (simple quoted scalars).
$url = ([regex]::Match($cfg, '(?m)^\s*url:\s*"([^"]+supabase\.co)"')).Groups[1].Value
$key = ([regex]::Match($cfg, '(?m)^\s*anon_key:\s*"([^"]+)"')).Groups[1].Value
if (-not $url -or -not $key) { Write-Error "Could not read board_overlay.supabase url/anon_key from config.yaml"; exit 2 }

# Refuse a service_role/secret key (mirrors overlay.py _looks_like_service_key).
$looksService = $false
if ($key.StartsWith('sb_secret_')) { $looksService = $true }
$parts = $key.Split('.')
if ($parts.Count -eq 3) {
  try {
    $p = $parts[1].Replace('-', '+').Replace('_', '/')
    $mod = $p.Length % 4
    if ($mod -eq 2) { $p = $p + '==' } elseif ($mod -eq 3) { $p = $p + '=' }
    $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
    if ($payload -match '"role"\s*:\s*"service_role"') { $looksService = $true }
  } catch { }
}
if ($looksService) { Write-Error "Configured key looks like a SERVICE_ROLE key. Use the PUBLIC anon key only."; exit 3 }

$hdr = @{ apikey = $key; Authorization = "Bearer $key" }
$ref = ([regex]::Match($url, 'https://([a-z0-9]+)\.supabase\.co')).Groups[1].Value
Write-Host "Project: $url" -ForegroundColor Cyan

# DNS pre-check so a paused project fails clearly instead of a raw exception.
try {
  [void][Net.Dns]::GetHostEntry("$ref.supabase.co")
} catch {
  Write-Error "Host $ref.supabase.co does not resolve. Project is paused/deleted. Un-pause it or fix config.yaml, then re-run."
  exit 4
}

$pass = $true

Write-Host "1) anon SELECT on overlay tables should succeed:" -ForegroundColor Yellow
foreach ($t in @('board_overlay', 'board_notes')) {
  try {
    $null = Invoke-RestMethod "$url/rest/v1/$t`?select=*&limit=2" -Headers $hdr
    Write-Host "  PASS  GET $t" -ForegroundColor Green
  } catch {
    Write-Host "  FAIL  GET $t ($($_.Exception.Message))" -ForegroundColor Red
    $pass = $false
  }
}

Write-Host "2) anon must be BLOCKED on non-overlay tables (RLS scoping):" -ForegroundColor Yellow
try {
  $r = Invoke-RestMethod "$url/rest/v1/players`?select=*&limit=1" -Headers $hdr
  if ($r -and @($r).Count -gt 0) {
    Write-Host "  FAIL  GET players returned rows to the anon key (scoping broken)" -ForegroundColor Red
    $pass = $false
  } else {
    Write-Host "  PASS  GET players returned nothing to the anon key" -ForegroundColor Green
  }
} catch {
  Write-Host "  PASS  GET players blocked ($($_.Exception.Message))" -ForegroundColor Green
}

if ($TestUpsert) {
  Write-Host "3) anon UPSERT on board_overlay (throwaway row; CLEAN UP FROM DASHBOARD after):" -ForegroundColor Yellow
  # player_id is `bigint primary key` (supabase/overlay_schema.sql:13). This used to send
  # "zzz-rls-test-<timestamp>", a string, which PostgREST rejects on TYPE before RLS is ever
  # consulted -- so the probe would have reported FAIL on a healthy write policy the first time
  # anyone actually ran it. A fixed negative id can never collide with a real NCAA player id and
  # makes the row trivial to find and delete in the dashboard.
  $tid = -999999
  $body = @{ player_id = $tid; lead_temp = '3'; updated_by = 'rls-verify-script' } | ConvertTo-Json
  $uh = $hdr.Clone()
  $uh['Content-Type'] = 'application/json'
  $uh['Prefer'] = 'resolution=merge-duplicates'
  try {
    $null = Invoke-RestMethod "$url/rest/v1/board_overlay" -Method Post -Headers $uh -Body $body
    Write-Host "  PASS  POST board_overlay upsert" -ForegroundColor Green
    Write-Host "        Remove player_id=$tid from the Supabase dashboard (anon has no DELETE policy)." -ForegroundColor DarkYellow
  } catch {
    Write-Host "  FAIL  POST board_overlay upsert ($($_.Exception.Message))" -ForegroundColor Red
    $pass = $false
  }
}

if ($pass) {
  Write-Host "`nRLS VERIFIED: overlay tables readable by anon, other tables scoped out." -ForegroundColor Green
  exit 0
} else {
  Write-Host "`nRLS CHECK FAILED. See FAIL lines above." -ForegroundColor Red
  exit 1
}
