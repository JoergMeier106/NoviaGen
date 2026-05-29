from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Any

from ...comfy import ComfyPromptCancelledError
from ...generation import OllamaStreamCancelledError
from ..models import JobCancelledError, QueuedJob


class JobExecutionJobMixin:
    def _run_generate_job(self, job: QueuedJob) -> Any:
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Starting generation",
        )
        return self.generator.generate(
            self._payloads.generation_payload(job.payload),
            self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
        )

    def _run_upscale_job(self, job: QueuedJob) -> Any:
        source_image = self.db.get_image(job.payload["image_id"])
        if source_image is None:
            raise KeyError(f"Source image not found: {job.payload['image_id']}")
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Starting scaling",
        )
        return self.generator.upscale(
            source_image_id=source_image["id"],
            source_image_path=Path(source_image["file_path"]),
            payload=self._payloads.upscale_generation_payload(
                source_image,
                job.payload,
            ),
            scale_factor=float(job.payload["scale_factor"]),
            output_dir=self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
        )

    def _run_upscale_video_job(self, job: QueuedJob) -> Any:
        source_video = self._get_source_video(
            job,
            invalid_media_message="Only videos can be scaled",
        )
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Starting video scaling",
        )
        return self.generator.upscale_video(
            source_video_path=Path(source_video["file_path"]),
            payload=self._payloads.video_upscale_payload(source_video, job.payload),
            output_dir=self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
            cancel_requested=lambda: self._is_cancel_requested(job.job_id),
        )

    def _run_convert_video_to_gif_job(self, job: QueuedJob) -> Any:
        source_video = self._get_source_video(
            job,
            invalid_media_message="Only videos can be converted to GIF",
        )
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Preparing GIF conversion",
        )
        return self.generator.convert_video_to_gif(
            source_video_path=Path(source_video["file_path"]),
            payload=self._payloads.video_to_gif_payload(source_video),
            output_dir=self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
        )

    def _run_generate_audio_video_job(self, job: QueuedJob) -> Any:
        source_video = self._get_source_video(
            job,
            invalid_media_message="Only videos can be used to generate audio video",
        )
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Preparing audio video",
        )
        return self.generator.generate_audio_video(
            source_video_path=Path(source_video["file_path"]),
            payload=self._payloads.video_to_audio_payload(source_video),
            output_dir=self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
            cancel_requested=lambda: self._is_cancel_requested(job.job_id),
        )

    def _run_generate_from_image_job(self, job: QueuedJob) -> Any:
        source_image_id = str(job.payload.get("image_id", "")).strip() or None
        source_image_path = self._payloads.resolve_image_source(job.payload)
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Starting image-to-image generation",
        )
        return self.generator.generate_from_image(
            source_image_path=source_image_path,
            source_image_id=source_image_id,
            payload=self._payloads.generation_payload(job.payload),
            output_dir=self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
        )

    def _run_generate_video_job(self, job: QueuedJob) -> Any:
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Preparing video generation",
        )
        return self.generator.generate_video(
            self._payloads.video_generation_payload(job.payload),
            self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
            cancel_requested=lambda: self._is_cancel_requested(job.job_id),
        )

    def _run_animate_image_job(self, job: QueuedJob) -> Any:
        source_image_id = str(job.payload.get("image_id", "")).strip() or None
        source_image_path = self._payloads.resolve_image_source(job.payload)
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.04,
            status_text="Preparing animation",
        )
        return self.generator.animate_image(
            source_image_path=source_image_path,
            payload=self._payloads.video_generation_payload(
                {
                    **job.payload,
                    "source_image_id": source_image_id,
                }
            ),
            output_dir=self.temp_dir,
            progress_callback=lambda progress, status_text: self._update_progress_for_job(
                job,
                progress=progress,
                status_text=status_text,
            ),
            cancel_requested=lambda: self._is_cancel_requested(job.job_id),
        )

    def _run_generate_prompt_job(self, job: QueuedJob) -> None:
        self._update_progress_for_job(
            job,
            progress=0.08,
            status_text="Generating prompt",
        )
        generated_prompt = self.generator.generate_prompt(
            str(job.payload.get("prompt", "")).strip(),
            model=str(job.payload.get("model_name") or "").strip() or None,
        ).strip()
        if not generated_prompt:
            raise ValueError("Prompt generation returned an empty result")
        self.db.update_job(
            job.job_id,
            status="completed",
            progress=1.0,
            status_text="Completed",
            result_data={"text": generated_prompt},
        )

    def _run_generate_i2v_prompt_job(self, job: QueuedJob) -> None:
        source_image_path = self._payloads.resolve_image_source(job.payload)
        self._update_progress_for_job(
            job,
            progress=0.08,
            status_text="Generating video prompt",
        )
        generated_prompt = self.generator.generate_i2v_prompt(
            prompt=str(job.payload.get("prompt", "")),
            source_image_path=source_image_path,
            model=str(job.payload.get("model_name") or "").strip() or None,
        ).strip()
        if not generated_prompt:
            raise ValueError("Prompt generation returned an empty result")
        self.db.update_job(
            job.job_id,
            status="completed",
            progress=1.0,
            status_text="Completed",
            result_data={"text": generated_prompt},
        )

    def _run_chat_message_job(self, job: QueuedJob) -> None:
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.08,
            status_text="Preparing chat",
        )
        chat_result = self._chat_executor.run(
            job,
            cancel_requested=self._is_cancel_requested,
            raise_if_cancel_requested=self._raise_if_cancel_requested,
        )
        self.db.update_job(
            job.job_id,
            status="completed",
            progress=1.0,
            status_text="Completed",
            result_data=chat_result,
        )

    def _run_chain_job(self, job: QueuedJob) -> None:
        steps = job.payload.get("steps")
        if not isinstance(steps, list) or not steps:
            raise ValueError("Chain payload must include at least one step")

        total_steps = len(steps)
        chain_state = self._initial_chain_state_for_steps(steps)
        if chain_state is None:
            raise ValueError("Chain payload must include at least one step")
        self._start_chain_parent_job(job.job_id, chain_state)

        outputs: dict[str, dict[str, str]] = {}
        for index, raw_step in enumerate(steps):
            step = self._require_chain_step(raw_step)
            step_id = str(step.get("id") or "").strip()
            self._raise_if_cancel_requested(job.job_id)

            child_payload = self._resolve_chain_step_payload(
                step=step,
                outputs=outputs,
                for_placeholder=False,
            )
            child_job = self._create_chain_child_job(
                parent_job_id=job.job_id,
                step=step,
                child_payload=child_payload,
            )
            self._queue_chain_child_step(
                parent_job_id=job.job_id,
                child_job=child_job,
                completed_steps=index,
                total_steps=total_steps,
                chain_state=chain_state,
            )

            self._execute_chain_child_step(child_job)

            child_record = self.db.get_job(child_job.job_id)
            if child_record is None:
                raise RuntimeError(f"Child job disappeared: {child_job.job_id}")
            outputs[step_id] = self._chain_outputs_for_job(child_record)
            self._finalize_chain_child_step(
                parent_job_id=job.job_id,
                child_job=child_job,
                child_record=child_record,
                step_outputs=outputs[step_id],
                completed_steps=index + 1,
                total_steps=total_steps,
                chain_state=chain_state,
            )

        self._complete_chain_parent_job(job.job_id, chain_state)

    def _start_chain_parent_job(self, job_id: str, chain_state: dict[str, Any]) -> None:
        self.db.update_job(
            job_id,
            status="running",
            progress=0.0,
            status_text="Queued for processing",
            result_data=chain_state,
        )

    def _require_chain_step(self, raw_step: Any) -> dict[str, Any]:
        if not isinstance(raw_step, dict):
            raise ValueError("Each chain step must be an object")
        step_id = str(raw_step.get("id") or "").strip()
        step_type = str(raw_step.get("type") or "").strip()
        if not step_id or not step_type:
            raise ValueError("Each chain step requires id and type")
        return raw_step

    def _create_chain_child_job(
        self,
        *,
        parent_job_id: str,
        step: dict[str, Any],
        child_payload: dict[str, Any],
    ) -> QueuedJob:
        child_job_id = str(uuid.uuid4())
        child_job = QueuedJob(
            job_id=child_job_id,
            job_type=str(step["type"]),
            payload=child_payload,
            parent_job_id=parent_job_id,
            chain_step_id=str(step["id"]),
        )
        self.db.insert_job(
            job_id=child_job_id,
            job_type=child_job.job_type,
            payload=child_payload,
            parent_job_id=parent_job_id,
            chain_step_id=child_job.chain_step_id,
            result_image_id=self._chain_step_result_image_id(step),
        )
        return child_job

    def _queue_chain_child_step(
        self,
        *,
        parent_job_id: str,
        child_job: QueuedJob,
        completed_steps: int,
        total_steps: int,
        chain_state: dict[str, Any],
    ) -> None:
        self._chain_progress_context_by_job[child_job.job_id] = {
            "parent_job_id": parent_job_id,
            "step_id": child_job.chain_step_id,
            "completed_steps": completed_steps,
            "total_steps": total_steps,
            "chain_state": chain_state,
        }
        self._update_chain_step_state(
            chain_state,
            step_id=str(child_job.chain_step_id or ""),
            child_job_id=child_job.job_id,
            status="queued",
        )
        self.db.update_job(
            parent_job_id,
            status="running",
            progress=float(completed_steps) / float(total_steps),
            status_text=self._chain_step_progress_label(child_job.job_type),
            result_data=chain_state,
        )

    def _chain_step_progress_label(self, step_type: str) -> str:
        return {
            "generate": "Generating image",
            "generate_from_image": "Generating image",
            "generate_prompt": "Generating prompt",
            "generate_i2v_prompt": "Generating video prompt",
            "generate_video": "Generating video",
            "animate_image": "Animating image",
            "upscale": "Scaling image",
            "upscale_video": "Scaling video",
            "convert_video_to_gif": "Converting video to GIF",
            "generate_audio_video": "Generating audio video",
            "chat_message": "Generating response",
        }.get(str(step_type or "").strip(), "Running workflow step")

    def _execute_chain_child_step(self, child_job: QueuedJob) -> None:
        artifact = None
        try:
            artifact = self._execute_job(child_job)
            if artifact is not None:
                self._complete_artifact_job(child_job, artifact)
        except (
            JobCancelledError,
            ComfyPromptCancelledError,
            OllamaStreamCancelledError,
        ):
            self._handle_cancelled_job(child_job, artifact)
            raise
        except Exception as exc:
            self._handle_failed_job(child_job, artifact, exc)
            raise
        finally:
            self._cleanup_uploaded_source(child_job)
            self._chain_progress_context_by_job.pop(child_job.job_id, None)

    def _finalize_chain_child_step(
        self,
        *,
        parent_job_id: str,
        child_job: QueuedJob,
        child_record: dict[str, Any],
        step_outputs: dict[str, str],
        completed_steps: int,
        total_steps: int,
        chain_state: dict[str, Any],
    ) -> None:
        self._update_chain_step_state(
            chain_state,
            step_id=str(child_job.chain_step_id or ""),
            child_job_id=child_job.job_id,
            status=str(child_record.get("status") or ""),
            result_image_id=str(child_record.get("result_image_id") or "").strip() or None,
            result_text=str(step_outputs.get("result_text") or "").strip() or None,
        )
        self.db.update_job(
            parent_job_id,
            status="running",
            progress=float(completed_steps) / float(total_steps),
            status_text="Completed" if completed_steps == total_steps else "Queued for processing",
            result_data=chain_state,
        )

    def _complete_chain_parent_job(self, parent_job_id: str, chain_state: dict[str, Any]) -> None:
        parent_record = self.db.get_job(parent_job_id)
        self.db.update_job(
            parent_job_id,
            status="completed",
            progress=1.0,
            status_text="Completed",
            result_image_id=(
                str(parent_record.get("result_image_id") or "").strip()
                if parent_record is not None
                else None
            )
            or None,
            result_data=chain_state,
        )

    def _update_chain_step_state(
        self,
        chain_state: dict[str, Any],
        *,
        step_id: str,
        child_job_id: str | None,
        status: str,
        result_image_id: str | None = None,
        result_text: str | None = None,
    ) -> None:
        chain_state["current_step_id"] = None if status != "queued" else step_id
        chain_state["current_child_job_id"] = None if status != "queued" else child_job_id
        if status == "running":
            chain_state["current_step_id"] = step_id
            chain_state["current_child_job_id"] = child_job_id
        for step_state in chain_state["steps"]:
            if str(step_state.get("id") or "") != step_id:
                continue
            step_state["status"] = status
            step_state["child_job_id"] = child_job_id
            if result_image_id:
                step_state["result_image_id"] = result_image_id
            if result_text:
                step_state["result_text"] = result_text
            break

    def _chain_outputs_for_job(self, job: dict[str, Any]) -> dict[str, str]:
        outputs: dict[str, str] = {}
        result_image_id = str(job.get("result_image_id") or "").strip()
        if result_image_id:
            outputs["result_image_id"] = result_image_id
        raw_result_data = job.get("result_json")
        try:
            result_data = json.loads(raw_result_data) if isinstance(raw_result_data, str) else {}
        except (TypeError, ValueError, json.JSONDecodeError):
            result_data = {}
        if isinstance(result_data, dict):
            result_text = str(result_data.get("text") or "").strip()
            if result_text:
                outputs["result_text"] = result_text
        return outputs

    def _get_source_video(
        self,
        job: QueuedJob,
        *,
        invalid_media_message: str,
    ) -> dict[str, Any]:
        source_video = self.db.get_image(job.payload["image_id"])
        if source_video is None:
            raise KeyError(f"Source video not found: {job.payload['image_id']}")
        if source_video.get("media_type", "image") != "video":
            raise ValueError(invalid_media_message)
        return source_video
