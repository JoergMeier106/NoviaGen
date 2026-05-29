from __future__ import annotations

from typing import Any

from .parsing import normalized_string_list


def is_multipart_request(request_obj: Any) -> bool:
    content_type = str(getattr(request_obj, "content_type", "") or "").lower()
    return "multipart/form-data" in content_type


def chat_request_body(request_obj: Any, *, is_multipart: bool) -> dict[str, Any]:
    if is_multipart:
        return request_obj.form.to_dict(flat=True)
    body = request_obj.get_json(silent=True) or {}
    return body if isinstance(body, dict) else {}


def chat_context_image_ids(
    request_obj: Any,
    body: dict[str, Any],
    *,
    is_multipart: bool,
) -> list[str]:
    if is_multipart:
        raw_context_image_ids = [
            *normalized_string_list(request_obj.form.getlist("context_image_ids")),
            *normalized_string_list(request_obj.form.getlist("context_image_id")),
        ]
    else:
        raw_context_image_ids = normalized_string_list(
            body.get("context_image_ids") or body.get("context_image_id")
        )
    return list(dict.fromkeys(raw_context_image_ids))


def chat_uploaded_files(request_obj: Any, *, is_multipart: bool) -> list[Any]:
    if not is_multipart:
        return []

    uploaded_files = [
        file
        for file in request_obj.files.getlist("images")
        if getattr(file, "filename", "")
    ]
    if uploaded_files:
        return uploaded_files

    uploaded_file = request_obj.files.get("image")
    if uploaded_file is not None and uploaded_file.filename:
        return [uploaded_file]
    return []

