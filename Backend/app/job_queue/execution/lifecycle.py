from __future__ import annotations

import logging
from dataclasses import replace
from pathlib import Path
from typing import Any

from ..models import JobCancelledError, QueuedJob
from ..metadata import (
    auto_metadata_enabled,
    auto_metadata_model_name,
    generate_image_metadata,
)


logger = logging.getLogger("app.job_queue")


class JobExecutionLifecycleMixin:
    def _complete_artifact_job(self, job: QueuedJob, artifact: Any) -> None:
        self._raise_if_cancel_requested(job.job_id)
        if artifact.media_type == "video" and not artifact.poster_path:
            self._update_job_progress(
                job.job_id,
                progress=0.98,
                status_text="Finalizing video",
            )
            artifact = self._attach_video_poster(artifact)
        current_job = self.db.get_job(job.job_id)
        if current_job is None:
            raise RuntimeError("Job disappeared before completion")
        result_image_id = (
            str(current_job.get("result_image_id") or "").strip()
            or artifact.image_id
        )
        finalized_image = self.db.finalize_image_placeholder(result_image_id, artifact)
        if finalized_image is not None:
            self._apply_completion_metadata(
                job=job,
                image=finalized_image,
            )
        self._last_progress_by_job.pop(job.job_id, None)
        self.db.update_job(
            job.job_id,
            status="completed",
            progress=1.0,
            status_text="Completed",
            result_image_id=result_image_id,
        )
        self._delete_scaling_source_if_requested(
            job.payload,
            result_image_id=result_image_id,
        )

    def _apply_completion_metadata(self, *, job: QueuedJob, image: dict[str, Any]) -> None:
        if job.job_type == "animate_image":
            self._copy_source_metadata_to_image(job=job, image=image)
            return
        if job.job_type not in {"generate", "generate_from_image"}:
            return
        model_name = auto_metadata_model_name(job.payload)
        if not auto_metadata_enabled(job.payload) or not model_name:
            return
        try:
            self.db.update_job(
                job.job_id,
                status="running",
                progress=0.99,
                status_text="Adding caption and tags",
            )
            metadata = generate_image_metadata(
                generator=self.generator,
                model_name=model_name,
                image_path=image["file_path"],
                existing_tags=self.db.list_tags(),
            )
            self.db.set_image_caption_and_tags(
                str(image["id"]),
                caption=str(metadata.get("caption") or ""),
                tags=list(metadata.get("tags") or []),
            )
        except Exception as exc:
            logger.warning(
                "Failed to add automatic metadata for image %s",
                image.get("id"),
                exc_info=True,
            )
            self._log_auto_metadata_error(
                job=job,
                image=image,
                model_name=model_name,
                exc=exc,
            )

    def _copy_source_metadata_to_image(
        self,
        *,
        job: QueuedJob,
        image: dict[str, Any],
    ) -> None:
        source_image_id = str(job.payload.get("image_id") or "").strip()
        if not source_image_id:
            return
        source_image = self.db.get_image(source_image_id)
        if source_image is None:
            return
        self.db.set_image_caption_and_tags(
            str(image["id"]),
            caption=str(source_image.get("caption") or ""),
            tags=list(source_image.get("tags") or []),
        )

    def _log_auto_metadata_error(
        self,
        *,
        job: QueuedJob,
        image: dict[str, Any],
        model_name: str,
        exc: Exception,
    ) -> None:
        try:
            self.error_store.log_system_error(
                operation="auto_metadata",
                error_text=str(exc),
                status_text="Automatic caption and tag generation failed",
                payload={
                    "job_id": job.job_id,
                    "image_id": str(image.get("id") or ""),
                    "mode": job.job_type,
                    "model_name": model_name,
                },
            )
        except Exception:
            logger.warning("Failed to log automatic metadata error", exc_info=True)

    def _handle_cancelled_job(self, job: QueuedJob, artifact: Any) -> None:
        self._cleanup_generated_artifact(artifact)
        self._last_progress_by_job.pop(job.job_id, None)
        try:
            self.db.mark_job_cancelled(job.job_id, status_text="Cancelled")
            self._cleanup_placeholder_chain_for_job(job.job_id)
        except Exception:
            logger.exception("Failed to mark job %s as cancelled", job.job_id)

    def _handle_failed_job(self, job: QueuedJob, artifact: Any, exc: Exception) -> None:
        self._cleanup_generated_artifact(artifact)
        self._last_progress_by_job.pop(job.job_id, None)
        try:
            self.db.update_job(
                job.job_id,
                status="failed",
                progress=1.0,
                status_text="Failed",
                error=str(exc),
            )
            failed_job = self.db.get_job(job.job_id)
            if failed_job is not None:
                self.error_store.log_job_error(failed_job)
            self._cleanup_placeholder_chain_for_job(job.job_id)
        except Exception:
            logger.exception("Failed to persist failure state for job %s", job.job_id)

    def _delete_scaling_source_if_requested(
        self,
        payload: dict[str, Any],
        *,
        result_image_id: str,
    ) -> None:
        if not bool(payload.get("delete_source_after_finish", False)):
            return
        source_image_id = str(payload.get("image_id", "")).strip()
        if not source_image_id or source_image_id == result_image_id:
            return
        try:
            self.db.delete_image(source_image_id)
        except Exception:
            logger.warning(
                "Failed to auto-delete scaling source %s after result %s",
                source_image_id,
                result_image_id,
                exc_info=True,
            )

    def _cleanup_uploaded_source(self, job: QueuedJob) -> None:
        uploaded_paths: list[str] = []
        if job.job_type in {"generate_from_image", "animate_image", "generate_i2v_prompt"}:
            uploaded_path = str(job.payload.get("upload_image_path", "")).strip()
            if uploaded_path:
                uploaded_paths.append(uploaded_path)
        if job.job_type == self.CHAIN_PARENT_JOB_TYPE:
            steps = job.payload.get("steps")
            if isinstance(steps, list):
                for step in steps:
                    if not isinstance(step, dict):
                        continue
                    payload = step.get("payload")
                    if not isinstance(payload, dict):
                        continue
                    uploaded_path = str(payload.get("upload_image_path", "")).strip()
                    if uploaded_path:
                        uploaded_paths.append(uploaded_path)
        if job.job_type == "chat_message":
            attachments = job.payload.get("attachments")
            if isinstance(attachments, list):
                for attachment in attachments:
                    if not isinstance(attachment, dict):
                        continue
                    context_image_path = str(attachment.get("context_image_path") or "").strip()
                    if context_image_path:
                        uploaded_paths.append(context_image_path)
        for uploaded_path in uploaded_paths:
            try:
                Path(uploaded_path).unlink(missing_ok=True)
            except OSError:
                pass

    def _attach_video_poster(self, artifact: Any) -> Any:
        if artifact.media_type != "video" or artifact.poster_path:
            return artifact
        source_image_path: Path | None = None
        source_image_id = str(artifact.source_image_id or "").strip()
        if source_image_id:
            source_image = self.db.get_image(source_image_id)
            if source_image is not None:
                poster_path = str(source_image.get("poster_path") or "").strip()
                if source_image.get("media_type") == "video" and poster_path:
                    source_image_path = Path(poster_path)
                else:
                    source_image_path = Path(source_image["file_path"])
        try:
            poster_path, poster_mime_type = self.generator.create_video_poster(
                video_path=Path(artifact.file_path),
                output_dir=self.temp_dir,
                image_id=artifact.image_id,
                fallback_source_image_path=source_image_path,
                width=artifact.width,
                height=artifact.height,
            )
            if poster_path is None:
                return artifact
            return replace(
                artifact,
                poster_path=str(poster_path),
                poster_mime_type=poster_mime_type,
            )
        except Exception:
            logger.warning(
                "Failed to generate poster for video %s before completion",
                artifact.image_id,
                exc_info=True,
            )
            return artifact

    def _update_progress_for_job(
        self,
        job: QueuedJob,
        *,
        progress: float,
        status_text: str,
    ) -> None:
        self._update_job_progress(
            job.job_id,
            progress=progress,
            status_text=status_text,
        )
        self._update_parent_chain_progress(
            job.job_id,
            progress=progress,
            status_text=status_text,
        )

    def _update_job_progress(self, job_id: str, *, progress: float, status_text: str) -> None:
        now = self._time.monotonic()
        progress = max(0.0, min(1.0, float(progress)))
        previous = self._last_progress_by_job.get(job_id)
        should_write = previous is None
        if previous is not None:
            last_progress, last_status_text, last_written_at = previous
            progress = max(last_progress, progress)
            should_write = (
                status_text != last_status_text
                or progress >= 1.0
                or progress - last_progress >= 0.01
                or now - last_written_at >= 1.0
            )
        if should_write:
            try:
                self.db.update_job(
                    job_id,
                    status="running",
                    progress=progress,
                    status_text=status_text,
                )
                self._last_progress_by_job[job_id] = (progress, status_text, now)
            except Exception:
                logger.warning(
                    "Skipping progress update for job %s due to transient database error",
                    job_id,
                    exc_info=True,
                )
        else:
            last_progress, last_status_text, last_written_at = previous
            self._last_progress_by_job[job_id] = (
                max(last_progress, progress),
                status_text if status_text != last_status_text else last_status_text,
                last_written_at,
            )
        if status_text != "Waiting for job to stop":
            self._raise_if_cancel_requested(job_id)

    def _update_parent_chain_progress(
        self,
        child_job_id: str,
        *,
        progress: float,
        status_text: str,
    ) -> None:
        context = self._chain_progress_context_by_job.get(child_job_id)
        if context is None:
            return
        total_steps = max(1, int(context["total_steps"]))
        completed_steps = max(0, int(context["completed_steps"]))
        parent_progress = min(
            0.999,
            (float(completed_steps) + max(0.0, min(1.0, float(progress)))) / float(total_steps),
        )
        chain_state = context.get("chain_state")
        if isinstance(chain_state, dict):
            chain_state["current_step_id"] = context.get("step_id")
            chain_state["current_child_job_id"] = child_job_id
            for item in chain_state.get("steps", []):
                if (
                    isinstance(item, dict)
                    and str(item.get("id") or "") == str(context.get("step_id") or "")
                ):
                    item["status"] = "running"
                    item["child_job_id"] = child_job_id
                    break
        self.db.update_job(
            str(context["parent_job_id"]),
            status="running",
            progress=parent_progress,
            status_text=status_text,
            result_data=chain_state if isinstance(chain_state, dict) else None,
        )

    def _raise_if_cancel_requested(self, job_id: str) -> None:
        if self._is_cancel_requested(job_id):
            raise JobCancelledError(job_id)

    def _is_cancel_requested(self, job_id: str) -> bool:
        try:
            if self.db.should_cancel_job(job_id):
                return True
            context = self._chain_progress_context_by_job.get(job_id)
            if context is not None and self.db.should_cancel_job(
                str(context["parent_job_id"])
            ):
                return True
            job = self.db.get_job(job_id)
            parent_job_id = str(job.get("parent_job_id") or "").strip() if job else ""
            if parent_job_id and self.db.should_cancel_job(parent_job_id):
                return True
            return False
        except Exception:
            logger.warning(
                "Skipping cancellation check for job %s due to transient database error",
                job_id,
                exc_info=True,
            )
            return False

    def _cleanup_generated_artifact(self, artifact: Any) -> None:
        if artifact is None:
            return
        for path_value in (
            getattr(artifact, "file_path", None),
            getattr(artifact, "poster_path", None),
        ):
            if not path_value:
                continue
            try:
                Path(path_value).unlink(missing_ok=True)
            except OSError:
                pass

    def _maybe_schedule_shutdown_when_idle(self) -> dict[str, Any] | None:
        with self._state_lock:
            active_job_id = self._active_job_id
            queued_jobs = self._queue.qsize()
            should_schedule = (
                self._shutdown_when_idle
                and active_job_id is None
                and queued_jobs == 0
                and self.shutdown_controller is not None
            )
            if should_schedule:
                self._shutdown_when_idle = False
            controller = self.shutdown_controller
        if not should_schedule or controller is None:
            return None
        logger.info("Job queue drained; requesting host shutdown")
        return controller.request_shutdown()

    def _maybe_pause_between_jobs(self) -> None:
        with self._state_lock:
            delay_seconds = self._inter_job_delay_seconds
            has_queued_jobs = self._queue.qsize() > 0
        if delay_seconds <= 0 or not has_queued_jobs:
            return
        logger.info(
            "Pausing %.1fs before starting the next queued job",
            float(delay_seconds),
        )
        self._time.sleep(float(delay_seconds))
