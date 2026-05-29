from __future__ import annotations

import sqlite3
import uuid
from pathlib import Path
from typing import Any

from ..records import utc_now_iso


class ChatAttachmentPersistenceMixin:
    def _decode_chat_attachment_row(self, row: sqlite3.Row) -> dict[str, Any]:
        item = self._row_to_dict(row)
        item["attachment_index"] = int(item.get("attachment_index") or 0)
        context_image_path = self._path_from_record_value(item.get("context_image_path"))
        item["context_image_path"] = (
            str(context_image_path) if context_image_path is not None else None
        )
        return item

    def _legacy_chat_message_attachment(
        self,
        message: dict[str, Any],
    ) -> dict[str, Any] | None:
        context_image_id = str(message.get("context_image_id") or "").strip() or None
        context_image_path = str(message.get("context_image_path") or "").strip() or None
        context_image_mime_type = (
            str(message.get("context_image_mime_type") or "").strip() or None
        )
        if context_image_id is None and context_image_path is None:
            return None
        return {
            "id": None,
            "message_id": message["id"],
            "attachment_index": 0,
            "context_image_id": context_image_id,
            "context_image_path": context_image_path,
            "context_image_mime_type": context_image_mime_type,
            "created_at": message["created_at"],
        }

    def _hydrate_chat_message_attachments(
        self,
        messages: list[dict[str, Any]],
    ) -> None:
        if not messages:
            return
        message_ids = [str(item["id"]) for item in messages]
        attachments_by_message_id = self.list_chat_message_attachments_for_messages(
            message_ids
        )
        for message in messages:
            attachments = attachments_by_message_id.get(str(message["id"]), [])
            if not attachments:
                legacy_attachment = self._legacy_chat_message_attachment(message)
                attachments = [legacy_attachment] if legacy_attachment is not None else []
            message["attachments"] = attachments

    def list_chat_message_attachments_for_messages(
        self,
        message_ids: list[str],
    ) -> dict[str, list[dict[str, Any]]]:
        normalized_ids = [str(item).strip() for item in message_ids if str(item).strip()]
        if not normalized_ids:
            return {}
        placeholders = ",".join("?" for _ in normalized_ids)
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT *
                FROM chat_message_attachments
                WHERE message_id IN ({placeholders})
                ORDER BY message_id ASC, attachment_index ASC, id ASC
                """,
                tuple(normalized_ids),
            ).fetchall()
        attachments_by_message_id: dict[str, list[dict[str, Any]]] = {
            message_id: [] for message_id in normalized_ids
        }
        for row in rows:
            attachment = self._decode_chat_attachment_row(row)
            attachments_by_message_id.setdefault(str(attachment["message_id"]), []).append(
                attachment
            )
        return attachments_by_message_id

    def get_chat_message_attachment(self, attachment_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                """
                SELECT *
                FROM chat_message_attachments
                WHERE id = ?
                """,
                (attachment_id,),
            ).fetchone()
        return self._decode_chat_attachment_row(row) if row else None

    def _insert_chat_message_attachments(
        self,
        conn: sqlite3.Connection,
        *,
        message_id: str,
        attachments: list[dict[str, Any]],
    ) -> None:
        now = utc_now_iso()
        for index, attachment in enumerate(attachments):
            context_image_id = str(attachment.get("context_image_id") or "").strip() or None
            context_image_path = attachment.get("context_image_path")
            context_image_mime_type = (
                str(attachment.get("context_image_mime_type") or "").strip() or None
            )
            if context_image_id is None and context_image_path is None:
                continue
            conn.execute(
                """
                INSERT INTO chat_message_attachments (
                    id,
                    message_id,
                    attachment_index,
                    context_image_id,
                    context_image_path,
                    context_image_mime_type,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    message_id,
                    index,
                    context_image_id,
                    (
                        self._path_to_record_value(Path(context_image_path))
                        if context_image_path is not None
                        else None
                    ),
                    context_image_mime_type,
                    now,
                ),
            )
