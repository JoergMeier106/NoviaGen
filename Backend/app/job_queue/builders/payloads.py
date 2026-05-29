from __future__ import annotations

from pathlib import Path
from typing import Any

from ...generation import (
    DEFAULT_GUIDANCE_SCALE,
    DEFAULT_IMAGE_ORIENTATION,
    DEFAULT_NUM_INFERENCE_STEPS,
    GenerationPayload,
    SelectedLora,
    VideoGenerationPayload,
    VideoToAudioPayload,
    VideoToGifPayload,
    VideoUpscalePayload,
    VideoWorkflowLora,
)


class JobPayloadFactory:
    def __init__(self, db: Any) -> None:
        self._db = db

    def generation_payload(self, payload: dict[str, Any]) -> GenerationPayload:
        return GenerationPayload(
            prompt=str(payload.get("prompt", "")),
            default_positive_prompt=str(payload.get("default_positive_prompt", "")),
            default_negative_prompt=str(payload.get("default_negative_prompt", "")),
            model_id=str(payload["model_id"]),
            num_inference_steps=int(
                payload.get("num_inference_steps", DEFAULT_NUM_INFERENCE_STEPS)
            ),
            guidance_scale=float(payload.get("guidance_scale", DEFAULT_GUIDANCE_SCALE)),
            image_orientation=str(
                payload.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
            ),
            loras=[
                SelectedLora(
                    lora_id=str(item["lora_id"]),
                    strength=float(item["strength"]),
                )
                for item in payload.get("loras", [])
            ],
            strength=(
                float(payload["strength"])
                if payload.get("strength") is not None
                else None
            ),
        )

    def upscale_generation_payload(
        self,
        source_image: dict[str, Any],
        job_payload: dict[str, Any],
    ) -> GenerationPayload:
        return self.generation_payload(
            {
                **source_image,
                "num_inference_steps": job_payload.get(
                    "num_inference_steps",
                    DEFAULT_NUM_INFERENCE_STEPS,
                ),
                "guidance_scale": job_payload.get(
                    "guidance_scale",
                    DEFAULT_GUIDANCE_SCALE,
                ),
            }
        )

    def video_generation_payload(
        self,
        payload: dict[str, Any],
    ) -> VideoGenerationPayload:
        return VideoGenerationPayload(
            prompt=str(payload.get("prompt", "")),
            default_positive_prompt=str(payload.get("default_positive_prompt", "")),
            default_negative_prompt=str(payload.get("default_negative_prompt", "")),
            video_model_id=str(payload["video_model_id"]),
            display_model_id=str(payload.get("display_model_id", "")).strip() or None,
            width=int(payload["width"]),
            height=int(payload["height"]),
            num_frames=int(payload["num_frames"]),
            fps=int(payload["fps"]),
            num_inference_steps=int(payload["num_inference_steps"]),
            guidance_scale=float(payload["guidance_scale"]),
            source_image_id=str(payload.get("source_image_id", "")).strip() or None,
            high_diffusion_model_name=str(
                payload.get("high_diffusion_model_name", "")
            ).strip()
            or None,
            low_diffusion_model_name=str(
                payload.get("low_diffusion_model_name", "")
            ).strip()
            or None,
            workflow_loras=[
                VideoWorkflowLora(
                    lora_id=str(item["lora_id"]),
                    strength=float(item["strength"]),
                )
                for item in payload.get("workflow_loras", [])
            ],
        )

    def video_upscale_payload(
        self,
        source_video: dict[str, Any],
        payload: dict[str, Any],
    ) -> VideoUpscalePayload:
        fps = source_video.get("fps")
        num_frames = source_video.get("num_frames")
        if fps is None or num_frames is None:
            raise ValueError("Source video must include fps and num_frames")
        return VideoUpscalePayload(
            prompt=str(source_video.get("prompt", "")),
            default_positive_prompt=str(source_video.get("default_positive_prompt", "")),
            default_negative_prompt=str(source_video.get("default_negative_prompt", "")),
            model_id=str(source_video.get("model_id", "")),
            width=int(source_video["width"]),
            height=int(source_video["height"]),
            num_frames=int(num_frames),
            fps=int(fps),
            num_inference_steps=int(
                source_video.get("num_inference_steps", DEFAULT_NUM_INFERENCE_STEPS)
            ),
            guidance_scale=float(
                source_video.get("guidance_scale", DEFAULT_GUIDANCE_SCALE)
            ),
            image_orientation=str(
                source_video.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
            ),
            source_image_id=str(source_video.get("id", "")).strip() or None,
            scale_factor=float(payload["scale_factor"]),
        )

    def video_to_gif_payload(self, source_video: dict[str, Any]) -> VideoToGifPayload:
        return VideoToGifPayload(
            prompt=str(source_video.get("prompt", "")),
            default_positive_prompt=str(source_video.get("default_positive_prompt", "")),
            default_negative_prompt=str(source_video.get("default_negative_prompt", "")),
            model_id=str(source_video.get("model_id", "")),
            width=int(source_video["width"]),
            height=int(source_video["height"]),
            fps=(
                int(source_video["fps"])
                if source_video.get("fps") is not None
                else None
            ),
            num_inference_steps=int(
                source_video.get("num_inference_steps", DEFAULT_NUM_INFERENCE_STEPS)
            ),
            guidance_scale=float(
                source_video.get("guidance_scale", DEFAULT_GUIDANCE_SCALE)
            ),
            image_orientation=str(
                source_video.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
            ),
            source_image_id=str(source_video.get("id", "")).strip() or None,
        )

    def video_to_audio_payload(self, source_video: dict[str, Any]) -> VideoToAudioPayload:
        width = int(source_video["width"])
        height = int(source_video["height"])
        return VideoToAudioPayload(
            prompt=str(source_video.get("prompt", "")),
            default_positive_prompt=str(source_video.get("default_positive_prompt", "")),
            default_negative_prompt=str(source_video.get("default_negative_prompt", "")),
            model_id="comfy-video-to-audio",
            width=width,
            height=height,
            image_orientation=(
                str(source_video.get("image_orientation", DEFAULT_IMAGE_ORIENTATION))
                or ("portrait" if height > width else "landscape")
            ),
            source_image_id=str(source_video.get("id", "")).strip() or None,
            duration_seconds=(
                float(source_video["duration_seconds"])
                if source_video.get("duration_seconds") is not None
                else None
            ),
            fps=(
                int(source_video["fps"])
                if source_video.get("fps") is not None
                else None
            ),
            num_frames=(
                int(source_video["num_frames"])
                if source_video.get("num_frames") is not None
                else None
            ),
        )

    def resolve_image_source(self, payload: dict[str, Any]) -> Path:
        image_id = str(payload.get("image_id", "")).strip()
        if image_id:
            source_image = self._db.get_image(image_id)
            if source_image is None:
                raise KeyError(f"Source image not found: {image_id}")
            return Path(source_image["file_path"])

        uploaded_path = str(payload.get("upload_image_path", "")).strip()
        if uploaded_path:
            path = Path(uploaded_path)
            if not path.exists():
                raise KeyError(f"Uploaded source image not found: {uploaded_path}")
            return path
        raise KeyError("Source image not provided")
