"""Stealth-browser fetch via CloakBrowser (drop-in stealth Playwright).

Some portal sources sit behind bot protection (Cloudflare etc.) that blocks a
plain `requests.get` with HTTP 403. This helper fetches the fully-rendered HTML
with CloakBrowser — which ships a real Chromium with source-level fingerprint
patches and clears those bot walls — optionally authenticated with a session
cookie for subscriber-gated pages, and caches the result so we don't re-hit a
source on every pipeline run.

CloakBrowser only defeats *bot* walls, not *auth* walls: subscriber content
(e.g. the D1Baseball tracker) still needs a logged-in session cookie passed in.

`cloakbrowser` is imported lazily; without it the caller gets a clear message
and can fall back to plain requests (cf. enrich.collegebaseball_baseline).
"""
from __future__ import annotations

import logging
import time
from pathlib import Path

log = logging.getLogger(__name__)
ROOT = Path(__file__).resolve().parents[2]
CACHE_DIR = ROOT / "data" / "cache"


def stealth_get(
    url: str,
    *,
    cookie: str | None = None,
    wait_selector: str | None = None,
    settle_seconds: float = 6.0,
    timeout_ms: int = 60000,
    cache_as: str | None = None,
) -> str:
    """Return fully-rendered HTML for `url` via CloakBrowser.

    cookie:        raw `Cookie:` header string (a logged-in session) for gated pages.
    wait_selector: CSS selector to wait for before reading (e.g. "table"); if None,
                   we just let the page settle for `settle_seconds` (JS challenge + late content).
    cache_as:      filename under data/cache/ to also write the HTML to (for offline parsing/replay).
    """
    try:
        from cloakbrowser import launch
    except Exception as e:  # pragma: no cover - only without the optional dep
        raise RuntimeError(
            "stealth fetch needs cloakbrowser (pip install cloakbrowser)"
        ) from e

    browser = launch()
    try:
        page = browser.new_page()
        if cookie:
            # Set the session cookie on the document request. CloakBrowser mirrors
            # Playwright's Page API; fall back silently if a method isn't present.
            try:
                page.set_extra_http_headers({"Cookie": cookie})
            except Exception:
                log.warning("could not set Cookie header; page may load logged-out")
        page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
        if wait_selector:
            try:
                page.wait_for_selector(wait_selector, timeout=timeout_ms)
            except Exception:
                log.warning("wait_selector %r not found before timeout", wait_selector)
        elif settle_seconds:
            time.sleep(settle_seconds)
        html = page.content()
    finally:
        browser.close()

    if cache_as:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        (CACHE_DIR / cache_as).write_text(html, encoding="utf-8")
    return html


def available() -> bool:
    """True if cloakbrowser can be imported (so adapters can choose a fallback)."""
    try:
        import cloakbrowser  # noqa: F401
        return True
    except Exception:
        return False
