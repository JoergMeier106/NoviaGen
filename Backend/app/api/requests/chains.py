from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

from ...generation import compose_positive_prompt, resolve_video_model_display_name
from ..common.validation import (
    validate_generation_settings,
    validate_generation_strength,
    validate_image_orientation,
    validate_loras,
)
from ..payloads.assets import comfy_workflow_configured
from ..payloads.video_settings import resolve_video_settings
from .errors import JobRequestError
from .images import (
    _require_model_id,
    _scale_factor,
    _validate_lora_ids,
    auto_metadata_options,
)
from .prompts import generate_prompt_payload
from .sources import _require_readable_stored_still_source, _save_uploaded_image
from .videos import _video_diffusion_model_overrides, _video_workflow_lora_overrides


SUPPORTED_CHAIN_STEP_TYPES = frozenset(
    {
        "generate",
        "generate_from_image",
        "generate_prompt",
        "generate_i2v_prompt",
        "generate_video",
        "animate_image",
        "upscale",
        "upscale_video",
        "convert_video_to_gif",
        "generate_audio_video",
    }
)
ARTIFACT_CHAIN_STEP_TYPES = frozenset(
    {
        "generate",
        "generate_from_image",
        "generate_video",
        "animate_image",
        "upscale",
        "upscale_video",
        "convert_video_to_gif",
        "generate_audio_video",
    }
)
TEXT_CHAIN_STEP_TYPES = frozenset({"generate_prompt", "generate_i2v_prompt"})
ALLOWED_CHAIN_OUTPUTS = frozenset({"result_image_id", "result_text"})


