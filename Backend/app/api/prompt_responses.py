from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any, Mapping

from flask import Response, jsonify

from ..generation import OllamaResponseError, OllamaUnavailableError


class PromptResponseError(ValueError):
    def __init__(self, message: str, *, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def generate_prompt_response(
    *,
    body: Mapping[str, Any],
    worker: Any,
) -> Response | tuple[Response, int]:
    prompt = str(body.get("prompt", "")).strip()
    if not prompt:
        return jsonify({"error": "prompt is required"}), 400

    generator = getattr(worker, "generator", None)
    if generator is None or not hasattr(generator, "generate_prompt"):
        return jsonify({"error": "Prompt generation is not available"}), 503

    model_name = str(body.get("model_name") or "").strip() or None
    try:
        generated_prompt = generator.generate_prompt(prompt, model=model_name)
    except OllamaUnavailableError as exc:
        return jsonify({"error": str(exc)}), 503
    except OllamaResponseError as exc:
        return jsonify({"error": str(exc)}), 502
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    return jsonify({"prompt": generated_prompt})


def generate_i2v_prompt_response(
    *,
    request_obj: Any,
    db: Any,
    worker: Any,
    config: Mapping[str, Any],
    is_still_media,
) -> Response | tuple[Response, int]:
    body, uploaded_file = _i2v_prompt_request_parts(request_obj)
    try:
        source_image_path, cleanup_upload_path = _source_image_path(
            body=body,
            uploaded_file=uploaded_file,
            db=db,
            config=config,
            is_still_media=is_still_media,
        )
    except PromptResponseError as exc:
        return jsonify({"error": str(exc)}), exc.status_code

    generator = getattr(worker, "generator", None)
    if generator is None or not hasattr(generator, "generate_i2v_prompt"):
        return jsonify({"error": "Prompt generation is not available"}), 503
    if not str(config.get("COMFY_I2V_PROMPT_WORKFLOW_PATH") or "").strip():
        return jsonify({"error": "Comfy image prompt workflow is not configured"}), 503

    model_name = str(body.get("model_name") or "").strip() or None
    try:
        generated_prompt = generator.generate_i2v_prompt(
            prompt=str(body.get("prompt", "")),
            source_image_path=source_image_path,
            model=model_name,
        )
    except OllamaUnavailableError as exc:
        return jsonify({"error": str(exc)}), 503
    except OllamaResponseError as exc:
        return jsonify({"error": str(exc)}), 502
    except FileNotFoundError as exc:
        return jsonify({"error": str(exc)}), 404
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    finally:
        if cleanup_upload_path is not None:
            cleanup_upload_path.unlink(missing_ok=True)
    return jsonify({"prompt": generated_prompt.strip()})


def _i2v_prompt_request_parts(request_obj: Any) -> tuple[dict[str, Any], Any]:
    is_multipart = bool(
        request_obj.content_type
        and "multipart/form-data" in request_obj.content_type.lower()
    )
    if is_multipart:
        return dict(request_obj.form), request_obj.files.get("image")
    return request_obj.get_json(silent=True) or {}, None


def _source_image_path(
    *,
    body: Mapping[str, Any],
    uploaded_file: Any,
    db: Any,
    config: Mapping[str, Any],
    is_still_media,
) -> tuple[Path, Path | None]:
    image_id = str(body.get("image_id", "")).strip()
    if image_id:
        source_image = db.get_image(image_id)
        if source_image is None:
            raise PromptResponseError("Unknown image_id", status_code=404)
        if source_image.get("status") != "stored":
            raise PromptResponseError("Only stored images or GIFs can be used")
        if not is_still_media(source_image):
            raise PromptResponseError("Only stored images or GIFs can be used")
        source_image_path = Path(source_image["file_path"])
        if not source_image_path.exists():
            raise PromptResponseError(
                "Source image file could not be read",
                status_code=404,
            )
        return source_image_path, None

    if uploaded_file is None or not uploaded_file.filename:
        raise PromptResponseError("Either image_id or image file is required")
    upload_path = _save_upload(uploaded_file, config)
    return upload_path, upload_path


def _save_upload(uploaded_file: Any, config: Mapping[str, Any]) -> Path:
    uploads_dir = Path(config["TEMP_DIR"]) / "uploads"
    uploads_dir.mkdir(parents=True, exist_ok=True)
    suffix = Path(uploaded_file.filename or "source.png").suffix or ".png"
    upload_path = uploads_dir / f"{uuid.uuid4()}{suffix}"
    uploaded_file.save(upload_path)
    return upload_path
