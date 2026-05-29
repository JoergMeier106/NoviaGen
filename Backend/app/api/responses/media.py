from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

from flask import Response, jsonify


SendMediaFile = Callable[..., Response]


def delete_media_response(*, db: Any, worker: Any, image_id: str) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is not None and image.get("status") in {"queued", "running"}:
        job = db.get_job_for_result_image(image_id)
        if job is not None and job.get("status") in {"queued", "running"}:
            worker.cancel(str(job["id"]))
            return jsonify(
                {
                    "deleted": True,
                    "image_id": image_id,
                    "cancelled_job_id": job["id"],
                }
            )

    deleted = db.delete_image(image_id)
    if not deleted:
        return jsonify({"error": "Image not found"}), 404
    return jsonify({"deleted": True, "image_id": image_id})


def restore_media_response(
    *,
    db: Any,
    image_payload,
    image_id: str,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    if image.get("status") != "deleted":
        return jsonify({"error": "Only deleted media can be restored"}), 409
    restored = db.restore_image(image_id)
    if restored is None:
        return jsonify({"error": "Image not found"}), 404
    return jsonify(image_payload(restored))


def media_file_response(
    *,
    db: Any,
    image_id: str,
    send_media_file: SendMediaFile,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404

    file_path = Path(image["file_path"])
    if not file_path.exists():
        return jsonify({"error": "File not found"}), 404
    return send_media_file(file_path, mimetype=image["mime_type"])


def poster_file_response(
    *,
    db: Any,
    image_id: str,
    ensure_video_poster,
    send_media_file: SendMediaFile,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    image = ensure_video_poster(image)
    poster_path_raw = image.get("poster_path")
    if not poster_path_raw:
        return jsonify({"error": "Poster not found"}), 404
    poster_path = Path(poster_path_raw)
    if not poster_path.exists():
        return jsonify({"error": "Poster file not found"}), 404
    return send_media_file(
        poster_path,
        mimetype=image.get("poster_mime_type") or "image/png",
    )


def thumbnail_file_response(
    *,
    db: Any,
    image_id: str,
    ensure_video_poster,
    send_media_file: SendMediaFile,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    if image.get("status") not in {"stored", "deleted"}:
        return jsonify({"error": "Thumbnail not available"}), 404

    if image.get("media_type") == "video":
        image = ensure_video_poster(image)
    image = db.ensure_image_thumbnail(image_id) or image
    thumbnail_path_raw = image.get("thumbnail_path")
    thumbnail_mime_type = image.get("thumbnail_mime_type") or "image/png"

    if not thumbnail_path_raw:
        return jsonify({"error": "Thumbnail not found"}), 404

    thumbnail_path = Path(thumbnail_path_raw)
    if not thumbnail_path.exists():
        return jsonify({"error": "Thumbnail file not found"}), 404
    return send_media_file(thumbnail_path, mimetype=thumbnail_mime_type)