def chain_payload(
    *,
    request_obj: Any,
    catalog: Any,
    db: Any,
    temp_dir: str | Path,
    is_still_media,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    body, uploaded_files = _chain_request_parts(request_obj)
    raw_steps = body.get("steps")
    if not isinstance(raw_steps, list) or not raw_steps:
        raise JobRequestError("steps must be a non-empty list")

    normalized_steps: list[dict[str, Any]] = []
    previous_step_types: dict[str, str] = {}
    seen_step_ids: set[str] = set()
    for raw_step in raw_steps:
        if not isinstance(raw_step, dict):
            raise JobRequestError("Each step must be an object")
        step_id = str(raw_step.get("id") or "").strip()
        step_type = str(raw_step.get("type") or "").strip()
        if not step_id:
            raise JobRequestError("Each step requires id")
        if step_id in seen_step_ids:
            raise JobRequestError(f"Duplicate chain step id: {step_id}")
        if step_type not in SUPPORTED_CHAIN_STEP_TYPES:
            raise JobRequestError(f"Unsupported chain step type: {step_type}")

        raw_payload = raw_step.get("payload")
        if not isinstance(raw_payload, dict):
            raise JobRequestError(f"Step {step_id} payload must be an object")

        bindings = _normalized_bindings(
            step_id=step_id,
            raw_bindings=raw_step.get("bindings"),
            previous_step_types=previous_step_types,
        )
        bound_fields = set(bindings.keys())
        payload = _normalize_step_uploads(
            payload=raw_payload,
            step_id=step_id,
            uploaded_files=uploaded_files,
            bound_fields=bound_fields,
            temp_dir=temp_dir,
        )
        validated_payload = _validate_chain_step_payload(
            step_type=step_type,
            payload=payload,
            bound_fields=bound_fields,
            catalog=catalog,
            db=db,
            is_still_media=is_still_media,
            config=config,
        )
        step_payload: dict[str, Any] = {
            "id": step_id,
            "type": step_type,
            "payload": validated_payload,
        }
        if bindings:
            step_payload["bindings"] = bindings
        normalized_steps.append(step_payload)
        previous_step_types[step_id] = step_type
        seen_step_ids.add(step_id)

    result: dict[str, Any] = {"steps": normalized_steps}
    client_request_id = str(body.get("client_request_id") or "").strip()
    if client_request_id:
        result["client_request_id"] = client_request_id[:128]
    return result


def _chain_request_parts(request_obj: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    if _is_multipart_request(request_obj):
        raw_chain = str(request_obj.form.get("chain") or "").strip()
        if not raw_chain:
            raise JobRequestError("chain form field is required")
        try:
            parsed = json.loads(raw_chain)
        except json.JSONDecodeError as exc:
            raise JobRequestError("chain must be valid JSON") from exc
        if not isinstance(parsed, dict):
            raise JobRequestError("chain must decode to an object")
        return parsed, dict(request_obj.files)
    body = request_obj.get_json(silent=True) or {}
    if not isinstance(body, dict):
        raise JobRequestError("Request body must be an object")
    return body, {}


def _is_multipart_request(request_obj: Any) -> bool:
    return bool(
        request_obj.content_type
        and "multipart/form-data" in request_obj.content_type.lower()
    )


def _normalized_bindings(
    *,
    step_id: str,
    raw_bindings: Any,
    previous_step_types: Mapping[str, str],
) -> dict[str, dict[str, str]]:
    if raw_bindings is None:
        return {}
    if not isinstance(raw_bindings, dict):
        raise JobRequestError(f"Step {step_id} bindings must be an object")

    bindings: dict[str, dict[str, str]] = {}
    for field, raw_binding in raw_bindings.items():
        field_name = str(field or "").strip()
        if not field_name:
            raise JobRequestError(f"Step {step_id} has an empty binding field")
        if not isinstance(raw_binding, dict):
            raise JobRequestError(
                f"Step {step_id} binding for {field_name} must be an object"
            )
        dependency_step_id = str(raw_binding.get("step_id") or "").strip()
        output_name = str(raw_binding.get("output") or "").strip()
        if dependency_step_id not in previous_step_types:
            raise JobRequestError(
                f"Step {step_id} binding for {field_name} must reference an earlier step"
            )
        if output_name not in ALLOWED_CHAIN_OUTPUTS:
            raise JobRequestError(
                f"Step {step_id} binding for {field_name} uses unsupported output {output_name}"
            )
        dependency_type = previous_step_types[dependency_step_id]
        if (
            output_name == "result_image_id"
            and dependency_type not in ARTIFACT_CHAIN_STEP_TYPES
        ):
            raise JobRequestError(
                f"Step {dependency_step_id} does not produce result_image_id"
            )
        if output_name == "result_text" and dependency_type not in TEXT_CHAIN_STEP_TYPES:
            raise JobRequestError(
                f"Step {dependency_step_id} does not produce result_text"
            )
        bindings[field_name] = {
            "step_id": dependency_step_id,
            "output": output_name,
        }
    return bindings


def _normalize_step_uploads(
    *,
    payload: Mapping[str, Any],
    step_id: str,
    uploaded_files: Mapping[str, Any],
    bound_fields: set[str],
    temp_dir: str | Path,
) -> dict[str, Any]:
    normalized = dict(payload)
    upload_ref = str(normalized.get("upload_ref") or "").strip()
    if not upload_ref:
        normalized.pop("upload_ref", None)
        return normalized
    if "upload_ref" in bound_fields:
        raise JobRequestError(f"Step {step_id} cannot bind upload_ref")
    uploaded_file = uploaded_files.get(upload_ref)
    if uploaded_file is None or not getattr(uploaded_file, "filename", ""):
        raise JobRequestError(
            f"Step {step_id} references unknown upload_ref: {upload_ref}"
        )
    normalized["upload_image_path"] = _save_uploaded_image(uploaded_file, temp_dir)
    normalized.pop("upload_ref", None)
    return normalized


def _validate_chain_step_payload(
    *,
    step_type: str,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    catalog: Any,
    db: Any,
    is_still_media,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    if step_type == "generate":
        return _validate_generate_payload(payload=payload, catalog=catalog)
    if step_type == "generate_from_image":
        return _validate_generate_from_image_payload(
            payload=payload,
            bound_fields=bound_fields,
            catalog=catalog,
            db=db,
            is_still_media=is_still_media,
        )
    if step_type == "generate_prompt":
        return generate_prompt_payload(payload)
    if step_type == "generate_i2v_prompt":
        return _validate_generate_i2v_prompt_payload(
            payload=payload,
            bound_fields=bound_fields,
            db=db,
            is_still_media=is_still_media,
        )
    if step_type == "generate_video":
        return _validate_generate_video_payload(payload=payload, config=config)
    if step_type == "animate_image":
        return _validate_animate_image_payload(
            payload=payload,
            bound_fields=bound_fields,
            db=db,
            is_still_media=is_still_media,
            config=config,
        )
    if step_type == "upscale":
        return _validate_upscale_payload(
            payload=payload,
            bound_fields=bound_fields,
            db=db,
        )
    if step_type == "upscale_video":
        return _validate_upscale_video_payload(
            payload=payload,
            bound_fields=bound_fields,
            db=db,
            config=config,
        )
    if step_type == "convert_video_to_gif":
        return _validate_convert_video_to_gif_payload(
            payload=payload,
            bound_fields=bound_fields,
            db=db,
        )
    if step_type == "generate_audio_video":
        return _validate_generate_audio_video_payload(
            payload=payload,
            bound_fields=bound_fields,
            db=db,
            config=config,
        )
    raise JobRequestError(f"Unsupported chain step type: {step_type}")


def _validate_generate_payload(
    *,
    payload: Mapping[str, Any],
    catalog: Any,
) -> dict[str, Any]:
    model_id = _require_model_id(payload, catalog)
    try:
        loras = validate_loras(payload.get("loras"))
        num_inference_steps, guidance_scale = validate_generation_settings(dict(payload))
        image_orientation = validate_image_orientation(dict(payload))
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    _validate_lora_ids(loras, catalog)
    return {
        "prompt": str(payload.get("prompt", "")),
        "default_positive_prompt": str(payload.get("default_positive_prompt", "")),
        "default_negative_prompt": str(payload.get("default_negative_prompt", "")),
        "final_positive_prompt": _final_positive_prompt(
            payload=payload,
            loras=loras,
            catalog=catalog,
        ),
        "model_id": model_id,
        "loras": loras,
        "num_inference_steps": num_inference_steps,
        "guidance_scale": guidance_scale,
        "image_orientation": image_orientation,
        **auto_metadata_options(payload),
    }


def _validate_generate_from_image_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    catalog: Any,
    db: Any,
    is_still_media,
) -> dict[str, Any]:
    result = _validate_generate_payload(payload=payload, catalog=catalog)
    try:
        strength = validate_generation_strength(dict(payload))
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    result["strength"] = strength
    _attach_chain_still_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        is_still_media=is_still_media,
        not_found_message="Unknown image_id",
        invalid_message="Only images or GIFs can be used as source",
        missing_file_message="Source image file could not be read",
    )
    return result


def _validate_generate_i2v_prompt_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
    is_still_media,
) -> dict[str, Any]:
    result = {
        "prompt": str(payload.get("prompt", "")).strip(),
    }
    model_name = str(payload.get("model_name") or "").strip()
    if model_name:
        result["model_name"] = model_name
    _attach_chain_still_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        is_still_media=is_still_media,
        not_found_message="Unknown image_id",
        invalid_message="Only stored images or GIFs can be used",
        missing_file_message="Source image file could not be read",
    )
    return result


