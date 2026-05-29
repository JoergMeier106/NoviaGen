from __future__ import annotations

import os
import re
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

import yaml

_CONFIG_ENV_VARS = ("NOVIAGEN_CONFIG_PATH", "OBSCURE_CONFIG_PATH")
_DEFAULT_CONFIG_FILE_NAME = "config.yaml"
_PATH_KEYS = {
    "paths.models_dir",
    "paths.video_models_dir",
    "paths.loras_dir",
    "paths.lora_triggers_dir",
    "paths.unknown_dir",
    "paths.data_dir",
    "paths.logs_dir",
    "paths.temp_dir",
    "paths.stored_dir",
    "paths.backups_dir",
    "paths.errors_dir",
    "paths.database_path",
    "generation.comfy.workflows.image_to_video",
    "generation.comfy.workflows.image_to_video_loop",
    "generation.comfy.workflows.image_prompt_generator",
    "generation.comfy.workflows.video_upscaler",
    "generation.comfy.workflows.video_to_audio",
    "generation.comfy.workflows.text_to_video",
    "generation.comfy.autostart.workdir",
    "generation.comfy.autostart.executable",
    "chat.mcp.local_env_path",
}
_FLAT_KEY_MAP = {
    "MODELS_DIR": "paths.models_dir",
    "VIDEO_MODELS_DIR": "paths.video_models_dir",
    "LORAS_DIR": "paths.loras_dir",
    "LORA_TRIGGERS_DIR": "paths.lora_triggers_dir",
    "UNKNOWN_DIR": "paths.unknown_dir",
    "DATA_DIR": "paths.data_dir",
    "LOGS_DIR": "paths.logs_dir",
    "TEMP_DIR": "paths.temp_dir",
    "STORED_DIR": "paths.stored_dir",
    "BACKUPS_DIR": "paths.backups_dir",
    "ERRORS_DIR": "paths.errors_dir",
    "DB_PATH": "paths.database_path",
    "LORA_DEFAULT_STRENGTH": "assets.lora_default_strength",
    "TEMP_TTL_SECONDS": "cleanup.temp_ttl_seconds",
    "CLEANUP_INTERVAL_SECONDS": "cleanup.interval_seconds",
    "DELETED_MEDIA_RETENTION_DAYS": "cleanup.deleted_media_retention_days",
    "INTER_JOB_DELAY_SECONDS": "jobs.inter_job_delay_seconds",
    "LOG_MAX_BYTES": "logging.max_bytes",
    "LOG_BACKUP_COUNT": "logging.backup_count",
    "USE_X_SENDFILE": "http.use_x_sendfile",
    "COMFY_URL": "generation.comfy.url",
    "COMFY_MODELS_TIMEOUT_SECONDS": "generation.comfy.models_timeout_seconds",
    "COMFY_I2V_WORKFLOW_PATH": "generation.comfy.workflows.image_to_video",
    "COMFY_I2V_LOOP_WORKFLOW_PATH": "generation.comfy.workflows.image_to_video_loop",
    "COMFY_I2V_PROMPT_WORKFLOW_PATH": "generation.comfy.workflows.image_prompt_generator",
    "COMFY_VIDEO_UPSCALER_WORKFLOW_PATH": "generation.comfy.workflows.video_upscaler",
    "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH": "generation.comfy.workflows.video_to_audio",
    "COMFY_T2V_WORKFLOW_PATH": "generation.comfy.workflows.text_to_video",
    "COMFY_AUTOSTART_ENABLED": "generation.comfy.autostart.enabled",
    "COMFY_AUTOSTART_WORKDIR": "generation.comfy.autostart.workdir",
    "COMFY_AUTOSTART_EXECUTABLE": "generation.comfy.autostart.executable",
    "COMFY_AUTOSTART_ARGS": "generation.comfy.autostart.args",
    "COMFY_AUTOSTART_COMMAND": "generation.comfy.autostart.command",
    "COMFY_AUTOSTART_HEALTH_PATH": "generation.comfy.autostart.health_path",
    "COMFY_AUTOSTART_HEALTH_TIMEOUT_SECONDS": "generation.comfy.autostart.health_timeout_seconds",
    "COMFY_AUTOSTART_WAIT_SECONDS": "generation.comfy.autostart.wait_seconds",
    "COMFY_AUTOSTART_POLL_SECONDS": "generation.comfy.autostart.poll_seconds",
    "OLLAMA_URL": "generation.ollama.url",
    "OLLAMA_PROMPT_MODEL": "generation.ollama.prompt_model",
    "OLLAMA_PROMPT_TIMEOUT_SECONDS": "generation.ollama.prompt_timeout_seconds",
    "CHAT_SUMMARY_KEEP_RECENT_MESSAGES": "chat.summary.keep_recent_messages",
    "CHAT_SUMMARY_MAX_PENDING_CHARS": "chat.summary.max_pending_chars",
    "CHAT_MCP_SERVERS": "chat.mcp.servers",
    "CHAT_MCP_TOOL_TIMEOUT_SECONDS": "chat.mcp.tool_timeout_seconds",
    "CHAT_TOOL_LOOP_MAX_STEPS": "chat.tool_loop.max_steps",
    "CHAT_TOOL_RESULT_MAX_CHARS": "chat.tool_loop.result_max_chars",
    "HOST_SHUTDOWN_COMMAND": "system_commands.host_shutdown",
    "SERVER_RESTART_COMMAND": "system_commands.server_restart",
    "SERVER_RESTART_DELAY_SECONDS": "system_commands.server_restart_delay_seconds",
}


