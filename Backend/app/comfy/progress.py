from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import requests


@dataclass(frozen=True)
class ComfyExecutionPhase:
    node_ids: tuple[str, ...]
    label: str
    weight: float
    step_count: int | None = None
    step_unit: str = "step"


@dataclass
class ComfyExecutionPlan:
    preparing_progress: float
    queue_progress: float
    active_start_progress: float
    active_end_progress: float
    node_progress: dict[str, tuple[float, float]]
    node_labels: dict[str, str]
    node_step_counts: dict[str, int]
    node_step_units: dict[str, str]
    fallback_running_label: str

    def progress_for_node(self, node_id: str, fraction: float) -> tuple[float, str] | None:
        node_range = self.node_progress.get(node_id)
        if node_range is None:
            return None
        fraction = max(0.0, min(1.0, float(fraction)))
        start_progress, end_progress = node_range
        progress = start_progress + (end_progress - start_progress) * fraction
        label = self.node_labels.get(node_id, self.fallback_running_label)
        step_count = self.node_step_counts.get(node_id)
        if step_count is not None and step_count > 1:
            current_step = min(step_count, max(1, int(fraction * step_count + 0.999999)))
            step_unit = self.node_step_units.get(node_id, "step")
            label = f"{label} • {step_unit} {current_step}/{step_count}"
        return progress, label