def _validate_generate_video_payload(
    *,
    payload: Mapping[str, Any],
    config: Mapping[str, Any],
) -> dict[str, Any]:
    if not comfy_workflow_configured(config, "COMFY_T2V_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy text-to-video workflow is not configured",
            status_code=503,
        )
    try:
        video_settings = resolve_video_settings(dict(payload))
        workflow_loras = _video_workflow_lora_overrides(
            payload,
            config=config,
            config_key="COMFY_T2V_WORKFLOW_PATH",
        )
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    return {
        "prompt": str(payload.get("prompt", "")).strip(),
        "default_positive_prompt": str(payload.get("default_positive_prompt", "")),
        "default_negative_prompt": str(payload.get("default_negative_prompt", "")),
        "final_positive_prompt": compose_positive_prompt(
            str(payload.get("default_positive_prompt", "")),
            str(payload.get("prompt", "")).strip(),
        ),
        "video_model_id": "comfy-text-to-video",
        "display_model_id": resolve_video_model_display_name(
            high_diffusion_model_name=payload.get("high_diffusion_model_name"),
            low_diffusion_model_name=payload.get("low_diffusion_model_name"),
            fallback_model_id="comfy-text-to-video",
        ),
        "width": int(video_settings["width"]),
        "height": int(video_settings["height"]),
        "num_frames": int(video_settings["num_frames"]),
        "fps": int(video_settings["fps"]),
        "num_inference_steps": int(video_settings["num_inference_steps"]),
        "guidance_scale": float(video_settings["guidance_scale"]),
        "workflow_loras": workflow_loras,
        **_video_diffusion_model_overrides(payload),
    }


def _validate_animate_image_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
    is_still_media,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    if not comfy_workflow_configured(config, "COMFY_I2V_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy image-to-video workflow is not configured",
            status_code=503,
        )
    try:
        video_settings = resolve_video_settings(dict(payload))
        workflow_loras = _video_workflow_lora_overrides(
            payload,
            config=config,
            config_key="COMFY_I2V_WORKFLOW_PATH",
        )
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    result = {
        "prompt": str(payload.get("prompt", "")).strip(),
        "default_positive_prompt": str(payload.get("default_positive_prompt", "")),
        "default_negative_prompt": str(payload.get("default_negative_prompt", "")),
        "final_positive_prompt": compose_positive_prompt(
            str(payload.get("default_positive_prompt", "")),
            str(payload.get("prompt", "")).strip(),
        ),
        "video_model_id": "comfy-image-to-video",
        "display_model_id": resolve_video_model_display_name(
            high_diffusion_model_name=payload.get("high_diffusion_model_name"),
            low_diffusion_model_name=payload.get("low_diffusion_model_name"),
            fallback_model_id="comfy-image-to-video",
        ),
        "width": int(video_settings["width"]),
        "height": int(video_settings["height"]),
        "num_frames": int(video_settings["num_frames"]),
        "fps": int(video_settings["fps"]),
        "num_inference_steps": int(video_settings["num_inference_steps"]),
        "guidance_scale": float(video_settings["guidance_scale"]),
        "workflow_loras": workflow_loras,
        **_video_diffusion_model_overrides(payload),
    }
    _attach_chain_still_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        is_still_media=is_still_media,
        not_found_message="Unknown image_id",
        invalid_message="Only images or GIFs can be animated",
        missing_file_message="Source image file could not be read",
    )
    return result


