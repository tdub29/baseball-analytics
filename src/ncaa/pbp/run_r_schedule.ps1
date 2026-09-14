# Run USD 2026 schedule R script using installed R (no PATH needed).
# Usage: .\run_r_schedule.ps1
# Or: powershell -ExecutionPolicy Bypass -File run_r_schedule.ps1

$rscript = "C:\Program Files\R\R-4.4.3\bin\Rscript.exe"
if (-not (Test-Path $rscript)) {
    # Try latest R in Program Files
    $rDir = Get-ChildItem "C:\Program Files\R" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($rDir) { $rscript = Join-Path $rDir.FullName "bin\Rscript.exe" }
}
if (-not (Test-Path $rscript)) {
    Write-Error "R not found. Install R from https://cran.r-project.org/ then run this again."
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
& $rscript r_fetch_usd_schedule_2026.R
exit $LASTEXITCODE