def default_config_path(base_dir: Path) -> Path:
    for env_var in _CONFIG_ENV_VARS:
        configured = os.environ.get(env_var, "").strip()
        if configured:
            return Path(configured).expanduser().resolve()
    return (base_dir / _DEFAULT_CONFIG_FILE_NAME).resolve()


def load_settings_tree(base_dir: Path) -> tuple[dict[str, Any], Path]:
    config_path = default_config_path(base_dir)
    try:
        raw_payload = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    except FileNotFoundError as exc:
        raise RuntimeError(f"Missing configuration file: {config_path}") from exc
    except OSError as exc:
        raise RuntimeError(f"Could not read configuration file: {config_path}") from exc
    if not isinstance(raw_payload, dict):
        raise RuntimeError(f"Configuration file must contain a YAML mapping: {config_path}")

    resolved = _resolve_settings_tree(
        raw_payload,
        base_dir=base_dir.resolve(),
        config_path=config_path,
    )
    _validate_settings_tree(resolved, config_path=config_path)
    return resolved, config_path


def load_runtime_config(base_dir: Path) -> dict[str, Any]:
    settings_tree, config_path = load_settings_tree(base_dir)
    runtime_config = {
        flat_key: _require_tree_value(settings_tree, dotted_path)
        for flat_key, dotted_path in _FLAT_KEY_MAP.items()
    }
    runtime_config["CHAT_MCP_LOCAL_ENV"] = _load_local_env(
        config_path.parent,
        Path(str(_require_tree_value(settings_tree, "chat.mcp.local_env_path"))),
    )
    runtime_config["CONFIG_PATH"] = str(config_path)
    runtime_config["SETTINGS_TREE"] = settings_tree
    return runtime_config


def load_development_server_config(base_dir: Path) -> dict[str, Any]:
    settings_tree, _ = load_settings_tree(base_dir)
    return deepcopy(_require_tree_value(settings_tree, "server.development"))


def load_gunicorn_config(base_dir: Path) -> dict[str, Any]:
    settings_tree, _ = load_settings_tree(base_dir)
    return deepcopy(_require_tree_value(settings_tree, "server.gunicorn"))


def configure_test_defaults(config: dict[str, Any], test_config: dict | None) -> None:
    if bool(config.get("TESTING", False)) and (
        not test_config or "COMFY_AUTOSTART_ENABLED" not in test_config
    ):
        config["COMFY_AUTOSTART_ENABLED"] = False
    if not bool(config.get("TESTING", False)):
        return

    package_dir = Path(__file__).resolve().parents[1]
    fixture_workflows_dir = package_dir.parent / "tests" / "fixtures" / "workflows"
    test_workflow_defaults = {
        "COMFY_T2V_WORKFLOW_PATH": fixture_workflows_dir / "text_to_video.json",
        "COMFY_I2V_WORKFLOW_PATH": fixture_workflows_dir / "image_to_video.json",
        "COMFY_I2V_LOOP_WORKFLOW_PATH": fixture_workflows_dir / "image_to_video.json",
        "COMFY_I2V_PROMPT_WORKFLOW_PATH": fixture_workflows_dir / "image_prompt.json",
        "COMFY_VIDEO_UPSCALER_WORKFLOW_PATH": fixture_workflows_dir / "video_upscaler.json",
        "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH": fixture_workflows_dir / "video_to_audio.json",
    }
    provided_test_config = test_config or {}
    for key, path in test_workflow_defaults.items():
        if key not in provided_test_config and not str(config.get(key) or "").strip():
            config[key] = str(path)
    if (
        "OLLAMA_PROMPT_MODEL" not in provided_test_config
        and not str(config.get("OLLAMA_PROMPT_MODEL") or "").strip()
    ):
        config["OLLAMA_PROMPT_MODEL"] = "test-prompt-model"
    if "DATA_DIR" in provided_test_config:
        data_dir = Path(str(config["DATA_DIR"]))
        test_path_defaults = {
            "LOGS_DIR": data_dir / "logs",
            "TEMP_DIR": data_dir / "temp",
            "STORED_DIR": data_dir / "stored",
            "BACKUPS_DIR": data_dir / "backups",
            "ERRORS_DIR": data_dir / "errors",
            "DB_PATH": data_dir / "app.db",
        }
        for key, path in test_path_defaults.items():
            if key not in provided_test_config:
                config[key] = str(path)


