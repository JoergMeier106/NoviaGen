from __future__ import annotations

import logging
import threading
import time
import uuid
from pathlib import Path
from typing import Callable

from PIL import Image
import requests

from ..assets import AssetCatalog
from ..comfy import ComfyVideoWorkflowManager
from .interfaces import ImageGenerator
from .local_pipelines import LocalPipelineMixin
from .ollama_runtime import (
    OllamaPromptRuntimeManager,
    OllamaResponseError,
    OllamaStreamCancelledError,
    OllamaUnavailableError,
)
from .ollama_generation import OllamaGenerationMixin
from .prompting import (
    ParsedThinkingContent,
    compose_positive_prompt,
    split_inline_thinking,
    strip_inline_thinking,
)
from .types import (
    UPSCALE_STRENGTH,
    GeneratedArtifact,
    GenerationPayload,
)
from .video_generation import VideoGenerationMixin

logger = logging.getLogger(__name__)


class DiffusersImageGenerator(
    OllamaGenerationMixin,
    VideoGenerationMixin,
    LocalPipelineMixin,
):
    def __init__(
        self,
        assets: AssetCatalog,
        device: str = "cuda",
        *,
        comfy_url: str = "http://127.0.0.1:8188",
        comfy_i2v_workflow_path: str | Path | None = None,
        comfy_i2v_loop_workflow_path: str | Path | None = None,
        comfy_i2v_prompt_workflow_path: str | Path | None = None,
        comfy_video_upscaler_workflow_path: str | Path | None = None,
        comfy_video_to_audio_workflow_path: str | Path | None = None,
        comfy_t2v_workflow_path: str | Path | None = None,
        ollama_url: str = "http://127.0.0.1:11434",
        ollama_prompt_model: str = "",
        ollama_prompt_timeout_seconds: float = 180.0,
    ) -> None:
        self.assets = assets
        self.device = device
        self._lock = threading.Lock()
        self._text_pipelines: dict[str, object] = {}
        self._upscale_pipelines: dict[str, object] = {}
        self._pipeline_lora_signatures: dict[int, tuple[tuple[str, float], ...]] = {}
        self._pipeline_lora_adapter_names: dict[int, tuple[str, ...]] = {}
        self._torch = None
        self._weighted_embeddings = None
        self._text_pipeline_cls = None
        self._img2img_pipeline_cls = None
        self._device_total_memory_bytes = 0
        self._attention_slicing_enabled = True
        self._xformers_available = False
        self._keep_both_pipeline_modes = False
        self._comfy_video_manager = ComfyVideoWorkflowManager(
            comfy_url=comfy_url,
            image_to_video_workflow_path=comfy_i2v_workflow_path,
            image_to_video_loop_workflow_path=comfy_i2v_loop_workflow_path,
            image_prompt_generator_workflow_path=comfy_i2v_prompt_workflow_path,
            video_upscaler_workflow_path=comfy_video_upscaler_workflow_path,
            video_to_audio_workflow_path=comfy_video_to_audio_workflow_path,
            text_to_video_workflow_path=comfy_t2v_workflow_path,
            ollama_url=ollama_url,
            ollama_timeout_seconds=ollama_prompt_timeout_seconds,
        )
        self._ollama_prompt_manager = OllamaPromptRuntimeManager(
            base_url=ollama_url,
            model=ollama_prompt_model,
            timeout_seconds=ollama_prompt_timeout_seconds,
        )
        self._active_runtime: str | None = None
        self._active_ollama_model: str | None = None

    def _evict_all_local_models(self) -> None:
        self._evict_all_image_pipelines()
        if self._active_runtime == "local":
            self._active_runtime = None

    def force_unload_all(self) -> dict[str, object]:
        with self._lock:
            self._evict_all_local_models()
            self._release_ollama_if_active()
            self._comfy_video_manager.release_active_workflow()
            self._comfy_video_manager.free_memory()
            self._active_runtime = None
            self._active_ollama_model = None
        return {
            "unloaded": True,
            "local_models": True,
            "ollama": True,
            "comfy": True,
        }

    def generate(
        self,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
            self._selected_lora_trigger_words(payload.loras),
        )
        image_id = str(uuid.uuid4())
        output_path = output_dir / f"{image_id}.png"

        with self._lock:
            self._lazy_imports()
            self._prepare_local_generation_runtime()
            model = self.assets.get_model(payload.model_id)
            if model is None:
                raise ValueError(f"Unknown model_id: {payload.model_id}")

            started_at = time.perf_counter()
            self._evict_stale_pipelines(model.path)
            self._evict_opposite_pipeline_mode(model.path, keep_mode="text")
            self._emit_progress(progress_callback, 0.08, "Loading model")
            pipe = self._prepare_text_pipeline_for_loras(model.path, payload.loras)
            self._configure_pipeline(pipe, payload.loras)
            self._emit_progress(progress_callback, 0.16, "Encoding prompts")
            with self._torch.inference_mode():
                prompt_embeds, neg_prompt_embeds, pooled, neg_pooled = self._weighted_embeddings(
                    pipe,
                    prompt=final_positive_prompt,
                    neg_prompt=payload.default_negative_prompt,
                    pad_last_block=True,
                )
                gen = self._torch.Generator(device=self.device).manual_seed(self._torch.seed())
                width, height = self._dimensions_for_orientation(payload.image_orientation)
                image = pipe(
                    prompt_embeds=prompt_embeds,
                    pooled_prompt_embeds=pooled,
                    negative_prompt_embeds=neg_prompt_embeds,
                    negative_pooled_prompt_embeds=neg_pooled,
                    width=width,
                    height=height,
                    num_inference_steps=payload.num_inference_steps,
                    guidance_scale=payload.guidance_scale,
                    generator=gen,
                    **self._progress_kwargs(
                        pipe=pipe,
                        total_steps=payload.num_inference_steps,
                        base_progress=0.22,
                        progress_span=0.7,
                        label="Generating image",
                        progress_callback=progress_callback,
                    ),
                ).images[0]
            self._emit_progress(progress_callback, 0.94, "Saving image")
            image.save(output_path)
            width, height = image.size
            logger.info(
                "Generated image in %.2fs using model=%s loras=%s",
                time.perf_counter() - started_at,
                payload.model_id,
                [item.lora_id for item in payload.loras],
            )
            self._active_runtime = "local"

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
            loras=[{"lora_id": item.lora_id, "strength": item.strength} for item in payload.loras],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation=payload.image_orientation,
            generation_duration_seconds=time.perf_counter() - started_at,
        )

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
        return self._generate_from_image_impl(
            source_image_path=source_image_path,
            source_image_id=source_image_id,
            payload=payload,
            output_dir=output_dir,
            progress_callback=progress_callback,
            resize_scale_factor=scale_factor,
            strength=UPSCALE_STRENGTH,
            status_text="Preparing upscale",
            progress_label="Scaling image",
            log_label=f"Upscaled image factor={scale_factor:.2f}",
            scale_factor=scale_factor,
            is_upscaled=True,
        )

    def generate_from_image(
        self,
        *,
        source_image_path: Path,
        source_image_id: str | None,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
    ) -> GeneratedArtifact:
        strength = payload.strength if payload.strength is not None else 0.35
        return self._generate_from_image_impl(
            source_image_path=source_image_path,
            source_image_id=source_image_id,
            payload=payload,
            output_dir=output_dir,
            progress_callback=progress_callback,
            resize_scale_factor=None,
            strength=strength,
            status_text="Preparing source image",
            progress_label="Generating image",
            log_label=f"Generated image from source strength={strength:.2f}",
            scale_factor=None,
            is_upscaled=False,
        )

    def _generate_from_image_impl(
        self,
        *,
        source_image_path: Path,
        source_image_id: str | None,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None,
        resize_scale_factor: float | None,
        strength: float,
        status_text: str,
        progress_label: str,
        log_label: str,
        scale_factor: float | None,
        is_upscaled: bool,
    ) -> GeneratedArtifact:
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
            self._selected_lora_trigger_words(payload.loras),
        )
        image_id = str(uuid.uuid4())
        output_path = output_dir / f"{image_id}.png"

        with self._lock:
            self._lazy_imports()
            self._prepare_local_generation_runtime()
            model = self.assets.get_model(payload.model_id)
            if model is None:
                raise ValueError(f"Unknown model_id: {payload.model_id}")

            started_at = time.perf_counter()
            self._evict_stale_pipelines(model.path)
            self._evict_opposite_pipeline_mode(model.path, keep_mode="upscale")
            self._emit_progress(progress_callback, 0.08, "Loading model")
            pipe = self._prepare_upscale_pipeline_for_loras(model.path, payload.loras)
            self._configure_pipeline(pipe, payload.loras)
            self._emit_progress(progress_callback, 0.16, status_text)
            with self._torch.inference_mode():
                prompt_embeds, neg_prompt_embeds, pooled, neg_pooled = self._weighted_embeddings(
                    pipe,
                    prompt=final_positive_prompt,
                    neg_prompt=payload.default_negative_prompt,
                    pad_last_block=True,
                )
                source_image = Image.open(source_image_path).convert("RGB")
                init_image = source_image
                if resize_scale_factor is not None:
                    upscaled_size = (
                        int(source_image.width * resize_scale_factor),
                        int(source_image.height * resize_scale_factor),
                    )
                    init_image = source_image.resize(
                        upscaled_size,
                        resample=Image.Resampling.LANCZOS,
                    )
                elif not is_upscaled:
                    init_image = self._prepare_generate_from_image_source(
                        source_image,
                        payload.image_orientation,
                    )
                gen = self._torch.Generator(device=self.device).manual_seed(self._torch.seed())
                approx_steps = max(1, int(round(payload.num_inference_steps * strength)))
                image = pipe(
                    prompt_embeds=prompt_embeds,
                    pooled_prompt_embeds=pooled,
                    negative_prompt_embeds=neg_prompt_embeds,
                    negative_pooled_prompt_embeds=neg_pooled,
                    image=init_image,
                    strength=strength,
                    num_inference_steps=payload.num_inference_steps,
                    guidance_scale=payload.guidance_scale,
                    generator=gen,
                    **self._progress_kwargs(
                        pipe=pipe,
                        total_steps=approx_steps,
                        base_progress=0.22,
                        progress_span=0.7,
                        label=progress_label,
                        progress_callback=progress_callback,
                    ),
                ).images[0]
            self._emit_progress(progress_callback, 0.94, "Saving image")
            image.save(output_path)
            width, height = image.size
            logger.info(
                "%s in %.2fs using model=%s",
                log_label,
                time.perf_counter() - started_at,
                payload.model_id,
            )
            self._active_runtime = "local"

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
            loras=[{"lora_id": item.lora_id, "strength": item.strength} for item in payload.loras],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation=payload.image_orientation,
            source_image_id=source_image_id,
            scale_factor=scale_factor,
            is_upscaled=is_upscaled,
            generation_duration_seconds=time.perf_counter() - started_at,
        )

    def _prepare_local_generation_runtime(self) -> None:
        self._release_ollama_if_active()
        self._release_comfy_if_active()

    def _prepare_ollama_runtime(self, model_name: str) -> None:
        normalized_model = str(model_name).strip()
        if not normalized_model:
            raise ValueError("model_name is required")
        if self._active_runtime == "ollama":
            if self._active_ollama_model == normalized_model:
                return
            if self._active_ollama_model:
                self._ollama_prompt_manager.unload_model(self._active_ollama_model)
        self._active_runtime = "ollama"
        self._active_ollama_model = normalized_model

    def _release_ollama_if_active(self) -> None:
        if self._active_runtime != "ollama":
            return
        if self._active_ollama_model:
            self._ollama_prompt_manager.unload_model(self._active_ollama_model)
        else:
            self._ollama_prompt_manager.release_model()
        self._active_runtime = None
        self._active_ollama_model = None

    def _release_comfy_if_active(self) -> None:
        if self._active_runtime != "comfy":
            return
        self._comfy_video_manager.release_active_workflow()
        self._active_runtime = None

    def cancel_active_job(self) -> bool:
        if self._active_runtime == "ollama":
            cancelled_stream = self._ollama_prompt_manager.cancel_active_chat()
            model_name = self._active_ollama_model
            if model_name:
                try:
                    self._ollama_prompt_manager.unload_model(model_name)
                except Exception:
                    logger.warning(
                        "Failed to unload active Ollama model during cancellation",
                        exc_info=True,
                    )
            return cancelled_stream or bool(model_name)
        return self._comfy_video_manager.cancel_active_prompt()
