from __future__ import annotations

from typing import Any

from ..generation import (
    DEFAULT_GUIDANCE_SCALE,
    DEFAULT_IMAGE_ORIENTATION,
    DEFAULT_NUM_INFERENCE_STEPS,
)


def validate_loras(raw_loras: Any) -> list[dict[str, Any]]:
    if raw_loras is None:
        return []
    if not isinstance(raw_loras, list):
        raise ValueError("loras must be a list")
    result: list[dict[str, Any]] = []
    for item in raw_loras:
        if not isinstance(item, dict):
            raise ValueError("Each lora entry must be an object")
        lora_id = str(item.get("lora_id", "")).strip()
        if not lora_id:
            raise ValueError("Each lora entry requires lora_id")
        strength = float(item.get("strength", 1.0))
        result.append({"lora_id": lora_id, "strength": strength})
    return result


def validate_generation_settings(body: dict[str, Any]) -> tuple[int, float]:
    try:
        num_inference_steps = int(
            body.get("num_inference_steps", DEFAULT_NUM_INFERENCE_STEPS)
        )
    except (TypeError, ValueError):
        raise ValueError("num_inference_steps must be an integer")
    if num_inference_steps < 1 or num_inference_steps > 150:
        raise ValueError("num_inference_steps must be between 1 and 150")

    try:
        guidance_scale = float(body.get("guidance_scale", DEFAULT_GUIDANCE_SCALE))
    except (TypeError, ValueError):
        raise ValueError("guidance_scale must be numeric")
    if guidance_scale < 0 or guidance_scale > 30:
        raise ValueError("guidance_scale must be between 0 and 30")

    return num_inference_steps, guidance_scale


def validate_generation_strength(body: dict[str, Any]) -> float:
    try:
        strength = float(body.get("strength"))
    except (TypeError, ValueError):
        raise ValueError("strength must be numeric")
    if strength <= 0 or strength >= 1:
        raise ValueError("strength must be greater than 0 and less than 1")
    return strength


def validate_image_orientation(body: dict[str, Any]) -> str:
    image_orientation = str(
        body.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
    ).strip().lower()
    if image_orientation not in {"landscape", "portrait"}:
        raise ValueError("image_orientation must be either landscape or portrait")
    return image_orientation


def derive_orientation_from_dimensions(
    width: Any,
    height: Any,
    *,
    fallback: str = DEFAULT_IMAGE_ORIENTATION,
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
    normalized_fallback = str(fallback or DEFAULT_IMAGE_ORIENTATION).strip().lower()
    return (
        normalized_fallback
        if normalized_fallback in {"landscape", "portrait"}
        else DEFAULT_IMAGE_ORIENTATION
    )


def validate_tags(raw_tags: Any) -> list[str]:
    if raw_tags is None:
        return []
    if not isinstance(raw_tags, list):
        raise ValueError("tags must be a list")
    tags: list[str] = []
    for item in raw_tags:
        if not isinstance(item, str):
            raise ValueError("each tag must be a string")
        cleaned = item.strip()
        if cleaned:
            tags.append(cleaned)
    return tags

