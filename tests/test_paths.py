"""Every module-level ROOT must be the repo root, not src/ (pure; no network)."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

import ncaa.cli as cli  # noqa: E402
from ncaa.portal import board, config, db, geo, stealth, trackman  # noqa: E402
from ncaa.portal.sources import perfectgame_bio, sidearm_bio  # noqa: E402


@pytest.mark.parametrize("mod", [
    cli, board, config, db, geo, stealth, trackman, perfectgame_bio, sidearm_bio,
], ids=lambda m: m.__name__)
def test_root_is_repo_root(mod):
    assert mod.ROOT == ROOT
    assert (mod.ROOT / "pyproject.toml").exists()


def test_cli_finds_its_scripts():
    assert (cli.ROOT / "scripts" / "init_db.py").exists()
    assert (cli.ROOT / "scripts" / "import_excel.py").exists()
