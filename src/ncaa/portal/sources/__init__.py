"""Portal-entry source adapters.

Each adapter yields normalized PortalEvent rows; BaseAdapter.ingest() resolves
them to players and writes the portal_events log (idempotent).
"""
from .base import BaseAdapter, PortalEvent  # noqa: F401
