from __future__ import annotations

import json
from typing import Any

from flask import current_app

from .chat import chat_message_payload, chat_session_payload
from .media import image_payload


def db():
    return current_app.extensions["db"]


def job_payload(
    job: dict[str, Any],
    *,
    include_result: bool = False,
) -> dict[str, Any]:
    payload = {
        "job_id": job["id"],
        "type": job["type"],
        "parent_job_id": job.get("parent_job_id"),
        "chain_step_id": job.get("chain_step_id"),
        "status": job["status"],
        "progress": job["progress"],
        "status_text": job["status_text"],
        "error": job["error"],
        "cancel_requested": bool(job.get("cancel_requested")),
        "cancel_requested_at": job.get("cancel_requested_at"),
        "cancelled_at": job.get("cancelled_at"),
        "started_at": job.get("started_at"),
        "created_at": job["created_at"],
        "updated_at": job["updated_at"],
        "payload": _decoded_payload(job.get("payload_json")),
    }
    if include_result:
        _attach_result_media(payload, job)
        _attach_result_data(payload, job)
        _attach_chain_state(payload, job)
    return payload


def _decoded_payload(raw_payload: Any) -> dict[str, Any]:
    if isinstance(raw_payload, dict):
        return raw_payload
    if not isinstance(raw_payload, str) or not raw_payload.strip():
        return {}
    try:
        parsed_payload = json.loads(raw_payload)
    except (TypeError, ValueError, json.JSONDecodeError):
        return {}
    return parsed_payload if isinstance(parsed_payload, dict) else {}


def _attach_result_media(payload: dict[str, Any], job: dict[str, Any]) -> None:
    if not job.get("result_image_id"):
        return
    image = db().get_image(job["result_image_id"])
    if image is not None:
        payload["result"] = image_payload(image)


def _attach_result_data(payload: dict[str, Any], job: dict[str, Any]) -> None:
    result_data = _decoded_result_data(job.get("result_json"))
    if result_data is None:
        return
    if str(job.get("type") or "") == "chain":
        return
    if str(job.get("type") or "") == "chat_message":
        payload["result_data"] = _chat_result_payload(result_data)
    else:
        payload["result_data"] = result_data


def _attach_chain_state(payload: dict[str, Any], job: dict[str, Any]) -> None:
    if str(job.get("type") or "").strip() != "chain":
        return
    chain_state = _decoded_result_data(job.get("result_json"))
    if chain_state is None:
        return
    payload["chain"] = chain_state


def _decoded_result_data(raw_result: Any) -> dict[str, Any] | None:
    if not raw_result:
        return None
    try:
        parsed = json.loads(str(raw_result or ""))
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    return parsed if isinstance(parsed, dict) else None


def _chat_result_payload(result_data: dict[str, Any]) -> dict[str, Any]:
    session = result_data.get("session")
    user_message = result_data.get("user_message")
    assistant_message = result_data.get("assistant_message")
    return {
        "streaming": bool(result_data.get("streaming")),
        "session_id": str(result_data.get("session_id") or ""),
        "assistant_message_id": str(result_data.get("assistant_message_id") or ""),
        "thinking": str(result_data.get("thinking") or ""),
        "content": str(result_data.get("content") or ""),
        "tool_traces": _tool_trace_payloads(result_data.get("tool_traces")),
        "session": chat_session_payload(session) if isinstance(session, dict) else None,
        "user_message": (
            chat_message_payload(user_message)
            if isinstance(user_message, dict)
            else None
        ),
        "assistant_message": (
            chat_message_payload(assistant_message)
            if isinstance(assistant_message, dict)
            else None
        ),
    }


def _tool_trace_payloads(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []
    traces: list[dict[str, str]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        content = str(item.get("content") or "").strip()
        if not content:
            continue
        trace = {"content": content}
        tool_id = str(item.get("tool_id") or "").strip()
        tool_name = str(item.get("tool_name") or "").strip()
        if tool_id:
            trace["tool_id"] = tool_id
        if tool_name:
            trace["tool_name"] = tool_name
        traces.append(trace)
    return traces
