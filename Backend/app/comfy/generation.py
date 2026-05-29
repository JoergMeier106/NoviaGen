from __future__ import annotations

import copy
import time
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from ..generation import GeneratedArtifact, VideoGenerationPayload


class ComfyGenerationMixin:
    def generate_video(
        self,
        *,
        payload: "VideoGenerationPayload",
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> "GeneratedArtifact":
        from ..generation import GeneratedArtifact, compose_positive_prompt

        workflow = self._load_workflow(self.text_to_video_workflow_path, "COMFY_T2V_WORKFLOW_PATH")
        self._ensure_workflow_runtime("t2v", workflow=workflow)
        image_id = str(uuid.uuid4())
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
        )

        started_at = time.perf_counter()
        workflow = copy.deepcopy(workflow)
        create_video_id = self._find_optional_node_id(workflow, "CreateVideo")
        latent_id = self._find_t2v_latent_node_id(workflow)
        positive_prompt_id, negative_prompt_id = self._find_clip_text_nodes(workflow)

        workflow[positive_prompt_id]["inputs"]["text"] = final_positive_prompt
        workflow[negative_prompt_id]["inputs"]["text"] = payload.default_negative_prompt.strip()
        workflow[latent_id]["inputs"]["width"] = int(payload.width)
        workflow[latent_id]["inputs"]["height"] = int(payload.height)
        workflow[latent_id]["inputs"]["length"] = int(payload.num_frames)
        if create_video_id is not None:
            workflow[create_video_id]["inputs"]["fps"] = int(payload.fps)
        self._apply_diffusion_model_overrides(workflow, payload)
        self._apply_workflow_lora_overrides(workflow, payload)
        self._apply_common_generation_controls(workflow, payload)
        save_video_id = self._find_video_save_node_id(workflow)
        save_video_inputs = workflow[save_video_id].get("inputs")
        if isinstance(save_video_inputs, dict):
            save_video_inputs["filename_prefix"] = f"video/api_{image_id}"
        self._randomize_workflow_seeds(workflow)

        execution_plan = self._build_execution_plan(
            workflow,
            workflow_kind="t2v",
            preparing_progress=0.04,
            queue_progress=0.1,
            active_start_progress=0.14,
            active_end_progress=0.9,
            fallback_running_label="Generating frames",
        )
        self._emit_progress(
            progress_callback,
            execution_plan.preparing_progress,
            "Preparing video generation",
        )
        prompt_id = self._queue_prompt(workflow, execution_plan=execution_plan)
        self._emit_progress(progress_callback, execution_plan.queue_progress, "Waiting in video queue")

        mime_type = "video/mp4"
        try:
            job = self._wait_for_history(
                prompt_id,
                progress_callback=progress_callback,
                expected_output="video",
                cancel_requested=cancel_requested,
            )
        finally:
            self._clear_prompt_state(prompt_id)
        file_info = self._find_video_output(job, preferred_node_id=save_video_id)
        output_path = self._output_path_for_download(output_dir, image_id, file_info)
        self._emit_progress(progress_callback, 0.96, "Saving video")
        saved_path = self._download_output_file(file_info, output_path)
        output_metadata = self._probe_video_metadata(saved_path) or {}
        output_width = int(output_metadata.get("width") or payload.width)
        output_height = int(output_metadata.get("height") or payload.height)
        output_fps = int(
            output_metadata.get("fps")
            or self._expected_saved_video_fps(
                workflow,
                save_video_id,
                fallback_fps=payload.fps,
            )
            or payload.fps
        )
        output_num_frames = int(output_metadata.get("num_frames") or payload.num_frames)
        output_duration_seconds = output_metadata.get("duration_seconds")
        if output_duration_seconds is None:
            output_duration_seconds = float(output_num_frames) / float(max(1, output_fps))
        mime_type = self._mime_type_for_path(saved_path)
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(saved_path),
            width=output_width,
            height=output_height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=final_positive_prompt,
            model_id=payload.display_model_id or payload.video_model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation="portrait" if output_height > output_width else "landscape",
            mime_type=mime_type,
            media_type="video",
            poster_path=None,
            poster_mime_type=None,
            duration_seconds=float(output_duration_seconds),
            generation_duration_seconds=time.perf_counter() - started_at,
            fps=output_fps,
            num_frames=output_num_frames,
            loop_video=False,
        )

    def animate_image(
        self,
        *,
        source_image_path: Path,
        payload: "VideoGenerationPayload",
        output_dir: Path,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> "GeneratedArtifact":
        from ..generation import GeneratedArtifact, compose_positive_prompt

        workflow = self._load_workflow(
            self.image_to_video_workflow_path,
            "COMFY_I2V_WORKFLOW_PATH",
        )
        self._ensure_workflow_runtime("COMFY_I2V_WORKFLOW_PATH", workflow=workflow)
        image_id = str(uuid.uuid4())
        final_positive_prompt = compose_positive_prompt(
            payload.default_positive_prompt,
            payload.prompt,
        )

        started_at = time.perf_counter()
        self._emit_progress(progress_callback, 0.04, "Uploading source image")
        upload_info = self._upload_image(source_image_path)
        uploaded_name = str(upload_info.get("name") or upload_info.get("filename") or "").strip()
        if not uploaded_name:
            raise RuntimeError(f"Unexpected ComfyUI upload response: {upload_info}")

        workflow = copy.deepcopy(workflow)
        load_image_id = self._find_first_node_id(workflow, "LoadImage")
        create_video_id = self._find_optional_node_id(workflow, "CreateVideo")
        positive_prompt_id, negative_prompt_id = self._find_clip_text_nodes(workflow)

        workflow[load_image_id]["inputs"]["image"] = uploaded_name
        workflow[positive_prompt_id]["inputs"]["text"] = final_positive_prompt
        workflow[negative_prompt_id]["inputs"]["text"] = payload.default_negative_prompt.strip()
        if create_video_id is not None:
            workflow[create_video_id]["inputs"]["fps"] = int(payload.fps)
        self._apply_diffusion_model_overrides(workflow, payload)
        self._apply_workflow_lora_overrides(workflow, payload)
        self._apply_common_generation_controls(workflow, payload)
        self._normalize_non_loop_i2v_workflow(workflow, source_image_path=source_image_path)
        save_video_id = self._find_video_save_node_id(workflow)
        save_video_inputs = workflow[save_video_id].get("inputs")
        if isinstance(save_video_inputs, dict):
            save_video_inputs["filename_prefix"] = f"video/api_{image_id}"
        self._randomize_workflow_seeds(workflow)

        execution_plan = self._build_execution_plan(
            workflow,
            workflow_kind="i2v",
            preparing_progress=0.08,
            queue_progress=0.12,
            active_start_progress=0.16,
            active_end_progress=0.9,
            fallback_running_label="Generating frames",
        )
        self._emit_progress(progress_callback, execution_plan.preparing_progress, "Preparing animation")
        prompt_id = self._queue_prompt(workflow, execution_plan=execution_plan)
        self._emit_progress(progress_callback, execution_plan.queue_progress, "Waiting in video queue")

        try:
            job = self._wait_for_history(
                prompt_id,
                progress_callback=progress_callback,
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
        output_width = int(output_metadata.get("width") or payload.width)
        output_height = int(output_metadata.get("height") or payload.height)
        output_fps = int(
            output_metadata.get("fps")
            or self._expected_saved_video_fps(
                workflow,
                save_video_id,
                fallback_fps=payload.fps,
            )
            or payload.fps
        )
        output_num_frames = int(output_metadata.get("num_frames") or payload.num_frames)
        output_duration_seconds = output_metadata.get("duration_seconds")
        if output_duration_seconds is None:
            output_duration_seconds = float(output_num_frames) / float(max(1, output_fps))
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(saved_path),
            width=output_width,
            height=output_height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=final_positive_prompt,
            model_id=payload.display_model_id or payload.video_model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation="portrait" if output_height > output_width else "landscape",
            source_image_id=payload.source_image_id,
            mime_type=self._mime_type_for_path(saved_path),
            media_type="video",
            poster_path=None,
            poster_mime_type=None,
            duration_seconds=float(output_duration_seconds),
            generation_duration_seconds=time.perf_counter() - started_at,
            fps=output_fps,
            num_frames=output_num_frames,
            loop_video=False,
        )

    def generate_i2v_prompt(
        self,
        *,
        source_image_path: Path,
        prompt: str,
        progress_callback: Callable[[float, str], None] | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ) -> str:
        workflow = self._load_workflow(
            self.image_prompt_generator_workflow_path,
            "COMFY_I2V_PROMPT_WORKFLOW_PATH",
        )
        self._ensure_workflow_runtime(
            "COMFY_I2V_PROMPT_WORKFLOW_PATH",
            workflow=workflow,
        )

        self._emit_progress(progress_callback, 0.04, "Uploading source image")
        upload_info = self._upload_image(source_image_path)
        uploaded_name = str(upload_info.get("name") or upload_info.get("filename") or "").strip()
        if not uploaded_name:
            raise RuntimeError(f"Unexpected ComfyUI upload response: {upload_info}")

        workflow = copy.deepcopy(workflow)
        load_image_id = self._find_first_node_id(workflow, "LoadImage")
        manual_prompter_id = self._find_first_node_id_by_title(
            workflow,
            "Manual Prompter",
            class_type="StringConcatenate",
        )
        generated_prompt_id = self._find_optional_node_id_by_title(
            workflow,
            "SFX Prompt (Ollama)",
            class_type="PreviewAny",
        )
        final_prompt_id = self._find_optional_node_id_by_title(
            workflow,
            "FINAL Prompt",
            class_type="PreviewAny",
        )
        preferred_output_id = generated_prompt_id or final_prompt_id

        workflow[load_image_id]["inputs"]["image"] = uploaded_name
        manual_inputs = workflow[manual_prompter_id].get("inputs")
        if not isinstance(manual_inputs, dict):
            raise RuntimeError("Manual Prompter node is missing inputs")
        manual_prompt = prompt.strip()
        updated_manual_prompt = False
        for key in ("string_a", "text", "prompt", "value", "string_b"):
            if key in manual_inputs:
                manual_inputs[key] = manual_prompt
                updated_manual_prompt = True
                break
        if not updated_manual_prompt:
            raise RuntimeError("Manual Prompter node does not expose a writable prompt input")
        self._randomize_workflow_seeds(workflow)

        execution_plan = self._build_execution_plan(
            workflow,
            workflow_kind="prompt",
            preparing_progress=0.08,
            queue_progress=0.12,
            active_start_progress=0.16,
            active_end_progress=0.9,
            fallback_running_label="Generating prompt",
        )
        self._emit_progress(
            progress_callback,
            execution_plan.preparing_progress,
            "Preparing prompt generation",
        )
        prompt_id = self._queue_prompt(workflow, execution_plan=execution_plan)
        self._emit_progress(progress_callback, execution_plan.queue_progress, "Waiting in video queue")

        try:
            job = self._wait_for_history(
                prompt_id,
                progress_callback=progress_callback,
                preparing_label="Preparing prompt generation",
                active_label="Generating prompt",
                expected_output="text",
                cancel_requested=cancel_requested,
            )
        finally:
            self._clear_prompt_state(prompt_id)
        self._emit_progress(progress_callback, 0.96, "Finalizing prompt")
        return self._find_text_output(job, preferred_node_id=preferred_output_id).strip()
