"""USD Baseball battles module — battle logic, calc, and feasibility tools."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DATA_DIR = ROOT / "data" / "pbp"            # play-by-play CSVs, schedules, lookup tables
VALIDATION_DIR = DATA_DIR / "validation"    # battle-calc text reports, roster lists, debug dumps