class ComfyProgressMixin:
    def _fetch_progress_snapshot(
        self,
        prompt_id: str,
        *,
        preparing_label: str = "Preparing video generation",
        active_label: str = "Generating frames",
    ) -> tuple[float, str] | None:
        try:
            queue_response = requests.get(f"{self.comfy_url}/queue", timeout=15)
            queue_response.raise_for_status()
            queue_payload = queue_response.json()
        except requests.RequestException:
            queue_payload = {}

        running_count = 0
        pending_count = 0
        try:
            running = queue_payload.get("queue_running") or []
            pending = queue_payload.get("queue_pending") or []
            running_count = len(running)
            pending_count = len(pending)
        except Exception:
            running_count = 0
            pending_count = 0

        try:
            progress_response = requests.get(f"{self.comfy_url}/progress", timeout=15)
            progress_response.raise_for_status()
            payload = progress_response.json()
            value = float(payload.get("value") or 0)
            maximum = float(payload.get("max") or 0)
            node = str(payload.get("node") or "").strip()
            progress_prompt_id = str(payload.get("prompt_id") or "").strip()
            if maximum > 0 and (not progress_prompt_id or progress_prompt_id == prompt_id):
                fraction = max(0.0, min(1.0, value / maximum))
                execution_plan = self._execution_plan_by_prompt_id.get(prompt_id)
                if execution_plan is not None:
                    node_snapshot = execution_plan.progress_for_node(node, fraction)
                    if node_snapshot is not None:
                        return self._clamp_progress_snapshot(
                            prompt_id,
                            node_snapshot[0],
                            node_snapshot[1],
                        )
                    conservative_progress = (
                        execution_plan.active_start_progress
                        + (execution_plan.active_end_progress - execution_plan.active_start_progress)
                        * fraction
                        * 0.6
                    )
                    return self._clamp_progress_snapshot(
                        prompt_id,
                        conservative_progress,
                        execution_plan.fallback_running_label,
                    )
                if "save" in node.lower() or "video" in node.lower():
                    return self._clamp_progress_snapshot(
                        prompt_id,
                        0.88 + fraction * 0.04,
                        "Finalizing video",
                    )
                return self._clamp_progress_snapshot(
                    prompt_id,
                    0.26 + fraction * 0.58,
                    active_label,
                )
        except requests.RequestException:
            pass

        execution_plan = self._execution_plan_by_prompt_id.get(prompt_id)
        if running_count > 0:
            fallback_progress = (
                execution_plan.active_start_progress
                if execution_plan is not None
                else 0.24
            )
            fallback_label = (
                execution_plan.fallback_running_label
                if execution_plan is not None
                else preparing_label
            )
            return self._clamp_progress_snapshot(prompt_id, fallback_progress, fallback_label)
        if pending_count > 0:
            queue_progress = execution_plan.queue_progress if execution_plan is not None else 0.16
            return self._clamp_progress_snapshot(prompt_id, queue_progress, "Waiting in video queue")
        return None

    def _build_execution_plan(
        self,
        workflow: dict[str, Any],
        *,
        workflow_kind: str,
        preparing_progress: float,
        queue_progress: float,
        active_start_progress: float,
        active_end_progress: float,
        fallback_running_label: str,
    ) -> ComfyExecutionPlan:
        phases: list[ComfyExecutionPhase]
        if workflow_kind in {"t2v", "i2v"}:
            phases = self._build_sampling_phases(workflow)
        elif workflow_kind == "upscale":
            phases = self._build_upscale_phases(workflow)
        elif workflow_kind == "audio_video":
            phases = self._build_audio_video_phases(workflow)
        elif workflow_kind == "prompt":
            phases = self._build_prompt_generation_phases(workflow)
        else:
            phases = []

        node_progress: dict[str, tuple[float, float]] = {}
        node_labels: dict[str, str] = {}
        node_step_counts: dict[str, int] = {}
        node_step_units: dict[str, str] = {}
        total_weight = sum(max(phase.weight, 0.1) for phase in phases)
        progress_cursor = active_start_progress
        progress_span = max(0.0, active_end_progress - active_start_progress)

        for index, phase in enumerate(phases):
            phase_weight = max(phase.weight, 0.1)
            phase_span = (
                progress_span * (phase_weight / total_weight)
                if total_weight > 0
                else 0.0
            )
            phase_end = (
                active_end_progress
                if index == len(phases) - 1
                else min(active_end_progress, progress_cursor + phase_span)
            )
            for node_id in phase.node_ids:
                node_progress[node_id] = (progress_cursor, phase_end)
                node_labels[node_id] = phase.label
                if phase.step_count is not None and phase.step_count > 1:
                    node_step_counts[node_id] = max(1, int(phase.step_count))
                    node_step_units[node_id] = phase.step_unit
            progress_cursor = phase_end

        return ComfyExecutionPlan(
            preparing_progress=preparing_progress,
            queue_progress=queue_progress,
            active_start_progress=active_start_progress,
            active_end_progress=active_end_progress,
            node_progress=node_progress,
            node_labels=node_labels,
            node_step_counts=node_step_counts,
            node_step_units=node_step_units,
            fallback_running_label=fallback_running_label,
        )

    @classmethod
    def _build_sampling_phases(cls, workflow: dict[str, Any]) -> list[ComfyExecutionPhase]:
        sampler_phases: list[tuple[int, int, str]] = []
        for node_id in cls._find_node_ids(workflow, "KSamplerAdvanced"):
            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            start_step = cls._resolve_workflow_int(workflow, inputs.get("start_at_step"))
            end_step = cls._resolve_workflow_int(workflow, inputs.get("end_at_step"))
            total_steps = cls._resolve_workflow_int(workflow, inputs.get("steps"))
            if start_step is None:
                start_step = 0
            if end_step is None:
                end_step = total_steps if total_steps is not None else start_step + 1
            effective_steps = total_steps if total_steps is not None else max(1, end_step - start_step)
            effective_steps = max(1, end_step - start_step) if end_step > start_step else max(1, effective_steps)
            sampler_phases.append((start_step, effective_steps, node_id))

        sampler_phases.sort(key=lambda item: (item[0], cls._node_sort_key(item[2])))
        phases = [
            ComfyExecutionPhase(
                node_ids=(node_id,),
                label=f"Generating frames {index + 1}/{len(sampler_phases)}",
                weight=float(weight),
                step_count=max(1, int(weight)),
                step_unit="step",
            )
            for index, (_start_step, weight, node_id) in enumerate(sampler_phases)
        ]

        decode_nodes = tuple(cls._find_node_ids(workflow, "VAEDecode"))
        if decode_nodes:
            phases.append(ComfyExecutionPhase(node_ids=decode_nodes, label="Decoding frames", weight=2.0))

        encode_nodes = tuple(
            dict.fromkeys(
                [
                    *cls._find_node_ids(workflow, "CreateVideo"),
                    *cls._find_node_ids(workflow, "VHS_VideoCombine"),
                ]
            )
        )
        if encode_nodes:
            phases.append(ComfyExecutionPhase(node_ids=encode_nodes, label="Encoding video", weight=1.5))

        save_nodes = tuple(cls._find_node_ids(workflow, "SaveVideo"))
        if not save_nodes:
            preferred_output_id = cls._find_preferred_vhs_video_node_id(workflow)
            if preferred_output_id is not None:
                save_nodes = (preferred_output_id,)
        if save_nodes:
            phases.append(ComfyExecutionPhase(node_ids=save_nodes, label="Saving video", weight=1.0))
        return phases

    @classmethod
    def _build_upscale_phases(cls, workflow: dict[str, Any]) -> list[ComfyExecutionPhase]:
        phases: list[ComfyExecutionPhase] = []
        upscale_nodes = tuple(cls._find_node_ids(workflow, "Video_Upscale_With_Model"))
        if upscale_nodes:
            phases.append(ComfyExecutionPhase(node_ids=upscale_nodes, label="Scaling video", weight=6.0))

        combine_nodes = tuple(cls._find_node_ids(workflow, "VHS_VideoCombine"))
        if combine_nodes:
            phases.append(ComfyExecutionPhase(node_ids=combine_nodes, label="Encoding video", weight=2.0))

        save_nodes = tuple(cls._find_node_ids(workflow, "SaveVideo"))
        if save_nodes:
            phases.append(ComfyExecutionPhase(node_ids=save_nodes, label="Saving video", weight=1.0))
        return phases

    @classmethod
    def _build_prompt_generation_phases(cls, workflow: dict[str, Any]) -> list[ComfyExecutionPhase]:
        phases: list[ComfyExecutionPhase] = []

        caption_nodes = tuple(cls._find_node_ids(workflow, "Florence2Run"))
        if caption_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=caption_nodes,
                    label="Analyzing image",
                    weight=2.0,
                )
            )

        planning_nodes = tuple(cls._find_node_ids(workflow, "OllamaChat"))
        if planning_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=planning_nodes,
                    label="Generating prompt",
                    weight=1.5,
                )
            )

        final_nodes = tuple(cls._find_node_ids(workflow, "PreviewAny"))
        if final_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=final_nodes,
                    label="Finalizing prompt",
                    weight=0.5,
                )
            )
        return phases

    @classmethod
    def _build_audio_video_phases(cls, workflow: dict[str, Any]) -> list[ComfyExecutionPhase]:
        phases: list[ComfyExecutionPhase] = []

        caption_nodes = tuple(cls._find_node_ids(workflow, "Florence2Run"))
        if caption_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=caption_nodes,
                    label="Captioning video",
                    weight=2.0,
                )
            )

        planning_nodes = tuple(cls._find_node_ids(workflow, "OllamaChat"))
        if planning_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=planning_nodes,
                    label="Planning audio",
                    weight=1.5,
                )
            )

        audio_nodes = tuple(cls._find_node_ids(workflow, "MMAudioSampler"))
        if audio_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=audio_nodes,
                    label="Generating audio",
                    weight=5.0,
                )
            )

        combine_nodes = tuple(cls._find_node_ids(workflow, "VHS_VideoCombine"))
        if combine_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=combine_nodes,
                    label="Combining audio and video",
                    weight=2.0,
                )
            )

        save_nodes = tuple(cls._find_node_ids(workflow, "SaveVideo"))
        if save_nodes:
            phases.append(
                ComfyExecutionPhase(
                    node_ids=save_nodes,
                    label="Saving video",
                    weight=1.0,
                )
            )
        return phases

    def _clamp_progress_snapshot(
        self,
        prompt_id: str,
        progress: float,
        status_text: str,
    ) -> tuple[float, str]:
        clamped_progress = self._progress_floor_for_prompt(prompt_id, progress)
        return clamped_progress, status_text

    def _progress_floor_for_prompt(self, prompt_id: str, progress: float) -> float:
        progress = max(0.0, min(1.0, float(progress)))
        previous_progress = self._last_progress_by_prompt_id.get(prompt_id, 0.0)
        clamped_progress = max(previous_progress, progress)
        self._last_progress_by_prompt_id[prompt_id] = clamped_progress
        return clamped_progress
