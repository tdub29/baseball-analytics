"""Regression guard on the Supabase overlay RLS posture.

The live project cannot be probed on demand (free tier pauses; three probes on
2026-07-22, 2026-07-30 and 2026-08-06 found the host unresolvable), so the
schema file is the only continuously-checkable statement of the security model.
A one-time read of it is not a control: someone can widen a policy later and
nothing would notice.

These tests assert the invariants the recipe in docs/supabase-rls-sync-recipe.md
depends on. They are offline, need no credentials, and fail loudly if the
security posture is loosened.

They do NOT prove the live project ran this schema. That is the one genuinely
blocked step; see scripts/verify-supabase-rls.ps1.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

SCHEMA = Path(__file__).resolve().parents[1] / "supabase" / "overlay_schema.sql"
OVERLAY_TABLES = ("public.board_overlay", "public.board_notes")


@pytest.fixture(scope="module")
def sql() -> str:
    assert SCHEMA.is_file(), f"missing schema: {SCHEMA}"
    text = SCHEMA.read_text(encoding="utf-8")
    # Strip line comments so the commented-out hardening block and the migration
    # notes cannot satisfy (or trip) any assertion below.
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("--"))


@pytest.mark.parametrize("table", OVERLAY_TABLES)
def test_rls_is_enabled(sql: str, table: str) -> None:
    pattern = rf"alter\s+table\s+{re.escape(table)}\s+enable\s+row\s+level\s+security"
    assert re.search(pattern, sql, re.I), f"RLS not enabled on {table}"


@pytest.mark.parametrize("table", OVERLAY_TABLES)
@pytest.mark.parametrize("cmd", ("select", "insert", "update"))
def test_anon_upsert_triad_present(sql: str, table: str, cmd: str) -> None:
    """PostgREST upsert is INSERT ... ON CONFLICT DO UPDATE, so an edit to an
    existing row needs the update policy too. All three or the board breaks."""
    pattern = rf"create\s+policy\s+\"[^\"]+\"\s+on\s+{re.escape(table)}\s+for\s+{cmd}\s+to\s+anon"
    assert re.search(pattern, sql, re.I), f"missing anon {cmd.upper()} policy on {table}"


def test_no_delete_policy_anywhere(sql: str) -> None:
    """anon may retag or clear a value but must never be able to drop rows."""
    assert not re.search(r"create\s+policy[^;]*for\s+delete", sql, re.I), (
        "a DELETE policy was added; anon must not be able to remove overlay rows"
    )


def test_no_policy_on_any_non_overlay_table(sql: str) -> None:
    """The anon key's whole safety story is that RLS defaults to deny and only
    these two tables grant anything to anon."""
    granted = {
        m.group(1).lower()
        for m in re.finditer(r"create\s+policy\s+\"[^\"]+\"\s+on\s+([\w.]+)", sql, re.I)
    }
    unexpected = granted - {t.lower() for t in OVERLAY_TABLES}
    assert not unexpected, f"policies granted on non-overlay tables: {sorted(unexpected)}"


def test_no_policy_targets_public_role(sql: str) -> None:
    """`to public` would extend the grant beyond the anon key."""
    assert not re.search(r"create\s+policy[^;]*\sto\s+public\b", sql, re.I), (
        "a policy targets the public role; it must target anon only"
    )


def test_no_broad_grant_bypasses_rls(sql: str) -> None:
    """A stray GRANT can hand out access that RLS policies then never gate."""
    assert not re.search(r"^\s*grant\s+", sql, re.I | re.M), (
        "an explicit GRANT appeared in the schema; RLS policies are the only intended gate"
    )


def test_lead_temp_is_the_one_to_five_rating(sql: str) -> None:
    """The overlay migrated off hot/warm/cold; the CHECK is what keeps the board,
    the sync, and call_assignments.lead_temp agreeing on the domain."""
    m = re.search(r"lead_temp\s+text\s+check\s*\(\s*lead_temp\s+in\s*\(([^)]*)\)", sql, re.I)
    assert m, "lead_temp CHECK constraint missing"
    values = {v.strip().strip("'") for v in m.group(1).split(",")}
    assert values == {"1", "2", "3", "4", "5"}, f"unexpected lead_temp domain: {sorted(values)}"


def test_player_id_is_the_stable_key(sql: str) -> None:
    """Tags re-attach across nightly rebuilds only because the PK is the stable
    players.player_id (composite with author for per-coach notes)."""
    assert re.search(r"player_id\s+bigint\s+primary\s+key", sql, re.I), (
        "board_overlay must key on player_id"
    )
    assert re.search(r"primary\s+key\s*\(\s*player_id\s*,\s*author\s*\)", sql, re.I), (
        "board_notes must key on (player_id, author)"
    )
