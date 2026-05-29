from __future__ import annotations

from pathlib import Path
from typing import Any

from flask import Response, jsonify

from ..payloads.chat import chat_message_payload, chat_session_payload


def list_chat_sessions_response(*, db: Any) -> Response:
    return jsonify({"items": [chat_session_payload(item) for item in db.list_chat_sessions()]})


def create_chat_session_response(
    *,
    db: Any,
    body: dict[str, Any],
    default_model_name: str | None,
) -> Response | tuple[Response, int]:
    model_name = str(body.get("model_name") or "").strip() or default_model_name
    if not model_name:
        return jsonify({"error": "model_name is required"}), 400
    title = str(body.get("title") or "").strip() or "New chat"
    system_message = str(body.get("system_message") or "")
    session = db.create_chat_session(
        title=title,
        model_name=model_name,
        system_message=system_message,
    )
    return jsonify(chat_session_payload(session)), 201


def update_chat_session_response(
    *,
    db: Any,
    session_id: str,
    body: dict[str, Any],
) -> Response | tuple[Response, int]:
    session = db.get_chat_session(session_id)
    if session is None:
        return jsonify({"error": "Chat session not found"}), 404

    title = body.get("title")
    model_name = body.get("model_name")
    system_message = body.get("system_message")
    if title is not None:
        title = str(title).strip() or session["title"]
    if model_name is not None:
        model_name = str(model_name).strip() or session["model_name"]
    if system_message is not None:
        system_message = str(system_message)
    updated = db.update_chat_session(
        session_id,
        title=title,
        model_name=model_name,
        system_message=system_message,
    )
    if updated is None:
        return jsonify({"error": "Chat session not found"}), 404
    return jsonify(chat_session_payload(updated))


def delete_chat_session_response(
    *,
    db: Any,
    session_id: str,
) -> Response | tuple[Response, int]:
    deleted = db.delete_chat_session(session_id)
    if not deleted:
        return jsonify({"error": "Chat session not found"}), 404
    return jsonify({"deleted": True, "id": session_id})


def list_chat_session_messages_response(
    *,
    db: Any,
    session_id: str,
) -> Response | tuple[Response, int]:
    session = db.get_chat_session(session_id)
    if session is None:
        return jsonify({"error": "Chat session not found"}), 404
    messages = db.list_chat_messages(session_id)
    return jsonify(
        {
            "session": chat_session_payload(session),
            "summary": db.get_chat_session_summary(session_id),
            "items": [chat_message_payload(item) for item in messages],
        }
    )


def message_context_image_response(
    *,
    db: Any,
    message_id: str,
    send_media_file,
) -> Response | tuple[Response, int]:
    message = db.get_chat_message(message_id)
    if message is None:
        return jsonify({"error": "Chat message not found"}), 404
    return _context_image_response(
        item=message,
        send_media_file=send_media_file,
    )


def attachment_context_image_response(
    *,
    db: Any,
    attachment_id: str,
    send_media_file,
) -> Response | tuple[Response, int]:
    attachment = db.get_chat_message_attachment(attachment_id)
    if attachment is None:
        return jsonify({"error": "Chat attachment not found"}), 404
    return _context_image_response(
        item=attachment,
        send_media_file=send_media_file,
    )


def _context_image_response(
    *,
    item: dict[str, Any],
    send_media_file,
) -> Response | tuple[Response, int]:
    context_image_path_raw = str(item.get("context_image_path") or "").strip()
    if not context_image_path_raw:
        return jsonify({"error": "Context image not found"}), 404
    context_image_path = Path(context_image_path_raw)
    if not context_image_path.exists():
        return jsonify({"error": "Context image file could not be read"}), 404
    return send_media_file(
        context_image_path,
        mimetype=str(item.get("context_image_mime_type") or "image/png"),
    )
