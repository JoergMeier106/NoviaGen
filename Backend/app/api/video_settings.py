from __future__ import annotations

from typing import Any

from .validation import derive_orientation_from_dimensions

VIDEO_PRESETS: dict[str, dict[str, Any]] = {
    "standard": {
        "label": "576p Recommended",
        "is_default": True,
        "max_width": 1024,
        "max_height": 576,
        "num_frames": 81,
        "fps": 16,
        "num_inference_steps": 8,
        "guidance_scale": 2.0,
        "description": "Model-author recommended baseline for 12 GB VRAM.",
    },
    "high": {
        "label": "720p High",
        "is_default": False,
        "max_width": 1280,
        "max_height": 720,
        "num_frames": 81,
        "fps": 16,
        "num_inference_steps": 8,
        "guidance_scale": 2.0,
        "description": "Higher quality. Expect materially longer generation time.",
    },
    "preview": {
        "label": "480p Preview",
        "is_default": False,
        "max_width": 832,
        "max_height": 480,
        "num_frames": 49,
        "fps": 16,
        "num_inference_steps": 8,
        "guidance_scale": 2.0,
        "description": "Faster preview for iteration. Lower quality than the recommended presets.",
    },
    "quick_test": {
        "label": "Quick Test",
        "is_default": False,
        "max_width": 512,
        "max_height": 288,
        "num_frames": 25,
        "fps": 12,
        "num_inference_steps": 8,
        "guidance_scale": 2.0,
        "description": "Lowest-cost smoke test only. Not representative of final quality.",
    },
}


def default_video_preset_id() -> str:
    for preset_id, config in VIDEO_PRESETS.items():
        if bool(config.get("is_default", False)):
            return preset_id
    return next(iter(VIDEO_PRESETS))


def validate_video_preset(body: dict[str, Any]) -> str:
    preset = str(body.get("preset", default_video_preset_id())).strip().lower()
    if preset not in VIDEO_PRESETS:
        allowed = ", ".join(VIDEO_PRESETS.keys())
        raise ValueError(f"preset must be one of: {allowed}")
    return preset


def coerce_video_setting(
    body: dict[str, Any],
    *,
    field_name: str,
    default: int,
    minimum: int,
    maximum: int | None = None,
) -> int:
    raw_value = body.get(field_name, default)
    if raw_value is None or (isinstance(raw_value, str) and not raw_value.strip()):
        value = int(default)
    else:
        try:
            value = int(raw_value)
        except (TypeError, ValueError):
            raise ValueError(f"{field_name} must be an integer")
    if value < minimum:
        raise ValueError(f"{field_name} must be at least {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{field_name} must be at most {maximum}")
    return value


def normalize_video_dimension(
    value: int,
    *,
    minimum: int,
    maximum: int,
    step: int = 32,
) -> int:
    clamped = max(minimum, min(maximum, int(value)))
    rounded = int(round(clamped / step) * step)
    return max(minimum, min(maximum, rounded))


def resolve_video_settings(body: dict[str, Any]) -> dict[str, Any]:
    preset = validate_video_preset(body)
    config = VIDEO_PRESETS[preset]
    requested_width = coerce_video_setting(
        body,
        field_name="width",
        default=int(config["max_width"]),
        minimum=32,
        maximum=1920,
    )
    requested_height = coerce_video_setting(
        body,
        field_name="height",
        default=int(config["max_height"]),
        minimum=32,
        maximum=1080,
    )
    fps = coerce_video_setting(
        body,
        field_name="fps",
        default=int(config["fps"]),
        minimum=1,
        maximum=60,
    )
    num_frames = coerce_video_setting(
        body,
        field_name="num_frames",
        default=int(config["num_frames"]),
        minimum=8,
    )
    width = normalize_video_dimension(requested_width, minimum=32, maximum=1920)
    height = normalize_video_dimension(requested_height, minimum=32, maximum=1080)
    return {
        "preset": preset,
        "width": width,
        "height": height,
        "image_orientation": derive_orientation_from_dimensions(width, height),
        "fps": fps,
        "num_frames": num_frames,
        "num_inference_steps": int(config["num_inference_steps"]),
        "guidance_scale": float(config["guidance_scale"]),
    }


def video_dimensions_for_orientation(
    *,
    preset: str,
    image_orientation: str,
) -> tuple[int, int]:
    config = VIDEO_PRESETS[preset]
    landscape_width = int(config["max_width"])
    landscape_height = int(config["max_height"])
    if image_orientation == "portrait":
        return (landscape_height, landscape_width)
    return (landscape_width, landscape_height)

