"""Create the SQLite database from db/schema.sql.

Usage:
    python scripts/init_db.py            # creates db/baseball.db
    python scripts/init_db.py --force    # drop & recreate
"""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "db" / "schema.sql"
DB = ROOT / "db" / "baseball.db"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="drop existing db first")
    args = ap.parse_args()

    if args.force and DB.exists():
        DB.unlink()
        print(f"removed {DB}")

    sql = SCHEMA.read_text(encoding="utf-8")
    con = sqlite3.connect(DB)
    try:
        con.executescript(sql)
        con.commit()
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )]
    finally:
        con.close()

    print(f"initialized {DB}")
    print("tables:", ", ".join(tables))


if __name__ == "__main__":
    main()
