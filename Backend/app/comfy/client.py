from __future__ import annotations

import json
import logging
import mimetypes
import secrets
import time
import uuid
from pathlib import Path
from typing import Any, Callable

import requests

from .progress import ComfyExecutionPlan

logger = logging.getLogger(__name__)
MAX_SAFE_COMFY_SEED = 1_125_899_906_842_624


class ComfyPromptCancelledError(RuntimeError):
    pass


class ComfyClientMixin:
    @staticmethod
    def _load_workflow(path: Path | None, config_name: str) -> dict[str, Any]:
        if path is None:
            raise RuntimeError(f"{config_name} is not configured")
        if not path.exists():
            raise FileNotFoundError(f"ComfyUI workflow not found: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("prompt"), dict):
            data = data["prompt"]
        if not isinstance(data, dict):
            raise ValueError("ComfyUI workflow JSON must be an object or a wrapped prompt object")
        return data

    def _upload_image(self, image_path: Path) -> dict[str, Any]:
        mime_type = mimetypes.guess_type(str(image_path))[0] or "application/octet-stream"
        with image_path.open("rb") as file_handle:
            response = requests.post(
                f"{self.comfy_url}/upload/image",
                files={"image": (image_path.name, file_handle, mime_type)},
                data={"type": "input", "overwrite": "true"},
                timeout=120,
            )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise RuntimeError(f"Unexpected ComfyUI upload response: {payload}")
        return payload

    def _queue_prompt(
        self,
        workflow: dict[str, Any],
        *,
        execution_plan: ComfyExecutionPlan | None = None,
    ) -> str:
        client_id = str(uuid.uuid4())
        response = requests.post(
            f"{self.comfy_url}/prompt",
            json={"prompt": workflow, "client_id": client_id},
            timeout=120,
        )
        try:
            response.raise_for_status()
        except requests.HTTPError as exc:
            response_text = response.text.strip()
            if response_text:
                raise RuntimeError(
                    f"ComfyUI prompt request failed ({response.status_code}): {response_text}"
                ) from exc
            raise RuntimeError(
                f"ComfyUI prompt request failed ({response.status_code})"
            ) from exc
        payload = response.json()
        prompt_id = str(payload.get("prompt_id") or "").strip()
        if not prompt_id:
            raise RuntimeError(f"Unexpected ComfyUI prompt response: {payload}")
        with self._state_lock:
            self._client_id = client_id
            self._active_prompt_id = prompt_id
            self._cancel_requested_prompt_ids.discard(prompt_id)
            if execution_plan is not None:
                self._execution_plan_by_prompt_id[prompt_id] = execution_plan
                self._last_progress_by_prompt_id[prompt_id] = execution_plan.queue_progress
        return prompt_id

    @classmethod
    def _randomize_workflow_seeds(cls, workflow: dict[str, Any]) -> None:
        for node in workflow.values():
            if isinstance(node, dict):
                cls._randomize_seed_values(node)

    @classmethod
    def _randomize_seed_values(cls, value: Any, *, key: str | None = None) -> None:
        if isinstance(value, dict):
            for child_key, child_value in value.items():
                if (
                    cls._is_seed_key(child_key)
                    and isinstance(child_value, int)
                    and not isinstance(child_value, bool)
                ):
                    value[child_key] = cls._random_seed_value()
                else:
                    cls._randomize_seed_values(child_value, key=child_key)
            return
        if isinstance(value, list):
            for item in value:
                cls._randomize_seed_values(item, key=key)

    @staticmethod
    def _is_seed_key(key: str) -> bool:
        normalized = key.strip().lower()
        return normalized == "seed" or normalized.endswith("_seed")

    @staticmethod
    def _random_seed_value() -> int:
        return secrets.randbelow(MAX_SAFE_COMFY_SEED) + 1

    def _wait_for_history(
        self,
        prompt_id: str,
        *,
        progress_callback: Callable[[float, str], None] | None = None,
        preparing_label: str = "Preparing video generation",
        active_label: str = "Generating frames",
        expected_output: str = "video",
        cancel_requested: Callable[[], bool] | None = None,
        timeout_seconds: int = 3600,
        poll_seconds: float = 0.75,
    ) -> dict[str, Any]:
        deadline = time.monotonic() + timeout_seconds
        last_status = preparing_label
        history_error_started_at: float | None = None
        history_error_count = 0
        history_error_grace_seconds = min(60.0, max(10.0, poll_seconds * 5.0))
        completed_without_output_started_at: float | None = None
        completed_without_output_grace_seconds = max(5.0, poll_seconds * 3.0)
        while time.monotonic() < deadline:
            if cancel_requested is not None and cancel_requested():
                with self._state_lock:
                    self._cancel_requested_prompt_ids.add(prompt_id)
                self._request_prompt_cancellation(prompt_id)
            try:
                response = requests.get(f"{self.comfy_url}/history/{prompt_id}", timeout=60)
                response.raise_for_status()
                history = response.json()
                history_error_started_at = None
                history_error_count = 0
            except requests.RequestException as exc:
                history_error_count += 1
                if history_error_started_at is None:
                    history_error_started_at = time.monotonic()
                elif (time.monotonic() - history_error_started_at) >= history_error_grace_seconds:
                    raise RuntimeError(
                        "Lost connection to ComfyUI while waiting for video output"
                    ) from exc

                if history_error_count == 1 or history_error_count % 5 == 0:
                    logger.warning(
                        "Transient ComfyUI history polling error for prompt %s; retrying: %s",
                        prompt_id,
                        exc,
                    )

                cancel_active = self._is_cancel_requested(prompt_id)
                if cancel_active:
                    prompt_state = self._inspect_prompt_state(prompt_id)
                    if not prompt_state["running"] and not prompt_state["pending"]:
                        raise ComfyPromptCancelledError(prompt_id)
                    last_status = "Waiting for job to stop"
                    self._emit_progress(
                        progress_callback,
                        self._progress_floor_for_prompt(prompt_id, 0.16),
                        last_status,
                    )
                    time.sleep(min(poll_seconds, 0.5))
                    continue

                snapshot = self._fetch_progress_snapshot(
                    prompt_id,
                    preparing_label=preparing_label,
                    active_label=active_label,
                )
                if snapshot is not None:
                    last_status = snapshot[1]
                    self._emit_progress(progress_callback, snapshot[0], snapshot[1])
                else:
                    self._emit_progress(
                        progress_callback,
                        self._progress_floor_for_prompt(prompt_id, 0.2),
                        last_status,
                    )
                time.sleep(min(poll_seconds, 1.0))
                continue
            job = history.get(prompt_id)
            sleep_seconds = poll_seconds
            cancel_active = self._is_cancel_requested(prompt_id)
            if isinstance(job, dict):
                outputs = job.get("outputs", {})
                if self._history_has_expected_output(job, expected_output):
                    self._emit_progress(
                        progress_callback,
                        self._progress_floor_for_prompt(prompt_id, 0.92),
                        "Finalizing prompt" if expected_output == "text" else "Finalizing video",
                    )
                    return job
                status = job.get("status", {})
                status_str = str(status.get("status_str") or "").lower()
                if cancel_active and status_str in {
                    "cancelled",
                    "canceled",
                    "interrupted",
                    "interrupt",
                    "aborted",
                }:
                    raise ComfyPromptCancelledError(prompt_id)
                if status_str in {"error", "failed"}:
                    if cancel_active:
                        raise ComfyPromptCancelledError(prompt_id)
                    raise RuntimeError(f"ComfyUI job failed: {status}")
                if status_str in {"success", "succeeded", "completed", "done"}:
                    if completed_without_output_started_at is None:
                        completed_without_output_started_at = time.monotonic()
                    elif (
                        time.monotonic() - completed_without_output_started_at
                        >= completed_without_output_grace_seconds
                    ):
                        raise RuntimeError(
                            "ComfyUI completed without producing the expected output: "
                            f"{outputs}"
                        )
                    last_status = "Finalizing video"
                    self._emit_progress(
                        progress_callback,
                        self._progress_floor_for_prompt(prompt_id, 0.9),
                        last_status,
                    )
                    sleep_seconds = min(poll_seconds, 0.5)
                else:
                    completed_without_output_started_at = None

            if cancel_active:
                prompt_state = self._inspect_prompt_state(prompt_id)
                if not prompt_state["running"] and not prompt_state["pending"]:
                    raise ComfyPromptCancelledError(prompt_id)
                last_status = "Waiting for job to stop"
                self._emit_progress(
                    progress_callback,
                    self._progress_floor_for_prompt(prompt_id, 0.16),
                    last_status,
                )
                time.sleep(min(poll_seconds, 0.5))
                continue

            snapshot = self._fetch_progress_snapshot(
                prompt_id,
                preparing_label=preparing_label,
                active_label=active_label,
            )
            if snapshot is not None:
                last_status = snapshot[1]
                self._emit_progress(progress_callback, snapshot[0], snapshot[1])
            else:
                if isinstance(job, dict):
                    last_status = "Finalizing video"
                    self._emit_progress(
                        progress_callback,
                        self._progress_floor_for_prompt(prompt_id, 0.88),
                        last_status,
                    )
                    sleep_seconds = min(poll_seconds, 0.5)
                else:
                    self._emit_progress(
                        progress_callback,
                        self._progress_floor_for_prompt(prompt_id, 0.2),
                        last_status,
                    )
            time.sleep(sleep_seconds)
        raise TimeoutError("Timed out waiting for ComfyUI output")

    def _request_prompt_cancellation(self, prompt_id: str) -> None:
        prompt_state = self._inspect_prompt_state(prompt_id)
        deleted_from_queue = False
        if prompt_state["pending"]:
            try:
                response = requests.post(
                    f"{self.comfy_url}/queue",
                    json={"delete": [prompt_id]},
                    timeout=30,
                )
                response.raise_for_status()
                deleted_from_queue = True
            except requests.RequestException:
                logger.warning(
                    "Failed to remove ComfyUI prompt %s from the queue",
                    prompt_id,
                    exc_info=True,
                )
        if prompt_state["running"]:
            try:
                response = requests.post(
                    f"{self.comfy_url}/interrupt",
                    json={},
                    timeout=30,
                )
                response.raise_for_status()
            except requests.RequestException:
                logger.warning("Failed to interrupt ComfyUI prompt %s", prompt_id, exc_info=True)
        elif not deleted_from_queue:
            try:
                response = requests.post(
                    f"{self.comfy_url}/queue",
                    json={"delete": [prompt_id]},
                    timeout=30,
                )
                response.raise_for_status()
            except requests.RequestException:
                logger.warning(
                    "Failed to send a fallback queue deletion request for ComfyUI prompt %s",
                    prompt_id,
                    exc_info=True,
                )

    def _inspect_prompt_state(self, prompt_id: str) -> dict[str, bool]:
        running = False
        pending = False
        try:
            queue_response = requests.get(f"{self.comfy_url}/queue", timeout=15)
            queue_response.raise_for_status()
            queue_payload = queue_response.json()
        except requests.RequestException:
            queue_payload = {}

        running = self._queue_contains_prompt_id(queue_payload.get("queue_running"), prompt_id)
        pending = self._queue_contains_prompt_id(queue_payload.get("queue_pending"), prompt_id)

        try:
            progress_response = requests.get(f"{self.comfy_url}/progress", timeout=15)
            progress_response.raise_for_status()
            progress_payload = progress_response.json()
        except requests.RequestException:
            progress_payload = {}

        progress_prompt_id = str(progress_payload.get("prompt_id") or "").strip()
        if progress_prompt_id and progress_prompt_id == prompt_id:
            running = True
        return {"running": running, "pending": pending}

    @classmethod
    def _queue_contains_prompt_id(cls, payload: Any, prompt_id: str) -> bool:
        if payload is None:
            return False
        if isinstance(payload, dict):
            return any(cls._queue_contains_prompt_id(value, prompt_id) for value in payload.values())
        if isinstance(payload, (list, tuple)):
            return any(cls._queue_contains_prompt_id(value, prompt_id) for value in payload)
        return str(payload).strip() == prompt_id

    def _is_cancel_requested(self, prompt_id: str) -> bool:
        with self._state_lock:
            return prompt_id in self._cancel_requested_prompt_ids

    def _clear_prompt_state(self, prompt_id: str) -> None:
        with self._state_lock:
            self._cancel_requested_prompt_ids.discard(prompt_id)
            self._execution_plan_by_prompt_id.pop(prompt_id, None)
            self._last_progress_by_prompt_id.pop(prompt_id, None)
            if self._active_prompt_id == prompt_id:
                self._active_prompt_id = None
                self._client_id = None

    def _download_output_file(self, file_info: dict[str, Any], save_path: Path) -> Path:
        params: dict[str, Any] = {"filename": file_info["filename"]}
        if file_info.get("subfolder"):
            params["subfolder"] = file_info["subfolder"]
        if file_info.get("type"):
            params["type"] = file_info["type"]
        response = requests.get(f"{self.comfy_url}/view", params=params, timeout=600)
        response.raise_for_status()
        save_path.parent.mkdir(parents=True, exist_ok=True)
        save_path.write_bytes(response.content)
        return save_path
