from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping

from .errors import JobRequestError
from .sources import _require_readable_stored_still_source, _save_uploaded_image


def generate_prompt_payload(body: Mapping[str, Any]) -> dict[str, Any]:
    prompt = str(body.get("prompt", "")).strip()
    if not prompt:
        raise JobRequestError("prompt is required")

    payload = {"prompt": prompt}
    model_name = str(body.get("model_name") or "").strip()
    if model_name:
        payload["model_name"] = model_name
    return payload


def generate_i2v_prompt_payload(
    *,
    body: Mapping[str, Any],
    uploaded_file: Any,
    db: Any,
    temp_dir: str | Path,
    is_still_media,
) -> dict[str, Any]:
    payload = {"prompt": str(body.get("prompt", "")).strip()}
    model_name = str(body.get("model_name") or "").strip()
    if model_name:
        payload["model_name"] = model_name

    image_id = str(body.get("image_id", "")).strip()
    if image_id:
        _require_readable_stored_still_source(
            db=db,
            image_id=image_id,
            is_still_media=is_still_media,
            not_found_message="Unknown image_id",
            invalid_message="Only stored images or GIFs can be used",
            missing_file_message="Source image file could not be read",
        )
        payload["image_id"] = image_id
        return payload

    if uploaded_file is None or not uploaded_file.filename:
        raise JobRequestError("Either image_id or image file is required")
    payload["upload_image_path"] = _save_uploaded_image(uploaded_file, temp_dir)
    return payload
