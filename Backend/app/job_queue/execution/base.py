from __future__ import annotations

import logging
from typing import Any

from ...comfy import ComfyPromptCancelledError
from ...generation import OllamaStreamCancelledError
from .jobs import JobExecutionJobMixin
from .lifecycle import JobExecutionLifecycleMixin
from ..models import JobCancelledError, QueuedJob


logger = logging.getLogger("app.job_queue")


class JobExecutionMixin(JobExecutionJobMixin, JobExecutionLifecycleMixin):
    def _run(self) -> None:
        while True:
            job = self._queue.get()
            with self._state_lock:
                self._queued_job_ids.discard(job.job_id)
                self._active_job_id = job.job_id

            artifact = None
            try:
                artifact = self._execute_job(job)
                if artifact is not None:
                    self._complete_artifact_job(job, artifact)
            except (JobCancelledError, ComfyPromptCancelledError, OllamaStreamCancelledError):
                self._handle_cancelled_job(job, artifact)
            except Exception as exc:
                self._handle_failed_job(job, artifact, exc)
            finally:
                self._cleanup_uploaded_source(job)
                with self._state_lock:
                    self._active_job_id = None
                self._queue.task_done()
                self._maybe_pause_between_jobs()
                self._maybe_schedule_shutdown_when_idle()

    def _execute_job(self, job: QueuedJob) -> Any:
        current_job = self.db.get_job(job.job_id)
        if current_job is None or current_job["status"] == "cancelled":
            if current_job is not None:
                self._cleanup_placeholder_chain_for_job(job.job_id)
            return None

        self._raise_if_cancel_requested(job.job_id)
        result_image_id = str(current_job.get("result_image_id") or "").strip() or None
        if result_image_id is not None:
            self.db.update_image_status(result_image_id, "running")
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.02,
            status_text="Queued for processing",
        )

        if job.job_type == "generate":
            return self._run_generate_job(job)
        if job.job_type == "upscale":
            return self._run_upscale_job(job)
        if job.job_type == "upscale_video":
            return self._run_upscale_video_job(job)
        if job.job_type == "convert_video_to_gif":
            return self._run_convert_video_to_gif_job(job)
        if job.job_type == "generate_audio_video":
            return self._run_generate_audio_video_job(job)
        if job.job_type == "generate_from_image":
            return self._run_generate_from_image_job(job)
        if job.job_type == "generate_video":
            return self._run_generate_video_job(job)
        if job.job_type == "animate_image":
            return self._run_animate_image_job(job)
        if job.job_type == "generate_prompt":
            self._run_generate_prompt_job(job)
            return None
        if job.job_type == "generate_i2v_prompt":
            self._run_generate_i2v_prompt_job(job)
            return None
        if job.job_type == self.CHAIN_PARENT_JOB_TYPE:
            self._run_chain_job(job)
            return None
        if job.job_type == "chat_message":
            self._run_chat_message_job(job)
            return None
        raise ValueError(f"Unsupported job_type: {job.job_type}")
