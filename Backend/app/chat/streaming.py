from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from ..generation import split_inline_thinking


@dataclass(frozen=True)
class ChatStreamDelta:
    thinking_deltas: tuple[str, ...] = ()
    content: str = ""

    @property
    def thinking(self) -> str:
        return "".join(self.thinking_deltas)


class ChatStreamAccumulator:
    def __init__(self) -> None:
        self._thinking_parts: list[str] = []
        self._content_parts: list[str] = []
        self._raw_content_parts: list[str] = []
        self.tool_traces: list[dict[str, str]] = []
        self._emitted_inline_thinking_length = 0
        self._emitted_content_length = 0

    @property
    def thinking(self) -> str:
        return "".join(self._thinking_parts)

    @property
    def content(self) -> str:
        return "".join(self._content_parts)

    def apply_chunk(self, chunk: dict[str, Any]) -> ChatStreamDelta:
        message = chunk.get("message")
        if not isinstance(message, dict):
            message = {}
        return self.apply_message(message)

    def apply_message(self, message: dict[str, Any]) -> ChatStreamDelta:
        thinking_delta = self._append_structured_thinking(message)
        inline_thinking_delta, content_delta = self._append_content(message)
        thinking_deltas = tuple(
            item for item in (thinking_delta, inline_thinking_delta) if item
        )
        return ChatStreamDelta(
            thinking_deltas=thinking_deltas,
            content=content_delta,
        )

    def _append_structured_thinking(self, message: dict[str, Any]) -> str:
        thinking_delta = str(message.get("thinking") or "")
        if thinking_delta:
            self._thinking_parts.append(thinking_delta)
        return thinking_delta

    def _append_content(self, message: dict[str, Any]) -> tuple[str, str]:
        content_delta = str(message.get("content") or "")
        if not content_delta:
            return "", ""

        self._raw_content_parts.append(content_delta)
        parsed = split_inline_thinking("".join(self._raw_content_parts))
        inline_delta = ""
        if len(parsed.thinking) > self._emitted_inline_thinking_length:
            inline_delta = parsed.thinking[self._emitted_inline_thinking_length:]
            self._emitted_inline_thinking_length = len(parsed.thinking)
            self._thinking_parts.append(inline_delta)
        if len(parsed.content) <= self._emitted_content_length:
            return inline_delta, ""

        normalized_delta = parsed.content[self._emitted_content_length:]
        self._emitted_content_length = len(parsed.content)
        self._content_parts.append(normalized_delta)
        return inline_delta, normalized_delta
