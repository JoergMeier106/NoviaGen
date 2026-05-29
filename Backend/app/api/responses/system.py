from __future__ import annotations

from typing import Any

from flask import Response, jsonify

from ...comfy import comfy_health_payload
from ...system.shutdown import (
    UnsupportedRestartServerError,
    UnsupportedShutdownPlatformError,
)


def health_response(
    *,
    config: Any,
    worker: Any,
    ollama_client: Any,
) -> Response:
    comfy = comfy_health_payload(
        comfy_url=str(config["COMFY_URL"]),
        timeout_seconds=5.0,
    )
    ollama = ollama_client.health()
    status = "ok" if comfy.get("ok") and ollama.get("ok") else "degraded"
    return jsonify(
        {
            "status": status,
            "backend": {"ok": True, "label": "Online", "detail": "Flask API reachable"},
            "comfy": comfy,
            "ollama": ollama,
            "queue": worker.stats(),
            "temp_ttl_seconds": config["TEMP_TTL_SECONDS"],
        }
    )


def system_info_response(*, collect_system_info) -> Response:
    return jsonify(collect_system_info())


def system_logs_response(
    *,
    request_args: Any,
    log_store: Any,
) -> Response | tuple[Response, int]:
    source = str(request_args.get("source", "server")).strip().lower()
    raw_limit = request_args.get("limit")
    try:
        limit = None if raw_limit in (None, "") else int(raw_limit)
    except (TypeError, ValueError):
        return jsonify({"error": "limit must be an integer"}), 400

    try:
        snapshot = log_store.read_snapshot(source, limit=limit)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    return jsonify(snapshot)


def shutdown_when_idle_status_response(*, worker: Any) -> Response:
    return jsonify(worker.stats())


def request_shutdown_when_idle_response(*, worker: Any) -> Response:
    return jsonify(worker.request_shutdown_when_idle())


def clear_shutdown_when_idle_response(*, worker: Any) -> Response:
    return jsonify(worker.clear_shutdown_when_idle())


def shutdown_host_response(*, shutdown_controller: Any) -> Response | tuple[Response, int]:
    try:
        return jsonify(shutdown_controller.request_shutdown()), 202
    except UnsupportedShutdownPlatformError as exc:
        return jsonify({"error": str(exc)}), 501


def restart_server_response(
    *,
    shutdown_controller: Any,
    shutdown_callback: Any,
) -> Response | tuple[Response, int]:
    try:
        return jsonify(
            shutdown_controller.request_server_restart(
                shutdown_callback=shutdown_callback,
            )
        ), 202
    except UnsupportedRestartServerError as exc:
        return jsonify({"error": str(exc)}), 501


def unload_models_response(*, worker: Any) -> Response | tuple[Response, int]:
    generator = getattr(worker, "generator", None)
    if generator is None or not hasattr(generator, "force_unload_all"):
        return jsonify({"error": "Model unloading is not available"}), 503
    return jsonify(generator.force_unload_all())
