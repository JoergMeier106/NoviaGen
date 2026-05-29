from __future__ import annotations

import json
import os
import re
import select
import subprocess
import time
from dataclasses import dataclass
from typing import Any, Mapping


class ChatMcpConfigurationError(RuntimeError):
    pass


class ChatMcpToolError(RuntimeError):
    pass


@dataclass(frozen=True)
class ChatMcpTool:
    id: str
    server_name: str
    name: str
    ollama_name: str
    description: str
    input_schema: dict[str, Any]
    result_mode: str = "model"

    def payload(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "server_name": self.server_name,
            "name": self.name,
            "ollama_name": self.ollama_name,
            "description": self.description,
            "input_schema": self.input_schema,
            "result_mode": self.result_mode,
        }

    def ollama_tool(self) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": self.ollama_name,
                "description": self.description or f"MCP tool {self.id}",
                "parameters": self.input_schema or {"type": "object", "properties": {}},
            },
        }


@dataclass(frozen=True)
class ChatMcpToolset:
    tools: tuple[ChatMcpTool, ...]

    @property
    def ollama_tools(self) -> list[dict[str, Any]]:
        return [tool.ollama_tool() for tool in self.tools]

    def tool_for_ollama_name(self, name: str) -> ChatMcpTool | None:
        for tool in self.tools:
            if tool.ollama_name == name:
                return tool
        return None


class ChatMcpToolProvider:
    def __init__(self, config: Mapping[str, Any]) -> None:
        self._config = config

    def list_tools(self) -> list[ChatMcpTool]:
        tools: list[ChatMcpTool] = []
        for server_name, server_config in self._server_configs().items():
            for item in _McpStdioSession(server_name, server_config, self._config).list_tools():
                name = str(item.get("name") or "").strip()
                if not name:
                    continue
                tool_id = f"{server_name}.{name}"
                tools.append(
                    ChatMcpTool(
                        id=tool_id,
                        server_name=server_name,
                        name=name,
                        ollama_name=_ollama_tool_name(tool_id),
                        description=str(item.get("description") or "").strip(),
                        input_schema=_object_schema(item.get("inputSchema")),
                        result_mode=_tool_result_mode(server_config, name),
                    )
                )
        return tools

    def toolset_for_ids(self, enabled_tool_ids: list[str]) -> ChatMcpToolset:
        requested = list(dict.fromkeys(item.strip() for item in enabled_tool_ids if item.strip()))
        if not requested:
            return ChatMcpToolset(tools=())
        available = {tool.id: tool for tool in self.list_tools()}
        missing = [tool_id for tool_id in requested if tool_id not in available]
        if missing:
            raise ChatMcpConfigurationError(
                f"Unknown or unavailable MCP tool id: {', '.join(missing)}"
            )
        return ChatMcpToolset(tools=tuple(available[tool_id] for tool_id in requested))

    def call_tool(self, tool: ChatMcpTool, arguments: Mapping[str, Any]) -> str:
        server_config = self._server_configs().get(tool.server_name)
        if not server_config:
            raise ChatMcpToolError(f"MCP server is not configured: {tool.server_name}")
        result = _McpStdioSession(tool.server_name, server_config, self._config).call_tool(
            tool.name,
            dict(arguments),
        )
        return _tool_result_text(result, max_chars=self._tool_result_max_chars())

    def is_configured(self) -> bool:
        return bool(self._server_configs())

    def max_loop_steps(self) -> int:
        return max(1, int(self._config["CHAT_TOOL_LOOP_MAX_STEPS"]))

    def _server_configs(self) -> dict[str, dict[str, Any]]:
        raw_servers = self._config.get("CHAT_MCP_SERVERS")
        if raw_servers is None:
            return {}
        if isinstance(raw_servers, Mapping):
            if "mcpServers" in raw_servers or "servers" in raw_servers:
                raw_servers = raw_servers.get("mcpServers") or raw_servers.get("servers") or {}
            if not isinstance(raw_servers, Mapping):
                raise ChatMcpConfigurationError("MCP servers config must be an object")
        else:
            raise ChatMcpConfigurationError("MCP servers config must be an object")
        servers: dict[str, dict[str, Any]] = {}
        for raw_name, raw_config in raw_servers.items():
            server_name = _safe_server_name(str(raw_name))
            if not server_name or not isinstance(raw_config, dict):
                continue
            command = str(raw_config.get("command") or "").strip()
            if not command:
                continue
            servers[server_name] = dict(raw_config)
        return servers

    def _tool_result_max_chars(self) -> int:
        return max(512, int(self._config["CHAT_TOOL_RESULT_MAX_CHARS"]))


