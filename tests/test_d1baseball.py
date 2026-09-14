"""Unit tests for the D1Baseball tracker paste parser (no network)."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from ncaa.portal.sources.d1baseball import (  # noqa: E402
    D1BaseballAdapter, parse_tracker_text, _is_anchor,
)

# A faithful miniature of a copied tracker page: header chrome, the two record
# shapes (uncommitted 4-line + committed 6-line), an exact duplicate, a compound
# position, then the "Showing ... entries" footer and trailing headline junk.
SAMPLE = "\n".join([
    "Scores", "Stories", "Login", "Subscribe Now",
    "Player\tPosition\tClass\tLatest Team\tSeason\tDestination Team\tDate Entered",
    "Diego Ortiz",
    "2B\tJR\t",
    "SIUE",
    "2026\t--\t2026-06-02",
    "Gavin Flores",
    "P-IF\tFR\t",
    "Creighton",
    "2026\t--\t2026-06-02",
    "Jake Wagoner",            # committed → 6-line split shape
    "C\tJR\t",
    "Lamar",
    "2026",
    "Houston",
    "2026-06-01",
    "Diego Ortiz",             # exact duplicate of the first row
    "2B\tJR\t",
    "SIUE",
    "2026\t--\t2026-06-02",
    "Showing 1 to 4 of 4 entriesPrevious1Next",
    "Top Headlines",
    "Some Story That Is Not A Player",
    "by: D1Baseball Staff",
])


def test_is_anchor():
    assert _is_anchor(["2B", "JR", ""])
    assert _is_anchor(["P-IF", "FR", ""])
    assert not _is_anchor(["2026", "--", "2026-06-02"])   # season line
    assert not _is_anchor(["Player", "Position", "Class"])  # header
    assert not _is_anchor(["SIUE"])                        # school (no class)


def test_parse_counts_and_dedup():
    evs = parse_tracker_text(SAMPLE, source_url="http://x")
    # 4 rows on the page, one an exact dup → 3 unique events
    assert len(evs) == 3
    names = [e.player_name for e in evs]
    assert names == ["Diego Ortiz", "Gavin Flores", "Jake Wagoner"]


def test_parse_uncommitted_entered():
    evs = parse_tracker_text(SAMPLE)
    ortiz = next(e for e in evs if e.player_name == "Diego Ortiz")
    assert ortiz.event_type == "ENTERED"
    assert ortiz.position == "2B" and ortiz.class_year == "JR"
    assert ortiz.from_school == "SIUE"
    assert ortiz.to_school is None
    assert ortiz.event_date == "2026-06-02"
    assert ortiz.raw["season"] == "2026"


def test_parse_committed_destination_split():
    evs = parse_tracker_text(SAMPLE)
    wag = next(e for e in evs if e.player_name == "Jake Wagoner")
    assert wag.event_type == "COMMITTED"
    assert wag.from_school == "Lamar"
    assert wag.to_school == "Houston"        # pulled out of the 3-line tail
    assert wag.event_date == "2026-06-01"
    assert wag.class_year == "JR"


def test_compound_position_preserved():
    evs = parse_tracker_text(SAMPLE)
    flores = next(e for e in evs if e.player_name == "Gavin Flores")
    assert flores.position == "P-IF" and flores.class_year == "FR"


def test_footer_and_header_trimmed():
    evs = parse_tracker_text(SAMPLE)
    names = {e.player_name for e in evs}
    # nothing from the chrome (header) or the post-"Showing" headline block
    assert "Some Story That Is Not A Player" not in names
    assert "Subscribe Now" not in names
    assert "Player" not in names


def test_no_header_still_parses():
    # tolerate a paste that starts straight at the first record (no column header)
    body = "\n".join(["Diego Ortiz", "2B\tJR\t", "SIUE", "2026\t--\t2026-06-02"])
    evs = parse_tracker_text(body)
    assert len(evs) == 1 and evs[0].player_name == "Diego Ortiz"


def test_blank_position_row_not_dropped_or_absorbed():
    # A row with a BLANK Position shifts its class into cell[0] ("JR<TAB>"). The
    # parser must still anchor it — otherwise the record is lost AND the prior row
    # swallows this player's name as a bogus destination (the Robey/Rivers bug).
    body = "\n".join([
        "Walker Robey", "C\tFR\t", "Murray State", "2026\t--\t2026-05-27",
        "Keller Rivers", "JR\t", "Alcorn State", "2026\t--\t2026-05-27",
        "Ridge Harvey", "P\tJR\t", "Tennessee", "2026\t--\t2026-05-27",
    ])
    evs = parse_tracker_text(body)
    assert [e.player_name for e in evs] == ["Walker Robey", "Keller Rivers", "Ridge Harvey"]
    robey = evs[0]
    assert robey.event_type == "ENTERED" and robey.to_school is None   # not "Keller Rivers"
    rivers = evs[1]
    assert rivers.position is None and rivers.class_year == "JR"        # blank pos preserved
    assert rivers.from_school == "Alcorn State" and rivers.event_type == "ENTERED"


def test_adapter_missing_paste_path_returns_empty():
    out = D1BaseballAdapter({"paste_path": "does_not_exist_12345.txt"}).fetch()
    assert out == []
