from __future__ import annotations

import copy
import logging
import secrets
import time
import uuid
from pathlib import Path
from typing import Any, Callable

import requests


logger = logging.getLogger(__name__)
MAX_SAFE_COMFY_SEED = 1_125_899_906_842_624


class ComfyWorkflowRuntimeMixin:
    def expected_output_fps(
        self,
        *,
        image_to_video: bool,
        requested_fps: int,
    ) -> int:
        workflow_path = (
            self.image_to_video_workflow_path
            if image_to_video
            else self.text_to_video_workflow_path
        )
        workflow_key = "COMFY_I2V_WORKFLOW_PATH" if image_to_video else "COMFY_T2V_WORKFLOW_PATH"
        workflow = copy.deepcopy(self._load_workflow(workflow_path, workflow_key))
        create_video_id = self._find_optional_node_id(workflow, "CreateVideo")
        if create_video_id is not None:
            workflow[create_video_id]["inputs"]["fps"] = int(requested_fps)
        if image_to_video:
            self._configure_interpolated_video_output_fps(
                workflow,
                requested_fps=int(requested_fps),
            )
        save_video_id = self._find_video_save_node_id(workflow)
        return int(
            self._expected_saved_video_fps(
                workflow,
                save_video_id,
                fallback_fps=int(requested_fps),
            )
            or requested_fps
        )

    @staticmethod
    def _coerce_positive_int(value: Any) -> int | None:
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            coerced = int(round(float(value)))
            return coerced if coerced > 0 else None
        return None

    @classmethod
    def _safe_vhs_force_rate(
        cls,
        requested_fps: Any,
        *,
        source_fps: Any = None,
        max_force_rate: int = 60,
    ) -> int:
        """
        VHS_LoadVideoPath.force_rate must stay within the node's validated range.
        Return 0 to preserve the source cadence whenever forcing would be invalid,
        unnecessary, or unknown.
        """
        requested = cls._coerce_positive_int(requested_fps)
        source = cls._coerce_positive_int(source_fps)

        if requested is None:
            return 0
        if requested > max_force_rate:
            return 0
        if source is not None and requested == source:
            return 0
        return requested

    @classmethod
    def _safe_frame_load_cap(
        cls,
        requested_num_frames: Any,
        *,
        source_num_frames: Any = None,
    ) -> int:
        requested = cls._coerce_positive_int(requested_num_frames)
        source = cls._coerce_positive_int(source_num_frames)

        if requested is None and source is None:
            return 0
        if requested is None:
            return source or 0
        if source is None:
            return requested
        return max(1, min(requested, source))

    @classmethod
    def _safe_output_frame_rate(
        cls,
        requested_fps: Any,
        *,
        source_fps: Any = None,
        default_fps: int = 24,
    ) -> int:
        requested = cls._coerce_positive_int(requested_fps)
        if requested is not None:
            return requested

        source = cls._coerce_positive_int(source_fps)
        if source is not None:
            return source

        return default_fps

    def upscale_video(
        self,
        *,
        source_video_path: Path,
        payload: "VideoUpscalePayload",
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> "GeneratedArtifact":
        from ..generation import GeneratedArtifact, compose_positive_prompt

        workflow = self._load_workflow(
            self.video_upscaler_workflow_path,
            "COMFY_VIDEO_UPSCALER_WORKFLOW_PATH",
        )
        self._ensure_workflow_runtime("video_upscaler", workflow=workflow)
        image_id = str(uuid.uuid4())
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
        )

        started_at = time.perf_counter()
        workflow = copy.deepcopy(workflow)
        load_video_id = self._find_first_node_id(workflow, "VHS_LoadVideoPath")
        upscale_id = self._find_supported_video_upscale_node_id(workflow)
        save_video_id = self._find_video_save_node_id(workflow)

        source_metadata = self._probe_video_metadata(source_video_path) or {}
        source_fps = self._coerce_positive_int(source_metadata.get("fps"))
        source_num_frames = self._coerce_positive_int(source_metadata.get("num_frames"))
        source_width = self._coerce_positive_int(source_metadata.get("width"))
        source_height = self._coerce_positive_int(source_metadata.get("height"))
        source_duration = source_metadata.get("duration_seconds")

        requested_fps = self._coerce_positive_int(getattr(payload, "fps", None))
        requested_num_frames = self._coerce_positive_int(getattr(payload, "num_frames", None))

        load_force_rate = self._safe_vhs_force_rate(
            requested_fps,
            source_fps=source_fps,
            max_force_rate=60,
        )
        frame_load_cap = self._safe_frame_load_cap(
            requested_num_frames,
            source_num_frames=source_num_frames,
        )
        output_frame_rate = self._safe_output_frame_rate(
            requested_fps,
            source_fps=source_fps,
        )

        load_inputs = workflow[load_video_id]["inputs"]
        load_inputs["video"] = str(source_video_path)
        load_inputs["force_rate"] = load_force_rate
        load_inputs["frame_load_cap"] = frame_load_cap

        upscale_inputs = workflow[upscale_id]["inputs"]
        upscale_inputs["factor"] = float(payload.scale_factor)
        if "device_strategy" in upscale_inputs:
            upscale_inputs["device_strategy"] = self.video_upscaler_device_strategy

        save_inputs = workflow[save_video_id]["inputs"]
        if "frame_rate" in save_inputs and not isinstance(save_inputs["frame_rate"], list):
            save_inputs["frame_rate"] = output_frame_rate
        save_inputs["filename_prefix"] = f"video/api_{image_id}"
        self._randomize_workflow_seeds(workflow)

        execution_plan = self._build_execution_plan(
            workflow,
            workflow_kind="upscale",
            preparing_progress=0.04,
            queue_progress=0.1,
            active_start_progress=0.14,
            active_end_progress=0.9,
            fallback_running_label="Scaling video",
        )
        self._emit_progress(progress_callback, execution_plan.preparing_progress, "Preparing video scaling")
        prompt_id = self._queue_prompt(workflow, execution_plan=execution_plan)
        self._emit_progress(progress_callback, execution_plan.queue_progress, "Waiting in video queue")

        try:
            job = self._wait_for_history(
                prompt_id,
                progress_callback=progress_callback,
                preparing_label="Preparing video scaling",
                active_label="Scaling video",
                expected_output="video",
                cancel_requested=cancel_requested,
            )
        finally:
            self._clear_prompt_state(prompt_id)

        file_info = self._find_video_output(job, preferred_node_id=save_video_id)
        output_path = self._output_path_for_download(output_dir, image_id, file_info)
        self._emit_progress(progress_callback, 0.96, "Saving video")
        saved_path = self._download_output_file(file_info, output_path)
        self._emit_progress(progress_callback, 0.98, "Video ready")

        output_metadata = self._probe_video_metadata(saved_path) or {}

        output_width = self._coerce_positive_int(output_metadata.get("width"))
        if output_width is None:
            fallback_width = self._coerce_positive_int(getattr(payload, "width", None)) or source_width or 0
            output_width = max(1, int(round(fallback_width * float(payload.scale_factor)))) if fallback_width else None

        output_height = self._coerce_positive_int(output_metadata.get("height"))
        if output_height is None:
            fallback_height = self._coerce_positive_int(getattr(payload, "height", None)) or source_height or 0
            output_height = max(1, int(round(fallback_height * float(payload.scale_factor)))) if fallback_height else None

        output_fps = self._coerce_positive_int(output_metadata.get("fps")) or output_frame_rate
        output_num_frames = (
            self._coerce_positive_int(output_metadata.get("num_frames"))
            or frame_load_cap
            or source_num_frames
        )

        output_duration_seconds = output_metadata.get("duration_seconds")
        if output_duration_seconds is None and output_fps and output_num_frames:
            output_duration_seconds = float(output_num_frames) / float(output_fps)
        if output_duration_seconds is None:
            output_duration_seconds = source_duration

        final_width = int(output_width) if output_width is not None else max(
            1,
            int(round((self._coerce_positive_int(getattr(payload, "width", None)) or 1) * float(payload.scale_factor))),
        )
        final_height = int(output_height) if output_height is not None else max(
            1,
            int(round((self._coerce_positive_int(getattr(payload, "height", None)) or 1) * float(payload.scale_factor))),
        )

        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(saved_path),
            width=final_width,
            height=final_height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=final_positive_prompt,
            model_id=payload.model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation="portrait" if final_height > final_width else "landscape",
            source_image_id=payload.source_image_id,
            scale_factor=payload.scale_factor,
            is_upscaled=True,
            mime_type=self._mime_type_for_path(saved_path),
            media_type="video",
            poster_path=None,
            poster_mime_type=None,
            duration_seconds=float(output_duration_seconds) if output_duration_seconds is not None else None,
            generation_duration_seconds=time.perf_counter() - started_at,
            fps=int(output_fps) if output_fps is not None else None,
            num_frames=int(output_num_frames) if output_num_frames is not None else None,
            loop_video=False,
        )

    def generate_audio_video(
        self,
        *,
        source_video_path: Path,
        payload: "VideoToAudioPayload",
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> "GeneratedArtifact":
        from ..generation import GeneratedArtifact, compose_positive_prompt

        workflow = self._load_workflow(
            self.video_to_audio_workflow_path,
            "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH",
        )
        self._ensure_workflow_runtime("video_to_audio", workflow=workflow)
        image_id = str(uuid.uuid4())
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
        )

        started_at = time.perf_counter()
        workflow = copy.deepcopy(workflow)
        load_video_id = self._find_first_node_id(workflow, "LoadVideo")
        save_video_id = self._find_video_save_node_id(workflow)

        workflow[load_video_id]["inputs"]["file"] = str(source_video_path)
        workflow[save_video_id]["inputs"]["filename_prefix"] = f"video/api_{image_id}"
        self._apply_audio_video_source_settings(workflow, payload)
        self._randomize_workflow_seeds(workflow)

        execution_plan = self._build_execution_plan(
            workflow,
            workflow_kind="audio_video",
            preparing_progress=0.04,
            queue_progress=0.1,
            active_start_progress=0.14,
            active_end_progress=0.9,
            fallback_running_label="Generating audio",
        )
        self._emit_progress(progress_callback, execution_plan.preparing_progress, "Preparing audio video")
        prompt_id = self._queue_prompt(workflow, execution_plan=execution_plan)
        self._emit_progress(progress_callback, execution_plan.queue_progress, "Waiting in video queue")

        try:
            job = self._wait_for_history(
                prompt_id,
                progress_callback=progress_callback,
                preparing_label="Preparing audio video",
                active_label="Generating audio",
                expected_output="video",
                cancel_requested=cancel_requested,
            )
        finally:
            self._clear_prompt_state(prompt_id)
        file_info = self._find_video_output(job, preferred_node_id=save_video_id)
        output_path = self._output_path_for_download(output_dir, image_id, file_info)
        self._emit_progress(progress_callback, 0.96, "Saving video")
        saved_path = self._download_output_file(file_info, output_path)
        metadata = self._probe_video_metadata(saved_path) or {}
        width = int(metadata.get("width") or payload.width)
        height = int(metadata.get("height") or payload.height)
        duration_seconds = metadata.get("duration_seconds")
        if duration_seconds is None:
            duration_seconds = payload.duration_seconds
        fps = metadata.get("fps")
        if fps is None:
            fps = payload.fps
        num_frames = metadata.get("num_frames")
        if num_frames is None:
            num_frames = payload.num_frames
        if duration_seconds is None and fps and num_frames:
            duration_seconds = float(num_frames) / float(fps)
        self._emit_progress(progress_callback, 0.98, "Audio video ready")
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(saved_path),
            width=width,
            height=height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=final_positive_prompt,
            model_id=payload.model_id,
            loras=[],
            image_orientation="portrait" if height > width else "landscape",
            source_image_id=payload.source_image_id,
            mime_type=self._mime_type_for_path(saved_path),
            media_type="video",
            poster_path=None,
            poster_mime_type=None,
            duration_seconds=duration_seconds,
            generation_duration_seconds=time.perf_counter() - started_at,
            fps=int(fps) if fps is not None else None,
            num_frames=int(num_frames) if num_frames is not None else None,
            loop_video=False,
        )

    def release_active_workflow(self) -> None:
        if self._active_workflow_key is None:
            return
        self.free_memory()
        self._release_ollama_models(self._active_ollama_models)
        self._active_workflow_key = None
        self._active_ollama_models = set()

    def cancel_active_prompt(self) -> bool:
        with self._state_lock:
            prompt_id = self._active_prompt_id
            if not prompt_id:
                return False
            self._cancel_requested_prompt_ids.add(prompt_id)
        self._request_prompt_cancellation(prompt_id)
        return True

    def _ensure_workflow_runtime(
        self,
        workflow_key: str,
        *,
        workflow: dict[str, Any] | None = None,
    ) -> None:
        next_ollama_models = self._ollama_models_for_workflow(workflow)
        if self._active_workflow_key == workflow_key:
            stale_ollama_models = self._active_ollama_models - next_ollama_models
            if stale_ollama_models:
                self._release_ollama_models(stale_ollama_models)
            self._active_ollama_models = next_ollama_models
            return
        if self._active_workflow_key is not None:
            self.free_memory()
            self._release_ollama_models(self._active_ollama_models)
        self._active_workflow_key = workflow_key
        self._active_ollama_models = next_ollama_models

    def _release_ollama_models(self, model_names: set[str]) -> None:
        for model_name in sorted(str(item).strip() for item in model_names if str(item).strip()):
            try:
                response = requests.post(
                    f"{self.ollama_url}/api/generate",
                    json={
                        "model": model_name,
                        "prompt": "",
                        "stream": False,
                        "think": False,
                        "keep_alive": 0,
                    },
                    timeout=self.ollama_timeout_seconds,
                )
                response.raise_for_status()
            except requests.RequestException:
                logger.warning("Failed to unload Ollama model %s", model_name, exc_info=True)

    @staticmethod
    def _ollama_models_for_workflow(workflow: dict[str, Any] | None) -> set[str]:
        if not isinstance(workflow, dict):
            return set()
        models: set[str] = set()
        for node in workflow.values():
            if not isinstance(node, dict):
                continue
            if str(node.get("class_type") or "") != "OllamaChat":
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            model_name = str(inputs.get("model") or "").strip()
            if model_name:
                models.add(model_name)
        return models

    @staticmethod
    def _random_seed_value() -> int:
        return secrets.randbelow(MAX_SAFE_COMFY_SEED) + 1

    @staticmethod
    def _emit_progress(
        progress_callback: Callable[[float, str], None] | None,
        progress: float,
        status_text: str,
    ) -> None:
        if progress_callback is not None:
            progress_callback(progress, status_text)
