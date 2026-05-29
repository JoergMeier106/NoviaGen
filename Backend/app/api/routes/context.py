from __future__ import annotations

from typing import Any

import requests
from flask import current_app

from ..payloads.assets import asset_payloads as build_asset_payloads
from ..requests.uploads import UploadedImageImporter
from ..payloads.media import is_still_media
from ..requests.parsing import (
    normalized_optional_bool as normalized_optional_bool_value,
    normalized_optional_int as normalized_optional_int_value,
)
from ...assets import AssetCatalog
from ...chat.context_images import ChatContextImageService
from ...chat.history import (
    ChatHistoryBuilder,
)
from ...chat.ollama import OllamaClient
from ...chat.mcp_tools import ChatMcpToolProvider


def catalog():
    return current_app.extensions["assets"]


def db():
    return current_app.extensions["db"]


def chat_context_images() -> ChatContextImageService:
    return ChatContextImageService(
        db=db(),
        temp_dir=current_app.config["TEMP_DIR"],
        is_still_media=is_still_media,
    )


def image_importer() -> UploadedImageImporter:
    return UploadedImageImporter(
        db=db(),
        temp_dir=current_app.config["TEMP_DIR"],
    )


def ollama_client(
    *,
    http_get=requests.get,
    http_post=requests.post,
) -> OllamaClient:
    return OllamaClient(
        current_app.config,
        http_get=http_get,
        http_post=http_post,
    )


def chat_history_builder() -> ChatHistoryBuilder:
    return ChatHistoryBuilder(
        db=db(),
        generator=getattr(worker(), "generator", None),
        context_images=chat_context_images(),
        keep_recent_messages=int(current_app.config["CHAT_SUMMARY_KEEP_RECENT_MESSAGES"]),
        max_pending_chars=int(current_app.config["CHAT_SUMMARY_MAX_PENDING_CHARS"]),
    )


def mcp_tool_provider() -> ChatMcpToolProvider:
    return current_app.extensions["mcp_tool_provider"]


def worker():
    return current_app.extensions["job_worker"]


def errors():
    return current_app.extensions["error_store"]


def shutdown():
    return current_app.extensions["shutdown_controller"]


def logs():
    return current_app.extensions["log_store"]


def refresh_catalog():
    refreshed_catalog = AssetCatalog.from_directories(
        current_app.config["MODELS_DIR"],
        current_app.config["LORAS_DIR"],
        video_models_dir=current_app.config["VIDEO_MODELS_DIR"],
        lora_default_strength=float(current_app.config["LORA_DEFAULT_STRENGTH"]),
        lora_triggers_dir=current_app.config["LORA_TRIGGERS_DIR"],
    ).without_deleted(
        deleted_model_ids=db().list_deleted_asset_ids("model"),
        deleted_lora_ids=db().list_deleted_asset_ids("lora"),
        deleted_video_model_ids=db().list_deleted_asset_ids("video_model"),
    )
    current_app.extensions["assets"] = refreshed_catalog
    generator = getattr(worker(), "generator", None)
    if generator is not None and hasattr(generator, "assets"):
        generator.assets = refreshed_catalog
        if hasattr(generator, "_video_manager"):
            generator._video_manager.assets = refreshed_catalog
    return refreshed_catalog


def asset_payloads(
    *,
    http_get=requests.get,
) -> dict[str, Any]:
    return build_asset_payloads(
        catalog=catalog(),
        db=db(),
        config=current_app.config,
        http_get=http_get,
    )


def normalized_optional_int(value: Any) -> int | None:
    return normalized_optional_int_value(value, field_name="context_window")


def normalized_optional_bool(value: Any) -> bool | None:
    return normalized_optional_bool_value(value, field_name="think")
