from __future__ import annotations

import io
import json
import logging
import os
import signal
import subprocess
import time
import unittest
import uuid
import zipfile
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image
import requests
from werkzeug.wsgi import FileWrapper

from app import create_app
from app.assets import AssetCatalog, AssetEntry, build_legacy_asset_id_maps, normalize_asset_id
from app.persistence import AppDatabase
from app.generation import (
    DiffusersImageGenerator,
    GeneratedArtifact,
    GenerationPayload,
    OllamaPromptRuntimeManager,
    OllamaResponseError,
    OllamaUnavailableError,
    SelectedLora,
    VideoGenerationPayload,
    VideoWorkflowLora,
    VideoToAudioPayload,
    VideoToGifPayload,
    VideoUpscalePayload,
    compose_positive_prompt,
)
from app.comfy import ComfyPromptCancelledError, ComfyVideoWorkflowManager
from app.system import ErrorStore
from app.job_queue import JobWorker
from app.system import ManagedLogStore
from app.system import CommandResult, collect_system_info


ASSETS_YAML = """\
models:
  - id: demo-model
    label: Demo Model
    path: /fixtures/models/demo-model.safetensors
loras:
  - id: demo-lora
    label: Demo LoRA
    path: /fixtures/loras/demo-lora.safetensors
    default_strength: 0.75
"""


