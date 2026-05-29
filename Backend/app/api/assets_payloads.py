from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping

import requests

from ..comfy import ComfyVideoWorkflowManager
from .video_settings import VIDEO_PRESETS


def asset_payloads(
    *,
    catalog: Any,
    db: Any,
    config: Mapping[str, Any],
    http_get=requests.get,
) -> dict[str, Any]:
    model_ratings = db.list_asset_rating_stats("model")
    lora_ratings = db.list_asset_rating_stats("lora")
    return {
        "models": [
            {
                "id": item["id"],
                "label": item["label"],
                "rating": float(model_ratings.get(item["id"], {}).get("rating", 0.0)),
                "rating_count": int(
                    model_ratings.get(item["id"], {}).get("rating_count", 0)
                ),
            }
            for item in catalog.list_models()
        ],
        "loras": [
            {
                "id": item["id"],
                "label": item["label"],
                "default_strength": item["default_strength"],
                "rating": float(lora_ratings.get(item["id"], {}).get("rating", 0.0)),
                "rating_count": int(
                    lora_ratings.get(item["id"], {}).get("rating_count", 0)
                ),
            }
            for item in catalog.list_loras()
        ],
        "video_models": video_model_payloads(config),
        "video_diffusion_models": comfy_diffusion_model_names(
            config,
            http_get=http_get,
        ),
        "video_presets": video_preset_payloads(),
    }


def video_model_payloads(config: Mapping[str, Any]) -> list[dict[str, Any]]:
    video_models: list[dict[str, Any]] = []
    if comfy_workflow_configured(config, "COMFY_T2V_WORKFLOW_PATH"):
        video_models.append(
            {
                "id": "comfy-text-to-video",
                "label": "ComfyUI Text-to-Video",
                "path": str(config["COMFY_T2V_WORKFLOW_PATH"]),
                "workflow_loras": workflow_loras_for_config(
                    config,
                    "COMFY_T2V_WORKFLOW_PATH",
                ),
            }
        )
    if comfy_workflow_configured(config, "COMFY_I2V_WORKFLOW_PATH"):
        video_models.append(
            {
                "id": "comfy-image-to-video",
                "label": "ComfyUI Image-to-Video",
                "path": str(config["COMFY_I2V_WORKFLOW_PATH"]),
                "workflow_loras": workflow_loras_for_config(
                    config,
                    "COMFY_I2V_WORKFLOW_PATH",
                ),
            }
        )
    return video_models


def video_preset_payloads() -> list[dict[str, Any]]:
    return [
        {
            "id": preset_id,
            "label": str(config["label"]),
            "max_width": int(config["max_width"]),
            "max_height": int(config["max_height"]),
            "num_frames": int(config["num_frames"]),
            "fps": int(config["fps"]),
            "num_inference_steps": int(config["num_inference_steps"]),
            "guidance_scale": float(config["guidance_scale"]),
            "is_default": bool(config.get("is_default", False)),
            "description": str(config.get("description", "")),
            "supports_custom_values": bool(config.get("supports_custom_values", False)),
        }
        for preset_id, config in VIDEO_PRESETS.items()
    ]


def comfy_diffusion_model_names(
    config: Mapping[str, Any],
    *,
    http_get=requests.get,
) -> list[str]:
    comfy_url = str(config["COMFY_URL"]).rstrip("/")
    if not comfy_url:
        return []
    try:
        response = http_get(
            f"{comfy_url}/models/diffusion_models",
            timeout=float(config["COMFY_MODELS_TIMEOUT_SECONDS"]),
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError, TypeError):
        return []
    return _extract_comfy_model_names(payload)


def workflow_loras_for_config(
    config: Mapping[str, Any],
    config_key: str,
) -> list[dict[str, Any]]:
    workflow_path = str(config.get(config_key) or "").strip()
    if not workflow_path:
        return []
    try:
        workflow = ComfyVideoWorkflowManager._load_workflow(
            Path(workflow_path),
            config_key,
        )
    except (FileNotFoundError, ValueError, OSError):
        return []
    return ComfyVideoWorkflowManager.workflow_loras(workflow)


def comfy_workflow_configured(config: Mapping[str, Any], config_key: str) -> bool:
    raw = config.get(config_key)
    if raw is None:
        return False
    return bool(str(raw).strip())


def _extract_comfy_model_names(payload: Any) -> list[str]:
    raw_items = _raw_comfy_model_items(payload)
    if raw_items is None:
        return []

    names: set[str] = set()
    for item in raw_items:
        name = _comfy_model_name(item)
        if name:
            names.add(name)
    return sorted(names, key=str.lower)


def _raw_comfy_model_items(payload: Any) -> list[Any] | None:
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return None
    for key in ("models", "diffusion_models", "items"):
        value = payload.get(key)
        if isinstance(value, list):
            return value
    return list(payload.keys())


def _comfy_model_name(item: Any) -> str:
    if isinstance(item, str):
        return item.strip()
    if not isinstance(item, dict):
        return ""
    return str(
        item.get("name")
        or item.get("filename")
        or item.get("model_name")
        or ""
    ).strip()
