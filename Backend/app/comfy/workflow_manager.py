from __future__ import annotations

import logging
import threading
from pathlib import Path

import requests

from .client import ComfyClientMixin
from .generation import ComfyGenerationMixin
from .media import ComfyMediaMixin
from .outputs import ComfyOutputMixin
from .progress import ComfyExecutionPlan, ComfyProgressMixin
from .workflow_graph import ComfyWorkflowGraphMixin
from .workflow_loras import ComfyWorkflowLoraMixin
from .workflow_runtime import ComfyWorkflowRuntimeMixin
from .workflow_video import ComfyVideoWorkflowMixin


logger = logging.getLogger(__name__)


class ComfyVideoWorkflowManager(
    ComfyWorkflowRuntimeMixin,
    ComfyClientMixin,
    ComfyGenerationMixin,
    ComfyMediaMixin,
    ComfyOutputMixin,
    ComfyProgressMixin,
    ComfyWorkflowLoraMixin,
    ComfyWorkflowGraphMixin,
    ComfyVideoWorkflowMixin,
):
    def __init__(
        self,
        *,
        comfy_url: str,
        image_to_video_workflow_path: str | Path | None,
        image_to_video_loop_workflow_path: str | Path | None,
        video_upscaler_workflow_path: str | Path | None,
        video_to_audio_workflow_path: str | Path | None,
        image_prompt_generator_workflow_path: str | Path | None = None,
        text_to_video_workflow_path: str | Path | None = None,
        video_upscaler_device_strategy: str = "keep_loaded",
        ollama_url: str = "http://127.0.0.1:11434",
        ollama_timeout_seconds: float = 30.0,
    ) -> None:
        self.comfy_url = comfy_url.rstrip("/")
        self.ollama_url = ollama_url.rstrip("/")
        self.ollama_timeout_seconds = float(ollama_timeout_seconds)
        self.image_to_video_workflow_path = (
            Path(image_to_video_workflow_path) if image_to_video_workflow_path else None
        )
        self.image_to_video_loop_workflow_path = (
            Path(image_to_video_loop_workflow_path)
            if image_to_video_loop_workflow_path
            else None
        )
        self.image_prompt_generator_workflow_path = (
            Path(image_prompt_generator_workflow_path)
            if image_prompt_generator_workflow_path
            else None
        )
        self.video_upscaler_workflow_path = (
            Path(video_upscaler_workflow_path) if video_upscaler_workflow_path else None
        )
        self.video_upscaler_device_strategy = self._normalize_video_upscaler_device_strategy(
            video_upscaler_device_strategy
        )
        self.video_to_audio_workflow_path = (
            Path(video_to_audio_workflow_path) if video_to_audio_workflow_path else None
        )
        self.text_to_video_workflow_path = (
            Path(text_to_video_workflow_path) if text_to_video_workflow_path else None
        )
        self._client_id: str | None = None
        self._active_prompt_id: str | None = None
        self._active_workflow_key: str | None = None
        self._active_ollama_models: set[str] = set()
        self._cancel_requested_prompt_ids: set[str] = set()
        self._execution_plan_by_prompt_id: dict[str, ComfyExecutionPlan] = {}
        self._last_progress_by_prompt_id: dict[str, float] = {}
        self._state_lock = threading.Lock()

    def free_memory(self) -> None:
        try:
            response = requests.post(
                f"{self.comfy_url}/free",
                json={"unload_models": True, "free_memory": True},
                timeout=30,
            )
            response.raise_for_status()
        except requests.RequestException:
            logger.warning("Failed to free ComfyUI memory", exc_info=True)
