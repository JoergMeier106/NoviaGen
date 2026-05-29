from __future__ import annotations

import json
import re
import uuid
from typing import Any

from flask import Response, current_app, jsonify, stream_with_context

from ...chat.streaming import ChatStreamAccumulator
from ...chat.tool_loop import run_chat_tool_loop
from ...generation import (
    OllamaResponseError,
    OllamaUnavailableError,
    strip_inline_thinking,
)
from ..payloads.chat import chat_message_payload, chat_session_payload
from ..requests.parsing import normalized_string_list


def chat_session_stream_response(
    *,
    session_id: str,
    request_obj: Any,
    db: Any,
    worker: Any,
    context_images: Any,
    history_builder: Any,
    error_store: Any,
    chat_context_image_ids,
    chat_request_body,
    chat_uploaded_files,
    is_multipart_request,
    normalized_optional_bool,
    normalized_optional_int,
    mcp_tool_provider: Any,
    ollama_client: Any,
) -> Response | tuple[Response, int]:
    session = db.get_chat_session(session_id)
    if session is None:
        return jsonify({"error": "Chat session not found"}), 404

    is_multipart = is_multipart_request(request_obj)
    body = chat_request_body(request_obj, is_multipart=is_multipart)
    content = str(body.get("content") or "").strip()
    if not content:
        return jsonify({"error": "content is required"}), 400

    model_name = str(body.get("model_name") or session["model_name"]).strip()
    if not model_name:
        return jsonify({"error": "model_name is required"}), 400

    if not bool(worker.stats().get("queue_idle", True)):
        return jsonify({"error": "Chat is paused while the generation queue is busy."}), 409

    try:
        chat_context = _prepare_chat_context(
            request_obj=request_obj,
            body=body,
            context_images=context_images,
            chat_context_image_ids=chat_context_image_ids,
            chat_uploaded_files=chat_uploaded_files,
            is_multipart=is_multipart,
        )
        think = normalized_optional_bool(body.get("think"))
        context_window = normalized_optional_int(body.get("context_window"))
        enabled_tool_ids = normalized_string_list(body.get("enabled_tool_ids"))
    except KeyError as exc:
        return jsonify({"error": str(exc)}), 404
    except FileNotFoundError as exc:
        return jsonify({"error": str(exc)}), 404
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    generator = getattr(worker, "generator", None)
    if generator is None or not hasattr(generator, "stream_chat"):
        chat_context.cleanup_uploads()
        return jsonify({"error": "Chat is not available"}), 503

    try:
        enabled_tool_ids = _resolved_enabled_tool_ids(
            enabled_tool_ids=enabled_tool_ids,
            mcp_tool_provider=mcp_tool_provider,
        )
        _validate_tool_model_support(
            enabled_tool_ids=enabled_tool_ids,
            model_name=model_name,
            ollama_client=ollama_client,
        )
    except OllamaUnavailableError as exc:
        chat_context.cleanup_uploads()
        return jsonify({"error": str(exc)}), 503
    except OllamaResponseError as exc:
        chat_context.cleanup_uploads()
        return jsonify({"error": str(exc)}), 502
    except Exception as exc:
        chat_context.cleanup_uploads()
        return jsonify({"error": str(exc)}), 503

    if model_name != str(session["model_name"]):
        session = db.update_chat_session(session_id, model_name=model_name) or session

    chat_messages = _chat_messages(
        session=session,
        content=content,
        chat_context=chat_context,
        history_builder=history_builder,
    )
    assistant_message_id = str(uuid.uuid4())

    return Response(
        stream_with_context(
            _generate_stream(
                session=session,
                session_id=session_id,
                model_name=model_name,
                content=content,
                chat_messages=chat_messages,
                chat_context=chat_context,
                generator=generator,
                db=db,
                error_store=error_store,
                assistant_message_id=assistant_message_id,
                think=think,
                context_window=context_window,
                enabled_tool_ids=enabled_tool_ids,
                mcp_tool_provider=mcp_tool_provider,
            )
        ),
        mimetype="application/x-ndjson",
    )


