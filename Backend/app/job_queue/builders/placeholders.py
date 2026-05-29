from __future__ import annotations

from typing import Any

from ...generation import (
    DEFAULT_GUIDANCE_SCALE,
    DEFAULT_IMAGE_ORIENTATION,
    DEFAULT_NUM_INFERENCE_STEPS,
    compose_positive_prompt,
)
from ...persistence import AppDatabase


class PlaceholderBuilder:
    def __init__(self, db: AppDatabase) -> None:
        self.db = db

    def build(
        self,
        *,
        job_type: str,
        payload: dict[str, Any],
        image_id: str,
    ) -> dict[str, Any]:
        builders = {
            "generate": self._build_generate,
            "generate_from_image": self._build_generate_from_image,
            "upscale": self._build_upscale,
            "generate_video": self._build_generate_video,
            "animate_image": self._build_animate_image,
            "upscale_video": self._build_upscale_video,
            "convert_video_to_gif": self._build_convert_video_to_gif,
            "generate_audio_video": self._build_generate_audio_video,
        }
        try:
            builder = builders[job_type]
        except KeyError as exc:
            raise ValueError(
                f"Unsupported job_type for placeholder reservation: {job_type}"
            ) from exc
        return builder(payload, image_id=image_id)

    def _build_generate(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        width, height = self._dimensions_for_orientation(
            str(payload.get("image_orientation", DEFAULT_IMAGE_ORIENTATION))
        )
        return {
            **self._base_image_payload(payload),
            "media_type": "image",
            "mime_type": "image/png",
            "width": width,
            "height": height,
        }

    def _build_generate_from_image(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        placeholder = self._build_generate(payload, image_id=image_id)
        placeholder["source_image_id"] = str(payload.get("image_id", "")).strip() or None
        return placeholder

    def _build_upscale(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        source_image = self._source_media(payload, media_label="image")
        scale_factor = float(payload["scale_factor"])
        return {
            **self._base_source_payload(source_image, payload),
            "media_type": "image",
            "mime_type": str(source_image.get("mime_type", "image/png")),
            "width": max(1, int(round(int(source_image["width"]) * scale_factor))),
            "height": max(1, int(round(int(source_image["height"]) * scale_factor))),
            "source_image_id": str(source_image.get("id", "")).strip() or None,
            "scale_factor": scale_factor,
            "is_upscaled": True,
        }

    def _build_generate_video(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        fps = int(payload["fps"])
        num_frames = int(payload["num_frames"])
        width = int(payload["width"])
        height = int(payload["height"])
        return {
            **self._base_video_payload(payload, width=width, height=height),
            "duration_seconds": float(num_frames) / float(fps),
            "fps": fps,
            "num_frames": num_frames,
        }

    def _build_animate_image(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        placeholder = self._build_generate_video(payload, image_id=image_id)
        placeholder["source_image_id"] = (
            str(payload.get("image_id", "")).strip() or f"local-source:{image_id}"
        )
        return placeholder

    def _build_upscale_video(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        source_video = self._source_media(payload, media_label="video")
        scale_factor = float(payload["scale_factor"])
        width = max(1, int(round(int(source_video["width"]) * scale_factor)))
        height = max(1, int(round(int(source_video["height"]) * scale_factor)))
        return {
            **self._base_source_payload(source_video, payload),
            "media_type": "video",
            "mime_type": "video/mp4",
            "width": width,
            "height": height,
            "loras": [],
            "source_image_id": str(source_video.get("id", "")).strip() or None,
            "scale_factor": scale_factor,
            "is_upscaled": True,
            "duration_seconds": source_video.get("duration_seconds"),
            "fps": source_video.get("fps"),
            "num_frames": source_video.get("num_frames"),
        }

    def _build_convert_video_to_gif(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        source_video = self._source_media(payload, media_label="video")
        return {
            **self._base_source_payload(source_video, payload),
            "media_type": "gif",
            "mime_type": "image/gif",
            "width": int(source_video["width"]),
            "height": int(source_video["height"]),
            "loras": [],
            "source_image_id": str(source_video.get("id", "")).strip() or None,
        }

    def _build_generate_audio_video(
        self,
        payload: dict[str, Any],
        *,
        image_id: str,
    ) -> dict[str, Any]:
        source_video = self._source_media(payload, media_label="video")
        width = int(source_video["width"])
        height = int(source_video["height"])
        return {
            **self._base_source_payload(source_video, payload),
            "media_type": "video",
            "mime_type": "video/mp4",
            "width": width,
            "height": height,
            "model_id": "comfy-video-to-audio",
            "loras": [],
            "image_orientation": str(
                source_video.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
                or ("portrait" if height > width else "landscape")
            ),
            "source_image_id": str(source_video.get("id", "")).strip() or None,
            "duration_seconds": source_video.get("duration_seconds"),
            "fps": source_video.get("fps"),
            "num_frames": source_video.get("num_frames"),
        }

    def _base_image_payload(self, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "prompt": str(payload.get("prompt", "")),
            "default_positive_prompt": str(payload.get("default_positive_prompt", "")),
            "default_negative_prompt": str(payload.get("default_negative_prompt", "")),
            "final_positive_prompt": self._final_positive_prompt(payload),
            "model_id": str(payload.get("model_id", "")),
            "loras": list(payload.get("loras", [])),
            "num_inference_steps": int(
                payload.get("num_inference_steps", DEFAULT_NUM_INFERENCE_STEPS)
            ),
            "guidance_scale": float(
                payload.get("guidance_scale", DEFAULT_GUIDANCE_SCALE)
            ),
            "image_orientation": str(
                payload.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
            ),
        }

    def _base_video_payload(
        self,
        payload: dict[str, Any],
        *,
        width: int,
        height: int,
    ) -> dict[str, Any]:
        return {
            "media_type": "video",
            "mime_type": "video/mp4",
            "width": width,
            "height": height,
            "prompt": str(payload.get("prompt", "")),
            "default_positive_prompt": str(payload.get("default_positive_prompt", "")),
            "default_negative_prompt": str(payload.get("default_negative_prompt", "")),
            "final_positive_prompt": self._final_positive_prompt(payload),
            "model_id": str(
                payload.get("display_model_id") or payload.get("video_model_id", "")
            ),
            "loras": [],
            "num_inference_steps": int(payload["num_inference_steps"]),
            "guidance_scale": float(payload["guidance_scale"]),
            "image_orientation": "portrait" if height > width else "landscape",
        }

    def _base_source_payload(
        self,
        source_media: dict[str, Any],
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        return {
            "prompt": str(source_media.get("prompt", "")),
            "default_positive_prompt": str(
                source_media.get("default_positive_prompt", "")
            ),
            "default_negative_prompt": str(
                source_media.get("default_negative_prompt", "")
            ),
            "final_positive_prompt": str(source_media.get("final_positive_prompt", "")),
            "model_id": str(source_media.get("model_id", "")),
            "loras": list(source_media.get("loras", [])),
            "num_inference_steps": int(
                payload.get(
                    "num_inference_steps",
                    source_media.get(
                        "num_inference_steps",
                        DEFAULT_NUM_INFERENCE_STEPS,
                    ),
                )
            ),
            "guidance_scale": float(
                payload.get(
                    "guidance_scale",
                    source_media.get("guidance_scale", DEFAULT_GUIDANCE_SCALE),
                )
            ),
            "image_orientation": str(
                source_media.get("image_orientation", DEFAULT_IMAGE_ORIENTATION)
            ),
        }

    def _source_media(
        self,
        payload: dict[str, Any],
        *,
        media_label: str,
    ) -> dict[str, Any]:
        source = self.db.get_image(str(payload["image_id"]))
        if source is None:
            raise KeyError(f"Source {media_label} not found: {payload['image_id']}")
        return source

    @staticmethod
    def _final_positive_prompt(payload: dict[str, Any]) -> str:
        return str(
            payload.get("final_positive_prompt")
            or compose_positive_prompt(
                str(payload.get("default_positive_prompt", "")),
                str(payload.get("prompt", "")),
            )
        )

    @staticmethod
    def _dimensions_for_orientation(image_orientation: str) -> tuple[int, int]:
        if str(image_orientation).lower() == "portrait":
            return (576, 1024)
        return (1024, 576)
