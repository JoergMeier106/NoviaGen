from __future__ import annotations

import time
import uuid
from pathlib import Path
from typing import Callable

from PIL import Image

from .prompting import compose_positive_prompt
from .types import (
    GeneratedArtifact,
    VideoGenerationPayload,
    VideoToAudioPayload,
    VideoToGifPayload,
    VideoUpscalePayload,
)


class VideoGenerationMixin:
    def generate_video(
        self,
        payload: VideoGenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> GeneratedArtifact:
        with self._lock:
            self._lazy_imports()
            self._release_ollama_if_active()
            self._evict_all_local_models()
            self._active_runtime = "comfy"
            return self._comfy_video_manager.generate_video(
                payload=payload,
                output_dir=output_dir,
                progress_callback=progress_callback,
                cancel_requested=cancel_requested,
            )

    def animate_image(
        self,
        *,
        source_image_path: Path,
        payload: VideoGenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> GeneratedArtifact:
        with self._lock:
            self._lazy_imports()
            self._release_ollama_if_active()
            self._evict_all_local_models()
            self._active_runtime = "comfy"
            return self._comfy_video_manager.animate_image(
                source_image_path=source_image_path,
                payload=payload,
                output_dir=output_dir,
                progress_callback=progress_callback,
                cancel_requested=cancel_requested,
            )

    def expected_video_output_fps(
        self,
        *,
        image_to_video: bool,
        requested_fps: int,
    ) -> int:
        with self._lock:
            self._lazy_imports()
            return self._comfy_video_manager.expected_output_fps(
                image_to_video=image_to_video,
                requested_fps=requested_fps,
            )

    def upscale_video(
        self,
        *,
        source_video_path: Path,
        payload: VideoUpscalePayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> GeneratedArtifact:
        with self._lock:
            self._lazy_imports()
            self._release_ollama_if_active()
            self._evict_all_local_models()
            self._active_runtime = "comfy"
            return self._comfy_video_manager.upscale_video(
                source_video_path=source_video_path,
                payload=payload,
                output_dir=output_dir,
                progress_callback=progress_callback,
                cancel_requested=cancel_requested,
            )

    def convert_video_to_gif(
        self,
        *,
        source_video_path: Path,
        payload: VideoToGifPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        import imageio.v3 as iio

        image_id = str(uuid.uuid4())
        output_path = output_dir / f"{image_id}.gif"
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
        )
        started_at = time.perf_counter()
        self._emit_progress(progress_callback, 0.08, "Preparing GIF conversion")

        frames: list[Image.Image] = []
        frame_counter = 0
        for frame_counter, frame in enumerate(iio.imiter(source_video_path), start=1):
            frames.append(Image.fromarray(frame).convert("RGB"))
            if frame_counter <= 3 or frame_counter % 8 == 0:
                self._emit_progress(
                    progress_callback,
                    min(0.9, 0.12 + min(frame_counter, 48) * 0.015),
                    f"Converting video to GIF {frame_counter}",
                )

        if not frames:
            raise ValueError("The source video does not contain any frames")

        self._emit_progress(progress_callback, 0.94, "Saving GIF")
        duration_ms = max(20, round(1000 / max(1, payload.fps or 12)))
        frames[0].save(
            output_path,
            format="GIF",
            save_all=True,
            append_images=frames[1:],
            duration=duration_ms,
            loop=0,
            optimize=False,
            disposal=2,
        )
        width, height = frames[0].size
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(output_path),
            width=width,
            height=height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=final_positive_prompt,
            model_id=payload.model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation=payload.image_orientation,
            source_image_id=payload.source_image_id,
            mime_type="image/gif",
            media_type="gif",
            generation_duration_seconds=time.perf_counter() - started_at,
        )

    def generate_audio_video(
        self,
        *,
        source_video_path: Path,
        payload: VideoToAudioPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> GeneratedArtifact:
        with self._lock:
            self._lazy_imports()
            self._release_ollama_if_active()
            self._evict_all_local_models()
            self._active_runtime = "comfy"
            return self._comfy_video_manager.generate_audio_video(
                source_video_path=source_video_path,
                payload=payload,
                output_dir=output_dir,
                progress_callback=progress_callback,
                cancel_requested=cancel_requested,
            )

    def create_video_poster(
        self,
        *,
        video_path: Path,
        output_dir: Path,
        image_id: str,
        fallback_source_image_path: Path | None = None,
        width: int | None = None,
        height: int | None = None,
    ) -> tuple[str | None, str | None]:
        poster_path, poster_mime_type = self._comfy_video_manager.create_video_poster(
            video_path=video_path,
            output_dir=output_dir,
            image_id=image_id,
            fallback_source_image_path=fallback_source_image_path,
            width=width,
            height=height,
        )
        return (str(poster_path) if poster_path is not None else None, poster_mime_type)
