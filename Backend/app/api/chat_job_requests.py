from __future__ import annotations

from typing import Any, Mapping

from .job_request_errors import JobRequestError


def chat_message_payload(
    *,
    body: Mapping[str, Any],
    request_obj: Any,
    is_multipart: bool,
    db: Any,
    context_images: Any,
    chat_context_image_ids,
    chat_uploaded_files,
    normalized_optional_bool,
    normalized_optional_int,
) -> dict[str, Any]:
    session_id = str(body.get("session_id") or "").strip()
    if not session_id:
        raise JobRequestError("session_id is required")
    session = db.get_chat_session(session_id)
    if session is None:
        raise JobRequestError("Chat session not found", status_code=404)

    content = str(body.get("content") or "").strip()
    if not content:
        raise JobRequestError("content is required")

    model_name = str(body.get("model_name") or session["model_name"]).strip()
    if not model_name:
        raise JobRequestError("model_name is required")

    try:
        context_image_ids = chat_context_image_ids(
            request_obj,
            body,
            is_multipart=is_multipart,
        )
        uploaded_files = chat_uploaded_files(request_obj, is_multipart=is_multipart)
        chat_context = context_images.prepare_job_context(
            context_image_ids=context_image_ids,
            uploaded_files=uploaded_files,
        )
        think = normalized_optional_bool(body.get("think"))
        context_window = normalized_optional_int(body.get("context_window"))
    except (KeyError, FileNotFoundError) as exc:
        raise JobRequestError(str(exc), status_code=404) from exc
    except ValueError as exc:
        raise JobRequestError(str(exc)) from exc

    return {
        "session_id": session_id,
        "content": content,
        "model_name": model_name,
        "context_image_ids": context_image_ids,
        "attachments": chat_context.message_attachments,
        "context_window": context_window,
        "think": think,
    }
