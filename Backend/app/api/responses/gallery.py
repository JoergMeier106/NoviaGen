from __future__ import annotations

from pathlib import Path
from typing import Any

from flask import Response, current_app, jsonify

from ...job_queue.metadata import generate_image_metadata
from ..requests.parsing import coerce_bool, parse_tag_filter_values, truthy_arg


def import_gallery_images_response(
    *,
    request_obj: Any,
    image_importer: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    uploaded_files = request_obj.files.getlist("images")
    if not uploaded_files:
        uploaded_file = request_obj.files.get("image")
        if uploaded_file is not None:
            uploaded_files = [uploaded_file]
    if not uploaded_files:
        return jsonify({"error": "At least one image file is required"}), 400

    imported_items: list[dict[str, Any]] = []
    failures: list[dict[str, str]] = []
    for uploaded_file in uploaded_files:
        filename = Path(uploaded_file.filename or "image").name or "image"
        try:
            imported_items.append(image_importer.import_upload(uploaded_file))
        except ValueError as exc:
            failures.append({"filename": filename, "error": str(exc)})
        except Exception:
            current_app.logger.exception("Failed to import gallery image %s", filename)
            failures.append(
                {
                    "filename": filename,
                    "error": "Could not import this image right now.",
                }
            )

    if not imported_items and failures:
        return (
            jsonify(
                {
                    "error": failures[0]["error"],
                    "items": [],
                    "failures": failures,
                    "imported_count": 0,
                }
            ),
            400,
        )

    return jsonify(
        {
            "items": [image_payload(item) for item in imported_items],
            "failures": failures,
            "imported_count": len(imported_items),
        }
    )


def list_gallery_images_response(
    *,
    request_args: Any,
    db: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    try:
        page = max(1, int(request_args.get("page", 1)))
        page_size = max(1, min(100, int(request_args.get("page_size", 20))))
        min_rating = max(0, int(request_args.get("min_rating", 0)))
        include_placeholders = coerce_bool(
            request_args.get("include_placeholders", "true"),
            "include_placeholders",
        )
    except ValueError:
        return jsonify(
            {
                "error": (
                    "page, page_size, and min_rating must be integers; "
                    "include_placeholders must be a boolean"
                )
            }
        ), 400

    listing = db.list_gallery_images(
        page=page,
        page_size=page_size,
        search=str(request_args.get("search") or ""),
        media_type=str(request_args.get("media_type") or ""),
        model_id=str(request_args.get("model_id") or ""),
        include_tags=parse_tag_filter_values(request_args.getlist("include_tags")),
        exclude_tags=parse_tag_filter_values(request_args.getlist("exclude_tags")),
        min_rating=min_rating,
        sort=str(request_args.get("sort") or "newest"),
        include_deleted=truthy_arg(request_args.get("include_deleted")),
        include_placeholders=include_placeholders,
    )
    return jsonify(
        {
            "items": [image_payload(item) for item in listing["items"]],
            "page": listing["page"],
            "page_size": listing["page_size"],
            "total": listing["total"],
            "has_more": bool(listing["has_more"]),
        }
    )


def list_gallery_filters_response(*, request_args: Any, db: Any) -> Response:
    return jsonify(
        db.list_gallery_filters(
            include_deleted=truthy_arg(request_args.get("include_deleted")),
        )
    )


def store_image_response(
    *,
    image_id: str,
    db: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    stored = db.store_image(image_id)
    return jsonify(image_payload(stored))


def list_stored_images_response(
    *,
    request_args: Any,
    db: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    try:
        page = max(1, int(request_args.get("page", 1)))
        page_size = max(1, min(100, int(request_args.get("page_size", 20))))
    except ValueError:
        return jsonify({"error": "page and page_size must be integers"}), 400

    listing = db.list_stored_images(page=page, page_size=page_size)
    return jsonify(
        {
            "items": [image_payload(item) for item in listing["items"]],
            "page": listing["page"],
            "page_size": listing["page_size"],
            "total": listing["total"],
        }
    )


def latest_temp_image_response(*, db: Any, image_payload) -> Response | tuple[Response, int]:
    image = db.get_latest_temp_image()
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    return jsonify(image_payload(image))


def get_image_response(
    *,
    image_id: str,
    db: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    return jsonify(image_payload(image))


def set_image_rating_response(
    *,
    image_id: str,
    body: dict[str, Any],
    db: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    if image.get("status") != "stored":
        return jsonify({"error": "Only ready media can be rated"}), 409

    try:
        rating = int(body.get("rating", 0))
    except (TypeError, ValueError):
        return jsonify({"error": "rating must be an integer"}), 400
    if rating < 0 or rating > 5:
        return jsonify({"error": "rating must be between 0 and 5"}), 400

    updated = db.set_image_rating(image_id, rating)
    if updated is None:
        return jsonify({"error": "Image not found"}), 404
    return jsonify(image_payload(updated))


def set_image_tags_response(
    *,
    image_id: str,
    body: dict[str, Any],
    db: Any,
    image_payload,
    validate_tags,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    if image.get("status") != "stored":
        return jsonify({"error": "Only ready media can be tagged"}), 409

    try:
        tags = validate_tags(body.get("tags"))
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    updated = db.set_image_tags(image_id, tags)
    if updated is None:
        return jsonify({"error": "Image not found"}), 404
    return jsonify(image_payload(updated))


def generate_image_tags_response(
    *,
    image_id: str,
    body: dict[str, Any],
    db: Any,
    generator: Any,
    error_store: Any,
    image_payload,
) -> Response | tuple[Response, int]:
    image = db.get_image(image_id)
    if image is None:
        return jsonify({"error": "Image not found"}), 404
    if image.get("status") != "stored":
        return jsonify({"error": "Only ready media can be tagged"}), 409
    if image.get("media_type") != "image":
        return jsonify({"error": "Tags can only be generated for images"}), 400

    model_name = str(body.get("model_name") or body.get("model") or "").strip()
    if not model_name:
        return jsonify({"error": "model_name is required"}), 400

    try:
        metadata = generate_image_metadata(
            generator=generator,
            model_name=model_name,
            image_path=image["file_path"],
            existing_tags=db.list_tags(),
        )
        tags = [
            *list(image.get("tags") or []),
            *list(metadata.get("tags") or []),
        ]
        updated = db.set_image_tags(image_id, tags)
        if updated is None:
            return jsonify({"error": "Image not found"}), 404
        return jsonify(image_payload(updated))
    except Exception as exc:
        current_app.logger.warning(
            "Failed to generate tags for image %s",
            image_id,
            exc_info=True,
        )
        try:
            error_store.log_system_error(
                operation="generate_tags",
                error_text=str(exc),
                status_text="Gallery tag generation failed",
                payload={
                    "image_id": image_id,
                    "model_name": model_name,
                },
            )
        except Exception:
            current_app.logger.warning("Failed to log tag generation error", exc_info=True)
        return jsonify({"error": "Could not generate tags right now."}), 500


def list_tags_response(*, db: Any) -> Response:
    return jsonify({"tags": db.list_tags()})


def delete_tag_response(*, tag_name: str, db: Any) -> Response:
    removed_from_images = db.delete_tag(tag_name)
    return jsonify(
        {
            "deleted": True,
            "tag": tag_name,
            "removed_from_images": removed_from_images,
            "tags": db.list_tags(),
        }
    )
