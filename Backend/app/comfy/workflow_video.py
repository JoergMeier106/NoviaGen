from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from PIL import Image


class ComfyVideoWorkflowMixin:
    @classmethod
    def _find_supported_video_upscale_node_id(cls, workflow: dict[str, Any]) -> str:
        node_id = cls._find_optional_node_id(workflow, "Video_Upscale_With_Model")
        if node_id is not None:
            return node_id
        raise KeyError(
            "Could not find supported video upscale node 'Video_Upscale_With_Model'"
        )

    @classmethod
    def _normalize_video_upscaler_device_strategy(cls, strategy: Any) -> str:
        strategy_text = str(strategy or "").strip()
        if strategy_text in {"auto", "load_unload_each_frame", "keep_loaded", "cpu_only"}:
            return strategy_text
        return "keep_loaded"

    @classmethod
    def _find_video_save_node_id(cls, workflow: dict[str, Any]) -> str:
        preferred_combine_id = cls._find_preferred_vhs_video_node_id(workflow)
        if preferred_combine_id is not None:
            return preferred_combine_id

        save_video_id = cls._find_optional_node_id(workflow, "SaveVideo")
        if save_video_id is not None:
            return save_video_id

        for node_id, node in workflow.items():
            if not isinstance(node, dict) or node.get("class_type") != "VHS_VideoCombine":
                continue
            inputs = node.get("inputs")
            if isinstance(inputs, dict) and bool(inputs.get("save_output", False)):
                return str(node_id)

        for node_id, node in workflow.items():
            if not isinstance(node, dict) or node.get("class_type") != "VHS_VideoCombine":
                continue
            title = str(node.get("_meta", {}).get("title", "")).strip().lower()
            if title == "output":
                return str(node_id)

        raise KeyError("Could not find a supported video output node")

    @staticmethod
    def _find_clip_text_nodes(workflow: dict[str, Any]) -> tuple[str, str]:
        positive_id: str | None = None
        negative_id: str | None = None
        fallback_positive_id: str | None = None
        for node_id, node in workflow.items():
            if not isinstance(node, dict) or node.get("class_type") != "CLIPTextEncode":
                continue
            title = str(node.get("_meta", {}).get("title", "")).lower()
            current_id = str(node_id)
            if "negative" in title and negative_id is None:
                negative_id = current_id
            elif "positive" in title and positive_id is None:
                positive_id = current_id
            elif fallback_positive_id is None:
                fallback_positive_id = current_id
        if positive_id is None:
            positive_id = fallback_positive_id
        if positive_id is None or negative_id is None:
            raise KeyError("Could not find positive and negative CLIPTextEncode nodes")
        return positive_id, negative_id

    @classmethod
    def _find_preferred_vhs_video_node_id(cls, workflow: dict[str, Any]) -> str | None:
        for node_id in cls._find_node_ids(workflow, "VHS_VideoCombine"):
            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            title = str(node.get("_meta", {}).get("title", "")).strip().lower()
            if cls._find_upstream_interpolation_node_id(workflow, node_id) is not None:
                return node_id
            if "60fps" in title or "interpolated" in title:
                return node_id
        return None

    @staticmethod
    def _find_t2v_latent_node_id(workflow: dict[str, Any]) -> str:
        for node_id, node in workflow.items():
            if not isinstance(node, dict):
                continue
            class_type = str(node.get("class_type") or "").lower()
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            if (
                "latent" in class_type
                and "video" in class_type
                and all(key in inputs for key in ("width", "height", "length"))
            ):
                return str(node_id)
        raise KeyError("Could not find a supported text-to-video latent node")

    @classmethod
    def _apply_common_generation_controls(cls, workflow: dict[str, Any], payload: Any) -> None:
        duration_seconds = float(payload.num_frames) / float(payload.fps)
        split_steps = max(1, int(round(payload.num_inference_steps / 2.0)))
        for _node_id, node in workflow.items():
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            title = str(node.get("_meta", {}).get("title", "")).strip().lower()
            class_type = str(node.get("class_type", ""))

            if class_type in {"PrimitiveInt", "INTConstant"}:
                if "split" in title and "step" in title:
                    inputs["value"] = split_steps
                elif "steps" in title:
                    inputs["value"] = int(payload.num_inference_steps)
                elif "length" in title or "lenght" in title:
                    inputs["value"] = int(payload.num_frames)
            elif class_type in {"PrimitiveFloat", "FloatConstant"}:
                if "guidance" in title or "cfg" in title:
                    inputs["value"] = float(payload.guidance_scale)
                elif "fps" in title:
                    inputs["value"] = float(payload.fps)
                elif "duration" in title:
                    inputs["value"] = duration_seconds
            elif class_type == "mxSlider":
                if "split" in title and "step" in title:
                    slider_value: int | float | None = split_steps
                elif "steps" in title:
                    slider_value = int(payload.num_inference_steps)
                elif "guidance" in title or "cfg" in title:
                    slider_value = float(payload.guidance_scale)
                elif "frame rate" in title or title == "fps":
                    slider_value = float(payload.fps)
                elif "duration" in title:
                    slider_value = duration_seconds
                elif title == "width":
                    slider_value = int(payload.width)
                elif title == "height":
                    slider_value = int(payload.height)
                else:
                    slider_value = None

                if slider_value is not None:
                    inputs["Xi"] = slider_value
                    inputs["Xf"] = slider_value

            if "fps" in inputs and not isinstance(inputs["fps"], list):
                inputs["fps"] = int(payload.fps)
            if "frame_rate" in inputs and not isinstance(inputs["frame_rate"], list):
                inputs["frame_rate"] = int(payload.fps)
            if "length" in inputs and not isinstance(inputs["length"], list):
                inputs["length"] = int(payload.num_frames)
            if "width" in inputs and not isinstance(inputs["width"], list):
                inputs["width"] = int(payload.width)
            if "height" in inputs and not isinstance(inputs["height"], list):
                inputs["height"] = int(payload.height)
            if "desired_width" in inputs and not isinstance(inputs["desired_width"], list):
                inputs["desired_width"] = int(payload.width)
            if "desired_height" in inputs and not isinstance(inputs["desired_height"], list):
                inputs["desired_height"] = int(payload.height)

        cls._configure_interpolated_video_output_nodes(
            workflow,
            payload,
        )

    @classmethod
    def _find_upstream_interpolation_node_id(
        cls,
        workflow: dict[str, Any],
        start_node_id: str,
    ) -> str | None:
        to_visit = [str(start_node_id)]
        visited: set[str] = set()

        while to_visit:
            node_id = to_visit.pop()
            if node_id in visited:
                continue
            visited.add(node_id)

            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue

            class_type = str(node.get("class_type") or "")
            if class_type in {"FL_RIFE", "RIFE VFI"}:
                return node_id

            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            for linked_node_id in cls._linked_input_node_ids(inputs):
                if linked_node_id not in visited:
                    to_visit.append(linked_node_id)

        return None

    @classmethod
    def _find_interpolated_multiplier(
        cls,
        workflow: dict[str, Any],
        preferred_node_id: str,
    ) -> int:
        interpolation_node_id = cls._find_upstream_interpolation_node_id(workflow, preferred_node_id)
        if interpolation_node_id is None:
            return 1
        source_node = workflow.get(interpolation_node_id)
        if not isinstance(source_node, dict):
            return 1
        source_inputs = source_node.get("inputs")
        if not isinstance(source_inputs, dict):
            return 1
        multiplier = cls._resolve_workflow_int(workflow, source_inputs.get("multiplier"))
        return max(1, int(multiplier or 1))

    @classmethod
    def _configure_interpolated_video_output_nodes(
        cls,
        workflow: dict[str, Any],
        payload: Any,
    ) -> None:
        cls._configure_interpolated_video_output_fps(
            workflow,
            requested_fps=int(payload.fps),
        )

    @classmethod
    def _configure_interpolated_video_output_fps(
        cls,
        workflow: dict[str, Any],
        *,
        requested_fps: int,
    ) -> None:
        preferred_node_id = cls._find_preferred_vhs_video_node_id(workflow)
        if preferred_node_id is None:
            return
        preferred_multiplier = cls._find_interpolated_multiplier(workflow, preferred_node_id)
        for node_id in cls._find_node_ids(workflow, "VHS_VideoCombine"):
            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            is_preferred = node_id == preferred_node_id
            if "save_output" in inputs and not isinstance(inputs["save_output"], list):
                inputs["save_output"] = is_preferred
            if "frame_rate" in inputs:
                inputs["frame_rate"] = (
                    cls._expected_saved_video_fps(
                        workflow,
                        node_id,
                        fallback_fps=int(requested_fps) * preferred_multiplier,
                    )
                    if is_preferred
                    else int(requested_fps)
                )

    @classmethod
    def _expected_saved_video_fps(
        cls,
        workflow: dict[str, Any],
        preferred_node_id: str | None = None,
        *,
        fallback_fps: int | None = None,
    ) -> int | None:
        candidate_node_ids = [preferred_node_id] if preferred_node_id is not None else []
        auto_preferred_node_id = cls._find_preferred_vhs_video_node_id(workflow)
        if auto_preferred_node_id is not None and auto_preferred_node_id not in candidate_node_ids:
            candidate_node_ids.append(auto_preferred_node_id)

        for node_id in candidate_node_ids:
            node = workflow.get(str(node_id))
            if not isinstance(node, dict):
                continue
            hinted_fps = cls._extract_video_output_fps_hint(node)
            if hinted_fps is not None:
                return hinted_fps
            if fallback_fps is not None:
                return max(1, int(fallback_fps))
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            frame_rate = cls._resolve_workflow_int(workflow, inputs.get("frame_rate"))
            if frame_rate is not None and frame_rate > 0:
                return frame_rate

        if fallback_fps is None:
            return None
        return max(1, int(fallback_fps))

    @staticmethod
    def _extract_video_output_fps_hint(node: dict[str, Any]) -> int | None:
        candidates = [
            str(node.get("_meta", {}).get("title", "")),
        ]
        inputs = node.get("inputs")
        if isinstance(inputs, dict):
            candidates.append(str(inputs.get("filename_prefix", "")))

        for candidate in candidates:
            match = re.search(r"(\d+)\s*fps", candidate, flags=re.IGNORECASE)
            if match is None:
                continue
            fps = int(match.group(1))
            if fps > 0:
                return fps
        return None

    @classmethod
    def _normalize_non_loop_i2v_workflow(
        cls,
        workflow: dict[str, Any],
        *,
        source_image_path: Path,
    ) -> None:
        constant_node_ids = tuple(
            node_id
            for class_type in ("FloatConstant", "INTConstant", "Seed (rgthree)")
            for node_id in cls._find_node_ids(workflow, class_type)
        )
        for node_id in constant_node_ids:
            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            literal_key = "seed" if node.get("class_type") == "Seed (rgthree)" else "value"
            literal_value = inputs.get(literal_key)
            if isinstance(literal_value, list):
                continue
            cls._replace_workflow_links(workflow, {(str(node_id), 0): literal_value})
            workflow.pop(str(node_id), None)

        for node_id in cls._find_node_ids(workflow, "FindPerfectResolution"):
            resolved_size = cls._resolve_find_perfect_resolution_size(
                workflow,
                node_id=node_id,
                source_image_path=source_image_path,
            )
            if resolved_size is None:
                continue
            width, height = resolved_size
            cls._replace_workflow_links(
                workflow,
                {
                    (node_id, 0): width,
                    (node_id, 1): height,
                },
            )
            if not cls._workflow_references_node(workflow, node_id):
                workflow.pop(node_id, None)

    @classmethod
    def _resolve_find_perfect_resolution_size(
        cls,
        workflow: dict[str, Any],
        *,
        node_id: str,
        source_image_path: Path,
    ) -> tuple[int, int] | None:
        node = workflow.get(node_id)
        if not isinstance(node, dict):
            return None
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            return None
        image_size = cls._resolve_image_dimensions(
            workflow,
            inputs.get("image"),
            source_image_path=source_image_path,
        )
        if image_size is None:
            return None
        orig_width, orig_height = image_size
        if orig_width <= 0 or orig_height <= 0:
            return None

        desired_width = int(cls._resolve_workflow_int(workflow, inputs.get("desired_width")) or 0)
        desired_height = int(cls._resolve_workflow_int(workflow, inputs.get("desired_height")) or 0)
        divisible_by = max(1, int(cls._resolve_workflow_int(workflow, inputs.get("divisible_by")) or 16))

        aspect_ratio = float(orig_width) / float(orig_height)
        if desired_width == 0 and desired_height == 0:
            return None
        if desired_width == 0:
            desired_width = int(round(desired_height * aspect_ratio))
        if desired_height == 0:
            desired_height = int(round(desired_width / max(aspect_ratio, 1e-8)))

        num_pixels = desired_width * desired_height
        if num_pixels <= 0:
            return None
        h_float = (num_pixels * orig_height / orig_width) ** 0.5
        new_height = max(divisible_by, int(round(h_float / divisible_by)) * divisible_by)
        new_width = max(
            divisible_by,
            int(round((aspect_ratio * h_float) / divisible_by)) * divisible_by,
        )
        return new_width, new_height

    @classmethod
    def _resolve_image_dimensions(
        cls,
        workflow: dict[str, Any],
        value: Any,
        *,
        source_image_path: Path,
    ) -> tuple[int, int] | None:
        if isinstance(value, list) and value:
            node = workflow.get(str(value[0]))
            if not isinstance(node, dict):
                return None
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                return None
            class_type = str(node.get("class_type") or "")
            if class_type == "ImageScaleBy":
                base_dimensions = cls._resolve_image_dimensions(
                    workflow,
                    inputs.get("image"),
                    source_image_path=source_image_path,
                )
                if base_dimensions is None:
                    return None
                scale_by = cls._resolve_workflow_value(workflow, inputs.get("scale_by"))
                if not isinstance(scale_by, (int, float)):
                    scale_by = 1.0
                return (
                    max(1, int(round(base_dimensions[0] * float(scale_by)))),
                    max(1, int(round(base_dimensions[1] * float(scale_by)))),
                )
            if class_type == "LoadImage":
                with Image.open(source_image_path) as image:
                    return image.size
        with Image.open(source_image_path) as image:
            return image.size

    @staticmethod
    def _apply_audio_video_source_settings(
        workflow: dict[str, Any],
        payload: Any,
    ) -> None:
        source_fps = payload.fps
        if source_fps is not None:
            for node in workflow.values():
                if not isinstance(node, dict):
                    continue
                class_type = str(node.get("class_type") or "")
                inputs = node.get("inputs")
                if not isinstance(inputs, dict):
                    continue

                if class_type == "RIFEInterpolation" and not isinstance(
                    inputs.get("target_fps"),
                    list,
                ):
                    inputs["target_fps"] = float(source_fps)
                elif class_type == "CreateVideo" and not isinstance(
                    inputs.get("fps"),
                    list,
                ):
                    inputs["fps"] = int(source_fps)

                title = str(node.get("_meta", {}).get("title", "")).strip().lower()
                if class_type == "PrimitiveFloat" and "final fps" in title:
                    inputs["value"] = float(source_fps)

        for node in workflow.values():
            if not isinstance(node, dict) or node.get("class_type") != "ImageScale":
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            title = str(node.get("_meta", {}).get("title", "")).strip().lower()
            if "upscale image" not in title:
                continue
            inputs["width"] = int(payload.width)
            inputs["height"] = int(payload.height)
