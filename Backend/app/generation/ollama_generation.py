from __future__ import annotations

from pathlib import Path
from typing import Callable

from .ollama_runtime import OllamaResponseError, OllamaStreamCancelledError
from .prompting import strip_inline_thinking


class OllamaGenerationMixin:
    def generate_prompt(
        self,
        prompt: str,
        image_bytes: bytes | None = None,
        *,
        model: str | None = None,
    ) -> str:
        if not prompt.strip():
            raise ValueError("prompt is required")

        selected_model = str(model or "").strip() or self._ollama_prompt_manager.model
        with self._lock:
            self._evict_all_local_models()
            self._release_comfy_if_active()
            self._prepare_ollama_runtime(selected_model)
            result = self._ollama_prompt_manager.generate_prompt(
                prompt.strip(),
                keep_alive=-1,
                image_bytes=image_bytes,
                model=selected_model,
            )
            self._active_runtime = "ollama"
            return result

    def generate_i2v_prompt(
        self,
        *,
        prompt: str,
        source_image_path: Path,
        model: str | None = None,
    ) -> str:
        if not source_image_path.exists():
            raise FileNotFoundError("Source image file could not be read")
        image_bytes = source_image_path.read_bytes()
        if not image_bytes:
            raise ValueError("Source image file is empty")

        selected_model = str(model or "").strip() or self._ollama_prompt_manager.model
        with self._lock:
            self._evict_all_local_models()
            self._release_comfy_if_active()
            self._prepare_ollama_runtime(selected_model)
            result = self._ollama_prompt_manager.generate_prompt(
                prompt.strip(),
                keep_alive=-1,
                image_bytes=image_bytes,
                model=selected_model,
            )
            self._active_runtime = "ollama"
            return result

    def chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        tools: list[dict[str, object]] | None = None,
        think: bool | str | None = True,
        context_window: int | None = None,
    ) -> dict[str, object]:
        if not messages:
            raise ValueError("messages are required")

        with self._lock:
            self._evict_all_local_models()
            self._release_comfy_if_active()
            self._prepare_ollama_runtime(model)
            response_json = self._ollama_prompt_manager.chat(
                model=model,
                messages=messages,
                tools=tools,
                think=think,
                keep_alive=-1,
                context_window=context_window,
            )
            self._active_runtime = "ollama"
            return response_json

    def summarize_chat_messages(
        self,
        *,
        model: str,
        summary_prompt: str,
        context_window: int | None = None,
    ) -> str:
        if not summary_prompt.strip():
            raise ValueError("summary_prompt is required")

        with self._lock:
            self._evict_all_local_models()
            self._release_comfy_if_active()
            self._prepare_ollama_runtime(model)
            response_json = self._ollama_prompt_manager.chat(
                model=model,
                messages=[
                    {
                        "role": "user",
                        "content": summary_prompt.strip(),
                    }
                ],
                think=False,
                keep_alive=-1,
                context_window=context_window,
            )
            message = response_json.get("message")
            if not isinstance(message, dict):
                raise OllamaResponseError("Ollama returned an invalid chat payload")
            content = strip_inline_thinking(str(message.get("content") or ""))
            if not content:
                raise OllamaResponseError("Ollama returned an empty chat summary")
            self._active_runtime = "ollama"
            return content

    def generate_chat_title(
        self,
        *,
        model: str,
        user_message: str,
        system_message: str = "",
        context_window: int | None = None,
    ) -> str:
        prompt = (
            "Write a short, specific title for this chat session based on the first user "
            "message. Use 2 to 6 words. Do not use quotes, markdown, or ending punctuation. "
            "Return only the title."
        )
        messages: list[dict[str, object]] = []
        normalized_system_message = system_message.strip()
        if normalized_system_message:
            messages.append(
                {
                    "role": "system",
                    "content": normalized_system_message,
                }
            )
        messages.append(
            {
                "role": "system",
                "content": prompt,
            }
        )
        messages.append(
            {
                "role": "user",
                "content": user_message.strip(),
            }
        )

        with self._lock:
            self._evict_all_local_models()
            self._release_comfy_if_active()
            self._prepare_ollama_runtime(model)
            response_json = self._ollama_prompt_manager.chat(
                model=model,
                messages=messages,
                think=False,
                keep_alive=-1,
                context_window=context_window,
            )
            message = response_json.get("message")
            if not isinstance(message, dict):
                raise OllamaResponseError("Ollama returned an invalid chat title payload")
            raw_content = str(message.get("content") or "")
            title = strip_inline_thinking(raw_content)
            self._active_runtime = "ollama"
            return title.strip()

    def stream_chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        think: bool | str | None = True,
        context_window: int | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ):
        if not messages:
            raise ValueError("messages are required")

        with self._lock:
            self._evict_all_local_models()
            self._release_comfy_if_active()
            self._prepare_ollama_runtime(model)
            if cancel_requested is not None and cancel_requested():
                raise OllamaStreamCancelledError("Ollama chat cancelled")
            for chunk in self._ollama_prompt_manager.stream_chat(
                model=model,
                messages=messages,
                think=think,
                keep_alive=-1,
                context_window=context_window,
                cancel_requested=cancel_requested,
            ):
                if cancel_requested is not None and cancel_requested():
                    raise OllamaStreamCancelledError("Ollama chat cancelled")
                yield chunk
            if cancel_requested is not None and cancel_requested():
                raise OllamaStreamCancelledError("Ollama chat cancelled")
            self._active_runtime = "ollama"
