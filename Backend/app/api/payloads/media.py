from __future__ import annotations

from pathlib import Path
from typing import Any

from flask import current_app, url_for

from ..common.validation import derive_orientation_from_dimensions


def db():
    return current_app.extensions["db"]


def worker():
    return current_app.extensions["job_worker"]


def image_payload(image: dict[str, Any]) -> dict[str, Any]:
    is_stored = image.get("status") in {"stored", "deleted"}
    is_video = image.get("media_type") == "video"
    source_image_id = str(image.get("source_image_id") or "").strip() or None
    source_image_exists = False
    if source_image_id:
        source_image_exists = db().get_image(source_image_id) is not None
    poster_url = (
        url_for("api.get_poster_file", image_id=image["id"], _external=True)
        if is_stored and is_video
        else None
    )
    thumbnail_url = (
        url_for(
            "api.get_thumbnail_file",
            image_id=image["id"],
            _external=True,
            v="video-square-v1" if is_video else None,
        )
        if is_stored
        else None
    )
    is_imported_image = str(image.get("model_id") or "").strip() == "Imported"
    return {
        "id": image["id"],
        "status": image["status"],
        "media_type": image.get("media_type", "image"),
        "mime_type": image["mime_type"],
        "width": image["width"],
        "height": image["height"],
        "prompt": "" if is_imported_image else image["prompt"],
        "default_positive_prompt": (
            "" if is_imported_image else image["default_positive_prompt"]
        ),
        "default_negative_prompt": (
            "" if is_imported_image else image["default_negative_prompt"]
        ),
        "final_positive_prompt": (
            "" if is_imported_image else image["final_positive_prompt"]
        ),
        "model_id": image["model_id"],
        "loras": image["loras"],
        "tags": image.get("tags", []),
        "caption": str(image.get("caption") or ""),
        "num_inference_steps": int(image.get("num_inference_steps", 40)),
        "guidance_scale": float(image.get("guidance_scale", 5.0)),
        "image_orientation": derive_orientation_from_dimensions(
            image.get("width"),
            image.get("height"),
            fallback=str(image.get("image_orientation", "landscape")),
        ),
        "source_image_id": source_image_id,
        "source_image_exists": source_image_exists,
        "scale_factor": image["scale_factor"],
        "is_upscaled": bool(image["is_upscaled"]),
        "duration_seconds": image.get("duration_seconds"),
        "generation_duration_seconds": image.get("generation_duration_seconds"),
        "fps": image.get("fps"),
        "num_frames": image.get("num_frames"),
        "rating": int(image.get("rating", 0)),
        "created_at": image["created_at"],
        "stored_at": image["stored_at"],
        "deleted_at": image.get("deleted_at"),
        "file_url": url_for("api.get_file", image_id=image["id"], _external=True),
        "poster_url": poster_url,
        "thumbnail_url": thumbnail_url,
        "preview_url": thumbnail_url
        or poster_url
        or url_for("api.get_file", image_id=image["id"], _external=True),
    }


def is_still_media(image: dict[str, Any]) -> bool:
    return image.get("media_type", "image") in {"image", "gif"}


def ensure_video_poster(image: dict[str, Any]) -> dict[str, Any]:
    if image.get("media_type") != "video" or image.get("status") != "stored":
        return image
    poster_path_value = str(image.get("poster_path") or "").strip()
    if poster_path_value and Path(poster_path_value).exists():
        return image

    generator = getattr(worker(), "generator", None)
    if generator is None or not hasattr(generator, "create_video_poster"):
        return image

    source_image_path = _source_image_path_for_poster(image)
    try:
        poster_path, poster_mime_type = generator.create_video_poster(
            video_path=Path(image["file_path"]),
            output_dir=Path(current_app.config["TEMP_DIR"]),
            image_id=str(image["id"]),
            fallback_source_image_path=source_image_path,
            width=int(image["width"]),
            height=int(image["height"]),
        )
        if poster_path is None:
            return image
        return (
            db().update_image_poster(
                str(image["id"]),
                poster_path=poster_path,
                poster_mime_type=poster_mime_type,
            )
            or image
        )
    except Exception:
        current_app.logger.warning(
            "Failed to ensure poster for video %s",
            image.get("id"),
            exc_info=True,
        )
        return image


def _source_image_path_for_poster(image: dict[str, Any]) -> Path | None:
    source_image_id = str(image.get("source_image_id") or "").strip()
    if not source_image_id:
        return None
    source_image = db().get_image(source_image_id)
    if source_image is None:
        return None
    return Path(source_image["file_path"])
