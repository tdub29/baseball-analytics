# Generate season + per-game PDFs from real5_battle_calc_output.txt
# Requires Node.js in PATH. Run from this folder (battle_pdf) or from battles/.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParentDir = Split-Path -Parent $ScriptDir
$InputTxt = Join-Path $ParentDir "real5_battle_calc_output.txt"
$PbpCsv = Join-Path $ParentDir "real5_pbp_baseballr_style.csv"
$Logo = Join-Path $ScriptDir "sd_logo.png"
$OutPdf = Join-Path $ScriptDir "season_battle_report.pdf"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js not found. Add Node to PATH or run from a terminal where 'node' works."
    exit 1
}
if (-not (Test-Path $InputTxt)) {
    Write-Error "Battle output not found: $InputTxt. Run baseballr_battle_calc.py first."
    exit 1
}

Set-Location $ScriptDir
& node generate-pdf.mjs $InputTxt $OutPdf $PbpCsv $Logo
if ($LASTEXITCODE -eq 0) {
    Write-Host "PDFs written to $ScriptDir (season_battle_report.pdf + per-game *_Battle_report.pdf)"
}