def _prepare_chat_context(
    *,
    request_obj: Any,
    body: dict[str, Any],
    context_images: Any,
    chat_context_image_ids,
    chat_uploaded_files,
    is_multipart: bool,
) -> Any:
    context_image_ids = chat_context_image_ids(
        request_obj,
        body,
        is_multipart=is_multipart,
    )
    uploaded_files = chat_uploaded_files(request_obj, is_multipart=is_multipart)
    return context_images.prepare_stream_context(
        context_image_ids=context_image_ids,
        uploaded_files=uploaded_files,
    )


def _chat_messages(
    *,
    session: dict[str, Any],
    content: str,
    chat_context: Any,
    history_builder: Any,
) -> list[dict[str, Any]]:
    user_message_payload: dict[str, Any] = {
        "role": "user",
        "content": content,
    }
    if chat_context.image_bytes:
        user_message_payload["images"] = chat_context.image_bytes
    history = history_builder.build(session)
    return [*history, user_message_payload]


def _resolved_enabled_tool_ids(
    *,
    enabled_tool_ids: list[str],
    mcp_tool_provider: Any,
) -> list[str]:
    if enabled_tool_ids and mcp_tool_provider is None:
        raise ValueError("Chat MCP tools are not configured.")
    if enabled_tool_ids:
        mcp_tool_provider.toolset_for_ids(enabled_tool_ids)
    return enabled_tool_ids


def _validate_tool_model_support(
    *,
    enabled_tool_ids: list[str],
    model_name: str,
    ollama_client: Any,
) -> None:
    if not enabled_tool_ids:
        return
    if ollama_client is None:
        raise OllamaUnavailableError("Could not validate Ollama tool support.")
    show_payload = ollama_client.show_model(model_name)
    capabilities = {
        str(item).strip().lower()
        for item in show_payload.get("capabilities", [])
        if str(item).strip()
    }
    if "tools" not in capabilities:
        raise ValueError("Selected Ollama model does not support tools.")


def _generate_stream(
    *,
    session: dict[str, Any],
    session_id: str,
    model_name: str,
    content: str,
    chat_messages: list[dict[str, Any]],
    chat_context: Any,
    generator: Any,
    db: Any,
    error_store: Any,
    assistant_message_id: str,
    think: bool | None,
    context_window: int | None,
    enabled_tool_ids: list[str],
    mcp_tool_provider: Any,
):
    stream_accumulator = ChatStreamAccumulator()
    final_chunk: dict[str, Any] = {}
    started = False
    try:
        if enabled_tool_ids:
            yield from _generate_tool_stream(
                session=session,
                session_id=session_id,
                model_name=model_name,
                content=content,
                chat_messages=chat_messages,
                chat_context=chat_context,
                generator=generator,
                db=db,
                assistant_message_id=assistant_message_id,
                think=think,
                context_window=context_window,
                enabled_tool_ids=enabled_tool_ids,
                mcp_tool_provider=mcp_tool_provider,
            )
            return
        for chunk in generator.stream_chat(
            model=model_name,
            messages=chat_messages,
            think=think,
            context_window=context_window,
        ):
            if not started:
                started = True
                yield _json_line(
                    {
                        "type": "message_start",
                        "message_id": assistant_message_id,
                        "session_id": session_id,
                        "model_name": model_name,
                    }
                )
            yield from _stream_chat_chunk(
                chunk=chunk,
                stream_accumulator=stream_accumulator,
                assistant_message_id=assistant_message_id,
            )
            if bool(chunk.get("done")):
                final_chunk = chunk

        yield _json_line(
            _persist_completed_stream(
                session=session,
                session_id=session_id,
                model_name=model_name,
                content=content,
                assistant_message_id=assistant_message_id,
                chat_context=chat_context,
                stream_accumulator=stream_accumulator,
                final_chunk=final_chunk,
                generator=generator,
                db=db,
                context_window=context_window,
            )
        )
    except OllamaUnavailableError as exc:
        chat_context.cleanup_uploads()
        _log_chat_stream_error(
            error_store=error_store,
            session_id=session_id,
            model_name=model_name,
            content=content,
            message_attachments=chat_context.message_attachments,
            think=think,
            context_window=context_window,
            error_text=str(exc),
            status_text="Ollama unavailable while streaming chat",
        )
        yield _json_line({"type": "error", "error": str(exc), "status": 503})
    except (OllamaResponseError, ValueError, FileNotFoundError) as exc:
        chat_context.cleanup_uploads()
        _log_chat_stream_error(
            error_store=error_store,
            session_id=session_id,
            model_name=model_name,
            content=content,
            message_attachments=chat_context.message_attachments,
            think=think,
            context_window=context_window,
            error_text=str(exc),
            status_text="Chat response parsing or model response failed",
        )
        yield _json_line({"type": "error", "error": str(exc), "status": 502})
    except Exception as exc:
        chat_context.cleanup_uploads()
        current_app.logger.exception("Failed to stream chat session %s", session_id)
        _log_chat_stream_error(
            error_store=error_store,
            session_id=session_id,
            model_name=model_name,
            content=content,
            message_attachments=chat_context.message_attachments,
            think=think,
            context_window=context_window,
            error_text=str(exc),
            status_text="Unexpected chat streaming failure",
        )
        yield _json_line({"type": "error", "error": str(exc), "status": 500})


