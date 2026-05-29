from __future__ import annotations

from pathlib import Path
from typing import Callable, Protocol

from .types import (
    GeneratedArtifact,
    GenerationPayload,
    VideoGenerationPayload,
    VideoToAudioPayload,
    VideoToGifPayload,
    VideoUpscalePayload,
)


class ImageGenerator(Protocol):
    def generate_prompt(
        self,
        prompt: str,
        image_bytes: bytes | None = None,
        *,
        model: str | None = None,
    ) -> str:
        ...

    def generate_i2v_prompt(
        self,
        *,
        prompt: str,
        source_image_path: Path,
        model: str | None = None,
    ) -> str:
        ...

    def generate(
        self,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def upscale(
        self,
        *,
        source_image_id: str,
        source_image_path: Path,
        payload: GenerationPayload,
        scale_factor: float,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def generate_from_image(
        self,
        *,
        source_image_path: Path,
        source_image_id: str | None,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def generate_video(
        self,
        payload: VideoGenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def animate_image(
        self,
        *,
        source_image_path: Path,
        payload: VideoGenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def expected_video_output_fps(
        self,
        *,
        image_to_video: bool,
        requested_fps: int,
    ) -> int:
        ...

    def upscale_video(
        self,
        *,
        source_video_path: Path,
        payload: VideoUpscalePayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def convert_video_to_gif(
        self,
        *,
        source_video_path: Path,
        payload: VideoToGifPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        ...

    def generate_audio_video(
        self,
        *,
        source_video_path: Path,
        payload: VideoToAudioPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> GeneratedArtifact:
        ...

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
        ...

    def cancel_active_job(self) -> bool:
        ...

    def summarize_chat_messages(
        self,
        *,
        model: str,
        summary_prompt: str,
    ) -> str:
        ...

    def stream_chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        think: bool | str | None = True,
        context_window: int | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ):
        ...

    def chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        tools: list[dict[str, object]] | None = None,
        think: bool | str | None = True,
        context_window: int | None = None,
    ) -> dict[str, object]:
        ...
