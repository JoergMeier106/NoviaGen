from __future__ import annotations

import json
from typing import Any


TRUTHY_VALUES = {"1", "true", "yes", "on"}
FALSY_VALUES = {"", "0", "false", "no", "off"}


def normalized_string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        normalized: list[str] = []
        for item in value:
            normalized.extend(normalized_string_list(item))
        return normalized
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return []
        try:
            decoded = json.loads(stripped)
        except json.JSONDecodeError:
            decoded = None
        if isinstance(decoded, list):
            return [str(item).strip() for item in decoded if str(item).strip()]
        return [stripped]
    return [str(value).strip()] if str(value).strip() else []


def normalized_optional_int(value: Any, *, field_name: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError(f"{field_name} must be an integer")
    if isinstance(value, int):
        parsed = value
    else:
        stripped = str(value).strip()
        if not stripped:
            return None
        parsed = int(stripped)
    if parsed <= 0:
        raise ValueError(f"{field_name} must be greater than zero")
    return parsed


def normalized_optional_bool(value: Any, *, field_name: str) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if not normalized:
        return None
    if normalized in TRUTHY_VALUES:
        return True
    if normalized in FALSY_VALUES - {""}:
        return False
    raise ValueError(f"{field_name} must be true or false")


def coerce_bool(value: Any, field_name: str) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, (int, float)):
        if value in (0, 1):
            return bool(value)
        raise ValueError(f"{field_name} must be a boolean")
    normalized = str(value).strip().lower()
    if normalized in FALSY_VALUES:
        return False
    if normalized in TRUTHY_VALUES:
        return True
    raise ValueError(f"{field_name} must be a boolean")


def truthy_arg(value: Any) -> bool:
    return str(value or "").strip().lower() in TRUTHY_VALUES


def parse_tag_filter_values(raw_values: list[Any]) -> list[str]:
    values: list[str] = []
    for raw_value in raw_values:
        for item in str(raw_value).split(","):
            cleaned = item.strip()
            if cleaned:
                values.append(cleaned)
    return values

