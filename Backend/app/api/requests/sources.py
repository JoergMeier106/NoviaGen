from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any, Mapping

from .errors import JobRequestError


def _require_source_image_id(
    body: Mapping[str, Any],
    db: Any,
    *,
    expected_media_type: str,
    invalid_message: str | None = None,
) -> str:
    image_id = str(body.get("image_id", "")).strip()
    if not image_id:
        raise JobRequestError("image_id is required")
    source_image = db.get_image(image_id)
    if source_image is None:
        raise JobRequestError("Unknown image_id", status_code=404)
    if source_image.get("media_type", "image") != expected_media_type:
        message = invalid_message or f"Only {expected_media_type}s can be scaled here"
        raise JobRequestError(message)
    return image_id


def _optional_still_source_image_id(
    *,
    body: Mapping[str, Any],
    uploaded_file: Any,
    db: Any,
    is_still_media,
    invalid_message: str,
) -> str:
    image_id = str(body.get("image_id", "")).strip()
    if image_id:
        source_image = db.get_image(image_id)
        if source_image is None:
            raise JobRequestError("Unknown image_id", status_code=404)
        if not is_still_media(source_image):
            raise JobRequestError(invalid_message)
        return image_id
    if uploaded_file is None or not uploaded_file.filename:
        raise JobRequestError("Either image_id or image file is required")
    return ""


def _require_readable_stored_still_source(
    *,
    db: Any,
    image_id: str,
    is_still_media,
    not_found_message: str,
    invalid_message: str,
    missing_file_message: str,
) -> None:
    source_image = db.get_image(image_id)
    if source_image is None:
        raise JobRequestError(not_found_message, status_code=404)
    if source_image.get("status") != "stored":
        raise JobRequestError(invalid_message)
    if not is_still_media(source_image):
        raise JobRequestError(invalid_message)
    if not Path(source_image["file_path"]).exists():
        raise JobRequestError(missing_file_message, status_code=404)


def _attach_image_source(
    payload: dict[str, Any],
    image_id: str,
    uploaded_file: Any,
    temp_dir: str | Path,
) -> None:
    if image_id:
        payload["image_id"] = image_id
    else:
        payload["upload_image_path"] = _save_uploaded_image(uploaded_file, temp_dir)


def _save_uploaded_image(uploaded_file: Any, temp_dir: str | Path) -> str:
    uploads_dir = Path(temp_dir) / "uploads"
    uploads_dir.mkdir(parents=True, exist_ok=True)
    suffix = Path(uploaded_file.filename or "source.png").suffix or ".png"
    upload_path = uploads_dir / f"{uuid.uuid4()}{suffix}"
    uploaded_file.save(upload_path)
    return str(upload_path)
