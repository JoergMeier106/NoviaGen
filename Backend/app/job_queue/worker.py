from __future__ import annotations

import json
import logging
import queue
import threading
import time
import uuid
from copy import deepcopy
from pathlib import Path
from typing import Any
from collections.abc import Callable

from ..persistence import AppDatabase
from ..system import ErrorStore
from ..generation import ImageGenerator
from .executors.chat import ChatMessageJobExecutor
from .execution.base import JobExecutionMixin
from .models import QueuedJob
from .builders.payloads import JobPayloadFactory
from .builders.placeholders import PlaceholderBuilder
from ..system import SystemShutdownController


logger = logging.getLogger(__name__)


class JobWorker(JobExecutionMixin):
    CHAIN_PARENT_JOB_TYPE = "chain"
    CHAIN_SUPPORTED_JOB_TYPES = frozenset(
        {
            "generate",
            "generate_from_image",
            "generate_prompt",
            "generate_i2v_prompt",
            "generate_video",
            "animate_image",
            "upscale",
            "upscale_video",
            "convert_video_to_gif",
            "generate_audio_video",
        }
    )
    CHAIN_ARTIFACT_JOB_TYPES = frozenset(
        {
            "generate",
            "generate_from_image",
            "generate_video",
            "animate_image",
            "upscale",
            "upscale_video",
            "convert_video_to_gif",
            "generate_audio_video",
        }
    )
    CHAIN_TEXT_RESULT_JOB_TYPES = frozenset(
        {
            "generate_prompt",
            "generate_i2v_prompt",
        }
    )
    CHAIN_ALLOWED_BINDING_OUTPUTS = frozenset({"result_image_id", "result_text"})
    COMFY_DEPENDENT_JOB_TYPES = frozenset(
        {
            "generate_video",
            "animate_image",
            "upscale_video",
            "generate_audio_video",
            CHAIN_PARENT_JOB_TYPE,
        }
    )

    def __init__(
        self,
        *,
        db: AppDatabase,
        error_store: ErrorStore,
        generator: ImageGenerator,
        temp_dir: str | Path,
        mcp_tool_provider: Any | None = None,
        shutdown_controller: SystemShutdownController | None = None,
        inter_job_delay_seconds: int = 0,
        recovered_job_gate: Callable[[str], bool] | None = None,
    ) -> None:
        self.db = db
        self.error_store = error_store
        self.generator = generator
        self.temp_dir = Path(temp_dir)
        self.shutdown_controller = shutdown_controller
        self._queue: queue.Queue[QueuedJob] = queue.Queue()
        self._queued_job_ids: set[str] = set()
        self._active_job_id: str | None = None
        self._shutdown_when_idle = False
        self._inter_job_delay_seconds = max(0, int(inter_job_delay_seconds))
        self._recovered_job_gate = recovered_job_gate
        self._state_lock = threading.Lock()
        self._thread = self._create_thread()
        self._started = False
        self._last_progress_by_job: dict[str, tuple[float, str, float]] = {}
        self._chain_progress_context_by_job: dict[str, dict[str, Any]] = {}
        self._deferred_recovery_job_ids: set[str] = set()
        self._placeholder_builder = PlaceholderBuilder(db)
        self._chat_executor = ChatMessageJobExecutor(
            db=db,
            generator=generator,
            mcp_tool_provider=mcp_tool_provider,
        )
        self._payloads = JobPayloadFactory(db)
        self._time = time

    def start(self) -> None:
        self.ensure_processing()

    def enqueue_generate(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="generate", payload=payload)

    def enqueue_upscale(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="upscale", payload=payload)

    def enqueue_upscale_video(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="upscale_video", payload=payload)

    def enqueue_convert_video_to_gif(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="convert_video_to_gif", payload=payload)

    def enqueue_generate_audio_video(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="generate_audio_video", payload=payload)

    def enqueue_generate_from_image(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="generate_from_image", payload=payload)

    def enqueue_generate_video(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="generate_video", payload=payload)

    def enqueue_animate_image(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="animate_image", payload=payload)

    def enqueue_generate_prompt(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="generate_prompt", payload=payload)

    def enqueue_generate_i2v_prompt(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="generate_i2v_prompt", payload=payload)

    def enqueue_chat_message(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type="chat_message", payload=payload)

    def enqueue_chain(self, payload: dict[str, Any]) -> str:
        return self._enqueue_job(job_type=self.CHAIN_PARENT_JOB_TYPE, payload=payload)

    def stats(self) -> dict[str, Any]:
        self.ensure_processing()
        with self._state_lock:
            return {
                "active_job_id": self._active_job_id,
                "queued_jobs": self._queue.qsize(),
                "shutdown_when_idle": self._shutdown_when_idle,
                "queue_idle": self._active_job_id is None and self._queue.qsize() == 0,
                "inter_job_delay_seconds": self._inter_job_delay_seconds,
                "worker_alive": self._thread.is_alive(),
            }

    def set_inter_job_delay_seconds(self, seconds: int) -> dict[str, Any]:
        self.ensure_processing()
        with self._state_lock:
            self._inter_job_delay_seconds = max(0, int(seconds))
        return self.stats()

    def cancel(self, job_id: str) -> dict[str, Any] | None:
        job = self.db.get_job(job_id)
        if job is None:
            return None
        parent_job_id = str(job.get("parent_job_id") or "").strip()
        with self._state_lock:
            is_active_job = self._active_job_id == job_id
            is_active_parent_job = bool(parent_job_id) and self._active_job_id == parent_job_id
        is_actively_running = job["status"] == "running" and is_active_job
        if parent_job_id:
            parent_job = self.db.get_job(parent_job_id)
            if parent_job is not None and parent_job["status"] not in {
                "completed",
                "failed",
                "cancelled",
            }:
                self.db.cancel_job(parent_job_id)
            if job["status"] not in {"completed", "failed", "cancelled"}:
                self.db.cancel_job(job_id)
            if is_active_parent_job or is_actively_running:
                try:
                    self.generator.cancel_active_job()
                except Exception:
                    logger.warning(
                        "Failed to propagate cancellation to the active runtime for child job %s",
                        job_id,
                        exc_info=True,
                    )
            refreshed_job = self.db.get_job(job_id)
            return refreshed_job if refreshed_job is not None else job
        if job["status"] not in {"completed", "failed", "cancelled"} and not is_actively_running:
            self.db.mark_job_cancelled(job_id, status_text="Cancelled")
            self._cleanup_placeholder_chain_for_job(job_id)
            refreshed_job = self.db.get_job(job_id)
            return refreshed_job if refreshed_job is not None else job

        job = self.db.cancel_job(job_id)
        if job is None:
            return None
        if is_actively_running:
            try:
                self.generator.cancel_active_job()
            except Exception:
                logger.warning(
                    "Failed to propagate cancellation to the active runtime for job %s",
                    job_id,
                    exc_info=True,
                )
        refreshed_job = self.db.get_job(job_id)
        return refreshed_job if refreshed_job is not None else job

    def cancel_all(self) -> list[dict[str, Any]]:
        active_jobs = self.db.list_jobs_by_statuses({"queued", "running"})
        cancelled_jobs: list[dict[str, Any]] = []
        for job in active_jobs:
            if job.get("cancel_requested"):
                continue
            job_id = str(job.get("id") or "").strip()
            if not job_id:
                continue
            cancelled_job = self.cancel(job_id)
            if cancelled_job is not None:
                cancelled_jobs.append(cancelled_job)
        return cancelled_jobs

    def request_shutdown_when_idle(self) -> dict[str, Any]:
        self.ensure_processing()
        with self._state_lock:
            self._shutdown_when_idle = True
            active_job_id = self._active_job_id
            queued_jobs = self._queue.qsize()
        if active_job_id is None and queued_jobs == 0:
            logger.info(
                "Shutdown when idle was requested while the queue was already idle; scheduling host shutdown now"
            )
        else:
            logger.info(
                "Shutdown when idle was enabled; waiting for %s running and %s queued jobs to finish",
                1 if active_job_id is not None else 0,
                queued_jobs,
            )
        shutdown = self._maybe_schedule_shutdown_when_idle()
        payload = self.stats()
        payload["scheduled"] = shutdown is not None
        if shutdown is not None:
            payload["shutdown"] = shutdown
        return payload

    def clear_shutdown_when_idle(self) -> dict[str, Any]:
        self.ensure_processing()
        with self._state_lock:
            self._shutdown_when_idle = False
        logger.info("Shutdown when idle was cleared")
        payload = self.stats()
        payload["scheduled"] = False
        return payload

    def _enqueue_job(self, *, job_type: str, payload: dict[str, Any]) -> str:
        self.ensure_processing()
        job_id = str(uuid.uuid4())
        result_image_id: str | None = None
        result_data: dict[str, Any] | None = None
        queued_payload = deepcopy(payload)
        if job_type == self.CHAIN_PARENT_JOB_TYPE:
            queued_payload, result_image_id = self._prepare_chain_parent_payload(
                job_id=job_id,
                payload=queued_payload,
            )
            result_data = self._initial_chain_state_for_steps(
                queued_payload.get("steps") if isinstance(queued_payload, dict) else None
            )
        elif self._needs_image_placeholder(job_type):
            result_image_id = str(uuid.uuid4())
            placeholder = self._build_placeholder(
                job_type=job_type,
                payload=queued_payload,
                image_id=result_image_id,
            )
            self.db.create_image_placeholder(
                image_id=result_image_id,
                status="queued",
                **placeholder,
            )
        self.db.insert_job(
            job_id=job_id,
            job_type=job_type,
            payload=queued_payload,
            result_image_id=result_image_id,
            result_data=result_data,
        )
        with self._state_lock:
            self._queued_job_ids.add(job_id)
        self._queue.put(QueuedJob(job_id=job_id, job_type=job_type, payload=queued_payload))
        return job_id

    def ensure_processing(self) -> None:
        with self._state_lock:
            self._start_thread_locked()
        self._recover_stalled_jobs()

    def cleanup_interrupted_jobs(self) -> int:
        try:
            interrupted_jobs = self.db.list_jobs_by_statuses({"running"})
        except Exception:
            logger.exception("Failed to inspect interrupted running jobs during startup cleanup")
            return 0

        cleaned = 0
        for job in interrupted_jobs:
            job_id = str(job.get("id") or "").strip()
            if not job_id:
                continue
            try:
                self._cleanup_interrupted_job(job)
                cleaned += 1
            except Exception:
                logger.exception("Failed to clean interrupted running job %s", job_id)
        return cleaned

    def has_recoverable_comfy_jobs(self) -> bool:
        try:
            recoverable_jobs = self.db.list_jobs_by_statuses({"queued", "running"})
        except Exception:
            logger.exception("Failed to inspect queued jobs for ComfyUI recovery gating")
            return False
        return any(
            str(job.get("type") or "").strip() in self.COMFY_DEPENDENT_JOB_TYPES
            for job in recoverable_jobs
        )

    def _create_thread(self) -> threading.Thread:
        return threading.Thread(target=self._run, daemon=True, name="gpu-worker")

    def _start_thread_locked(self) -> None:
        if self._thread.is_alive():
            return
        self._thread = self._create_thread()
        self._thread.start()
        self._started = True

    def _recover_stalled_jobs(self) -> None:
        try:
            recoverable_jobs = self.db.list_jobs_by_statuses({"queued", "running"})
        except Exception:
            logger.exception("Failed to inspect queued jobs for worker recovery")
            return

        for job in recoverable_jobs:
            job_id = str(job.get("id") or "").strip()
            job_type = str(job.get("type") or "").strip()
            parent_job_id = str(job.get("parent_job_id") or "").strip()
            if not job_id or not job_type:
                continue
            if parent_job_id:
                logger.info(
                    "Skipping direct recovery for child job %s because parent job %s owns it",
                    job_id,
                    parent_job_id,
                )
                continue

            payload_json = job.get("payload_json")
            try:
                payload = json.loads(payload_json) if isinstance(payload_json, str) else {}
            except (TypeError, ValueError, json.JSONDecodeError):
                logger.warning("Skipping recovery for job %s because its payload is invalid", job_id)
                continue
            if not isinstance(payload, dict):
                logger.warning("Skipping recovery for job %s because its payload is not an object", job_id)
                continue

            result_image_id = str(job.get("result_image_id") or "").strip()
            recovered_status = str(job.get("status") or "").strip().lower()
            with self._state_lock:
                if job_id == self._active_job_id or job_id in self._queued_job_ids:
                    continue

            if self._recovered_job_gate is not None and not self._recovered_job_gate(job_type):
                with self._state_lock:
                    first_deferral = job_id not in self._deferred_recovery_job_ids
                    self._deferred_recovery_job_ids.add(job_id)
                if first_deferral:
                    logger.info(
                        "Deferring recovery of %s job %s until its runtime is healthy",
                        job_type,
                        job_id,
                    )
                continue

            if result_image_id and not self._ensure_recovery_placeholder(
                job_type=job_type,
                payload=payload,
                result_image_id=result_image_id,
                recovered_status=recovered_status,
            ):
                continue

            with self._state_lock:
                self._deferred_recovery_job_ids.discard(job_id)

            if recovered_status == "running":
                try:
                    self._cleanup_interrupted_job(job)
                except Exception:
                    logger.exception("Failed to clean interrupted running job %s", job_id)
                continue

            with self._state_lock:
                if job_id == self._active_job_id or job_id in self._queued_job_ids:
                    continue
                self._queued_job_ids.add(job_id)
            self._queue.put(
                QueuedJob(
                    job_id=job_id,
                    job_type=job_type,
                    payload=payload,
                    parent_job_id=None,
                    chain_step_id=str(job.get("chain_step_id") or "").strip() or None,
                )
            )
            logger.info("Recovered %s job %s back into the worker queue", recovered_status or "queued", job_id)

    def _needs_image_placeholder(self, job_type: str) -> bool:
        return job_type not in {
            "generate_prompt",
            "generate_i2v_prompt",
            "chat_message",
            self.CHAIN_PARENT_JOB_TYPE,
        }

    def _ensure_recovery_placeholder(
        self,
        *,
        job_type: str,
        payload: dict[str, Any],
        result_image_id: str,
        recovered_status: str,
    ) -> bool:
        if not result_image_id or not self._needs_image_placeholder(job_type):
            return True
        if self.db.get_image(result_image_id) is not None:
            return True
        try:
            placeholder = self._build_placeholder(
                job_type=job_type,
                payload=payload,
                image_id=result_image_id,
            )
            self.db.create_image_placeholder(
                image_id=result_image_id,
                status=recovered_status if recovered_status in {"queued", "running"} else "queued",
                **placeholder,
            )
            logger.info(
                "Recreated missing %s placeholder %s during worker recovery",
                job_type,
                result_image_id,
            )
            return True
        except Exception:
            logger.exception(
                "Skipping recovery for job placeholder %s because it could not be rebuilt",
                result_image_id,
            )
            return False

    def _cleanup_interrupted_job(self, job: dict[str, Any]) -> None:
        job_id = str(job.get("id") or "").strip()
        if not job_id:
            return
        if str(job.get("type") or "").strip() == self.CHAIN_PARENT_JOB_TYPE:
            for child_job in self.db.list_jobs_by_parent(job_id):
                child_job_id = str(child_job.get("id") or "").strip()
                if not child_job_id or str(child_job.get("status") or "").strip() in {
                    "completed",
                    "failed",
                    "cancelled",
                }:
                    continue
                self.db.mark_job_cancelled(
                    child_job_id,
                    status_text="Cancelled because the chain was interrupted",
                )
                self._cleanup_placeholder_chain_for_job(child_job_id)
        if self._complete_interrupted_job_with_stored_result(job):
            return
        error_text = "Job was interrupted because the server restarted or the worker stopped."
        self.db.update_job(
            job_id,
            status="failed",
            progress=1.0,
            status_text="Interrupted by server restart",
            error=error_text,
        )
        failed_job = self.db.get_job(job_id)
        if failed_job is not None:
            self.error_store.log_job_error(failed_job)
        self._cleanup_placeholder_chain_for_job(job_id)

    def _complete_interrupted_job_with_stored_result(self, job: dict[str, Any]) -> bool:
        job_id = str(job.get("id") or "").strip()
        result_image_id = str(job.get("result_image_id") or "").strip()
        if not job_id or not result_image_id:
            return False
        result_image = self.db.get_image(result_image_id)
        if result_image is None or result_image.get("status") != "stored":
            return False
        self.db.update_job(
            job_id,
            status="completed",
            progress=1.0,
            status_text="Completed",
            result_image_id=result_image_id,
        )
        logger.info(
            "Recovered interrupted job %s as completed because result %s was already stored",
            job_id,
            result_image_id,
        )
        return True

    def _cleanup_placeholder_chain_for_job(self, job_id: str) -> None:
        job = self.db.get_job(job_id)
        if job is None:
            return
        self._cleanup_pending_chain_placeholders(job)
        result_image_id = str(job.get("result_image_id") or "").strip()
        if not result_image_id:
            return
        self._cancel_dependent_jobs(result_image_id)
        self.db.delete_image(result_image_id)

    def _cancel_dependent_jobs(self, source_image_id: str) -> None:
        dependent_jobs = self.db.list_jobs_using_source_image(source_image_id, statuses={"queued", "running"})
        for dependent_job in dependent_jobs:
            dependent_job_id = str(dependent_job.get("id") or "").strip()
            if not dependent_job_id:
                continue
            self.db.mark_job_cancelled(
                dependent_job_id,
                status_text="Cancelled because a source item was cancelled or failed",
            )
            self._cleanup_placeholder_chain_for_job(dependent_job_id)

    def _build_placeholder(
        self,
        *,
        job_type: str,
        payload: dict[str, Any],
        image_id: str,
    ) -> dict[str, Any]:
        return self._placeholder_builder.build(
            job_type=job_type,
            payload=payload,
            image_id=image_id,
        )

    def _prepare_chain_parent_payload(
        self,
        *,
        job_id: str,
        payload: dict[str, Any],
    ) -> tuple[dict[str, Any], str | None]:
        steps = payload.get("steps")
        if not isinstance(steps, list) or not steps:
            raise ValueError("Chain payload must include at least one step")

        prepared_steps: list[dict[str, Any]] = []
        for raw_step in steps:
            if not isinstance(raw_step, dict):
                raise ValueError("Each chain step must be an object")
            step = deepcopy(raw_step)
            step_id = str(step.get("id") or "").strip()
            step_type = str(step.get("type") or "").strip()
            if not step_id or step_type not in self.CHAIN_SUPPORTED_JOB_TYPES:
                raise ValueError(f"Unsupported chain step: {step_type or '<missing>'}")
            if step_type in self.CHAIN_ARTIFACT_JOB_TYPES:
                step["reserved_result_image_id"] = str(uuid.uuid4())
            prepared_steps.append(step)

        self._create_chain_placeholders(prepared_steps)
        final_result_image_id = self._chain_step_result_image_id(prepared_steps[-1])
        prepared_payload = {
            "steps": prepared_steps,
            "chain_parent_job_id": job_id,
        }
        client_request_id = str(payload.get("client_request_id") or "").strip()
        if client_request_id:
            prepared_payload["client_request_id"] = client_request_id
        return prepared_payload, final_result_image_id

    def _resolve_chain_step_payload(
        self,
        *,
        step: dict[str, Any],
        outputs: dict[str, dict[str, str]],
        for_placeholder: bool,
    ) -> dict[str, Any]:
        payload = deepcopy(step.get("payload") or {})
        if not isinstance(payload, dict):
            raise ValueError("Chain step payload must be an object")
        bindings = step.get("bindings") or {}
        if not isinstance(bindings, dict):
            raise ValueError("Chain step bindings must be an object")

        for field, binding in bindings.items():
            if not isinstance(binding, dict):
                raise ValueError("Each chain binding must be an object")
            dependency_step_id = str(binding.get("step_id") or "").strip()
            output_name = str(binding.get("output") or "").strip()
            if output_name not in self.CHAIN_ALLOWED_BINDING_OUTPUTS:
                raise ValueError(f"Unsupported chain binding output: {output_name}")
            dependency_outputs = outputs.get(dependency_step_id, {})
            if output_name == "result_text" and for_placeholder:
                payload[str(field)] = ""
                continue
            value = str(dependency_outputs.get(output_name) or "").strip()
            if not value:
                raise ValueError(
                    f"Missing chained output {output_name} from step {dependency_step_id}"
                )
            payload[str(field)] = value
        return payload

    def _cleanup_pending_chain_placeholders(self, job: dict[str, Any]) -> None:
        if str(job.get("type") or "").strip() != self.CHAIN_PARENT_JOB_TYPE:
            return
        for step in self._chain_steps_from_job_record(job):
            if not isinstance(step, dict):
                continue
            reserved_result_image_id = self._chain_step_result_image_id(step)
            step_id = str(step.get("id") or "").strip()
            if not reserved_result_image_id or not step_id:
                continue
            image = self.db.get_image(reserved_result_image_id)
            if image is None or image.get("status") == "stored":
                continue
            child_job = self.db.get_job_for_parent_step(str(job["id"]), step_id)
            if child_job is not None and child_job.get("status") == "completed":
                continue
            self.db.delete_image(reserved_result_image_id)

    def _initial_chain_state_for_steps(self, steps: Any) -> dict[str, Any] | None:
        if not isinstance(steps, list):
            return None
        return self._build_chain_state(steps)

    def _build_chain_state(self, steps: list[Any]) -> dict[str, Any]:
        return {
            "current_step_id": None,
            "current_child_job_id": None,
            "steps": self._build_chain_state_steps(steps),
        }

    def _build_chain_state_steps(self, steps: list[Any]) -> list[dict[str, Any]]:
        return [
            {
                "id": str(step.get("id") or ""),
                "type": str(step.get("type") or ""),
                "status": "queued",
                "child_job_id": None,
                "result_image_id": self._chain_step_result_image_id(step),
            }
            for step in steps
            if isinstance(step, dict)
        ]

    def _chain_step_result_image_id(self, step: dict[str, Any]) -> str | None:
        return str(step.get("reserved_result_image_id") or "").strip() or None

    def _create_chain_placeholders(self, steps: list[dict[str, Any]]) -> None:
        placeholder_outputs: dict[str, dict[str, str]] = {}
        for step in steps:
            step_id = str(step.get("id") or "").strip()
            reserved_result_image_id = self._chain_step_result_image_id(step)
            if not step_id or not reserved_result_image_id:
                continue
            resolved_payload = self._resolve_chain_step_payload(
                step=step,
                outputs=placeholder_outputs,
                for_placeholder=True,
            )
            placeholder = self._build_placeholder(
                job_type=str(step["type"]),
                payload=resolved_payload,
                image_id=reserved_result_image_id,
            )
            self.db.create_image_placeholder(
                image_id=reserved_result_image_id,
                status="queued",
                **placeholder,
            )
            placeholder_outputs[step_id] = {
                "result_image_id": reserved_result_image_id,
            }

    def _chain_steps_from_job_record(self, job: dict[str, Any]) -> list[dict[str, Any]]:
        raw_payload = job.get("payload_json")
        try:
            payload = json.loads(raw_payload) if isinstance(raw_payload, str) else {}
        except (TypeError, ValueError, json.JSONDecodeError):
            payload = {}
        if not isinstance(payload, dict):
            return []
        steps = payload.get("steps")
        if not isinstance(steps, list):
            return []
        return [step for step in steps if isinstance(step, dict)]