class MockGenerator:
    def __init__(self) -> None:
        self.last_generate_from_image_payload: GenerationPayload | None = None
        self.last_prompt_generation_input: str | None = None
        self.last_prompt_generation_image_bytes: bytes | None = None
        self.last_i2v_prompt_generation_input: str | None = None
        self.last_i2v_prompt_generation_image_bytes: bytes | None = None
        self.last_chat_model: str | None = None
        self.last_chat_messages: list[dict[str, object]] | None = None
        self.last_chat_tools: list[dict[str, object]] | None = None
        self.last_chat_think: bool | str | None = None
        self.last_chat_context_window: int | None = None
        self.chat_call_count = 0
        self.last_summary_model: str | None = None
        self.last_summary_prompt: str | None = None
        self.last_chat_title_model: str | None = None
        self.last_chat_title_user_message: str | None = None
        self.last_chat_title_system_message: str | None = None
        self.last_chat_title_context_window: int | None = None
        self.prompt_response = "generated prompt"
        self.i2v_prompt_response = "generated i2v prompt"
        self.chat_response = "generated chat response"
        self.chat_thinking = "thinking trace"
        self.summary_response = "rolling memory summary"
        self.chat_title_response = "Generated title"
        self.chat_chunks: list[dict[str, object]] | None = None
        self.chat_responses: list[dict[str, object]] | None = None
        self.prompt_generation_error: Exception | None = None
        self.i2v_prompt_generation_error: Exception | None = None
        self.chat_generation_error: Exception | None = None
        self.summary_generation_error: Exception | None = None
        self.chat_title_generation_error: Exception | None = None

    def generate(
        self,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        image_id = f"generated-image-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.png"
        Image.new("RGB", (1024, 576), color="red").save(file_path)
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=1024,
            height=576,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.model_id,
            loras=[{"lora_id": item.lora_id, "strength": item.strength} for item in payload.loras],
            generation_duration_seconds=1.25,
        )

    def generate_prompt(
        self,
        prompt: str,
        image_bytes: bytes | None = None,
        model: str | None = None,
    ) -> str:
        self.last_prompt_generation_input = prompt
        self.last_prompt_generation_image_bytes = image_bytes
        if self.prompt_generation_error is not None:
            raise self.prompt_generation_error
        return self.prompt_response

    def generate_i2v_prompt(
        self,
        *,
        prompt: str,
        source_image_path: Path,
        model: str | None = None,
    ) -> str:
        self.last_i2v_prompt_generation_input = prompt
        self.last_i2v_prompt_generation_image_bytes = source_image_path.read_bytes()
        if self.i2v_prompt_generation_error is not None:
            raise self.i2v_prompt_generation_error
        return self.i2v_prompt_response

    def summarize_chat_messages(
        self,
        *,
        model: str,
        summary_prompt: str,
        context_window: int | None = None,
    ) -> str:
        self.last_summary_model = model
        self.last_summary_prompt = summary_prompt
        if self.summary_generation_error is not None:
            raise self.summary_generation_error
        return self.summary_response

    def stream_chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        think=True,
        context_window: int | None = None,
        cancel_requested=None,
    ):
        self.last_chat_model = model
        self.last_chat_messages = messages
        self.last_chat_think = think
        self.last_chat_context_window = context_window
        if self.chat_generation_error is not None:
            raise self.chat_generation_error
        if self.chat_chunks is not None:
            for chunk in self.chat_chunks:
                yield dict(chunk)
            return
        yield {
            "message": {
                "thinking": self.chat_thinking,
                "content": "",
            },
            "done": False,
        }
        yield {
            "message": {
                "thinking": "",
                "content": self.chat_response,
            },
            "total_duration": 100,
            "load_duration": 20,
            "prompt_eval_count": 30,
            "prompt_eval_duration": 40,
            "eval_count": 50,
            "eval_duration": 60,
            "done": True,
        }

    def chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        tools: list[dict[str, object]] | None = None,
        think=True,
        context_window: int | None = None,
    ) -> dict[str, object]:
        self.chat_call_count += 1
        self.last_chat_model = model
        self.last_chat_messages = messages
        self.last_chat_tools = tools
        self.last_chat_think = think
        self.last_chat_context_window = context_window
        if self.chat_generation_error is not None:
            raise self.chat_generation_error
        if self.chat_responses:
            return dict(self.chat_responses.pop(0))
        return {
            "message": {
                "thinking": self.chat_thinking,
                "content": self.chat_response,
            },
            "total_duration": 100,
            "load_duration": 20,
            "prompt_eval_count": 30,
            "prompt_eval_duration": 40,
            "eval_count": 50,
            "eval_duration": 60,
            "done": True,
        }

    def generate_chat_title(
        self,
        *,
        model: str,
        user_message: str,
        system_message: str = "",
        context_window: int | None = None,
    ) -> str:
        self.last_chat_title_model = model
        self.last_chat_title_user_message = user_message
        self.last_chat_title_system_message = system_message
        self.last_chat_title_context_window = context_window
        if self.chat_title_generation_error is not None:
            raise self.chat_title_generation_error
        return self.chat_title_response

    def upscale(
        self,
        *,
        source_image_id: str,
        source_image_path: Path,
        payload: GenerationPayload,
        scale_factor: float,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        image_id = f"upscaled-image-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.png"
        Image.new("RGB", (2048, 1152), color="blue").save(file_path)
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=2048,
            height=1152,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.model_id,
            loras=[{"lora_id": item.lora_id, "strength": item.strength} for item in payload.loras],
            source_image_id=source_image_id,
            scale_factor=scale_factor,
            is_upscaled=True,
            generation_duration_seconds=2.5,
        )

    def generate_video(
        self,
        payload,
        output_dir: Path,
        progress_callback=None,
        cancel_requested=None,
    ) -> GeneratedArtifact:
        self.last_video_generation_payload = payload
        image_id = f"generated-video-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.mp4"
        poster_path = output_dir / f"{image_id}_poster.png"
        file_path.write_bytes(b"fake-mp4")
        Image.new("RGB", (payload.width, payload.height), color="green").save(
            poster_path
        )
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=payload.width,
            height=payload.height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.display_model_id or payload.video_model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            mime_type="video/mp4",
            media_type="video",
            poster_path=str(poster_path),
            poster_mime_type="image/png",
            duration_seconds=payload.num_frames / payload.fps,
            generation_duration_seconds=3.75,
            fps=payload.fps,
            num_frames=payload.num_frames,
            loop_video=False,
        )

    def upscale_video(
        self,
        *,
        source_video_path: Path,
        payload: VideoUpscalePayload,
        output_dir: Path,
        progress_callback=None,
        cancel_requested=None,
    ) -> GeneratedArtifact:
        image_id = f"upscaled-video-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.mp4"
        poster_path = output_dir / f"{image_id}_poster.png"
        file_path.write_bytes(b"fake-upscaled-mp4")
        Image.new(
            "RGB",
            (
                max(1, int(round(payload.width * payload.scale_factor))),
                max(1, int(round(payload.height * payload.scale_factor))),
            ),
            color="navy",
        ).save(poster_path)
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=max(1, int(round(payload.width * payload.scale_factor))),
            height=max(1, int(round(payload.height * payload.scale_factor))),
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation=payload.image_orientation,
            source_image_id=payload.source_image_id,
            scale_factor=payload.scale_factor,
            is_upscaled=True,
            mime_type="video/mp4",
            media_type="video",
            poster_path=str(poster_path),
            poster_mime_type="image/png",
            duration_seconds=payload.num_frames / payload.fps,
            generation_duration_seconds=2.0,
            fps=payload.fps,
            num_frames=payload.num_frames,
        )

    def convert_video_to_gif(
        self,
        *,
        source_video_path: Path,
        payload: VideoToGifPayload,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        image_id = f"converted-gif-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.gif"
        first = Image.new("RGB", (payload.width, payload.height), color="teal")
        second = Image.new("RGB", (payload.width, payload.height), color="gold")
        first.save(
            file_path,
            format="GIF",
            save_all=True,
            append_images=[second],
            duration=100,
            loop=0,
        )
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=payload.width,
            height=payload.height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation=payload.image_orientation,
            source_image_id=payload.source_image_id,
            mime_type="image/gif",
            media_type="gif",
            generation_duration_seconds=1.5,
        )

    def generate_audio_video(
        self,
        *,
        source_video_path: Path,
        payload: VideoToAudioPayload,
        output_dir: Path,
        progress_callback=None,
        cancel_requested=None,
    ) -> GeneratedArtifact:
        image_id = f"audio-video-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.mp4"
        poster_path = output_dir / f"{image_id}_poster.png"
        file_path.write_bytes(b"fake-audio-mp4")
        Image.new("RGB", (payload.width, payload.height), color="maroon").save(
            poster_path
        )
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=payload.width,
            height=payload.height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.model_id,
            loras=[],
            image_orientation=payload.image_orientation,
            source_image_id=payload.source_image_id,
            mime_type="video/mp4",
            media_type="video",
            poster_path=str(poster_path),
            poster_mime_type="image/png",
            duration_seconds=payload.duration_seconds or 4.92,
            generation_duration_seconds=2.25,
            fps=payload.fps or 25,
            num_frames=payload.num_frames or 123,
        )

    def generate_from_image(
        self,
        *,
        source_image_path: Path,
        source_image_id: str | None,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        self.last_generate_from_image_payload = payload
        image_id = f"image-to-image-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.png"
        Image.new("RGB", (896, 896), color="orange").save(file_path)
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=896,
            height=896,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.model_id,
            loras=[{"lora_id": item.lora_id, "strength": item.strength} for item in payload.loras],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            image_orientation=payload.image_orientation,
            source_image_id=source_image_id,
            generation_duration_seconds=1.75,
        )

    def animate_image(
        self,
        *,
        source_image_path: Path,
        payload,
        output_dir: Path,
        progress_callback=None,
        cancel_requested=None,
    ) -> GeneratedArtifact:
        self.last_animation_payload = payload
        image_id = f"animated-video-{uuid.uuid4().hex}"
        file_path = output_dir / f"{image_id}.mp4"
        poster_path = output_dir / f"{image_id}_poster.png"
        file_path.write_bytes(b"fake-mp4")
        Image.new("RGB", (payload.width, payload.height), color="purple").save(
            poster_path
        )
        return GeneratedArtifact(
            image_id=image_id,
            file_path=str(file_path),
            width=payload.width,
            height=payload.height,
            prompt=payload.prompt,
            default_positive_prompt=payload.default_positive_prompt,
            default_negative_prompt=payload.default_negative_prompt,
            final_positive_prompt=compose_positive_prompt(
                payload.default_positive_prompt, payload.prompt
            ),
            model_id=payload.display_model_id or payload.video_model_id,
            loras=[],
            num_inference_steps=payload.num_inference_steps,
            guidance_scale=payload.guidance_scale,
            source_image_id=payload.source_image_id,
            mime_type="video/mp4",
            media_type="video",
            poster_path=str(poster_path),
            poster_mime_type="image/png",
            duration_seconds=payload.num_frames / payload.fps,
            generation_duration_seconds=4.25,
            fps=payload.fps,
            num_frames=payload.num_frames,
            loop_video=payload.loop_video,
        )

    def create_video_poster(
        self,
        *,
        video_path: Path,
        output_dir: Path,
        image_id: str,
        fallback_source_image_path: Path | None = None,
        width: int | None = None,
        height: int | None = None,
    ) -> tuple[str | None, str | None]:
        poster_path = output_dir / f"{image_id}_poster.png"
        Image.new("RGB", (640, 360), color="black").save(poster_path)
        return str(poster_path), "image/png"

    def cancel_active_job(self) -> bool:
        return False


