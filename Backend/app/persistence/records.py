from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat()


def normalize_tags(tags: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for tag in tags:
        cleaned = str(tag).strip()
        if not cleaned:
            continue
        key = cleaned.lower()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(cleaned)
    return normalized


def derive_image_orientation(
    width: Any,
    height: Any,
    *,
    fallback: str = "landscape",
) -> str:
    try:
        normalized_width = int(width)
        normalized_height = int(height)
    except (TypeError, ValueError):
        return fallback
    if normalized_height > normalized_width:
        return "portrait"
    if normalized_width > normalized_height:
        return "landscape"
    normalized_fallback = str(fallback or "landscape").strip().lower()
    return (
        normalized_fallback
        if normalized_fallback in {"landscape", "portrait"}
        else "landscape"
    )


def remap_loras_json(loras_json: str, lora_id_map: dict[str, str]) -> str:
    try:
        decoded = json.loads(loras_json)
    except (TypeError, ValueError, json.JSONDecodeError):
        decoded = []

    if not isinstance(decoded, list):
        return json.dumps(decoded)

    remapped: list[Any] = []
    for item in decoded:
        if isinstance(item, dict):
            updated = dict(item)
            lora_id = str(updated.get("lora_id", ""))
            if lora_id in lora_id_map:
                updated["lora_id"] = lora_id_map[lora_id]
            remapped.append(updated)
        else:
            remapped.append(item)
    return json.dumps(remapped)


def remap_job_payload_json(
    payload_json: str,
    *,
    model_id_map: dict[str, str],
    lora_id_map: dict[str, str],
) -> str:
    try:
        payload = json.loads(payload_json)
    except (TypeError, ValueError, json.JSONDecodeError):
        return payload_json

    if not isinstance(payload, dict):
        return json.dumps(payload)

    updated = dict(payload)
    model_id = str(updated.get("model_id", ""))
    if model_id in model_id_map:
        updated["model_id"] = model_id_map[model_id]
    if "loras" in updated:
        updated["loras"] = json.loads(
            remap_loras_json(json.dumps(updated["loras"]), lora_id_map)
        )
    return json.dumps(updated)
