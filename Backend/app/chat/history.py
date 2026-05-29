from __future__ import annotations

from typing import Any

from .context_images import ChatContextImageService


DEFAULT_CHAT_SUMMARY_KEEP_RECENT_MESSAGES = 10
DEFAULT_CHAT_SUMMARY_MAX_PENDING_CHARS = 18000


class ChatHistoryBuilder:
    def __init__(
        self,
        *,
        db: Any,
        generator: Any,
        context_images: ChatContextImageService,
        keep_recent_messages: int = DEFAULT_CHAT_SUMMARY_KEEP_RECENT_MESSAGES,
        max_pending_chars: int = DEFAULT_CHAT_SUMMARY_MAX_PENDING_CHARS,
    ) -> None:
        self._db = db
        self._generator = generator
        self._context_images = context_images
        self._keep_recent_messages = max(4, int(keep_recent_messages))
        self._max_pending_chars = max(4000, int(max_pending_chars))

    def build(self, session: dict[str, Any]) -> list[dict[str, object]]:
        summary = self._ensure_summary(session)
        history: list[dict[str, object]] = []
        self._append_system_message(history, session)
        self._append_summary(history, summary)

        for message in self._db.list_chat_messages(str(session["id"])):
            if bool(message.get("summarized_into_memory")):
                continue
            history.append(self._message_payload(message))
        return history

    def _ensure_summary(self, session: dict[str, Any]) -> dict[str, Any] | None:
        summary = self._db.get_chat_session_summary(str(session["id"]))
        pending_messages = self._db.list_unsummarized_chat_messages(str(session["id"]))
        if not pending_messages:
            return summary

        total_pending_chars = sum(_pending_message_size(item) for item in pending_messages)
        if (
            len(pending_messages) <= self._keep_recent_messages
            and total_pending_chars <= self._max_pending_chars
        ):
            return summary

        messages_to_summarize = self._messages_to_summarize(pending_messages)
        if not messages_to_summarize or not hasattr(
            self._generator,
            "summarize_chat_messages",
        ):
            return summary

        summary_text = self._generator.summarize_chat_messages(
            model=str(session["model_name"]),
            summary_prompt=_build_summary_prompt(
                existing_summary=str((summary or {}).get("summary_text") or ""),
                messages=messages_to_summarize,
            ),
            context_window=None,
        )
        covered_through_message_id = str(messages_to_summarize[-1]["id"])
        self._db.mark_chat_messages_summarized(
            session_id=str(session["id"]),
            through_message_id=covered_through_message_id,
        )
        return self._db.upsert_chat_session_summary(
            session_id=str(session["id"]),
            summary_text=summary_text.strip(),
            covered_through_message_id=covered_through_message_id,
        )

    def _messages_to_summarize(
        self,
        pending_messages: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        summarize_count = len(pending_messages) - self._keep_recent_messages
        if summarize_count <= 0:
            summarize_count = max(1, len(pending_messages) - 1)
        if summarize_count <= 0:
            return []
        return pending_messages[:summarize_count]

    def _append_system_message(
        self,
        history: list[dict[str, object]],
        session: dict[str, Any],
    ) -> None:
        system_message = str(session.get("system_message") or "").strip()
        if system_message:
            history.append({"role": "system", "content": system_message})

    def _append_summary(
        self,
        history: list[dict[str, object]],
        summary: dict[str, Any] | None,
    ) -> None:
        summary_text = str((summary or {}).get("summary_text") or "").strip()
        if not summary_text:
            return
        history.append(
            {
                "role": "system",
                "content": (
                    "Conversation memory from earlier in this same session. "
                    "Use it as context while prioritizing newer verbatim turns.\n\n"
                    f"{summary_text}"
                ),
            }
        )

    def _message_payload(self, message: dict[str, Any]) -> dict[str, object]:
        payload: dict[str, object] = {
            "role": str(message["role"]),
            "content": str(message.get("content") or ""),
        }
        thinking = str(message.get("thinking") or "").strip()
        if thinking and payload["role"] == "assistant":
            payload["thinking"] = thinking
        if payload["role"] == "user":
            encoded_images = self._encoded_images(message)
            if encoded_images:
                payload["images"] = encoded_images
        return payload

    def _encoded_images(self, message: dict[str, Any]) -> list[str]:
        encoded_images = self._encoded_attachment_images(message)
        if encoded_images:
            return encoded_images

        context_image_id = str(message.get("context_image_id") or "").strip()
        context_image_path = str(message.get("context_image_path") or "").strip()
        if context_image_id:
            return self._load_image_safely(context_image_id=context_image_id)
        if context_image_path:
            return self._load_image_safely(context_image_path=context_image_path)
        return []

    def _encoded_attachment_images(self, message: dict[str, Any]) -> list[str]:
        encoded_images: list[str] = []
        attachments = message.get("attachments")
        if not isinstance(attachments, list):
            return encoded_images
        for attachment in attachments:
            if not isinstance(attachment, dict):
                continue
            try:
                encoded_image = self._context_images.load_attachment_base64(attachment)
            except (KeyError, FileNotFoundError, ValueError):
                encoded_image = None
            if encoded_image:
                encoded_images.append(encoded_image)
        return encoded_images

    def _load_image_safely(
        self,
        *,
        context_image_id: str | None = None,
        context_image_path: str | None = None,
    ) -> list[str]:
        try:
            if context_image_id:
                encoded_image = self._context_images.load_context_image_base64(
                    context_image_id
                )
            else:
                encoded_image = self._context_images.load_uploaded_context_image_base64(
                    context_image_path
                )
        except (KeyError, FileNotFoundError, ValueError):
            encoded_image = None
        return [encoded_image] if encoded_image else []


def _message_attachment_note(message: dict[str, Any]) -> str:
    attachments = message.get("attachments")
    if isinstance(attachments, list) and attachments:
        attachment_count = len([item for item in attachments if isinstance(item, dict)])
        if attachment_count > 1:
            return f" [The user attached {attachment_count} images as context.]"
        if attachment_count == 1:
            first_attachment = attachments[0]
            if str(first_attachment.get("context_image_id") or "").strip():
                return " [The user attached a gallery image as context.]"
            return " [The user attached an uploaded image as context.]"
    if str(message.get("context_image_id") or "").strip():
        return " [The user attached a gallery image as context.]"
    if str(message.get("context_image_path") or "").strip():
        return " [The user attached an uploaded image as context.]"
    return ""


def _build_summary_prompt(
    *,
    existing_summary: str | None,
    messages: list[dict[str, Any]],
) -> str:
    transcript_parts: list[str] = []
    for message in messages:
        role = str(message.get("role") or "user").strip() or "user"
        content = str(message.get("content") or "").strip()
        thinking = str(message.get("thinking") or "").strip()
        section = f"{role.upper()}: {content}{_message_attachment_note(message)}"
        if thinking:
            section += f"\nTHINKING: {thinking}"
        transcript_parts.append(section.strip())
    transcript = "\n\n".join(part for part in transcript_parts if part)
    summary_prefix = ""
    if str(existing_summary or "").strip():
        summary_prefix = (
            "Existing rolling summary:\n"
            f"{str(existing_summary).strip()}\n\n"
        )
    return (
        "Update the rolling conversation memory for an ongoing chat session. "
        "Preserve durable facts, user preferences, open tasks, important decisions, "
        "and what any attached gallery image was used for when it matters. "
        "Be concise and factual. Do not speak to the user. "
        "Return only the updated memory summary.\n\n"
        f"{summary_prefix}"
        "New transcript to fold into memory:\n"
        f"{transcript}"
    )


def _pending_message_size(message: dict[str, Any]) -> int:
    total = len(str(message.get("content") or ""))
    total += len(str(message.get("thinking") or ""))
    attachments = message.get("attachments")
    if isinstance(attachments, list) and attachments:
        total += 128 * len([item for item in attachments if isinstance(item, dict)])
    elif (
        str(message.get("context_image_id") or "").strip()
        or str(message.get("context_image_path") or "").strip()
    ):
        total += 128
    return total

