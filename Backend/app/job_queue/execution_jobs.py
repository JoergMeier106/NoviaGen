from __future__ import annotations

from pathlib import Path
from typing import Any

from .models import QueuedJob


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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
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
            progress_callback=lambda progress, status_text: self._update_job_progress(
                job.job_id,
                progress=progress,
                status_text=status_text,
            ),
            cancel_requested=lambda: self._is_cancel_requested(job.job_id),
        )

    def _run_generate_prompt_job(self, job: QueuedJob) -> None:
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.08,
            status_text="Preparing prompt generation",
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
        self.db.update_job(
            job.job_id,
            status="running",
            progress=0.08,
            status_text="Preparing prompt generation",
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
