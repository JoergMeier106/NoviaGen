from __future__ import annotations

from typing import Any

import requests


def is_comfy_healthy(
    *,
    comfy_url: str,
    health_path: str = "/system_stats",
    timeout_seconds: float = 5.0,
) -> bool:
    base_url = str(comfy_url or "").rstrip("/")
    if not base_url:
        return False
    try:
        response = requests.get(f"{base_url}{health_path}", timeout=timeout_seconds)
        return response.ok
    except requests.RequestException:
        return False


def comfy_health_payload(
    *,
    comfy_url: str,
    timeout_seconds: float = 5.0,
) -> dict[str, Any]:
    base_url = str(comfy_url or "").rstrip("/")
    if not base_url:
        return {"ok": False, "label": "Not configured", "detail": None}
    try:
        response = requests.get(f"{base_url}/system_stats", timeout=timeout_seconds)
        response.raise_for_status()
        return {"ok": True, "label": "Online", "detail": base_url}
    except requests.RequestException as exc:
        return {"ok": False, "label": "Offline", "detail": str(exc)}
