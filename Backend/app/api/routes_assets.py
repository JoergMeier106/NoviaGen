from __future__ import annotations

from flask import Response, current_app, jsonify, request

from .asset_responses import (
    delete_asset_response as _delete_asset_response,
    readonly_asset_rating_response as _readonly_asset_rating_response,
)
from .blueprint import api
from .media import is_still_media as _is_still_media
from .prompt_responses import (
    generate_i2v_prompt_response as _generate_i2v_prompt_response,
    generate_prompt_response as _generate_prompt_response,
)
from .route_context import (
    catalog as _catalog,
    db as _db,
    refresh_catalog as _refresh_catalog,
    worker as _worker,
)
from .route_helpers import asset_payloads as _asset_payloads, ollama_client as _ollama_client
from ..generation import OllamaResponseError, OllamaUnavailableError


@api.get("/api/assets")
def assets() -> Response:
    return jsonify(_asset_payloads())


@api.post("/api/assets/<asset_type>/<asset_id>/rating")
def set_asset_rating(asset_type: str, asset_id: str) -> Response:
    return _readonly_asset_rating_response()


@api.delete("/api/assets/<asset_type>/<asset_id>")
def delete_asset(asset_type: str, asset_id: str) -> Response:
    return _delete_asset_response(
        asset_type=asset_type,
        asset_id=asset_id,
        catalog=_catalog(),
        db=_db(),
        config=current_app.config,
        refresh_catalog=_refresh_catalog,
    )


@api.get("/api/chat/models")
def list_chat_models() -> Response:
    try:
        items = _ollama_client().collect_model_items()
    except OllamaUnavailableError as exc:
        return jsonify({"error": str(exc)}), 503
    except OllamaResponseError as exc:
        return jsonify({"error": str(exc)}), 502
    return jsonify({"items": items})


@api.get("/api/prompt/models")
def list_auto_prompt_models() -> Response:
    try:
        items = _ollama_client().collect_model_items(vision_only=True)
    except OllamaUnavailableError as exc:
        return jsonify({"error": str(exc)}), 503
    except OllamaResponseError as exc:
        return jsonify({"error": str(exc)}), 502
    default_model_name = str(current_app.config.get("OLLAMA_PROMPT_MODEL") or "").strip() or None
    return jsonify(
        {
            "items": items,
            "default_model_name": default_model_name,
        }
    )


@api.post("/api/prompt/generate")
def generate_prompt() -> Response:
    return _generate_prompt_response(
        body=request.get_json(silent=True) or {},
        worker=_worker(),
    )


@api.post("/api/prompt/generate-i2v")
def generate_i2v_prompt() -> Response:
    return _generate_i2v_prompt_response(
        request_obj=request,
        db=_db(),
        worker=_worker(),
        config=current_app.config,
        is_still_media=_is_still_media,
    )
