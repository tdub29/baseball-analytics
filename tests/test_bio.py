import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.bio import load_player_bio  # noqa: E402


def _db():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript((ROOT / "db" / "schema.sql").read_text(encoding="utf-8"))
    return con


def test_bio_loader_preserves_file_level_evidence(tmp_path):
    con = _db()
    con.execute(
        "INSERT INTO players (player_id, full_name, from_school) VALUES (1, 'Test Player', 'Test U')"
    )
    con.commit()

    a = tmp_path / "ncaa_a.csv"
    b = tmp_path / "ncaa_b.csv"
    a.write_text(
        "player,team,season,hometown_city,hometown_state,high_school\n"
        "Test Player,Test U,2026,San Diego,CA,Alpha HS\n",
        encoding="utf-8",
    )
    b.write_text(
        "player,team,season,hometown_city,hometown_state,high_school\n"
        "Test Player,Test U,2026,San Diego,CA,Beta HS\n",
        encoding="utf-8",
    )

    assert load_player_bio(con, a, source="ncaa")["evidence_rows"] == 1
    assert load_player_bio(con, b, source="ncaa")["evidence_rows"] == 1
    assert load_player_bio(con, a, source="ncaa")["evidence_rows"] == 0

    canonical = con.execute("SELECT COUNT(*) n FROM player_bio").fetchone()["n"]
    evidence = con.execute(
        "SELECT source_file, high_school FROM player_bio_evidence ORDER BY source_file"
    ).fetchall()

    assert canonical == 1
    assert [(r["source_file"], r["high_school"]) for r in evidence] == [
        ("ncaa_a.csv", "Alpha HS"),
        ("ncaa_b.csv", "Beta HS"),
    ]