def _generate_tool_stream(
    *,
    session: dict[str, Any],
    session_id: str,
    model_name: str,
    content: str,
    chat_messages: list[dict[str, Any]],
    chat_context: Any,
    generator: Any,
    db: Any,
    assistant_message_id: str,
    think: bool | None,
    context_window: int | None,
    enabled_tool_ids: list[str],
    mcp_tool_provider: Any,
):
    yield _json_line(
        {
            "type": "message_start",
            "message_id": assistant_message_id,
            "session_id": session_id,
            "model_name": model_name,
        }
    )

    def status_callback(event: dict[str, Any]) -> None:
        events.append(dict(event))

    events: list[dict[str, Any]] = []
    toolset = mcp_tool_provider.toolset_for_ids(enabled_tool_ids)
    result = run_chat_tool_loop(
        generator=generator,
        model=model_name,
        messages=chat_messages,
        tool_provider=mcp_tool_provider,
        toolset=toolset,
        think=think,
        context_window=context_window,
        max_steps=mcp_tool_provider.max_loop_steps(),
        status_callback=status_callback,
    )
    for event in events:
        yield _json_line(event)
    if result.thinking:
        yield _json_line(
            {
                "type": "thinking_delta",
                "message_id": assistant_message_id,
                "delta": result.thinking,
            }
        )
    yield _json_line(
        {
            "type": "content_delta",
            "message_id": assistant_message_id,
            "delta": result.content,
        }
    )
    accumulator = ChatStreamAccumulator()
    accumulator.apply_message(
        {
            "thinking": result.thinking or "",
            "content": result.content,
        }
    )
    accumulator.tool_traces = list(result.tool_traces)
    yield _json_line(
        _persist_completed_stream(
            session=session,
            session_id=session_id,
            model_name=model_name,
            content=content,
            assistant_message_id=assistant_message_id,
            chat_context=chat_context,
            stream_accumulator=accumulator,
            final_chunk=result.final_chunk,
            generator=generator,
            db=db,
            context_window=context_window,
        )
    )


def _stream_chat_chunk(
    *,
    chunk: dict[str, Any],
    stream_accumulator: ChatStreamAccumulator,
    assistant_message_id: str,
):
    message = chunk.get("message")
    if not isinstance(message, dict):
        message = {}
    delta = stream_accumulator.apply_message(message)
    for thinking_delta in delta.thinking_deltas:
        yield _json_line(
            {
                "type": "thinking_delta",
                "message_id": assistant_message_id,
                "delta": thinking_delta,
            }
        )
    if delta.content:
        yield _json_line(
            {
                "type": "content_delta",
                "message_id": assistant_message_id,
                "delta": delta.content,
            }
        )


