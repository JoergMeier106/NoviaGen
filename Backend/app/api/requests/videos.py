from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

from ...generation import compose_positive_prompt, resolve_video_model_display_name
from ..payloads.assets import comfy_workflow_configured, workflow_loras_for_config
from .images import _scale_factor
from .errors import JobRequestError
from .sources import (
    _attach_image_source,
    _optional_still_source_image_id,
    _require_source_image_id,
)
from ..payloads.video_settings import resolve_video_settings


def video_upscale_payload(
    *,
    body: Mapping[str, Any],
    db: Any,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    image_id = _require_source_image_id(
        body,
        db,
        expected_media_type="video",
        invalid_message="Only videos can be scaled",
    )
    if not comfy_workflow_configured(config, "COMFY_VIDEO_UPSCALER_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy video upscaler workflow is not configured",
            status_code=503,
        )
    return {
        "image_id": image_id,
        "scale_factor": _scale_factor(body),
        "delete_source_after_finish": bool(
            body.get("delete_source_after_finish", False)
        ),
    }


def video_to_gif_payload(*, body: Mapping[str, Any], db: Any) -> dict[str, Any]:
    image_id = _require_source_image_id(
        body,
        db,
        expected_media_type="video",
        invalid_message="Only videos can be converted to GIF",
    )
    return {"image_id": image_id}


def video_to_audio_payload(
    *,
    body: Mapping[str, Any],
    db: Any,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    image_id = str(body.get("image_id", "")).strip()
    if not image_id:
        raise JobRequestError("image_id is required")
    source_image = db.get_image(image_id)
    if source_image is None:
        raise JobRequestError("Unknown image_id", status_code=404)
    if source_image.get("media_type", "image") != "video":
        raise JobRequestError("Only videos can be used to generate audio video")
    source_status = str(source_image.get("status") or "").strip().lower()
    if source_status not in {"queued", "running", "stored"}:
        raise JobRequestError("Only queued, running, or stored videos can be used here")
    source_file = Path(str(source_image.get("file_path") or ""))
    if source_status == "stored" and not source_file.exists():
        raise JobRequestError("Stored video file is missing")
    if not comfy_workflow_configured(config, "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy video-to-audio workflow is not configured",
            status_code=503,
        )
    return {"image_id": image_id}


def generate_video_payload(
    *,
    body: Mapping[str, Any],
    config: Mapping[str, Any],
) -> dict[str, Any]:
    if not comfy_workflow_configured(config, "COMFY_T2V_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy text-to-video workflow is not configured",
            status_code=503,
        )
    try:
        video_settings = resolve_video_settings(dict(body))
        workflow_loras = _video_workflow_lora_overrides(
            body,
            config=config,
            config_key="COMFY_T2V_WORKFLOW_PATH",
        )
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    return _video_generation_payload(
        body=body,
        video_settings=video_settings,
        workflow_loras=workflow_loras,
        video_model_id="comfy-text-to-video",
    )


def animate_image_payload(
    *,
    body: Mapping[str, Any],
    uploaded_file: Any,
    db: Any,
    temp_dir: str | Path,
    is_still_media,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    image_id = _optional_still_source_image_id(
        body=body,
        uploaded_file=uploaded_file,
        db=db,
        is_still_media=is_still_media,
        invalid_message="Only images or GIFs can be animated",
    )
    try:
        video_settings = resolve_video_settings(dict(body))
        workflow_loras = _video_workflow_lora_overrides(
            body,
            config=config,
            config_key="COMFY_I2V_WORKFLOW_PATH",
        )
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc

    if not comfy_workflow_configured(config, "COMFY_I2V_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy image-to-video workflow is not configured",
            status_code=503,
        )

    payload = _video_generation_payload(
        body=body,
        video_settings=video_settings,
        workflow_loras=workflow_loras,
        video_model_id="comfy-image-to-video",
    )
    _attach_image_source(payload, image_id, uploaded_file, temp_dir)
    return payload


def _video_workflow_lora_overrides(
    body: Mapping[str, Any],
    *,
    config: Mapping[str, Any],
    config_key: str,
) -> list[dict[str, Any]]:
    raw_loras = body.get("workflow_loras")
    if raw_loras is None:
        return []
    if isinstance(raw_loras, str):
        try:
            raw_loras = json.loads(raw_loras)
        except json.JSONDecodeError as exc:
            raise ValueError("workflow_loras must be valid JSON") from exc
    if not isinstance(raw_loras, list):
        raise ValueError("workflow_loras must be a list")

    valid_lora_ids = {
        str(item["id"])
        for item in workflow_loras_for_config(config, config_key)
        if str(item.get("id", "")).strip()
    }
    result: list[dict[str, Any]] = []
    for item in raw_loras:
        if not isinstance(item, dict):
            raise ValueError("Each workflow_loras entry must be an object")
        lora_id = str(item.get("lora_id") or item.get("id") or "").strip()
        if not lora_id:
            raise ValueError("Each workflow_loras entry requires lora_id")
        if valid_lora_ids and lora_id not in valid_lora_ids:
            raise ValueError(f"Unknown workflow lora_id: {lora_id}")
        try:
            strength = float(item.get("strength"))
        except (TypeError, ValueError) as exc:
            raise ValueError("workflow_loras strength must be numeric") from exc
        if strength < 0 or strength > 2:
            raise ValueError("workflow_loras strength must be between 0 and 2")
        result.append({"lora_id": lora_id, "strength": strength})
    return result


def _video_generation_payload(
    *,
    body: Mapping[str, Any],
    video_settings: Mapping[str, Any],
    workflow_loras: list[dict[str, Any]],
    video_model_id: str,
) -> dict[str, Any]:
    return {
        "prompt": str(body.get("prompt", "")).strip(),
        "default_positive_prompt": str(body.get("default_positive_prompt", "")),
        "default_negative_prompt": str(body.get("default_negative_prompt", "")),
        "final_positive_prompt": compose_positive_prompt(
            str(body.get("default_positive_prompt", "")),
            str(body.get("prompt", "")).strip(),
        ),
        "video_model_id": video_model_id,
        "display_model_id": resolve_video_model_display_name(
            high_diffusion_model_name=body.get("high_diffusion_model_name"),
            low_diffusion_model_name=body.get("low_diffusion_model_name"),
            fallback_model_id=video_model_id,
        ),
        "width": int(video_settings["width"]),
        "height": int(video_settings["height"]),
        "num_frames": int(video_settings["num_frames"]),
        "fps": int(video_settings["fps"]),
        "num_inference_steps": int(video_settings["num_inference_steps"]),
        "guidance_scale": float(video_settings["guidance_scale"]),
        "workflow_loras": workflow_loras,
        **_video_diffusion_model_overrides(body),
    }


def _video_diffusion_model_overrides(body: Mapping[str, Any]) -> dict[str, str]:
    overrides: dict[str, str] = {}
    high_name = str(body.get("high_diffusion_model_name", "")).strip()
    low_name = str(body.get("low_diffusion_model_name", "")).strip()
    if high_name:
        overrides["high_diffusion_model_name"] = high_name
    if low_name:
        overrides["low_diffusion_model_name"] = low_name
    return overrides
