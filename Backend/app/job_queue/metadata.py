from __future__ import annotations

import base64
import json
import re
from pathlib import Path
from typing import Any

from ..generation.prompting import strip_inline_thinking
from ..persistence.records import normalize_tags


AUTO_METADATA_ENABLED_KEY = "auto_metadata_enabled"
AUTO_METADATA_MODEL_KEY = "auto_metadata_model_name"


def auto_metadata_enabled(payload: dict[str, Any]) -> bool:
    return bool(payload.get(AUTO_METADATA_ENABLED_KEY))


def auto_metadata_model_name(payload: dict[str, Any]) -> str:
    return str(payload.get(AUTO_METADATA_MODEL_KEY) or "").strip()


def generate_image_metadata(
    *,
    generator: Any,
    model_name: str,
    image_path: str | Path,
    existing_tags: list[str],
) -> dict[str, Any]:
    normalized_model = str(model_name or "").strip()
    if not normalized_model:
        raise ValueError("auto metadata model is required")
    image_bytes = Path(image_path).read_bytes()
    if not image_bytes:
        raise ValueError("image file is empty")

    response = generator.chat(
        model=normalized_model,
        messages=[
            {
                "role": "system",
                "content": _system_prompt(existing_tags),
            },
            {
                "role": "user",
                "content": "Create metadata for this generated image.",
                "images": [base64.b64encode(image_bytes).decode("ascii")],
            },
        ],
        think=False,
    )
    message = response.get("message") if isinstance(response, dict) else None
    if not isinstance(message, dict):
        raise ValueError("Ollama returned an invalid metadata response")
    raw_content = strip_inline_thinking(str(message.get("content") or ""))
    decoded = _decode_json_object(raw_content)
    return clean_metadata_response(decoded, existing_tags=existing_tags)


def clean_metadata_response(
    payload: dict[str, Any],
    *,
    existing_tags: list[str],
) -> dict[str, Any]:
    caption = str(payload.get("caption") or "").strip()
    raw_tags = payload.get("tags")
    if not isinstance(raw_tags, list):
        raw_tags = []
    return {
        "caption": caption,
        "tags": _normalize_suggested_tags(raw_tags, existing_tags=existing_tags),
    }


def _system_prompt(existing_tags: list[str]) -> str:
    existing = normalize_tags(existing_tags)
    existing_text = ", ".join(existing) if existing else "none"
    return (
        "You create concise gallery metadata for generated media. "
        "Return only strict JSON with keys caption and tags. "
        "caption must be one short sentence without markdown. "
        "tags must be 3 to 8 short descriptive tags. "
        "Use existing tags only as a canonical spelling reference, not as a menu. "
        "Choose an existing tag only when it is clearly visible or conceptually relevant "
        "to the image, preserving its spelling: "
        f"{existing_text}. "
        "Create new tags whenever they describe the image better than the existing tags. "
        "Ignore unrelated existing tags even if they are common in the gallery. "
        "Do not include duplicate tags with different capitalization or spelling."
    )


def _decode_json_object(text: str) -> dict[str, Any]:
    candidate = _strip_code_fence(text.strip())
    try:
        decoded = json.loads(candidate)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", candidate, flags=re.DOTALL)
        if match is None:
            raise ValueError("Ollama metadata response did not contain JSON")
        decoded = json.loads(match.group(0))
    if not isinstance(decoded, dict):
        raise ValueError("Ollama metadata response must be a JSON object")
    return decoded


def _strip_code_fence(text: str) -> str:
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if len(lines) >= 3 and lines[-1].strip() == "```":
        return "\n".join(lines[1:-1]).strip()
    return text


def _normalize_suggested_tags(
    raw_tags: list[Any],
    *,
    existing_tags: list[str],
) -> list[str]:
    existing_by_lower = {tag.lower(): tag for tag in normalize_tags(existing_tags)}
    selected: list[str] = []
    seen: set[str] = set()
    for raw_tag in raw_tags:
        cleaned = str(raw_tag or "").strip()
        if not cleaned:
            continue
        normalized = normalize_tags([cleaned])
        if not normalized:
            continue
        candidate = normalized[0]
        resolved = existing_by_lower.get(candidate.lower(), candidate)
        key = resolved.lower()
        if key in seen:
            continue
        seen.add(key)
        selected.append(resolved)
    return selected
