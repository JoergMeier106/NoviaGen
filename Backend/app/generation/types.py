from __future__ import annotations

from dataclasses import dataclass, field


DEFAULT_NUM_INFERENCE_STEPS = 40
DEFAULT_GUIDANCE_SCALE = 5.0
DEFAULT_IMAGE_ORIENTATION = "landscape"
UPSCALE_STRENGTH = 0.20


@dataclass(frozen=True)
class SelectedLora:
    lora_id: str
    strength: float


@dataclass(frozen=True)
class VideoWorkflowLora:
    lora_id: str
    strength: float


@dataclass(frozen=True)
class GenerationPayload:
    prompt: str
    default_positive_prompt: str
    default_negative_prompt: str
    model_id: str
    loras: list[SelectedLora]
    num_inference_steps: int = DEFAULT_NUM_INFERENCE_STEPS
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE
    image_orientation: str = DEFAULT_IMAGE_ORIENTATION
    strength: float | None = None


@dataclass(frozen=True)
class VideoGenerationPayload:
    prompt: str
    default_positive_prompt: str
    default_negative_prompt: str
    video_model_id: str
    width: int
    height: int
    num_frames: int
    fps: int
    num_inference_steps: int
    guidance_scale: float
    display_model_id: str | None = None
    source_image_id: str | None = None
    high_diffusion_model_name: str | None = None
    low_diffusion_model_name: str | None = None
    loop_video: bool = False
    workflow_loras: list[VideoWorkflowLora] = field(default_factory=list)


@dataclass(frozen=True)
class VideoUpscalePayload:
    prompt: str
    default_positive_prompt: str
    default_negative_prompt: str
    model_id: str
    width: int
    height: int
    num_frames: int
    fps: int
    num_inference_steps: int = DEFAULT_NUM_INFERENCE_STEPS
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE
    image_orientation: str = DEFAULT_IMAGE_ORIENTATION
    source_image_id: str | None = None
    scale_factor: float = 1.0


@dataclass(frozen=True)
class VideoToGifPayload:
    prompt: str
    default_positive_prompt: str
    default_negative_prompt: str
    model_id: str
    width: int
    height: int
    fps: int | None = None
    num_inference_steps: int = DEFAULT_NUM_INFERENCE_STEPS
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE
    image_orientation: str = DEFAULT_IMAGE_ORIENTATION
    source_image_id: str | None = None


@dataclass(frozen=True)
class VideoToAudioPayload:
    prompt: str
    default_positive_prompt: str
    default_negative_prompt: str
    model_id: str
    width: int
    height: int
    image_orientation: str = DEFAULT_IMAGE_ORIENTATION
    source_image_id: str | None = None
    duration_seconds: float | None = None
    fps: int | None = None
    num_frames: int | None = None


@dataclass(frozen=True)
class GeneratedArtifact:
    image_id: str
    file_path: str
    width: int
    height: int
    prompt: str
    default_positive_prompt: str
    default_negative_prompt: str
    final_positive_prompt: str
    model_id: str
    loras: list[dict[str, float | str]]
    num_inference_steps: int = DEFAULT_NUM_INFERENCE_STEPS
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE
    image_orientation: str = DEFAULT_IMAGE_ORIENTATION
    source_image_id: str | None = None
    scale_factor: float | None = None
    is_upscaled: bool = False
    mime_type: str = "image/png"
    media_type: str = "image"
    poster_path: str | None = None
    poster_mime_type: str | None = None
    duration_seconds: float | None = None
    generation_duration_seconds: float | None = None
    fps: int | None = None
    num_frames: int | None = None
    loop_video: bool = False
