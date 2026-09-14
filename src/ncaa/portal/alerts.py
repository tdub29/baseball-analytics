"""Alerts — fire when a high-fit player newly enters the portal.

find_alerts() returns players whose latest portal event is recent ENTERED and
whose fit score clears a threshold. send_alerts() posts to a Teams/Slack webhook,
or just prints (dry-run) when alerts are disabled / no webhook configured.
"""
from __future__ import annotations

import json
import sqlite3

import requests

ALERT_SQL = """
SELECT pl.full_name, pl.position, pl.from_school, pl.division,
       e.fit_score, json_extract(e.components,'$.need_label') AS need,
       MAX(ev.observed_at) AS last_seen
FROM evaluations e
JOIN players pl ON pl.player_id = e.player_id
JOIN portal_events ev ON ev.player_id = e.player_id AND ev.event_type='ENTERED'
WHERE e.fit_score >= ? AND pl.current_status = 'ENTERED'
GROUP BY pl.player_id
ORDER BY e.fit_score DESC
LIMIT ?
"""


def find_alerts(con: sqlite3.Connection, min_fit: float = 60.0, limit: int = 25) -> list[dict]:
    return [dict(r) for r in con.execute(ALERT_SQL, (min_fit, limit)).fetchall()]


def _format(rows: list[dict], min_fit: float) -> str:
    lines = [f"[PORTAL] {len(rows)} target(s) with fit >= {min_fit:.0f}:"]
    for r in rows:
        lines.append(
            f"  - {r['full_name']} ({r['position'] or '?'}, {r['from_school'] or '?'}, "
            f"D{r['division']}) -- fit {r['fit_score']}"
            + (f" [{r['need']}]" if r['need'] else "")
        )
    return "\n".join(lines)


def send_alerts(con: sqlite3.Connection, config: dict, *, min_fit: float = 60.0) -> dict:
    rows = find_alerts(con, min_fit)
    msg = _format(rows, min_fit)
    cfg = (config or {}).get("alerts") or {}
    if not cfg.get("enabled") or not cfg.get("webhook_url"):
        print(msg)
        return {"sent": 0, "matched": len(rows), "mode": "dry-run"}

    channel = cfg.get("channel", "slack")
    payload = {"text": msg} if channel == "slack" else {
        "@type": "MessageCard", "@context": "http://schema.org/extensions",
        "summary": "Portal targets", "text": msg.replace("\n", "  \n"),
    }
    resp = requests.post(cfg["webhook_url"], data=json.dumps(payload),
                         headers={"Content-Type": "application/json"}, timeout=20)
    resp.raise_for_status()
    return {"sent": len(rows), "matched": len(rows), "mode": channel}
