from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

from ...generation import compose_positive_prompt
from .errors import JobRequestError
from .sources import (
    _attach_image_source,
    _optional_still_source_image_id,
    _require_source_image_id,
)
from ..common.validation import (
    validate_generation_settings,
    validate_generation_strength,
    validate_image_orientation,
    validate_loras,
)


def generate_payload(
    *,
    body: Mapping[str, Any],
    catalog: Any,
) -> dict[str, Any]:
    model_id = _require_model_id(body, catalog)
    try:
        loras = validate_loras(body.get("loras"))
        num_inference_steps, guidance_scale = validate_generation_settings(dict(body))
        image_orientation = validate_image_orientation(dict(body))
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    _validate_lora_ids(loras, catalog)

    return {
        "prompt": str(body.get("prompt", "")),
        "default_positive_prompt": str(body.get("default_positive_prompt", "")),
        "default_negative_prompt": str(body.get("default_negative_prompt", "")),
        "final_positive_prompt": _final_positive_prompt(body, catalog, loras=loras),
        "model_id": model_id,
        "loras": loras,
        "num_inference_steps": num_inference_steps,
        "guidance_scale": guidance_scale,
        "image_orientation": image_orientation,
        **auto_metadata_options(body),
    }


def upscale_payload(*, body: Mapping[str, Any], db: Any) -> dict[str, Any]:
    image_id = _require_source_image_id(body, db, expected_media_type="image")
    scale_factor = _scale_factor(body)
    try:
        num_inference_steps, guidance_scale = validate_generation_settings(dict(body))
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc

    return {
        "image_id": image_id,
        "scale_factor": scale_factor,
        "num_inference_steps": num_inference_steps,
        "guidance_scale": guidance_scale,
        "delete_source_after_finish": bool(
            body.get("delete_source_after_finish", False)
        ),
    }


def generate_from_image_payload(
    *,
    body: Mapping[str, Any],
    uploaded_file: Any,
    is_multipart: bool,
    catalog: Any,
    db: Any,
    temp_dir: str | Path,
    is_still_media,
) -> dict[str, Any]:
    model_id = _require_model_id(body, catalog)
    image_id = _optional_still_source_image_id(
        body=body,
        uploaded_file=uploaded_file,
        db=db,
        is_still_media=is_still_media,
        invalid_message="Only images or GIFs can be used as source",
    )

    try:
        raw_loras = body.get("loras")
        if is_multipart:
            raw_loras = json.loads(str(body.get("loras", "[]")))
        loras = validate_loras(raw_loras)
        num_inference_steps, guidance_scale = validate_generation_settings(dict(body))
        image_orientation = validate_image_orientation(dict(body))
        strength = validate_generation_strength(dict(body))
    except (ValueError, json.JSONDecodeError) as exc:
        raise JobRequestError(str(exc)) from exc
    _validate_lora_ids(loras, catalog)

    payload = {
        "prompt": str(body.get("prompt", "")).strip(),
        "default_positive_prompt": str(body.get("default_positive_prompt", "")),
        "default_negative_prompt": str(body.get("default_negative_prompt", "")),
        "final_positive_prompt": _final_positive_prompt(body, catalog, loras=loras),
        "model_id": model_id,
        "loras": loras,
        "num_inference_steps": num_inference_steps,
        "guidance_scale": guidance_scale,
        "image_orientation": image_orientation,
        "strength": strength,
        **auto_metadata_options(body),
    }
    _attach_image_source(payload, image_id, uploaded_file, temp_dir)
    return payload


def _require_model_id(body: Mapping[str, Any], catalog: Any) -> str:
    model_id = str(body.get("model_id", "")).strip()
    if not model_id:
        raise JobRequestError("model_id is required")
    if catalog.get_model(model_id) is None:
        raise JobRequestError("Unknown model_id")
    return model_id


def _validate_lora_ids(loras: list[dict[str, Any]], catalog: Any) -> None:
    for item in loras:
        if catalog.get_lora(item["lora_id"]) is None:
            raise JobRequestError(f"Unknown lora_id: {item['lora_id']}")


def _scale_factor(body: Mapping[str, Any]) -> float:
    try:
        scale_factor = float(body.get("scale_factor"))
    except (TypeError, ValueError):
        raise JobRequestError("scale_factor must be numeric")
    if scale_factor <= 1.0:
        raise JobRequestError("scale_factor must be greater than 1.0")
    return scale_factor


def _final_positive_prompt(
    body: Mapping[str, Any],
    catalog: Any,
    *,
    loras: list[dict[str, Any]] | None = None,
) -> str:
    lora_triggers: list[str] = []
    for item in loras or []:
        lora_id = str(item.get("lora_id", "")).strip()
        if not lora_id:
            continue
        lora = catalog.get_lora(lora_id)
        trigger_words = getattr(lora, "trigger_words", "") if lora is not None else ""
        if str(trigger_words).strip():
            lora_triggers.append(str(trigger_words).strip())
    return compose_positive_prompt(
        str(body.get("default_positive_prompt", "")),
        str(body.get("prompt", "")),
        ", ".join(lora_triggers),
    )


def auto_metadata_options(body: Mapping[str, Any]) -> dict[str, Any]:
    enabled = _bool_value(body.get("auto_metadata_enabled"))
    model_name = str(body.get("auto_metadata_model_name") or "").strip()
    if not enabled:
        return {"auto_metadata_enabled": False}
    result: dict[str, Any] = {"auto_metadata_enabled": True}
    if model_name:
        result["auto_metadata_model_name"] = model_name
    return result


def _bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)
