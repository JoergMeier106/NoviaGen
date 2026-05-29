from __future__ import annotations

import re
from dataclasses import dataclass


def compose_positive_prompt(*parts: str) -> str:
    parts = [part.strip() for part in parts if part and part.strip()]
    return ", ".join(parts)


@dataclass(frozen=True)
class ParsedThinkingContent:
    thinking: str
    content: str


_CHANNEL_THOUGHT_START = "<|channel>thought"
_CHANNEL_THOUGHT_END = "<channel|>"
_THINK_CLOSE_PATTERN = re.compile(r"</think>", re.IGNORECASE)


def split_inline_thinking(text: str) -> ParsedThinkingContent:
    if not text:
        return ParsedThinkingContent(thinking="", content="")

    thinking_parts: list[str] = []
    content_parts: list[str] = []
    cursor = 0
    lowered = text.lower()

    while cursor < len(text):
        think_index = lowered.find("<think", cursor)
        channel_index = text.find(_CHANNEL_THOUGHT_START, cursor)
        candidates = [index for index in (think_index, channel_index) if index >= 0]
        if not candidates:
            content_parts.append(text[cursor:])
            break

        marker_index = min(candidates)
        content_parts.append(text[cursor:marker_index])

        if marker_index == channel_index:
            body_start = marker_index + len(_CHANNEL_THOUGHT_START)
            end_index = text.find(_CHANNEL_THOUGHT_END, body_start)
            if end_index == -1:
                thinking_parts.append(text[body_start:])
                break
            thinking_parts.append(text[body_start:end_index])
            cursor = end_index + len(_CHANNEL_THOUGHT_END)
            continue

        tag_end = text.find(">", marker_index)
        if tag_end == -1:
            break
        body_start = tag_end + 1
        closing_match = _THINK_CLOSE_PATTERN.search(text, body_start)
        if closing_match is None:
            thinking_parts.append(text[body_start:])
            break
        thinking_parts.append(text[body_start:closing_match.start()])
        cursor = closing_match.end()

    return ParsedThinkingContent(
        thinking="".join(thinking_parts),
        content="".join(content_parts),
    )


def strip_inline_thinking(text: str) -> str:
    return split_inline_thinking(text).content.strip()