class _McpStdioSession:
    def __init__(
        self,
        server_name: str,
        server_config: Mapping[str, Any],
        app_config: Mapping[str, Any],
    ) -> None:
        self._server_name = server_name
        self._server_config = server_config
        self._app_config = app_config
        self._next_id = 1

    def list_tools(self) -> list[dict[str, Any]]:
        result = self._run_request("tools/list", {})
        tools = result.get("tools") if isinstance(result, dict) else None
        return [item for item in tools if isinstance(item, dict)] if isinstance(tools, list) else []

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        result = self._run_request(
            "tools/call",
            {
                "name": name,
                "arguments": arguments,
            },
        )
        return result if isinstance(result, dict) else {"content": [{"type": "text", "text": str(result)}]}

    def _run_request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        timeout = float(self._app_config["CHAT_MCP_TOOL_TIMEOUT_SECONDS"])
        process = subprocess.Popen(
            self._command(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            env=self._env(),
        )
        try:
            self._send(process, "initialize", _initialize_params())
            self._read_result(process, 1, timeout)
            self._send_notification(process, "notifications/initialized")
            request_id = self._send(process, method, params)
            return self._read_result(process, request_id, timeout)
        finally:
            try:
                process.terminate()
                process.wait(timeout=1)
            except Exception:
                process.kill()

    def _command(self) -> list[str]:
        command = str(self._server_config.get("command") or "").strip()
        args = self._server_config.get("args")
        return [command, *[str(item) for item in args]] if isinstance(args, list) else [command]

    def _env(self) -> dict[str, str]:
        env = dict(os.environ)
        local_env = self._app_config["CHAT_MCP_LOCAL_ENV"]
        if isinstance(local_env, dict):
            for key, value in local_env.items():
                env.setdefault(str(key), str(value))
        raw_env = self._server_config.get("env")
        if isinstance(raw_env, dict):
            for key, value in raw_env.items():
                env[str(key)] = _expand_env_value(str(value), env)
        return env

    def _send(
        self,
        process: subprocess.Popen[str],
        method: str,
        params: dict[str, Any],
    ) -> int:
        request_id = self._next_id
        self._next_id += 1
        _write_message(
            process,
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            },
        )
        return request_id

    def _send_notification(self, process: subprocess.Popen[str], method: str) -> None:
        _write_message(process, {"jsonrpc": "2.0", "method": method})

    def _read_result(
        self,
        process: subprocess.Popen[str],
        request_id: int,
        timeout: float,
    ) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if process.stdout is None:
                break
            ready, _, _ = select.select(
                [process.stdout],
                [],
                [],
                max(0.0, deadline - time.monotonic()),
            )
            if not ready:
                break
            line = process.stdout.readline()
            if not line:
                break
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if payload.get("id") != request_id:
                continue
            if "error" in payload:
                raise ChatMcpToolError(
                    f"MCP tool server {self._server_name} returned an error: {payload['error']}"
                )
            result = payload.get("result")
            return result if isinstance(result, dict) else {"value": result}
        raise ChatMcpToolError(f"MCP tool server timed out: {self._server_name}")


def _write_message(process: subprocess.Popen[str], payload: dict[str, Any]) -> None:
    if process.stdin is None:
        raise ChatMcpToolError("MCP server stdin is unavailable")
    process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    process.stdin.flush()


def _initialize_params() -> dict[str, Any]:
    return {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "NoviaGen", "version": "1.0"},
    }


def _object_schema(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        schema = dict(value)
        schema.setdefault("type", "object")
        schema.setdefault("properties", {})
        return schema
    return {"type": "object", "properties": {}}


def _ollama_tool_name(tool_id: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_]+", "__", tool_id).strip("_")
    return f"mcp__{cleaned}"[:64]


def _tool_result_mode(server_config: Mapping[str, Any], tool_name: str) -> str:
    raw_modes = server_config.get("tool_result_modes")
    if isinstance(raw_modes, Mapping):
        raw_mode = raw_modes.get(tool_name)
        mode = str(raw_mode or "").strip().lower()
        if mode in {"direct", "model"}:
            return mode
    mode = str(server_config.get("result_mode") or "").strip().lower()
    return mode if mode in {"direct", "model"} else "model"


def _safe_server_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", value.strip())


def _expand_env_value(value: str, env: Mapping[str, str]) -> str:
    def replacement(match: re.Match[str]) -> str:
        return env.get(match.group(1), "")

    return re.sub(r"\$\{([^}]+)\}", replacement, value)


def _tool_result_text(result: dict[str, Any], *, max_chars: int) -> str:
    parts: list[str] = []
    content = result.get("content")
    if isinstance(content, list):
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text":
                parts.append(str(item.get("text") or ""))
            elif "text" in item:
                parts.append(str(item.get("text") or ""))
            else:
                parts.append(json.dumps(item, sort_keys=True, default=str))
    structured = result.get("structuredContent")
    if structured not in (None, {}, []):
        parts.append(json.dumps(structured, sort_keys=True, default=str))
    if not parts:
        parts.append(json.dumps(result, sort_keys=True, default=str))
    text = "\n\n".join(part.strip() for part in parts if part and part.strip()).strip()
    return text[:max_chars] if len(text) > max_chars else text
