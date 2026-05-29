from __future__ import annotations

import base64
import json
import logging
import threading
from typing import Callable

import requests

from .prompting import strip_inline_thinking

logger = logging.getLogger(__name__)


class OllamaUnavailableError(RuntimeError):
    pass


class OllamaResponseError(RuntimeError):
    pass


class OllamaStreamCancelledError(RuntimeError):
    pass


class OllamaPromptRuntimeManager:
    def __init__(
        self,
        *,
        base_url: str,
        model: str,
        timeout_seconds: float,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout_seconds = timeout_seconds
        self._active_stream_lock = threading.Lock()
        self._active_stream_response: requests.Response | None = None
        self._active_stream_cancelled = False

    def generate_prompt(
        self,
        prompt: str,
        *,
        keep_alive: int,
        image_bytes: bytes | None = None,
        model: str | None = None,
    ) -> str:
        normalized_model = self._normalized_model_name(model)
        if image_bytes:
            response_json = self.chat(
                model=normalized_model,
                messages=[
                    {
                        "role": "user",
                        "content": prompt,
                        "images": [base64.b64encode(image_bytes).decode("ascii")],
                    }
                ],
                keep_alive=keep_alive,
                think=True,
            )
            message_payload = response_json.get("message")
            if not isinstance(message_payload, dict):
                raise OllamaResponseError("Ollama returned an invalid prompt response")
            response_text = self._sanitize_generated_prompt(
                strip_inline_thinking(str(message_payload.get("content") or ""))
            )
        else:
            payload = {
                "model": normalized_model,
                "prompt": prompt,
                "stream": False,
                "think": True,
                "keep_alive": keep_alive,
            }
            response_json = self._post_generate(payload)
            response_text = self._sanitize_generated_prompt(
                str(response_json.get("response") or "")
            )
        if not response_text:
            raise OllamaResponseError("Ollama returned an empty prompt response")
        return response_text

    def chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        tools: list[dict[str, object]] | None = None,
        keep_alive: int,
        think: bool | str | None = True,
        context_window: int | None = None,
    ) -> dict[str, object]:
        payload = {
            "model": self._normalized_model_name(model),
            "messages": messages,
            "stream": False,
            "keep_alive": keep_alive,
        }
        if tools:
            payload["tools"] = tools
        if think is not None:
            payload["think"] = think
        if context_window is not None:
            payload["options"] = {"num_ctx": int(context_window)}
        return self._post_chat(payload)

    def stream_chat(
        self,
        *,
        model: str,
        messages: list[dict[str, object]],
        keep_alive: int,
        think: bool | str | None = True,
        context_window: int | None = None,
        cancel_requested: Callable[[], bool] | None = None,
    ):
        payload = {
            "model": self._normalized_model_name(model),
            "messages": messages,
            "stream": True,
            "keep_alive": keep_alive,
        }
        if think is not None:
            payload["think"] = think
        if context_window is not None:
            payload["options"] = {"num_ctx": int(context_window)}
        yield from self._post_chat_stream(
            payload,
            cancel_requested=cancel_requested,
        )

    def release_model(self) -> None:
        self.unload_model(self.model)

    def cancel_active_chat(self) -> bool:
        with self._active_stream_lock:
            self._active_stream_cancelled = True
            response = self._active_stream_response
        if response is not None:
            try:
                response.close()
            except Exception:
                logger.debug("Failed to close active Ollama chat stream", exc_info=True)
            return True
        return False

    def unload_model(self, model: str) -> None:
        model_name = str(model).strip()
        if not model_name:
            return
        try:
            self._post_generate(
                {
                    "model": model_name,
                    "prompt": "",
                    "stream": False,
                    "think": False,
                    "keep_alive": 0,
                }
            )
        except OllamaUnavailableError:
            logger.warning("Failed to unload Ollama prompt model", exc_info=True)

    def _chat_payload_variants(self, payload: dict[str, object]) -> list[dict[str, object]]:
        variants: list[dict[str, object]] = [dict(payload)]
        without_think = dict(payload)
        removed_think = without_think.pop("think", None) is not None
        if removed_think:
            variants.append(without_think)
        without_keep_alive = dict(payload)
        removed_keep_alive = without_keep_alive.pop("keep_alive", None) is not None
        if removed_keep_alive:
            variants.append(without_keep_alive)
        without_both = dict(payload)
        removed_any = False
        for key in ("think", "keep_alive"):
            if without_both.pop(key, None) is not None:
                removed_any = True
        if removed_any:
            variants.append(without_both)

        unique_variants: list[dict[str, object]] = []
        seen_keys: set[str] = set()
        for item in variants:
            key = json.dumps(item, sort_keys=True, default=str)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            unique_variants.append(item)
        return unique_variants

    @staticmethod
    def _http_error_detail(response: requests.Response) -> str:
        try:
            payload = response.json()
        except (ValueError, json.JSONDecodeError):
            payload = None
        if isinstance(payload, dict):
            for key in ("error", "message", "detail"):
                value = str(payload.get(key) or "").strip()
                if value:
                    return value
        text = response.text.strip()
        return text

    def _post_chat(self, payload: dict[str, object]) -> dict[str, object]:
        last_http_error: requests.HTTPError | None = None
        last_detail = ""
        for payload_variant in self._chat_payload_variants(payload):
            try:
                response = requests.post(
                    f"{self.base_url}/api/chat",
                    json=payload_variant,
                    timeout=self.timeout_seconds,
                )
                response.raise_for_status()
            except requests.HTTPError as exc:
                last_http_error = exc
                response = exc.response
                last_detail = self._http_error_detail(response) if response is not None else ""
                continue
            except requests.RequestException as exc:
                raise OllamaUnavailableError("Ollama is not reachable") from exc

            try:
                response_json = response.json()
            except json.JSONDecodeError as exc:
                raise OllamaResponseError("Ollama returned invalid JSON") from exc
            if not isinstance(response_json, dict):
                raise OllamaResponseError("Ollama returned an invalid response payload")
            return response_json

        if last_http_error is not None:
            raise OllamaResponseError(
                f"Ollama rejected the chat request: {last_detail or last_http_error}"
            ) from last_http_error
        raise OllamaResponseError("Ollama rejected the chat request")

    def _post_chat_stream(
        self,
        payload: dict[str, object],
        *,
        cancel_requested: Callable[[], bool] | None = None,
    ):
        last_http_error: requests.HTTPError | None = None
        last_detail = ""
        for payload_variant in self._chat_payload_variants(payload):
            try:
                with self._active_stream_lock:
                    self._active_stream_cancelled = False
                if cancel_requested is not None and cancel_requested():
                    raise OllamaStreamCancelledError("Ollama chat cancelled")
                with requests.post(
                    f"{self.base_url}/api/chat",
                    json=payload_variant,
                    timeout=self.timeout_seconds,
                    stream=True,
                ) as response:
                    with self._active_stream_lock:
                        self._active_stream_cancelled = False
                        self._active_stream_response = response
                    try:
                        response.raise_for_status()
                        for line in response.iter_lines(decode_unicode=True):
                            with self._active_stream_lock:
                                stream_cancelled = self._active_stream_cancelled
                            if stream_cancelled or (
                                cancel_requested is not None and cancel_requested()
                            ):
                                self.cancel_active_chat()
                                raise OllamaStreamCancelledError(
                                    "Ollama chat cancelled"
                                )
                            if not line:
                                continue
                            try:
                                response_json = json.loads(line)
                            except json.JSONDecodeError as exc:
                                raise OllamaResponseError(
                                    "Ollama returned invalid streaming JSON"
                                ) from exc
                            if not isinstance(response_json, dict):
                                raise OllamaResponseError(
                                    "Ollama returned an invalid streaming response payload"
                                )
                            yield response_json
                        with self._active_stream_lock:
                            stream_cancelled = self._active_stream_cancelled
                        if stream_cancelled or (
                            cancel_requested is not None and cancel_requested()
                        ):
                            raise OllamaStreamCancelledError("Ollama chat cancelled")
                        with self._active_stream_lock:
                            self._active_stream_cancelled = False
                        return
                    finally:
                        with self._active_stream_lock:
                            if self._active_stream_response is response:
                                self._active_stream_response = None
            except requests.HTTPError as exc:
                last_http_error = exc
                response = exc.response
                last_detail = self._http_error_detail(response) if response is not None else ""
                continue
            except requests.RequestException as exc:
                with self._active_stream_lock:
                    stream_cancelled = self._active_stream_cancelled
                if stream_cancelled or (cancel_requested is not None and cancel_requested()):
                    raise OllamaStreamCancelledError("Ollama chat cancelled") from exc
                raise OllamaUnavailableError("Ollama is not reachable") from exc

        if last_http_error is not None:
            raise OllamaResponseError(
                f"Ollama rejected the chat request: {last_detail or last_http_error}"
            ) from last_http_error
        raise OllamaResponseError("Ollama rejected the chat request")

    def _normalized_model_name(self, model: str | None) -> str:
        model_name = str(model or self.model).strip()
        if not model_name:
            raise ValueError("model is required")
        return model_name

    def _post_generate(self, payload: dict[str, object]) -> dict[str, object]:
        try:
            response = requests.post(
                f"{self.base_url}/api/generate",
                json=payload,
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise OllamaUnavailableError("Ollama is not reachable") from exc

        try:
            response_json = response.json()
        except json.JSONDecodeError as exc:
            raise OllamaResponseError("Ollama returned invalid JSON") from exc
        if not isinstance(response_json, dict):
            raise OllamaResponseError("Ollama returned an invalid response payload")
        return response_json

    @classmethod
    def _sanitize_generated_prompt(cls, response_text: str) -> str:
        return strip_inline_thinking(response_text)
