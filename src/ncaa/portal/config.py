"""Load config.yaml (falls back to config.example.yaml).

Secrets never have to live in the file. Any string value written as
``${ENV_VAR}`` (or ``${ENV_VAR:-fallback}``) is expanded from the process
environment at load time, so live-feed credentials — the D1Baseball /
64 Analytics session cookie, the X bearer token, the alert webhook URL, the
Google service-account JSON path — can be supplied via env vars instead of
being pasted into config.yaml. Plain values pass through unchanged, so this is
backward-compatible with existing configs. An unset ``${VAR}`` with no fallback
resolves to an empty string (which every adapter already treats as "not
configured" and no-ops on).
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parents[2]

# ${VAR} or ${VAR:-default} — nothing else is touched.
_ENV_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-(.*?))?\}")


def _expand(value: Any) -> Any:
    """Recursively expand ${ENV_VAR} / ${ENV_VAR:-fallback} in strings."""
    if isinstance(value, str):
        return _ENV_RE.sub(
            lambda m: os.environ.get(m.group(1), m.group(2) if m.group(2) is not None else ""),
            value,
        )
    if isinstance(value, dict):
        return {k: _expand(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_expand(v) for v in value]
    return value


def load_config(path: str | Path | None = None) -> dict[str, Any]:
    if path is None:
        cfg = ROOT / "config.yaml"
        path = cfg if cfg.exists() else ROOT / "config.example.yaml"
    with open(path, "r", encoding="utf-8") as f:
        return _expand(yaml.safe_load(f) or {})
