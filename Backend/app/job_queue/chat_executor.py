from __future__ import annotations

import base64
import time
import uuid
from pathlib import Path
from typing import Any
from collections.abc import Callable

from ..chat.streaming import ChatStreamAccumulator


class ChatMessageJobExecutor:
    def __init__(self, *, db: Any, generator: Any) -> None:
        self._db = db
        self._generator = generator

    def run(
        self,
        job: Any,
        *,
        cancel_requested: Callable[[str], bool],
        raise_if_cancel_requested: Callable[[str], None],
    ) -> dict[str, Any]:
        session_id = str(job.payload.get("session_id", "")).strip()
        if not session_id:
            raise ValueError("session_id is required")
        session = self._db.get_chat_session(session_id)
        if session is None:
            raise KeyError(f"Chat session not found: {session_id}")

        model_name = str(
            job.payload.get("model_name") or session.get("model_name") or ""
        ).strip()
        if not model_name:
            raise ValueError("model_name is required")

        content = str(job.payload.get("content") or "").strip()
        if not content:
            raise ValueError("content is required")

        if model_name != str(session.get("model_name") or "").strip():
            updated_session = self._db.update_chat_session(
                session_id,
                model_name=model_name,
            )
            if updated_session is not None:
                session = updated_session

        had_messages = len(self._db.list_chat_messages(session_id)) > 0
        context_window = (
            int(job.payload["context_window"])
            if job.payload.get("context_window") is not None
            else None
        )
        prepared_context = self._prepare_context(job.payload)
        user_message_payload: dict[str, object] = {
            "role": "user",
            "content": content,
        }
        if prepared_context["image_bytes"]:
            user_message_payload["images"] = prepared_context["image_bytes"]

        chat_messages = [
            *self._build_chat_history_messages(session=session),
            user_message_payload,
        ]
        assistant_message_id = str(uuid.uuid4())
        stream_result = self._stream_response(
            job=job,
            model_name=model_name,
            chat_messages=chat_messages,
            assistant_message_id=assistant_message_id,
            context_window=context_window,
            cancel_requested=cancel_requested,
            raise_if_cancel_requested=raise_if_cancel_requested,
        )

        user_message = self._db.create_chat_message(
            session_id=session_id,
            role="user",
            content=content,
            model_name=model_name,
            attachments=prepared_context["message_attachments"],
        )
        assistant_message = self._create_assistant_message(
            session_id=session_id,
            model_name=model_name,
            assistant_message_id=assistant_message_id,
            assistant_content=stream_result["content"],
            assistant_thinking=stream_result["thinking"],
            final_chunk=stream_result["final_chunk"],
        )
        session = self._refresh_session_title(
            session=session,
            session_id=session_id,
            model_name=model_name,
            content=content,
            context_window=context_window,
            had_messages=had_messages,
        )

        return {
            "session": session,
            "user_message": user_message,
            "assistant_message": assistant_message,
            "streaming": False,
        }

    def _prepare_context(self, payload: dict[str, Any]) -> dict[str, Any]:
        message_attachments: list[dict[str, Any]] = []
        image_bytes: list[str] = []

        for image_id in payload.get("context_image_ids", []):
            normalized_image_id = str(image_id).strip()
            if not normalized_image_id:
                continue
            context_image = self._db.get_image(normalized_image_id)
            if context_image is None:
                raise KeyError(f"Unknown context image_id: {normalized_image_id}")
            encoded = self._read_base64_image(Path(str(context_image["file_path"])))
            if encoded:
                image_bytes.append(encoded)
                message_attachments.append({"context_image_id": normalized_image_id})

        raw_attachments = payload.get("attachments")
        if isinstance(raw_attachments, list):
            for attachment in raw_attachments:
                if not isinstance(attachment, dict):
                    continue
                context_image_path = str(
                    attachment.get("context_image_path") or ""
                ).strip()
                if not context_image_path:
                    continue
                encoded = self._read_base64_image(Path(context_image_path))
                if encoded:
                    image_bytes.append(encoded)
                    message_attachments.append(
                        {
                            "context_image_path": context_image_path,
                            "context_image_mime_type": str(
                                attachment.get("context_image_mime_type") or "image/png"
                            ),
                        }
                    )

        return {
            "message_attachments": message_attachments,
            "image_bytes": image_bytes,
        }

    def _stream_response(
        self,
        *,
        job: Any,
        model_name: str,
        chat_messages: list[dict[str, object]],
        assistant_message_id: str,
        context_window: int | None,
        cancel_requested: Callable[[str], bool],
        raise_if_cancel_requested: Callable[[str], None],
    ) -> dict[str, Any]:
        session_id = str(job.payload.get("session_id") or "")
        stream_accumulator = ChatStreamAccumulator()
        final_chunk: dict[str, Any] = {}
        last_stream_sync_at = 0.0
        last_stream_thinking_length = 0
        last_stream_content_length = 0

        self._sync_stream_state(
            job_id=job.job_id,
            progress=0.2,
            status_text="Generating response",
            session_id=session_id,
            assistant_message_id=assistant_message_id,
            thinking_text="",
            content_text="",
        )

        for chunk in self._generator.stream_chat(
            model=model_name,
            messages=chat_messages,
            think=job.payload.get("think"),
            context_window=context_window,
            cancel_requested=lambda: cancel_requested(job.job_id),
        ):
            raise_if_cancel_requested(job.job_id)
            message_payload = chunk.get("message")
            if not isinstance(message_payload, dict):
                message_payload = {}

            stream_accumulator.apply_message(message_payload)
            current_thinking = stream_accumulator.thinking
            current_content = stream_accumulator.content
            if (
                len(current_thinking) != last_stream_thinking_length
                or len(current_content) != last_stream_content_length
            ):
                last_stream_sync_at = self._throttled_sync_stream_state(
                    job_id=job.job_id,
                    progress=0.2,
                    status_text="Generating response",
                    session_id=session_id,
                    assistant_message_id=assistant_message_id,
                    thinking_text=current_thinking,
                    content_text=current_content,
                    last_stream_sync_at=last_stream_sync_at,
                    last_stream_thinking_length=last_stream_thinking_length,
                    last_stream_content_length=last_stream_content_length,
                )
                last_stream_thinking_length = len(current_thinking)
                last_stream_content_length = len(current_content)

            if bool(chunk.get("done")):
                final_chunk = chunk

        raise_if_cancel_requested(job.job_id)
        assistant_content = stream_accumulator.content.strip()
        assistant_thinking = stream_accumulator.thinking.strip() or None
        if not assistant_content and not assistant_thinking:
            raise RuntimeError("Chat response was empty")

        self._sync_stream_state(
            job_id=job.job_id,
            progress=0.92,
            status_text="Saving chat messages",
            session_id=session_id,
            assistant_message_id=assistant_message_id,
            thinking_text=assistant_thinking or "",
            content_text=assistant_content,
        )
        return {
            "content": assistant_content,
            "thinking": assistant_thinking,
            "final_chunk": final_chunk,
        }

    def _throttled_sync_stream_state(
        self,
        *,
        job_id: str,
        progress: float,
        status_text: str,
        session_id: str,
        assistant_message_id: str,
        thinking_text: str,
        content_text: str,
        last_stream_sync_at: float,
        last_stream_thinking_length: int,
        last_stream_content_length: int,
    ) -> float:
        now = time.monotonic()
        if (
            now - last_stream_sync_at < 0.2
            and len(thinking_text) == last_stream_thinking_length
            and len(content_text) == last_stream_content_length
        ):
            return last_stream_sync_at
        self._sync_stream_state(
            job_id=job_id,
            progress=progress,
            status_text=status_text,
            session_id=session_id,
            assistant_message_id=assistant_message_id,
            thinking_text=thinking_text,
            content_text=content_text,
        )
        return now

    def _sync_stream_state(
        self,
        *,
        job_id: str,
        progress: float,
        status_text: str,
        session_id: str,
        assistant_message_id: str,
        thinking_text: str,
        content_text: str,
    ) -> None:
        self._db.update_job(
            job_id,
            status="running",
            progress=progress,
            status_text=status_text,
            result_data={
                "streaming": True,
                "session_id": session_id,
                "assistant_message_id": assistant_message_id,
                "thinking": thinking_text,
                "content": content_text,
            },
        )

    def _create_assistant_message(
        self,
        *,
        session_id: str,
        model_name: str,
        assistant_message_id: str,
        assistant_content: str,
        assistant_thinking: str | None,
        final_chunk: dict[str, Any],
    ) -> dict[str, Any]:
        return self._db.create_chat_message(
            session_id=session_id,
            role="assistant",
            content=assistant_content,
            thinking=assistant_thinking,
            model_name=model_name,
            total_duration_ns=_optional_int(final_chunk.get("total_duration")),
            load_duration_ns=_optional_int(final_chunk.get("load_duration")),
            prompt_eval_count=_optional_int(final_chunk.get("prompt_eval_count")),
            prompt_eval_duration_ns=_optional_int(
                final_chunk.get("prompt_eval_duration")
            ),
            eval_count=_optional_int(final_chunk.get("eval_count")),
            eval_duration_ns=_optional_int(final_chunk.get("eval_duration")),
            message_id=assistant_message_id,
        )

    def _refresh_session_title(
        self,
        *,
        session: dict[str, Any],
        session_id: str,
        model_name: str,
        content: str,
        context_window: int | None,
        had_messages: bool,
    ) -> dict[str, Any]:
        if not had_messages:
            try:
                generated_title = self._generator.generate_chat_title(
                    model=model_name,
                    user_message=content,
                    system_message=str(session.get("system_message") or ""),
                    context_window=context_window,
                ).strip()
            except Exception:
                generated_title = ""
            title = generated_title or content.replace("\n", " ").strip()
            if len(title) > 60:
                title = f"{title[:57].rstrip()}..."
            updated_session = self._db.update_chat_session(session_id, title=title)
            if updated_session is not None:
                session = updated_session
        else:
            refreshed_session = self._db.get_chat_session(session_id)
            if refreshed_session is not None:
                session = refreshed_session

        for session_item in self._db.list_chat_sessions():
            if str(session_item.get("id") or "") == session_id:
                return session_item
        return session

    def _build_chat_history_messages(
        self,
        *,
        session: dict[str, Any],
    ) -> list[dict[str, object]]:
        history: list[dict[str, object]] = []
        system_message = str(session.get("system_message") or "").strip()
        if system_message:
            history.append({"role": "system", "content": system_message})

        for message in self._db.list_chat_messages(str(session["id"])):
            payload: dict[str, object] = {
                "role": str(message.get("role") or "user"),
                "content": str(message.get("content") or ""),
            }
            thinking = str(message.get("thinking") or "").strip()
            if thinking and payload["role"] == "assistant":
                payload["thinking"] = thinking
            if payload["role"] == "user":
                encoded_images = self._encoded_message_images(message)
                if encoded_images:
                    payload["images"] = encoded_images
            history.append(payload)
        return history

    def _encoded_message_images(self, message: dict[str, Any]) -> list[str]:
        encoded_images: list[str] = []
        attachments = message.get("attachments")
        if not isinstance(attachments, list):
            return encoded_images

        for attachment in attachments:
            if not isinstance(attachment, dict):
                continue
            context_image_id = str(attachment.get("context_image_id") or "").strip()
            context_image_path = str(attachment.get("context_image_path") or "").strip()
            try:
                encoded = self._encoded_attachment_image(
                    context_image_id=context_image_id,
                    context_image_path=context_image_path,
                )
            except (FileNotFoundError, OSError):
                continue
            if encoded:
                encoded_images.append(encoded)
        return encoded_images

    def _encoded_attachment_image(
        self,
        *,
        context_image_id: str,
        context_image_path: str,
    ) -> str | None:
        if context_image_id:
            context_image = self._db.get_image(context_image_id)
            if context_image is not None:
                return self._read_base64_image(Path(str(context_image["file_path"])))
        if context_image_path:
            return self._read_base64_image(Path(context_image_path))
        return None

    @staticmethod
    def _read_base64_image(path: Path) -> str | None:
        if not path.exists():
            raise FileNotFoundError(str(path))
        raw_bytes = path.read_bytes()
        if not raw_bytes:
            return None
        return base64.b64encode(raw_bytes).decode("ascii")


def _optional_int(value: Any) -> int | None:
    return int(value) if value is not None else None