class MockMcpToolProvider:
    def __init__(self) -> None:
        from app.chat.mcp_tools import ChatMcpTool

        self.called_tools: list[tuple[str, dict[str, object]]] = []
        self.tools = (
            ChatMcpTool(
                id="library.lookup",
                server_name="library",
                name="lookup",
                ollama_name="mcp__library__lookup",
                description="Look up library data",
                input_schema={
                    "type": "object",
                    "properties": {"query": {"type": "string"}},
                    "required": ["query"],
                },
            ),
            ChatMcpTool(
                id="demo.lookup",
                server_name="demo",
                name="lookup",
                ollama_name="mcp__demo__lookup",
                description="Look up demo data",
                input_schema={
                    "type": "object",
                    "properties": {"query": {"type": "string"}},
                    "required": ["query"],
                },
            ),
            ChatMcpTool(
                id="agent.run",
                server_name="agent",
                name="run",
                ollama_name="mcp__agent__run",
                description="Run an agent task",
                input_schema={
                    "type": "object",
                    "properties": {"query": {"type": "string"}},
                    "required": ["query"],
                },
                result_mode="direct",
            ),
        )

    def list_tools(self):
        return list(self.tools)

    def toolset_for_ids(self, enabled_tool_ids):
        from app.chat.mcp_tools import ChatMcpToolset, ChatMcpConfigurationError

        wanted = set(enabled_tool_ids)
        found = tuple(tool for tool in self.tools if tool.id in wanted)
        missing = wanted - {tool.id for tool in found}
        if missing:
            raise ChatMcpConfigurationError(f"Unknown MCP tool id: {', '.join(missing)}")
        return ChatMcpToolset(found)

    def max_loop_steps(self) -> int:
        return 4

    def call_tool(self, tool, arguments):
        self.called_tools.append((tool.id, dict(arguments)))
        if tool.id == "agent.run":
            return json.dumps(
                {
                    "content": f"Agent completed {arguments.get('query', '')}",
                    "threadId": "thread-1",
                }
            )
        return f"Tool result for {arguments.get('query', '')}"


