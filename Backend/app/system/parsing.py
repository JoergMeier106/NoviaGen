from __future__ import annotations

import json
import re
from typing import Any


def _parse_json_object(raw: str) -> dict[str, Any] | None:
    payload = _parse_json_value(raw)
    return payload if isinstance(payload, dict) else None


def _parse_json_value(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def _coerce_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    match = re.search(r"-?\d+", text)
    if not match:
        return None
    try:
        return int(match.group(0))
    except ValueError:
        return None


def _coerce_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", text)
    if not match:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def _extract_first_numeric(payload: dict[str, Any], keys: tuple[str, ...]) -> int | None:
    for key in keys:
        if key in payload:
            value = _coerce_int(payload.get(key))
            if value is not None:
                return value
    return None


def _extract_first_float(payload: dict[str, Any], keys: tuple[str, ...]) -> float | None:
    for key in keys:
        if key in payload:
            value = _coerce_float(payload.get(key))
            if value is not None:
                return value
    return None