def _validate_upscale_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
) -> dict[str, Any]:
    try:
        num_inference_steps, guidance_scale = validate_generation_settings(dict(payload))
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc
    result = {
        "scale_factor": _scale_factor(payload),
        "num_inference_steps": num_inference_steps,
        "guidance_scale": guidance_scale,
        "delete_source_after_finish": bool(payload.get("delete_source_after_finish", False)),
    }
    _attach_required_media_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        expected_media_type="image",
        invalid_message="Only images can be scaled here",
    )
    return result


def _validate_upscale_video_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    if not comfy_workflow_configured(config, "COMFY_VIDEO_UPSCALER_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy video upscaler workflow is not configured",
            status_code=503,
        )
    result = {
        "scale_factor": _scale_factor(payload),
        "delete_source_after_finish": bool(payload.get("delete_source_after_finish", False)),
    }
    _attach_required_media_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        expected_media_type="video",
        invalid_message="Only videos can be scaled",
    )
    return result


def _validate_convert_video_to_gif_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    _attach_required_media_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        expected_media_type="video",
        invalid_message="Only videos can be converted to GIF",
    )
    return result


def _validate_generate_audio_video_payload(
    *,
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
    config: Mapping[str, Any],
) -> dict[str, Any]:
    if not comfy_workflow_configured(config, "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH"):
        raise JobRequestError(
            "Comfy video-to-audio workflow is not configured",
            status_code=503,
        )
    result: dict[str, Any] = {}
    _attach_required_media_source(
        result=result,
        payload=payload,
        bound_fields=bound_fields,
        db=db,
        expected_media_type="video",
        invalid_message="Only videos can be used to generate audio video",
    )
    return result


def _attach_chain_still_source(
    *,
    result: dict[str, Any],
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
    is_still_media,
    not_found_message: str,
    invalid_message: str,
    missing_file_message: str,
) -> None:
    image_id = str(payload.get("image_id", "")).strip()
    upload_image_path = str(payload.get("upload_image_path", "")).strip()
    if "image_id" in bound_fields:
        if image_id or upload_image_path:
            raise JobRequestError("A bound image_id cannot be combined with a static source")
        return
    if image_id:
        _require_readable_stored_still_source(
            db=db,
            image_id=image_id,
            is_still_media=is_still_media,
            not_found_message=not_found_message,
            invalid_message=invalid_message,
            missing_file_message=missing_file_message,
        )
        result["image_id"] = image_id
        return
    if upload_image_path:
        if not Path(upload_image_path).exists():
            raise JobRequestError(missing_file_message, status_code=404)
        result["upload_image_path"] = upload_image_path
        return
    raise JobRequestError("Either image_id or image file is required")


def _attach_required_media_source(
    *,
    result: dict[str, Any],
    payload: Mapping[str, Any],
    bound_fields: set[str],
    db: Any,
    expected_media_type: str,
    invalid_message: str,
) -> None:
    image_id = str(payload.get("image_id", "")).strip()
    if "image_id" in bound_fields:
        if image_id:
            raise JobRequestError("A bound image_id cannot be combined with a static image_id")
        return
    if not image_id:
        raise JobRequestError("image_id is required")
    source_image = db.get_image(image_id)
    if source_image is None:
        raise JobRequestError("Unknown image_id", status_code=404)
    if source_image.get("media_type", "image") != expected_media_type:
        raise JobRequestError(invalid_message)
    if source_image.get("status") not in {"queued", "running", "stored"}:
        raise JobRequestError(
            f"Only queued, running, or stored {expected_media_type}s can be used here"
        )
    file_path = Path(str(source_image.get("file_path") or ""))
    if source_image.get("status") == "stored" and not file_path.exists():
        raise JobRequestError(
            f"Stored {expected_media_type} file is missing",
            status_code=404,
        )
    result["image_id"] = image_id


def _final_positive_prompt(
    *,
    payload: Mapping[str, Any],
    loras: list[dict[str, Any]],
    catalog: Any,
) -> str:
    lora_triggers: list[str] = []
    for item in loras:
        lora_id = str(item.get("lora_id", "")).strip()
        if not lora_id:
            continue
        lora = catalog.get_lora(lora_id)
        trigger_words = getattr(lora, "trigger_words", "") if lora is not None else ""
        if str(trigger_words).strip():
            lora_triggers.append(str(trigger_words).strip())
    return compose_positive_prompt(
        str(payload.get("default_positive_prompt", "")),
        str(payload.get("prompt", "")),
        ", ".join(lora_triggers),
    )
