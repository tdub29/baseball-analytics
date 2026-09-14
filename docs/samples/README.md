# Battle PDFs

**`generate-pdf.mjs`** is the entry point. It reads `../real5_battle_calc_output.txt` and writes:

- **Season report:** `season_battle_report.pdf` (all games, one landscape table + avg/success rows)
- **Per-game reports:** `{date}_{opponent}_{gameId}_Battle_report.pdf` for each game

## Requirements

- **Node.js** in your PATH (`node --version` should work).
- Dependencies installed: `npm install` (already done if you have `node_modules/`).

## How to run

From **this folder** (`battle_pdf/`):

```bash
node generate-pdf.mjs ../real5_battle_calc_output.txt season_battle_report.pdf ../real5_pbp_baseballr_style.csv sd_logo.png
```

Or use the helper script (PowerShell):

```powershell
.\run-pdf.ps1
```

Optional: add game IDs at the end to generate **only** those per-game PDFs:

```bash
node generate-pdf.mjs ../real5_battle_calc_output.txt season_battle_report.pdf ../real5_pbp_baseballr_style.csv sd_logo.png 6539457
```

## Inputs

| Arg   | Default | Description |
|-------|---------|-------------|
| 1     | `../real5_battle_calc_output.txt` | Battle text report from `baseballr_battle_calc.py` |
| 2     | `season_battle_report.pdf`        | Output path for season PDF |
| 3     | `../real5_pbp_baseballr_style.csv` | PBP CSV (for date/score per game) |
| 4     | `sd_logo.png`                     | Logo image path |
| 5+    | (none)                            | Optional: only generate per-game PDFs for these game IDs |