def ensure_data_directories(config: Mapping[str, Any]) -> None:
    for key in (
        "DATA_DIR",
        "LOGS_DIR",
        "TEMP_DIR",
        "STORED_DIR",
        "BACKUPS_DIR",
        "ERRORS_DIR",
        "MODELS_DIR",
        "VIDEO_MODELS_DIR",
        "LORAS_DIR",
        "LORA_TRIGGERS_DIR",
        "UNKNOWN_DIR",
    ):
        Path(str(config[key])).mkdir(parents=True, exist_ok=True)


def _resolve_settings_tree(
    value: Any,
    *,
    base_dir: Path,
    config_path: Path,
    dotted_path: str = "",
) -> Any:
    config_dir = config_path.parent
    if isinstance(value, dict):
        return {
            str(key): _resolve_settings_tree(
                item,
                base_dir=base_dir,
                config_path=config_path,
                dotted_path=f"{dotted_path}.{key}" if dotted_path else str(key),
            )
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [
            _resolve_settings_tree(
                item,
                base_dir=base_dir,
                config_path=config_path,
                dotted_path=dotted_path,
            )
            for item in value
        ]
    if isinstance(value, str):
        expanded = _expand_placeholders(
            value,
            {
                "BASE_DIR": str(base_dir),
                "CONFIG_DIR": str(config_dir),
                "HOME": _safe_home_dir(),
            },
        )
        if dotted_path in _PATH_KEYS:
            if not expanded.strip():
                return ""
            return str(_resolve_path_string(expanded, config_dir=config_dir))
        return expanded
    return value


def _safe_home_dir() -> str:
    try:
        return str(Path.home())
    except RuntimeError:
        return ""


def _expand_placeholders(value: str, replacements: Mapping[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key in replacements:
            return replacements[key]
        return os.environ.get(key, match.group(0))

    return re.sub(r"\$\{([^}]+)\}", replace, value)


def _resolve_path_string(value: str, *, config_dir: Path) -> Path:
    candidate = Path(value).expanduser()
    if candidate.is_absolute():
        return candidate
    return (config_dir / candidate).resolve()


def _validate_settings_tree(settings_tree: Mapping[str, Any], *, config_path: Path) -> None:
    missing = [path for path in _FLAT_KEY_MAP.values() if _lookup_tree_value(settings_tree, path) is None]
    if missing:
        joined = ", ".join(sorted(missing))
        raise RuntimeError(
            f"Configuration file is missing required settings in {config_path}: {joined}"
        )


def _require_tree_value(settings_tree: Mapping[str, Any], dotted_path: str) -> Any:
    value = _lookup_tree_value(settings_tree, dotted_path)
    if value is None:
        raise RuntimeError(f"Missing configuration value: {dotted_path}")
    return value


def _lookup_tree_value(settings_tree: Mapping[str, Any], dotted_path: str) -> Any:
    current: Any = settings_tree
    for part in dotted_path.split("."):
        if not isinstance(current, Mapping) or part not in current:
            return None
        current = current[part]
    return current


def _load_local_env(config_dir: Path, env_path: Path) -> dict[str, str]:
    resolved_path = env_path if env_path.is_absolute() else (config_dir / env_path).resolve()
    if not resolved_path.is_file():
        legacy_path = _legacy_local_env_path(resolved_path)
        if legacy_path is not None and legacy_path.is_file():
            resolved_path = legacy_path
    values: dict[str, str] = {}
    if not resolved_path.is_file():
        return values
    for raw_line in resolved_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        cleaned_key = key.strip()
        cleaned_value = value.strip().strip("'\"")
        if cleaned_key:
            values[cleaned_key] = cleaned_value
    return values


def _legacy_local_env_path(path: Path) -> Path | None:
    if path.name != "noviagen.env":
        return None
    return path.with_name("obscure.env")
