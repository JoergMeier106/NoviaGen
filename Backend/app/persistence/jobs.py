from __future__ import annotations

import json
from typing import Any

from .records import utc_now_iso


class JobPersistenceMixin:
    def insert_job(
        self,
        *,
        job_id: str,
        job_type: str,
        payload: dict[str, Any],
        result_image_id: str | None = None,
        result_data: dict[str, Any] | None = None,
    ) -> None:
        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO jobs (
                    id,
                    type,
                    status,
                    progress,
                    status_text,
                    payload_json,
                    result_image_id,
                    result_json,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, 'queued', 0, 'Queued', ?, ?, ?, ?, ?)
                """,
                (
                    job_id,
                    job_type,
                    json.dumps(payload),
                    result_image_id,
                    json.dumps(result_data) if result_data is not None else None,
                    now,
                    now,
                ),
            )

    def update_job(
        self,
        job_id: str,
        *,
        status: str,
        progress: float,
        status_text: str,
        result_image_id: str | None = None,
        result_data: dict[str, Any] | None = None,
        error: str | None = None,
    ) -> None:
        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE jobs
                SET status = ?,
                    progress = ?,
                    status_text = ?,
                    result_image_id = COALESCE(?, result_image_id),
                    result_json = COALESCE(?, result_json),
                    error = ?,
                    started_at = CASE
                        WHEN started_at IS NULL AND ? = 'running' THEN ?
                        ELSE started_at
                    END,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    status,
                    progress,
                    status_text,
                    result_image_id,
                    json.dumps(result_data) if result_data is not None else None,
                    error,
                    status,
                    now,
                    now,
                    job_id,
                ),
            )

    def get_job(self, job_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return self._row_to_dict(row) if row else None

    def get_job_for_result_image(self, image_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM jobs WHERE result_image_id = ? ORDER BY created_at DESC LIMIT 1",
                (image_id,),
            ).fetchone()
        return self._row_to_dict(row) if row else None

    def list_jobs(self, page: int, page_size: int, status: str | None = None) -> dict[str, Any]:
        offset = (page - 1) * page_size
        query = "SELECT * FROM jobs"
        params: list[Any] = []
        if status:
            query += " WHERE status = ?"
            params.append(status)
        query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        params.extend([page_size, offset])

        count_query = "SELECT COUNT(*) AS total FROM jobs"
        count_params: list[Any] = []
        if status:
            count_query += " WHERE status = ?"
            count_params.append(status)

        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(query, tuple(params)).fetchall()
            total = conn.execute(count_query, tuple(count_params)).fetchone()["total"]

        return {
            "items": [self._row_to_dict(row) for row in rows],
            "page": page,
            "page_size": page_size,
            "total": total,
        }

    def list_jobs_by_statuses(
        self,
        statuses: list[str] | tuple[str, ...] | set[str],
    ) -> list[dict[str, Any]]:
        normalized = [str(status).strip() for status in statuses if str(status).strip()]
        if not normalized:
            return []

        placeholders = ", ".join("?" for _ in normalized)
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT *
                FROM jobs
                WHERE status IN ({placeholders})
                ORDER BY created_at ASC
                """,
                tuple(normalized),
            ).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def has_active_jobs(self) -> bool:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                """
                SELECT 1
                FROM jobs
                WHERE status IN ('queued', 'running')
                LIMIT 1
                """
            ).fetchone()
        return row is not None

    def delete_jobs_by_statuses(self, statuses: list[str] | tuple[str, ...] | set[str]) -> int:
        normalized = sorted({str(status).strip() for status in statuses if str(status).strip()})
        if not normalized:
            return 0

        placeholders = ", ".join("?" for _ in normalized)
        with self._write_lock(), self._connect() as conn:
            cursor = conn.execute(
                f"DELETE FROM jobs WHERE status IN ({placeholders})",
                tuple(normalized),
            )
        return max(cursor.rowcount, 0)

    def list_jobs_using_source_image(
        self,
        source_image_id: str,
        *,
        statuses: list[str] | tuple[str, ...] | set[str] = ("queued", "running"),
    ) -> list[dict[str, Any]]:
        normalized_statuses = [
            str(status).strip()
            for status in statuses
            if str(status).strip()
        ]
        if not normalized_statuses:
            return []

        placeholders = ", ".join("?" for _ in normalized_statuses)
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT *
                FROM jobs
                WHERE status IN ({placeholders})
                ORDER BY created_at DESC
                """,
                tuple(normalized_statuses),
            ).fetchall()

        matches: list[dict[str, Any]] = []
        for row in rows:
            item = self._row_to_dict(row)
            raw_payload = item.get("payload_json")
            try:
                payload = json.loads(raw_payload) if isinstance(raw_payload, str) else {}
            except (TypeError, ValueError, json.JSONDecodeError):
                payload = {}
            if (
                isinstance(payload, dict)
                and str(payload.get("image_id", "")).strip() == source_image_id
            ):
                matches.append(item)
        return matches

    def should_cancel_job(self, job_id: str) -> bool:
        job = self.get_job(job_id)
        return bool(job and job.get("cancel_requested"))

    def cancel_job(self, job_id: str) -> dict[str, Any] | None:
        job = self.get_job(job_id)
        if job is None:
            return None
        if job["status"] in {"completed", "failed", "cancelled"}:
            return job

        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            if job["status"] == "queued":
                conn.execute(
                    """
                    UPDATE jobs
                    SET status = 'cancelled',
                        progress = 1.0,
                        status_text = 'Cancelled',
                        cancel_requested = 1,
                        cancel_requested_at = COALESCE(cancel_requested_at, ?),
                        cancelled_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (now, now, now, job_id),
                )
            else:
                conn.execute(
                    """
                    UPDATE jobs
                    SET cancel_requested = 1,
                        cancel_requested_at = COALESCE(cancel_requested_at, ?),
                        status_text = CASE
                            WHEN cancel_requested = 1 THEN status_text
                            ELSE 'Cancellation requested'
                        END,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (now, now, job_id),
                )
        return self.get_job(job_id)

    def mark_job_cancelled(self, job_id: str, status_text: str = "Cancelled") -> None:
        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE jobs
                SET status = 'cancelled',
                    progress = 1.0,
                    status_text = ?,
                    cancel_requested = 1,
                    cancel_requested_at = COALESCE(cancel_requested_at, ?),
                    cancelled_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (status_text, now, now, now, job_id),
            )

    def cleanup_cancel_requested_jobs(self, status_text: str = "Cancelled") -> int:
        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE jobs
                SET status = 'cancelled',
                    progress = 1.0,
                    status_text = ?,
                    cancel_requested = 1,
                    cancel_requested_at = COALESCE(cancel_requested_at, ?),
                    cancelled_at = COALESCE(cancelled_at, ?),
                    updated_at = ?
                WHERE cancel_requested = 1
                  AND status IN ('queued', 'running')
                """,
                (status_text, now, now, now),
            )
        return max(cursor.rowcount, 0)
