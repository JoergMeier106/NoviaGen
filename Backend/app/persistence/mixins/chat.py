from __future__ import annotations

import json
import sqlite3
import uuid
from pathlib import Path
from typing import Any

from ...storage.files import remove_file_if_present
from .chat_attachments import ChatAttachmentPersistenceMixin
from ..records import utc_now_iso


class ChatPersistenceMixin(ChatAttachmentPersistenceMixin):
    def create_chat_session(
        self,
        *,
        title: str,
        model_name: str,
        system_message: str = "",
        session_id: str | None = None,
    ) -> dict[str, Any]:
        now = utc_now_iso()
        created_session_id = session_id or str(uuid.uuid4())
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO chat_sessions (
                    id,
                    title,
                    model_name,
                    system_message,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    created_session_id,
                    title,
                    model_name,
                    system_message,
                    now,
                    now,
                ),
            )
        session = self.get_chat_session(created_session_id)
        if session is None:
            raise KeyError(created_session_id)
        return session

    def get_chat_session(self, session_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                """
                SELECT *
                FROM chat_sessions
                WHERE id = ?
                """,
                (session_id,),
            ).fetchone()
        return self._decode_chat_session_row(row) if row else None

    def list_chat_sessions(self) -> list[dict[str, Any]]:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT
                    s.*,
                    (
                        SELECT m.content
                        FROM chat_messages AS m
                        WHERE m.session_id = s.id
                        ORDER BY m.created_at DESC, m.id DESC
                        LIMIT 1
                    ) AS last_message_content,
                    (
                        SELECT m.role
                        FROM chat_messages AS m
                        WHERE m.session_id = s.id
                        ORDER BY m.created_at DESC, m.id DESC
                        LIMIT 1
                    ) AS last_message_role,
                    (
                        SELECT m.created_at
                        FROM chat_messages AS m
                        WHERE m.session_id = s.id
                        ORDER BY m.created_at DESC, m.id DESC
                        LIMIT 1
                    ) AS last_message_at,
                    (
                        SELECT COUNT(*)
                        FROM chat_messages AS m
                        WHERE m.session_id = s.id
                    ) AS message_count
                FROM chat_sessions AS s
                ORDER BY s.updated_at DESC, s.created_at DESC, s.id DESC
                """
            ).fetchall()
        return [self._decode_chat_session_row(row) for row in rows]

    def update_chat_session(
        self,
        session_id: str,
        *,
        title: str | None = None,
        model_name: str | None = None,
        system_message: str | None = None,
    ) -> dict[str, Any] | None:
        updates: list[str] = []
        params: list[Any] = []
        if title is not None:
            updates.append("title = ?")
            params.append(title)
        if model_name is not None:
            updates.append("model_name = ?")
            params.append(model_name)
        if system_message is not None:
            updates.append("system_message = ?")
            params.append(system_message)
        updates.append("updated_at = ?")
        params.append(utc_now_iso())
        params.append(session_id)
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                f"""
                UPDATE chat_sessions
                SET {", ".join(updates)}
                WHERE id = ?
                """,
                tuple(params),
            )
        return self.get_chat_session(session_id)

    def touch_chat_session(self, session_id: str) -> None:
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE chat_sessions
                SET updated_at = ?
                WHERE id = ?
                """,
                (utc_now_iso(), session_id),
            )

    def delete_chat_session(self, session_id: str) -> bool:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT m.context_image_path AS path
                FROM chat_messages AS m
                WHERE m.session_id = ?
                  AND m.context_image_path IS NOT NULL
                UNION ALL
                SELECT a.context_image_path AS path
                FROM chat_message_attachments AS a
                INNER JOIN chat_messages AS m ON m.id = a.message_id
                WHERE m.session_id = ?
                  AND a.context_image_path IS NOT NULL
                """,
                (session_id, session_id),
            ).fetchall()
            attachment_paths = [
                Path(str(row["path"]))
                for row in rows
                if str(row["path"] or "").strip()
            ]
        for path in attachment_paths:
            remove_file_if_present(path)
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                "DELETE FROM chat_session_summaries WHERE session_id = ?",
                (session_id,),
            )
            conn.execute(
                """
                DELETE FROM chat_message_attachments
                WHERE message_id IN (
                    SELECT id
                    FROM chat_messages
                    WHERE session_id = ?
                )
                """,
                (session_id,),
            )
            conn.execute(
                "DELETE FROM chat_messages WHERE session_id = ?",
                (session_id,),
            )
            cursor = conn.execute(
                "DELETE FROM chat_sessions WHERE id = ?",
                (session_id,),
            )
        return max(cursor.rowcount, 0) > 0

    def create_chat_message(
        self,
        *,
        session_id: str,
        role: str,
        content: str,
        thinking: str | None = None,
        tool_traces: Any = None,
        context_image_id: str | None = None,
        context_image_path: str | Path | None = None,
        context_image_mime_type: str | None = None,
        model_name: str | None = None,
        total_duration_ns: int | None = None,
        load_duration_ns: int | None = None,
        prompt_eval_count: int | None = None,
        prompt_eval_duration_ns: int | None = None,
        eval_count: int | None = None,
        eval_duration_ns: int | None = None,
        summarized_into_memory: bool = False,
        message_id: str | None = None,
        attachments: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        now = utc_now_iso()
        created_message_id = message_id or str(uuid.uuid4())
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO chat_messages (
                    id,
                    session_id,
                    role,
                    content,
                    thinking,
                    tool_traces_json,
                    context_image_id,
                    context_image_path,
                    context_image_mime_type,
                    model_name,
                    total_duration_ns,
                    load_duration_ns,
                    prompt_eval_count,
                    prompt_eval_duration_ns,
                    eval_count,
                    eval_duration_ns,
                    summarized_into_memory,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    created_message_id,
                    session_id,
                    role,
                    content,
                    thinking,
                    _encode_tool_traces(tool_traces),
                    context_image_id,
                    (
                        self._path_to_record_value(Path(context_image_path))
                        if context_image_path is not None
                        else None
                    ),
                    context_image_mime_type,
                    model_name,
                    total_duration_ns,
                    load_duration_ns,
                    prompt_eval_count,
                    prompt_eval_duration_ns,
                    eval_count,
                    eval_duration_ns,
                    1 if summarized_into_memory else 0,
                    now,
                ),
            )
            self._insert_chat_message_attachments(
                conn,
                message_id=created_message_id,
                attachments=attachments or [],
            )
            conn.execute(
                """
                UPDATE chat_sessions
                SET updated_at = ?
                WHERE id = ?
                """,
                (now, session_id),
            )
        message = self.get_chat_message(created_message_id)
        if message is None:
            raise KeyError(created_message_id)
        return message

    def get_chat_message(self, message_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                """
                SELECT *
                FROM chat_messages
                WHERE id = ?
                """,
                (message_id,),
            ).fetchone()
        if not row:
            return None
        items = [self._decode_chat_message_row(row)]
        self._hydrate_chat_message_attachments(items)
        return items[0]

    def list_chat_messages(self, session_id: str) -> list[dict[str, Any]]:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT *
                FROM chat_messages
                WHERE session_id = ?
                ORDER BY created_at ASC, id ASC
                """,
                (session_id,),
            ).fetchall()
        items = [self._decode_chat_message_row(row) for row in rows]
        self._hydrate_chat_message_attachments(items)
        return items

    def list_unsummarized_chat_messages(self, session_id: str) -> list[dict[str, Any]]:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT *
                FROM chat_messages
                WHERE session_id = ?
                  AND summarized_into_memory = 0
                ORDER BY created_at ASC, id ASC
                """,
                (session_id,),
            ).fetchall()
        items = [self._decode_chat_message_row(row) for row in rows]
        self._hydrate_chat_message_attachments(items)
        return items

    def mark_chat_messages_summarized(
        self,
        *,
        session_id: str,
        through_message_id: str,
    ) -> None:
        target = self.get_chat_message(through_message_id)
        if target is None or target.get("session_id") != session_id:
            return
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE chat_messages
                SET summarized_into_memory = 1
                WHERE session_id = ?
                  AND (
                    created_at < ?
                    OR (created_at = ? AND id <= ?)
                  )
                """,
                (
                    session_id,
                    target["created_at"],
                    target["created_at"],
                    through_message_id,
                ),
            )

    def get_chat_session_summary(self, session_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                """
                SELECT *
                FROM chat_session_summaries
                WHERE session_id = ?
                """,
                (session_id,),
            ).fetchone()
        return self._row_to_dict(row) if row else None

    def upsert_chat_session_summary(
        self,
        *,
        session_id: str,
        summary_text: str,
        covered_through_message_id: str | None,
    ) -> dict[str, Any]:
        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO chat_session_summaries (
                    session_id,
                    summary_text,
                    covered_through_message_id,
                    updated_at
                )
                VALUES (?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    summary_text = excluded.summary_text,
                    covered_through_message_id = excluded.covered_through_message_id,
                    updated_at = excluded.updated_at
                """,
                (session_id, summary_text, covered_through_message_id, now),
            )
            conn.execute(
                """
                UPDATE chat_sessions
                SET updated_at = ?
                WHERE id = ?
                """,
                (now, session_id),
            )
        summary = self.get_chat_session_summary(session_id)
        if summary is None:
            raise KeyError(session_id)
        return summary

    def _decode_chat_session_row(self, row: sqlite3.Row) -> dict[str, Any]:
        item = self._row_to_dict(row)
        item["message_count"] = int(item.get("message_count") or 0)
        item["system_message"] = str(item.get("system_message") or "")
        return item

    def _decode_chat_message_row(self, row: sqlite3.Row) -> dict[str, Any]:
        item = self._row_to_dict(row)
        item["summarized_into_memory"] = bool(item.get("summarized_into_memory"))
        item["tool_traces"] = _decode_tool_traces(item.get("tool_traces_json"))
        context_image_path = self._path_from_record_value(item.get("context_image_path"))
        item["context_image_path"] = (
            str(context_image_path) if context_image_path is not None else None
        )
        return item


def _encode_tool_traces(value: Any) -> str | None:
    if not value:
        return None
    if isinstance(value, tuple):
        items = list(value)
    elif isinstance(value, list):
        items = value
    else:
        items = []
    traces: list[dict[str, str]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        content = str(item.get("content") or "").strip()
        if not content:
            continue
        trace: dict[str, str] = {"content": content}
        tool_id = str(item.get("tool_id") or "").strip()
        tool_name = str(item.get("tool_name") or "").strip()
        if tool_id:
            trace["tool_id"] = tool_id
        if tool_name:
            trace["tool_name"] = tool_name
        traces.append(trace)
    return json.dumps(traces, ensure_ascii=False) if traces else None


def _decode_tool_traces(value: Any) -> list[dict[str, str]]:
    if not value:
        return []
    try:
        decoded = json.loads(str(value))
    except json.JSONDecodeError:
        return []
    if not isinstance(decoded, list):
        return []
    traces: list[dict[str, str]] = []
    for item in decoded:
        if not isinstance(item, dict):
            continue
        content = str(item.get("content") or "").strip()
        if not content:
            continue
        traces.append(
            {
                "tool_id": str(item.get("tool_id") or "").strip(),
                "tool_name": str(item.get("tool_name") or "").strip(),
                "content": content,
            }
        )
    return traces
