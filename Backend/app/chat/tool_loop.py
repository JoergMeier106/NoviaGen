from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable, Mapping

from .mcp_tools import ChatMcpToolProvider, ChatMcpToolset
from ..generation import OllamaResponseError


@dataclass(frozen=True)
class ChatToolLoopResult:
    content: str
    thinking: str | None
    final_chunk: dict[str, Any]
    tool_traces: tuple[dict[str, str], ...]


ToolStatusCallback = Callable[[dict[str, Any]], None]


def tool_trace(*, tool_id: str, tool_name: str, content: str) -> dict[str, str]:
    trace = {
        "tool_name": tool_name,
        "content": content,
    }
    if tool_id:
        trace["tool_id"] = tool_id
    return trace


def run_chat_tool_loop(
    *,
    generator: Any,
    model: str,
    messages: list[dict[str, Any]],
    tool_provider: ChatMcpToolProvider,
    toolset: ChatMcpToolset,
    think: bool | str | None,
    context_window: int | None,
    max_steps: int,
    status_callback: ToolStatusCallback | None = None,
) -> ChatToolLoopResult:
    if not toolset.tools:
        raise ValueError("toolset must not be empty")
    if not hasattr(generator, "chat"):
        raise OllamaResponseError("Selected generator does not support tool calling")

    working_messages = [
        _tool_instruction_message(),
        *[dict(message) for message in messages],
    ]
    final_response: dict[str, Any] = {}
    tool_results: list[dict[str, str]] = []
    for step in range(max(1, max_steps)):
        response = generator.chat(
            model=model,
            messages=working_messages,
            tools=toolset.ollama_tools,
            think=think,
            context_window=context_window,
        )
        final_response = response if isinstance(response, dict) else {}
        message = final_response.get("message")
        if not isinstance(message, dict):
            raise OllamaResponseError("Ollama returned an invalid tool chat payload")

        tool_calls = _tool_calls(message)
        if not tool_calls:
            return _final_result(final_response, tool_results=tool_results)

        working_messages.append(_assistant_tool_message(message, tool_calls))
        for call in tool_calls:
            function = call.get("function") if isinstance(call, dict) else None
            if not isinstance(function, dict):
                continue
            function_name = str(function.get("name") or "").strip()
            arguments = _tool_arguments(function.get("arguments"))
            tool = toolset.tool_for_ollama_name(function_name)
            if tool is None:
                tool_result = f"Tool {function_name} is not enabled or unavailable."
            else:
                if status_callback is not None:
                    status_callback(
                        {
                            "type": "tool_status",
                            "status": "running",
                            "tool_id": tool.id,
                            "tool_name": tool.name,
                        }
                    )
                try:
                    tool_result = tool_provider.call_tool(tool, arguments)
                    if status_callback is not None:
                        status_callback(
                            {
                                "type": "tool_status",
                                "status": "completed",
                                "tool_id": tool.id,
                                "tool_name": tool.name,
                                "content": tool_result,
                            }
                        )
                except Exception as exc:
                    tool_result = f"Tool {tool.id} failed: {exc}"
                    if status_callback is not None:
                        status_callback(
                            {
                                "type": "tool_status",
                                "status": "failed",
                                "tool_id": tool.id,
                                "tool_name": tool.name,
                                "error": str(exc),
                                "content": tool_result,
                            }
                        )
            tool_results.append(
                tool_trace(
                    tool_id=tool.id if tool is not None else "",
                    tool_name=function_name,
                    content=tool_result,
                )
            )
            working_messages.append(
                {
                    "role": "tool",
                    "tool_name": function_name,
                    "content": tool_result,
                }
            )
            if tool is not None and tool.result_mode == "direct":
                return ChatToolLoopResult(
                    content=_direct_tool_content(tool_result),
                    thinking=None,
                    final_chunk={},
                    tool_traces=tuple(tool_results),
                )

    raise OllamaResponseError("Tool calling did not finish before the configured limit")


def _tool_instruction_message() -> dict[str, str]:
    return {
        "role": "system",
        "content": (
            "When tools are available, call them only when useful. After receiving tool "
            "results, always write a final non-empty answer for the user. If a tool "
            "fails or returns an error, explain that result clearly."
        ),
    }


def _tool_calls(message: Mapping[str, Any]) -> list[dict[str, Any]]:
    raw_calls = message.get("tool_calls")
    if not isinstance(raw_calls, list):
        return []
    return [call for call in raw_calls if isinstance(call, dict)]


def _assistant_tool_message(
    message: Mapping[str, Any],
    tool_calls: list[dict[str, Any]],
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "role": "assistant",
        "content": str(message.get("content") or ""),
        "tool_calls": tool_calls,
    }
    thinking = str(message.get("thinking") or "").strip()
    if thinking:
        payload["thinking"] = thinking
    return payload


def _tool_arguments(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return dict(value)
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError:
            return {}
        return dict(decoded) if isinstance(decoded, dict) else {}
    return {}


def _final_result(
    response: dict[str, Any],
    *,
    tool_results: list[dict[str, str]],
) -> ChatToolLoopResult:
    message = response.get("message")
    if not isinstance(message, dict):
        raise OllamaResponseError("Ollama returned an invalid chat payload")
    content = str(message.get("content") or "").strip()
    thinking = str(message.get("thinking") or "").strip() or None
    if not content:
        content = _fallback_empty_content(tool_results)
    if not content:
        raise OllamaResponseError("Ollama returned an empty chat response")
    return ChatToolLoopResult(
        content=content,
        thinking=thinking,
        final_chunk=response,
        tool_traces=tuple(tool_results),
    )


def _fallback_empty_content(tool_results: list[dict[str, str]]) -> str:
    for result in reversed(tool_results):
        content = str(result.get("content") or "").strip()
        if not content:
            continue
        tool_name = str(result.get("tool_name") or "tool").strip() or "tool"
        return (
            "The model used a tool but returned an empty final answer. "
            f"Last tool result from `{tool_name}`:\n\n{content}"
        )
    return (
        "The model returned an empty answer without calling any enabled MCP tool. "
        "Try enabling only the specific tool you want to use, or ask the model to "
        "call that tool explicitly."
    )


def _direct_tool_content(tool_result: str) -> str:
    content = tool_result.strip()
    if not content:
        return "The tool completed without returning text."
    extracted = _json_content_field(content)
    return extracted or content


def _json_content_field(value: str) -> str:
    candidates = [value]
    object_index = value.rfind("{")
    if object_index > 0:
        candidates.append(value[object_index:])
    for candidate in candidates:
        try:
            payload = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            content = str(payload.get("content") or "").strip()
            if content:
                return content
    return ""
