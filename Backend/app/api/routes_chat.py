from __future__ import annotations

from flask import Response, request

from .blueprint import api
from .chat_requests import (
    chat_context_image_ids as _chat_context_image_ids,
    chat_request_body as _chat_request_body,
    chat_uploaded_files as _chat_uploaded_files,
    is_multipart_request as _is_multipart_request,
)
from .chat_session_responses import (
    attachment_context_image_response as _attachment_context_image_response,
    create_chat_session_response as _create_chat_session_response,
    delete_chat_session_response as _delete_chat_session_response,
    list_chat_session_messages_response as _list_chat_session_messages_response,
    list_chat_sessions_response as _list_chat_sessions_response,
    message_context_image_response as _message_context_image_response,
    update_chat_session_response as _update_chat_session_response,
)
from .chat_stream_response import (
    chat_session_stream_response as _chat_session_stream_response,
)
from .file_responses import send_media_file as _send_media_file
from .route_context import (
    chat_context_images as _chat_context_images,
    chat_history_builder as _chat_history_builder,
    db as _db,
    errors as _errors,
    normalized_optional_bool as _normalized_optional_bool,
    normalized_optional_int as _normalized_optional_int,
    worker as _worker,
)
from .route_helpers import ollama_client as _ollama_client


@api.get("/api/chat/sessions")
def list_chat_sessions() -> Response:
    return _list_chat_sessions_response(db=_db())


@api.post("/api/chat/sessions")
def create_chat_session() -> Response:
    return _create_chat_session_response(
        db=_db(),
        body=request.get_json(silent=True) or {},
        default_model_name=_ollama_client().select_default_model(),
    )


@api.patch("/api/chat/sessions/<session_id>")
def update_chat_session(session_id: str) -> Response:
    return _update_chat_session_response(
        db=_db(),
        session_id=session_id,
        body=request.get_json(silent=True) or {},
    )


@api.delete("/api/chat/sessions/<session_id>")
def delete_chat_session(session_id: str) -> Response:
    return _delete_chat_session_response(db=_db(), session_id=session_id)


@api.get("/api/chat/sessions/<session_id>/messages")
def list_chat_session_messages(session_id: str) -> Response:
    return _list_chat_session_messages_response(db=_db(), session_id=session_id)


@api.get("/api/chat/messages/<message_id>/context-image")
def get_chat_message_context_image(message_id: str) -> Response:
    return _message_context_image_response(
        db=_db(),
        message_id=message_id,
        send_media_file=_send_media_file,
    )


@api.get("/api/chat/attachments/<attachment_id>/context-image")
def get_chat_attachment_context_image(attachment_id: str) -> Response:
    return _attachment_context_image_response(
        db=_db(),
        attachment_id=attachment_id,
        send_media_file=_send_media_file,
    )


@api.post("/api/chat/sessions/<session_id>/stream")
def stream_chat_session_message(session_id: str) -> Response:
    return _chat_session_stream_response(
        session_id=session_id,
        request_obj=request,
        db=_db(),
        worker=_worker(),
        context_images=_chat_context_images(),
        history_builder=_chat_history_builder(),
        error_store=_errors(),
        chat_context_image_ids=_chat_context_image_ids,
        chat_request_body=_chat_request_body,
        chat_uploaded_files=_chat_uploaded_files,
        is_multipart_request=_is_multipart_request,
        normalized_optional_bool=_normalized_optional_bool,
        normalized_optional_int=_normalized_optional_int,
    )
