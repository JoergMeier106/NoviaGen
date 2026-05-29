from __future__ import annotations

from typing import Any

from flask import current_app, url_for

from .media import image_payload


def db():
    return current_app.extensions["db"]


def chat_session_payload(session: dict[str, Any]) -> dict[str, Any]:
    preview = str(session.get("last_message_content") or "").replace("\n", " ").strip()
    if len(preview) > 140:
        preview = f"{preview[:137].rstrip()}..."
    return {
        "id": session["id"],
        "title": session["title"],
        "model_name": session["model_name"],
        "system_message": str(session.get("system_message") or ""),
        "created_at": session["created_at"],
        "updated_at": session["updated_at"],
        "message_count": int(session.get("message_count") or 0),
        "last_message_preview": preview,
        "last_message_role": session.get("last_message_role"),
        "last_message_at": session.get("last_message_at"),
    }


def chat_message_payload(message: dict[str, Any]) -> dict[str, Any]:
    attachment_payloads = _attachment_payloads(message)
    payload = {
        "id": message["id"],
        "session_id": message["session_id"],
        "role": message["role"],
        "content": message["content"],
        "thinking": message.get("thinking"),
        "context_image_id": message.get("context_image_id"),
        "context_image_url": None,
        "attachments": attachment_payloads,
        "model_name": message.get("model_name"),
        "total_duration_ns": message.get("total_duration_ns"),
        "load_duration_ns": message.get("load_duration_ns"),
        "prompt_eval_count": message.get("prompt_eval_count"),
        "prompt_eval_duration_ns": message.get("prompt_eval_duration_ns"),
        "eval_count": message.get("eval_count"),
        "eval_duration_ns": message.get("eval_duration_ns"),
        "summarized_into_memory": bool(message.get("summarized_into_memory")),
        "created_at": message["created_at"],
    }
    if attachment_payloads:
        _apply_first_attachment_context(payload, attachment_payloads[0])
        return payload
    _apply_legacy_context_image(payload, message)
    return payload


def chat_message_attachment_payload(attachment: dict[str, Any]) -> dict[str, Any]:
    payload = {
        "id": attachment.get("id"),
        "message_id": attachment.get("message_id"),
        "attachment_index": int(attachment.get("attachment_index") or 0),
        "context_image_id": attachment.get("context_image_id"),
        "context_image_url": None,
    }
    context_image_id = str(attachment.get("context_image_id") or "").strip()
    if context_image_id:
        context_image = db().get_image(context_image_id)
        if context_image is not None:
            payload["context_image"] = image_payload(context_image)
            payload["context_image_url"] = payload["context_image"]["preview_url"]
        return payload

    attachment_id = str(attachment.get("id") or "").strip()
    if attachment_id and str(attachment.get("context_image_path") or "").strip():
        payload["context_image_url"] = url_for(
            "api.get_chat_attachment_context_image",
            attachment_id=attachment_id,
            _external=True,
        )
    return payload


def _attachment_payloads(message: dict[str, Any]) -> list[dict[str, Any]]:
    attachments = message.get("attachments")
    if not isinstance(attachments, list):
        return []
    return [
        chat_message_attachment_payload(item)
        for item in attachments
        if isinstance(item, dict)
    ]


def _apply_first_attachment_context(
    payload: dict[str, Any],
    first_attachment: dict[str, Any],
) -> None:
    payload["context_image_id"] = first_attachment.get("context_image_id")
    payload["context_image"] = first_attachment.get("context_image")
    payload["context_image_url"] = first_attachment.get("context_image_url")


def _apply_legacy_context_image(
    payload: dict[str, Any],
    message: dict[str, Any],
) -> None:
    context_image_id = str(message.get("context_image_id") or "").strip()
    if context_image_id:
        context_image = db().get_image(context_image_id)
        if context_image is not None:
            payload["context_image"] = image_payload(context_image)
            payload["context_image_url"] = payload["context_image"]["preview_url"]
    elif str(message.get("context_image_path") or "").strip():
        payload["context_image_url"] = url_for(
            "api.get_chat_message_context_image",
            message_id=message["id"],
            _external=True,
        )