class MockOllamaClient:
    def __init__(self, *, supports_tools: bool = True) -> None:
        self.supports_tools = supports_tools

    def show_model(self, model_name: str):
        return {"capabilities": ["tools"] if self.supports_tools else []}


class SlowMockGenerator(MockGenerator):
    def generate(
        self,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        time.sleep(0.25)
        return super().generate(payload, output_dir, progress_callback)


class InterruptibleMockGenerator(MockGenerator):
    def generate(
        self,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        for step in range(8):
            if progress_callback is not None:
                progress_callback(
                    0.2 + ((step + 1) / 8.0) * 0.5,
                    f"Generating image {step + 1}/8",
                )
            time.sleep(0.05)
        return super().generate(payload, output_dir, progress_callback)


class PosterlessVideoMockGenerator(MockGenerator):
    def generate_video(
        self,
        payload,
        output_dir: Path,
        progress_callback=None,
        cancel_requested=None,
    ) -> GeneratedArtifact:
        artifact = super().generate_video(
            payload,
            output_dir,
            progress_callback,
            cancel_requested,
        )
        return GeneratedArtifact(
            image_id=artifact.image_id,
            file_path=artifact.file_path,
            width=artifact.width,
            height=artifact.height,
            prompt=artifact.prompt,
            default_positive_prompt=artifact.default_positive_prompt,
            default_negative_prompt=artifact.default_negative_prompt,
            final_positive_prompt=artifact.final_positive_prompt,
            model_id=artifact.model_id,
            loras=artifact.loras,
            num_inference_steps=artifact.num_inference_steps,
            guidance_scale=artifact.guidance_scale,
            mime_type=artifact.mime_type,
            media_type=artifact.media_type,
            poster_path=None,
            poster_mime_type=None,
            duration_seconds=artifact.duration_seconds,
            generation_duration_seconds=artifact.generation_duration_seconds,
            fps=artifact.fps,
            num_frames=artifact.num_frames,
        )


class CancelTrackingMockGenerator(MockGenerator):
    def __init__(self) -> None:
        super().__init__()
        self.cancel_calls = 0

    def cancel_active_job(self) -> bool:
        self.cancel_calls += 1
        return True


class FailingGenerator(MockGenerator):
    def generate(
        self,
        payload: GenerationPayload,
        output_dir: Path,
        progress_callback=None,
    ) -> GeneratedArtifact:
        raise RuntimeError("Failed to load model weights for demo_model")


class FakePipeline:
    def __init__(self) -> None:
        self.unload_calls = 0
        self.to_calls: list[str] = []
        self.loaded_loras: list[tuple[str, float]] = []

    def unload_lora_weights(self) -> None:
        self.unload_calls += 1

    def to(self, device: str) -> "FakePipeline":
        self.to_calls.append(device)
        return self

    def load_lora_weights(self, path: str, strength: float) -> None:
        self.loaded_loras.append((path, strength))


class FakeCuda:
    def __init__(self) -> None:
        self.empty_cache_calls = 0
        self.ipc_collect_calls = 0
        self.synchronize_calls = 0

    def empty_cache(self) -> None:
        self.empty_cache_calls += 1

    def ipc_collect(self) -> None:
        self.ipc_collect_calls += 1

    def synchronize(self) -> None:
        self.synchronize_calls += 1


class FakeTorch:
    def __init__(self) -> None:
        self.cuda = FakeCuda()


class TrackingVideoPlaceholderGenerator(MockGenerator):
    def __init__(self) -> None:
        super().__init__()
        self.expected_video_output_fps_calls = 0

    def expected_video_output_fps(
        self,
        *,
        image_to_video: bool,
        requested_fps: int,
    ) -> int:
        self.expected_video_output_fps_calls += 1
        return 99


class BackendTestCase(unittest.TestCase):
    def _workspace_dir(self, name: str) -> Path:
        path = Path(__file__).resolve().parent / "_runtime" / f"{name}_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _create_demo_asset_dirs(self, runtime_dir: Path) -> tuple[Path, Path, Path, Path]:
        assets_dir = runtime_dir / "assets"
        models_dir = assets_dir / "models"
        loras_dir = assets_dir / "loras"
        lora_triggers_dir = assets_dir / "loras_triggers"
        unknown_dir = assets_dir / "unknown"
        models_dir.mkdir(parents=True, exist_ok=True)
        loras_dir.mkdir(parents=True, exist_ok=True)
        lora_triggers_dir.mkdir(parents=True, exist_ok=True)
        unknown_dir.mkdir(parents=True, exist_ok=True)
        (models_dir / "demo-model.safetensors").write_bytes(b"")
        (loras_dir / "demo-lora.safetensors").write_bytes(b"")
        (unknown_dir / "ignored-model.safetensors").write_bytes(b"")
        return models_dir, loras_dir, lora_triggers_dir, unknown_dir

    def _create_demo_video_models_dir(self, runtime_dir: Path) -> Path:
        video_models_dir = runtime_dir / "assets" / "models" / "videos"
        video_models_dir.mkdir(parents=True, exist_ok=True)
        (video_models_dir / "demo-video-model.safetensors").write_bytes(b"")
        return video_models_dir

    def _create_test_app(self, runtime_dir: Path, *, generator=None, **extra_config: object):
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        text_to_video_workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        image_to_video_workflow_path = self._create_test_image_to_video_workflow_path(runtime_dir)
        prompt_workflow_path = self._create_test_prompt_workflow_path(runtime_dir)
        config = {
            "TESTING": True,
            "MODELS_DIR": str(models_dir),
            "LORAS_DIR": str(loras_dir),
            "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
            "DATA_DIR": str(data_dir),
            "LOGS_DIR": str(data_dir / "logs"),
            "TEMP_DIR": str(data_dir / "temp"),
            "STORED_DIR": str(data_dir / "stored"),
            "BACKUPS_DIR": str(data_dir / "backups"),
            "ERRORS_DIR": str(data_dir / "errors"),
            "DB_PATH": ":memory:",
            "TEMP_TTL_SECONDS": 7200,
            "CLEANUP_INTERVAL_SECONDS": 3600,
            "COMFY_AUTOSTART_ENABLED": False,
            "COMFY_T2V_WORKFLOW_PATH": str(text_to_video_workflow_path),
            "COMFY_I2V_WORKFLOW_PATH": str(image_to_video_workflow_path),
            "COMFY_I2V_LOOP_WORKFLOW_PATH": str(image_to_video_workflow_path),
            "COMFY_I2V_PROMPT_WORKFLOW_PATH": str(prompt_workflow_path),
            "COMFY_VIDEO_UPSCALER_WORKFLOW_PATH": str(text_to_video_workflow_path),
            "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH": str(text_to_video_workflow_path),
            **extra_config,
        }
        return create_app(test_config=config, generator=generator or MockGenerator())

    def _create_test_video_bundle_dir(self, runtime_dir: Path) -> Path:
        video_models_dir = runtime_dir / "assets" / "models" / "videos"
        video_models_dir.mkdir(parents=True, exist_ok=True)
        (video_models_dir / "test_video_variant_high.safetensors").write_bytes(b"")
        (video_models_dir / "test_video_variant_low.safetensors").write_bytes(b"")
        (video_models_dir / "test_video_helper_vae.safetensors").write_bytes(b"")
        (video_models_dir / "test_video_text_encoder.safetensors").write_bytes(b"")
        return video_models_dir

    def _write_test_workflow(
        self,
        runtime_dir: Path,
        *,
        name: str,
        workflow: dict[str, object],
    ) -> Path:
        workflows_dir = runtime_dir / "workflows"
        workflows_dir.mkdir(parents=True, exist_ok=True)
        workflow_path = workflows_dir / name
        workflow_path.write_text(json.dumps(workflow), encoding="utf-8")
        return workflow_path

    def _create_test_prompt_workflow_path(self, runtime_dir: Path) -> Path:
        return self._write_test_workflow(
            runtime_dir,
            name="test_prompt_workflow.json",
            workflow={
                "10": {
                    "class_type": "LoadImage",
                    "inputs": {"image": "placeholder.png"},
                },
                "20": {
                    "class_type": "StringConcatenate",
                    "_meta": {"title": "Manual Prompter"},
                    "inputs": {"string_a": "", "string_b": ""},
                },
                "30": {
                    "class_type": "PreviewAny",
                    "_meta": {"title": "FINAL Prompt"},
                    "inputs": {},
                },
                "40": {
                    "class_type": "PreviewAny",
                    "_meta": {"title": "SFX Prompt (Ollama)"},
                    "inputs": {},
                },
                "50": {
                    "class_type": "Florence2Run",
                    "inputs": {},
                },
                "60": {
                    "class_type": "OllamaChat",
                    "inputs": {"model": "test-prompt-model"},
                },
            },
        )

    def _create_test_text_to_video_workflow_path(self, runtime_dir: Path) -> Path:
        return self._write_test_workflow(
            runtime_dir,
            name="test_text_to_video_workflow.json",
            workflow={
                "10": {
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "Positive Prompt"},
                    "inputs": {"text": ""},
                },
                "11": {
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "Negative Prompt"},
                    "inputs": {"text": ""},
                },
                "20": {
                    "class_type": "EmptyLatentVideo",
                    "inputs": {"width": 512, "height": 512, "length": 16},
                },
                "30": {
                    "class_type": "KSamplerAdvanced",
                    "inputs": {"steps": 4, "start_at_step": 0, "end_at_step": 2},
                },
                "31": {
                    "class_type": "KSamplerAdvanced",
                    "inputs": {"steps": 4, "start_at_step": 2, "end_at_step": 4},
                },
                "40": {
                    "class_type": "VAEDecode",
                    "inputs": {"samples": ["31", 0]},
                },
                "50": {
                    "class_type": "CreateVideo",
                    "inputs": {"fps": 16, "images": ["40", 0]},
                },
                "60": {
                    "class_type": "VHS_VideoCombine",
                    "_meta": {"title": "Standard Output"},
                    "inputs": {"save_output": True, "frame_rate": 16, "images": ["40", 0]},
                },
                "61": {
                    "class_type": "FL_RIFE",
                    "_meta": {"title": "Interpolation"},
                    "inputs": {"multiplier": 4, "images": ["40", 0]},
                },
                "62": {
                    "class_type": "VHS_VideoCombine",
                    "_meta": {"title": "Interpolated Output 60FPS"},
                    "inputs": {"save_output": False, "frame_rate": 60, "images": ["61", 0]},
                },
                "70": {
                    "class_type": "LoraLoaderModelOnly",
                    "_meta": {"title": "Workflow Adapter"},
                    "inputs": {
                        "lora_name": "test_t2v_adapter.safetensors",
                        "strength_model": 1.0,
                    },
                },
            },
        )

    def _create_test_image_to_video_workflow_path(self, runtime_dir: Path) -> Path:
        return self._write_test_workflow(
            runtime_dir,
            name="test_image_to_video_workflow.json",
            workflow={
                "5": {
                    "class_type": "LoadImage",
                    "inputs": {"image": "placeholder.png"},
                },
                "10": {
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "Positive Prompt"},
                    "inputs": {"text": ""},
                },
                "11": {
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "Negative Prompt"},
                    "inputs": {"text": ""},
                },
                "12": {
                    "class_type": "ResolutionHint",
                    "inputs": {"desired_width": 512, "desired_height": 512},
                },
                "13": {
                    "class_type": "INTConstant",
                    "_meta": {"title": "lenght"},
                    "inputs": {"value": 16},
                },
                "14": {
                    "class_type": "KSamplerAdvanced",
                    "inputs": {"steps": 4, "start_at_step": 0, "end_at_step": 2},
                },
                "15": {
                    "class_type": "KSamplerAdvanced",
                    "inputs": {"steps": 4, "start_at_step": 2, "end_at_step": 4},
                },
                "16": {
                    "class_type": "VAEDecode",
                    "inputs": {"samples": ["15", 0]},
                },
                "17": {
                    "class_type": "VHS_VideoCombine",
                    "_meta": {"title": "Standard Output"},
                    "inputs": {"save_output": True, "frame_rate": 16, "images": ["16", 0]},
                },
                "18": {
                    "class_type": "FL_RIFE",
                    "_meta": {"title": "Interpolation"},
                    "inputs": {"multiplier": 4, "images": ["16", 0]},
                },
                "19": {
                    "class_type": "VHS_VideoCombine",
                    "_meta": {"title": "Interpolated Output 60FPS"},
                    "inputs": {"save_output": False, "frame_rate": 60, "images": ["18", 0]},
                },
                "20": {
                    "class_type": "LoraLoaderModelOnly",
                    "_meta": {"title": "Workflow Adapter"},
                    "inputs": {
                        "lora_name": "test_i2v_adapter.safetensors",
                        "strength_model": 0.9,
                    },
                },
            },
        )

    def _insert_image_record(
        self,
        db: AppDatabase,
        *,
        image_id: str,
        status: str,
        file_path: Path,
        created_at: str,
        media_type: str = "image",
        mime_type: str = "image/png",
        poster_path: Path | None = None,
        poster_mime_type: str | None = None,
        model_id: str = "demo-model",
        tags: list[str] | None = None,
        caption: str = "",
        rating: int = 0,
        width: int = 10,
        height: int = 10,
        prompt: str = "prompt",
        final_positive_prompt: str = "default pos, prompt",
        duration_seconds: float | None = None,
        generation_duration_seconds: float | None = None,
        fps: int | None = None,
        num_frames: int | None = None,
        source_image_id: str | None = None,
        stored_at: str | None = None,
        deleted_at: str | None = None,
    ) -> None:
        with db._connect() as conn:
            conn.execute(
                """
                INSERT INTO images (
                    id, status, media_type, file_name, file_path, mime_type, poster_path,
                    poster_mime_type, width, height, prompt, default_positive_prompt,
                    default_negative_prompt, final_positive_prompt, model_id, loras_json,
                    tags_json, caption, num_inference_steps, guidance_scale, image_orientation,
                    source_image_id, scale_factor, is_upscaled, duration_seconds,
                    generation_duration_seconds, fps,
                    num_frames, loop_video, rating, created_at, stored_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    image_id,
                    status,
                    media_type,
                    file_path.name,
                    db._path_to_record_value(file_path),
                    mime_type,
                    db._path_to_record_value(poster_path) if poster_path else None,
                    poster_mime_type,
                    width,
                    height,
                    prompt,
                    "default pos",
                    "default neg",
                    final_positive_prompt,
                    model_id,
                    "[]",
                    json.dumps(tags or []),
                    caption,
                    40,
                    5.0,
                    "landscape",
                    source_image_id,
                    None,
                    0,
                    duration_seconds,
                    generation_duration_seconds,
                    fps,
                    num_frames,
                    0,
                    rating,
                    created_at,
                    stored_at,
                    deleted_at,
                ),
            )
            conn.commit()

    @staticmethod
    def _wait_for_job(client, job_id: str, timeout: float = 15.0) -> dict:
        deadline = time.time() + timeout
        while time.time() < deadline:
            response = client.get(f"/api/jobs/{job_id}")
            payload = response.get_json()
            if payload["status"] in {"completed", "failed", "cancelled"}:
                return payload
            time.sleep(0.05)
        raise AssertionError(f"Timed out waiting for job {job_id}")

    @staticmethod
    def _wait_for_status(client, job_id: str, statuses: set[str], timeout: float = 15.0) -> dict:
        deadline = time.time() + timeout
        while time.time() < deadline:
            response = client.get(f"/api/jobs/{job_id}")
            payload = response.get_json()
            if payload["status"] in statuses:
                return payload
            time.sleep(0.05)
        raise AssertionError(f"Timed out waiting for statuses {statuses} on job {job_id}")
