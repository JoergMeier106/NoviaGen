from __future__ import annotations

import json
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def _utc_now_iso() -> str:
    return datetime.now(UTC).isoformat()


class ErrorStore:
    def __init__(self, errors_dir: str | Path) -> None:
        self.errors_dir = Path(errors_dir)
        self.errors_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def log_job_error(self, job: dict[str, Any]) -> dict[str, Any]:
        logged_at = _utc_now_iso()
        error_id = f"{logged_at.replace(':', '').replace('-', '')}_{job['id']}"
        entry = {
            "id": error_id,
            "logged_at": logged_at,
            "error_text": str(job.get("error") or ""),
            "job": {
                "job_id": job["id"],
                "type": job["type"],
                "status": job["status"],
                "progress": float(job.get("progress", 0.0)),
                "status_text": str(job.get("status_text") or ""),
                "cancel_requested": bool(job.get("cancel_requested")),
                "cancel_requested_at": job.get("cancel_requested_at"),
                "cancelled_at": job.get("cancelled_at"),
                "created_at": job.get("created_at"),
                "updated_at": job.get("updated_at"),
                "payload": self._decode_payload(job.get("payload_json")),
            },
        }
        file_path = self.errors_dir / f"{error_id}.json"
        with self._lock:
            file_path.write_text(
                json.dumps(entry, indent=2, ensure_ascii=True),
                encoding="utf-8",
            )
        return entry

    def log_chat_error(
        self,
        *,
        session_id: str,
        model_name: str,
        content: str,
        attachments: list[dict[str, Any]] | None,
        think: bool | None,
        context_window: int | None,
        error_text: str,
        status_text: str,
    ) -> dict[str, Any]:
        logged_at = _utc_now_iso()
        error_id = f"{logged_at.replace(':', '').replace('-', '')}_chat_{session_id}"
        entry = {
            "id": error_id,
            "logged_at": logged_at,
            "error_text": str(error_text or ""),
            "job": {
                "job_id": session_id,
                "type": "chat",
                "status": "failed",
                "progress": 1.0,
                "status_text": str(status_text or "Chat request failed"),
                "cancel_requested": False,
                "cancel_requested_at": None,
                "cancelled_at": None,
                "created_at": logged_at,
                "updated_at": logged_at,
                "payload": {
                    "session_id": session_id,
                    "model_name": model_name,
                    "content": content,
                    "attachments": attachments or [],
                    "think": think,
                    "context_window": context_window,
                },
            },
        }
        file_path = self.errors_dir / f"{error_id}.json"
        with self._lock:
            file_path.write_text(
                json.dumps(entry, indent=2, ensure_ascii=True),
                encoding="utf-8",
            )
        return entry


    def log_system_error(
        self,
        *,
        operation: str,
        error_text: str,
        status_text: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        logged_at = _utc_now_iso()
        error_id = f"{logged_at.replace(':', '').replace('-', '')}_{operation}"
        entry = {
            "id": error_id,
            "logged_at": logged_at,
            "error_text": str(error_text or ""),
            "job": {
                "job_id": operation,
                "type": "system",
                "status": "failed",
                "progress": 1.0,
                "status_text": str(status_text or "System operation failed"),
                "cancel_requested": False,
                "cancel_requested_at": None,
                "cancelled_at": None,
                "created_at": logged_at,
                "updated_at": logged_at,
                "payload": payload or {},
            },
        }
        file_path = self.errors_dir / f"{error_id}.json"
        with self._lock:
            file_path.write_text(
                json.dumps(entry, indent=2, ensure_ascii=True),
                encoding="utf-8",
            )
        return entry

    def list_errors(self) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        with self._lock:
            for file_path in sorted(self.errors_dir.glob("*.json"), reverse=True):
                try:
                    decoded = json.loads(file_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError, ValueError, TypeError):
                    continue
                if isinstance(decoded, dict):
                    items.append(decoded)
        items.sort(
            key=lambda item: str(item.get("logged_at") or ""),
            reverse=True,
        )
        return items

    def clear_errors(self) -> int:
        deleted = 0
        with self._lock:
            for file_path in self.errors_dir.glob("*.json"):
                try:
                    file_path.unlink()
                except OSError:
                    continue
                deleted += 1
        return deleted

    @staticmethod
    def _decode_payload(raw_payload: Any) -> dict[str, Any]:
        if isinstance(raw_payload, dict):
            return raw_payload
        if not isinstance(raw_payload, str) or not raw_payload.strip():
            return {}
        try:
            decoded = json.loads(raw_payload)
        except (json.JSONDecodeError, ValueError, TypeError):
            return {}
        return decoded if isinstance(decoded, dict) else {}