def _persist_completed_stream(
    *,
    session: dict[str, Any],
    session_id: str,
    model_name: str,
    content: str,
    assistant_message_id: str,
    chat_context: Any,
    stream_accumulator: ChatStreamAccumulator,
    final_chunk: dict[str, Any],
    generator: Any,
    db: Any,
    context_window: int | None,
) -> dict[str, Any]:
    assistant_content = stream_accumulator.content.strip()
    assistant_thinking = stream_accumulator.thinking.strip() or None
    if not assistant_content:
        raise OllamaResponseError("Ollama returned an empty chat response")

    user_message = db.create_chat_message(
        session_id=session_id,
        role="user",
        content=content,
        model_name=model_name,
        attachments=chat_context.message_attachments,
    )
    updated_title = _updated_session_title(
        session=session,
        session_id=session_id,
        model_name=model_name,
        content=content,
        generator=generator,
        db=db,
        context_window=context_window,
    )
    assistant_message = db.create_chat_message(
        session_id=session_id,
        role="assistant",
        content=assistant_content,
        thinking=assistant_thinking,
        tool_traces=getattr(stream_accumulator, "tool_traces", None),
        model_name=model_name,
        total_duration_ns=_optional_int(final_chunk.get("total_duration")),
        load_duration_ns=_optional_int(final_chunk.get("load_duration")),
        prompt_eval_count=_optional_int(final_chunk.get("prompt_eval_count")),
        prompt_eval_duration_ns=_optional_int(final_chunk.get("prompt_eval_duration")),
        eval_count=_optional_int(final_chunk.get("eval_count")),
        eval_duration_ns=_optional_int(final_chunk.get("eval_duration")),
        message_id=assistant_message_id,
    )
    return {
        "type": "done",
        "message_id": assistant_message_id,
        "session": chat_session_payload(db.get_chat_session(session_id) or session),
        "user_message": chat_message_payload(user_message),
        "assistant_message": chat_message_payload(assistant_message),
    }


def _updated_session_title(
    *,
    session: dict[str, Any],
    session_id: str,
    model_name: str,
    content: str,
    generator: Any,
    db: Any,
    context_window: int | None,
) -> str:
    existing_message_count = int(session.get("message_count") or 0)
    updated_title = str(session["title"])
    if updated_title != "New chat" or existing_message_count != 0:
        return updated_title

    generated_title = ""
    if hasattr(generator, "generate_chat_title"):
        try:
            generated_title = _sanitize_generated_chat_title(
                generator.generate_chat_title(
                    model=model_name,
                    user_message=content,
                    system_message=str(session.get("system_message") or ""),
                    context_window=context_window,
                )
            )
        except Exception:
            current_app.logger.exception(
                "Failed to generate chat title for session %s",
                session_id,
            )
    updated_title = generated_title or _title_fallback_from_message(content)
    session_update = db.update_chat_session(
        session_id,
        title=updated_title or "New chat",
    )
    if session_update is not None:
        updated_title = str(session_update["title"])
    return updated_title


def _optional_int(value: Any) -> int | None:
    return int(value) if isinstance(value, int) else None


def _json_line(payload: dict[str, Any]) -> str:
    return f"{json.dumps(payload, ensure_ascii=True)}\n"


def _log_chat_stream_error(
    *,
    error_store: Any,
    session_id: str,
    model_name: str,
    content: str,
    message_attachments: list[dict[str, Any]],
    think: bool | None,
    context_window: int | None,
    error_text: str,
    status_text: str,
) -> None:
    error_store.log_chat_error(
        session_id=session_id,
        model_name=model_name,
        content=content,
        attachments=message_attachments,
        think=think,
        context_window=context_window,
        error_text=error_text,
        status_text=status_text,
    )


def _title_fallback_from_message(content: str) -> str:
    updated_title = strip_inline_thinking(content).replace("\n", " ").strip()
    if len(updated_title) > 60:
        updated_title = f"{updated_title[:57].rstrip()}..."
    return updated_title or "New chat"


def _sanitize_generated_chat_title(title: str) -> str:
    cleaned = strip_inline_thinking(title)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    cleaned = cleaned.strip("'\"`*#-:;,.!?()[]{} ")
    if not cleaned:
        return ""
    words = cleaned.split(" ")
    if len(words) > 6:
        cleaned = " ".join(words[:6]).strip()
    if len(cleaned) > 60:
        cleaned = cleaned[:60].rstrip()
    return cleaned
