from __future__ import annotations

import gc
import inspect
import logging
from typing import Callable

from PIL import Image, ImageOps

from .types import SelectedLora

logger = logging.getLogger(__name__)


class LocalPipelineMixin:
    def _lazy_imports(self) -> None:
        if self._torch is not None:
            return
        import torch
        from diffusers import StableDiffusionXLPipeline, StableDiffusionXLImg2ImgPipeline
        from sd_embed.embedding_funcs import get_weighted_text_embeddings_sdxl

        self._torch = torch
        self._text_pipeline_cls = StableDiffusionXLPipeline
        self._img2img_pipeline_cls = StableDiffusionXLImg2ImgPipeline
        self._weighted_embeddings = get_weighted_text_embeddings_sdxl
        self._configure_torch_backends()

    def _get_or_create_text_pipeline(self, model_path: str) -> object:
        pipe = self._text_pipelines.get(model_path)
        if pipe is None:
            pipe = self._text_pipeline_cls.from_single_file(
                model_path,
                torch_dtype=self._torch.float16,
            ).to(self.device)
            self._optimize_pipeline(pipe)
            self._text_pipelines[model_path] = pipe
        return pipe

    def _get_or_create_upscale_pipeline(self, model_path: str) -> object:
        pipe = self._upscale_pipelines.get(model_path)
        if pipe is None:
            pipe = self._img2img_pipeline_cls.from_single_file(
                model_path,
                torch_dtype=self._torch.float16,
            ).to(self.device)
            self._optimize_pipeline(pipe)
            self._upscale_pipelines[model_path] = pipe
        return pipe

    def _evict_stale_pipelines(self, model_path: str) -> None:
        stale_text_models = [path for path in self._text_pipelines if path != model_path]
        stale_upscale_models = [path for path in self._upscale_pipelines if path != model_path]
        if not stale_text_models and not stale_upscale_models:
            return

        for stale_model_path in stale_text_models:
            self._dispose_pipeline(self._text_pipelines.pop(stale_model_path, None))
        for stale_model_path in stale_upscale_models:
            self._dispose_pipeline(self._upscale_pipelines.pop(stale_model_path, None))
        self._clear_device_cache()

    def _evict_all_image_pipelines(self) -> None:
        had_pipelines = bool(self._text_pipelines or self._upscale_pipelines)
        for stale_model_path in list(self._text_pipelines):
            self._dispose_pipeline(self._text_pipelines.pop(stale_model_path, None))
        for stale_model_path in list(self._upscale_pipelines):
            self._dispose_pipeline(self._upscale_pipelines.pop(stale_model_path, None))
        if had_pipelines:
            self._clear_device_cache()

    def _dispose_pipeline(self, pipe: object | None) -> None:
        if pipe is None:
            return

        self._reset_pipeline_loras(pipe, force_unload=True)

        if hasattr(pipe, "to"):
            try:
                pipe.to("cpu")
            except Exception:
                pass

    @staticmethod
    def _callable_accepts_kwarg(func: object, kwarg_name: str) -> bool:
        if not callable(func):
            return False
        try:
            signature = inspect.signature(func)
        except (TypeError, ValueError):
            return False
        return kwarg_name in signature.parameters or any(
            parameter.kind == inspect.Parameter.VAR_KEYWORD
            for parameter in signature.parameters.values()
        )

    @staticmethod
    def _dedupe_loras(loras: list[SelectedLora]) -> list[SelectedLora]:
        deduped: list[SelectedLora] = []
        seen: set[str] = set()
        for item in loras:
            if item.lora_id in seen:
                continue
            seen.add(item.lora_id)
            deduped.append(item)
        return deduped

    def _desired_lora_signature(
        self, loras: list[SelectedLora]
    ) -> tuple[tuple[str, float], ...]:
        return tuple(
            (item.lora_id, float(item.strength))
            for item in self._dedupe_loras(loras)
        )

    def _prepare_text_pipeline_for_loras(
        self,
        model_path: str,
        loras: list[SelectedLora],
    ) -> object:
        pipe = self._get_or_create_text_pipeline(model_path)
        desired_signature = self._desired_lora_signature(loras)
        existing_signature = self._pipeline_lora_signatures.get(id(pipe))
        if desired_signature != existing_signature and (desired_signature or existing_signature):
            self._dispose_pipeline(pipe)
            self._text_pipelines.pop(model_path, None)
            self._clear_device_cache()
            pipe = self._get_or_create_text_pipeline(model_path)
        return pipe

    def _prepare_upscale_pipeline_for_loras(
        self,
        model_path: str,
        loras: list[SelectedLora],
    ) -> object:
        pipe = self._get_or_create_upscale_pipeline(model_path)
        desired_signature = self._desired_lora_signature(loras)
        existing_signature = self._pipeline_lora_signatures.get(id(pipe))
        if desired_signature != existing_signature and (desired_signature or existing_signature):
            self._dispose_pipeline(pipe)
            self._upscale_pipelines.pop(model_path, None)
            self._clear_device_cache()
            pipe = self._get_or_create_upscale_pipeline(model_path)
        return pipe

    def _reset_pipeline_loras(self, pipe: object, *, force_unload: bool = False) -> None:
        pipe_key = id(pipe)
        existing_signature = self._pipeline_lora_signatures.get(pipe_key)
        adapter_names = self._pipeline_lora_adapter_names.pop(pipe_key, ())
        if adapter_names:
            for component_name in ("unet", "text_encoder", "text_encoder_2"):
                component = getattr(pipe, component_name, None)
                delete_adapters = getattr(component, "delete_adapters", None)
                if not callable(delete_adapters):
                    continue
                try:
                    delete_adapters(list(adapter_names))
                except Exception:
                    logger.debug(
                        "Failed to delete LoRA adapters from %s",
                        component_name,
                        exc_info=True,
                    )

        had_lora_state = force_unload or bool(adapter_names) or existing_signature is not None
        if had_lora_state:
            unload_lora_weights = getattr(pipe, "unload_lora_weights", None)
            if callable(unload_lora_weights):
                try:
                    unload_lora_weights()
                except Exception:
                    logger.debug("Failed to unload LoRA weights", exc_info=True)

            self._pipeline_lora_signatures.pop(pipe_key, None)

    def _evict_opposite_pipeline_mode(self, model_path: str, *, keep_mode: str) -> None:
        if self._keep_both_pipeline_modes:
            return

        released_pipeline = None
        if keep_mode == "text":
            released_pipeline = self._upscale_pipelines.pop(model_path, None)
        elif keep_mode == "upscale":
            released_pipeline = self._text_pipelines.pop(model_path, None)

        if released_pipeline is not None:
            self._dispose_pipeline(released_pipeline)
            self._clear_device_cache()

    def _clear_device_cache(self) -> None:
        gc.collect()
        cuda = getattr(self._torch, "cuda", None)
        if cuda is None:
            return

        for method_name in ("empty_cache", "ipc_collect", "synchronize"):
            method = getattr(cuda, method_name, None)
            if callable(method):
                try:
                    method()
                except Exception:
                    pass

    def _configure_pipeline(self, pipe: object, loras: list[SelectedLora]) -> None:
        normalized_loras = self._dedupe_loras(loras)
        desired_signature = tuple(
            (item.lora_id, float(item.strength)) for item in normalized_loras
        )
        pipe_key = id(pipe)
        if self._pipeline_lora_signatures.get(pipe_key) == desired_signature:
            return

        self._reset_pipeline_loras(pipe)

        adapter_names: list[str] = []
        adapter_weights: list[float] = []
        load_lora_weights = getattr(pipe, "load_lora_weights", None)
        supports_adapter_name = self._callable_accepts_kwarg(
            load_lora_weights, "adapter_name"
        )
        supports_strength = self._callable_accepts_kwarg(load_lora_weights, "strength")

        for index, item in enumerate(normalized_loras):
            lora = self.assets.get_lora(item.lora_id)
            if lora is None:
                raise ValueError(f"Unknown lora_id: {item.lora_id}")
            if not callable(load_lora_weights):
                raise RuntimeError("Pipeline does not support LoRA loading")

            adapter_name = f"app_lora_{index}"
            load_kwargs: dict[str, object] = {}
            if supports_adapter_name:
                load_kwargs["adapter_name"] = adapter_name
            if supports_strength:
                load_kwargs["strength"] = item.strength

            load_lora_weights(lora.path, **load_kwargs)
            if supports_adapter_name:
                adapter_names.append(adapter_name)
                adapter_weights.append(float(item.strength))

        set_adapters = getattr(pipe, "set_adapters", None)
        if adapter_names and callable(set_adapters):
            try:
                if len(adapter_names) == 1:
                    set_adapters(adapter_names[0], adapter_weights=adapter_weights[0])
                else:
                    set_adapters(adapter_names, adapter_weights=adapter_weights)
            except TypeError:
                if len(adapter_names) == 1:
                    set_adapters(adapter_names[0], adapter_weights[0])
                else:
                    set_adapters(adapter_names, adapter_weights)

        self._pipeline_lora_adapter_names[pipe_key] = tuple(adapter_names)
        self._pipeline_lora_signatures[pipe_key] = desired_signature

    def _progress_kwargs(
        self,
        *,
        pipe: object,
        total_steps: int,
        base_progress: float,
        progress_span: float,
        label: str,
        progress_callback: Callable[[float, str], None] | None,
    ) -> dict[str, object]:
        if progress_callback is None:
            return {}

        try:
            signature = inspect.signature(pipe.__call__)
        except (TypeError, ValueError):
            return {}

        if "callback_on_step_end" in signature.parameters:
            def on_step_end(
                _pipe: object,
                step_index: int,
                _timestep: int,
                callback_kwargs: dict[str, object],
            ) -> dict[str, object]:
                current_step = min(total_steps, max(1, step_index + 1))
                progress_callback(
                    base_progress + (current_step / total_steps) * progress_span,
                    f"{label} {current_step}/{total_steps}",
                )
                return callback_kwargs

            return {
                "callback_on_step_end": on_step_end,
                "callback_on_step_end_tensor_inputs": [],
            }

        if "callback" in signature.parameters:
            def on_step(_step_index: int, _timestep: int, _latents: object) -> None:
                current_step = min(total_steps, max(1, _step_index + 1))
                progress_callback(
                    base_progress + (current_step / total_steps) * progress_span,
                    f"{label} {current_step}/{total_steps}",
                )

            kwargs: dict[str, object] = {"callback": on_step}
            if "callback_steps" in signature.parameters:
                kwargs["callback_steps"] = 1
            return kwargs

        return {}

    @staticmethod
    def _emit_progress(
        progress_callback: Callable[[float, str], None] | None,
        progress: float,
        status_text: str,
    ) -> None:
        if progress_callback is not None:
            progress_callback(progress, status_text)

    def _selected_lora_trigger_words(self, loras: list[SelectedLora]) -> str:
        parts: list[str] = []
        for item in loras:
            lora = self.assets.get_lora(item.lora_id)
            if lora is None or not lora.trigger_words.strip():
                continue
            parts.append(lora.trigger_words.strip())
        return ", ".join(parts)

    @staticmethod
    def _dimensions_for_orientation(image_orientation: str) -> tuple[int, int]:
        if str(image_orientation).lower() == "portrait":
            return (576, 1024)
        return (1024, 576)

    @classmethod
    def _prepare_generate_from_image_source(
        cls,
        source_image: Image.Image,
        image_orientation: str,
    ) -> Image.Image:
        target_size = cls._dimensions_for_orientation(image_orientation)
        if source_image.size == target_size:
            return source_image
        return ImageOps.fit(
            source_image,
            target_size,
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )

    def _configure_torch_backends(self) -> None:
        if not self.device.startswith("cuda") or not self._torch.cuda.is_available():
            return

        device_index = 0
        if ":" in self.device:
            try:
                device_index = int(self.device.split(":", maxsplit=1)[1])
            except ValueError:
                device_index = 0

        device_properties = self._torch.cuda.get_device_properties(device_index)
        self._device_total_memory_bytes = int(device_properties.total_memory)
        self._attention_slicing_enabled = self._device_total_memory_bytes < 14 * 1024**3
        # Keep exactly one local pipeline mode resident at a time.
        self._keep_both_pipeline_modes = False

        if hasattr(self._torch, "set_float32_matmul_precision"):
            self._torch.set_float32_matmul_precision("high")
        if hasattr(self._torch.backends, "cuda") and hasattr(self._torch.backends.cuda, "matmul"):
            self._torch.backends.cuda.matmul.allow_tf32 = True
        if hasattr(self._torch.backends, "cudnn"):
            self._torch.backends.cudnn.allow_tf32 = True
            self._torch.backends.cudnn.benchmark = True

        try:
            import xformers  # noqa: F401

            self._xformers_available = True
        except Exception:
            self._xformers_available = False

        logger.info(
            "Initialized generator on %s with %.1f GiB VRAM; attention_slicing=%s keep_both_pipeline_modes=%s xformers=%s",
            device_properties.name,
            self._device_total_memory_bytes / (1024**3),
            self._attention_slicing_enabled,
            self._keep_both_pipeline_modes,
            self._xformers_available,
        )

    def _optimize_pipeline(self, pipe: object) -> None:
        if hasattr(pipe, "set_progress_bar_config"):
            try:
                pipe.set_progress_bar_config(disable=True)
            except Exception:
                pass

        if hasattr(pipe, "vae"):
            try:
                pipe.vae.enable_tiling()
            except Exception:
                pass

        if self._attention_slicing_enabled:
            if hasattr(pipe, "enable_attention_slicing"):
                try:
                    pipe.enable_attention_slicing()
                except Exception:
                    pass
        elif hasattr(pipe, "disable_attention_slicing"):
            try:
                pipe.disable_attention_slicing()
            except Exception:
                pass

        if self._xformers_available and hasattr(pipe, "enable_xformers_memory_efficient_attention"):
            try:
                pipe.enable_xformers_memory_efficient_attention()
            except Exception:
                pass

        channels_last = getattr(self._torch, "channels_last", None)
        if channels_last is None:
            return

        for module_name in ("unet", "vae"):
            module = getattr(pipe, module_name, None)
            if module is None or not hasattr(module, "to"):
                continue
            try:
                module.to(memory_format=channels_last)
            except Exception:
                pass
