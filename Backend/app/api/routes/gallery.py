from __future__ import annotations

from flask import Response, request

from .blueprint import api
from ..responses.files import send_media_file as _send_media_file
from ..responses.gallery import (
    delete_tag_response as _delete_tag_response,
    generate_image_tags_response as _generate_image_tags_response,
    get_image_response as _get_image_response,
    import_gallery_images_response as _import_gallery_images_response,
    latest_temp_image_response as _latest_temp_image_response,
    list_gallery_filters_response as _list_gallery_filters_response,
    list_gallery_images_response as _list_gallery_images_response,
    list_stored_images_response as _list_stored_images_response,
    list_tags_response as _list_tags_response,
    set_image_rating_response as _set_image_rating_response,
    set_image_tags_response as _set_image_tags_response,
    store_image_response as _store_image_response,
)
from ..payloads.media import (
    ensure_video_poster as _ensure_video_poster,
    image_payload as _image_payload,
)
from ..responses.media import (
    delete_media_response as _delete_media_response,
    media_file_response as _media_file_response,
    poster_file_response as _poster_file_response,
    restore_media_response as _restore_media_response,
    thumbnail_file_response as _thumbnail_file_response,
)
from .context import (
    db as _db,
    errors as _errors,
    image_importer as _image_importer,
    worker as _worker,
)
from ..common.validation import validate_tags as _validate_tags


@api.post("/api/images/import")
def import_gallery_images() -> Response:
    return _import_gallery_images_response(
        request_obj=request,
        image_importer=_image_importer(),
        image_payload=_image_payload,
    )


@api.get("/api/images")
def list_gallery_images() -> Response:
    return _list_gallery_images_response(
        request_args=request.args,
        db=_db(),
        image_payload=_image_payload,
    )


@api.get("/api/images/filters")
def list_gallery_filters() -> Response:
    return _list_gallery_filters_response(request_args=request.args, db=_db())


@api.post("/api/images/<image_id>/store")
def store_image(image_id: str) -> Response:
    return _store_image_response(
        image_id=image_id,
        db=_db(),
        image_payload=_image_payload,
    )


@api.get("/api/images/stored")
def list_stored_images() -> Response:
    return _list_stored_images_response(
        request_args=request.args,
        db=_db(),
        image_payload=_image_payload,
    )


@api.get("/api/images/latest-temp")
def get_latest_temp_image() -> Response:
    return _latest_temp_image_response(db=_db(), image_payload=_image_payload)


@api.get("/api/images/<image_id>")
def get_image(image_id: str) -> Response:
    return _get_image_response(
        image_id=image_id,
        db=_db(),
        image_payload=_image_payload,
    )


@api.post("/api/images/<image_id>/rating")
def set_image_rating(image_id: str) -> Response:
    return _set_image_rating_response(
        image_id=image_id,
        body=request.get_json(silent=True) or {},
        db=_db(),
        image_payload=_image_payload,
    )


@api.post("/api/images/<image_id>/tags")
def set_image_tags(image_id: str) -> Response:
    return _set_image_tags_response(
        image_id=image_id,
        body=request.get_json(silent=True) or {},
        db=_db(),
        image_payload=_image_payload,
        validate_tags=_validate_tags,
    )


@api.post("/api/images/<image_id>/generate-tags")
def generate_image_tags(image_id: str) -> Response:
    return _generate_image_tags_response(
        image_id=image_id,
        body=request.get_json(silent=True) or {},
        db=_db(),
        generator=_worker().generator,
        error_store=_errors(),
        image_payload=_image_payload,
    )


@api.get("/api/tags")
def list_tags() -> Response:
    return _list_tags_response(db=_db())


@api.delete("/api/tags/<path:tag_name>")
def delete_tag(tag_name: str) -> Response:
    return _delete_tag_response(tag_name=tag_name, db=_db())


@api.delete("/api/images/<image_id>")
def delete_image(image_id: str) -> Response:
    return _delete_media_response(db=_db(), worker=_worker(), image_id=image_id)


@api.post("/api/images/<image_id>/delete")
def delete_image_post(image_id: str) -> Response:
    return _delete_media_response(db=_db(), worker=_worker(), image_id=image_id)


@api.post("/api/images/<image_id>/restore")
def restore_image(image_id: str) -> Response:
    return _restore_media_response(
        db=_db(),
        image_payload=_image_payload,
        image_id=image_id,
    )


@api.get("/api/files/<image_id>")
def get_file(image_id: str):
    return _media_file_response(
        db=_db(),
        image_id=image_id,
        send_media_file=_send_media_file,
    )


@api.get("/api/files/<image_id>/poster")
def get_poster_file(image_id: str):
    return _poster_file_response(
        db=_db(),
        image_id=image_id,
        ensure_video_poster=_ensure_video_poster,
        send_media_file=_send_media_file,
    )


@api.get("/api/files/<image_id>/thumbnail")
def get_thumbnail_file(image_id: str):
    return _thumbnail_file_response(
        db=_db(),
        image_id=image_id,
        ensure_video_poster=_ensure_video_poster,
        send_media_file=_send_media_file,
    )
