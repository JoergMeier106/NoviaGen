from __future__ import annotations

from flask import Response, current_app, jsonify, request

from .blueprint import api
from ..responses.jobs import inter_job_delay_response as _inter_job_delay_response
from .context import (
    errors as _errors,
    logs as _logs,
    shutdown as _shutdown,
    worker as _worker,
)
from .helpers import ollama_client as _ollama_client
from ..responses.system import (
    clear_shutdown_when_idle_response as _clear_shutdown_when_idle_response,
    health_response as _health_response,
    request_shutdown_when_idle_response as _request_shutdown_when_idle_response,
    restart_server_response as _restart_server_response,
    shutdown_host_response as _shutdown_host_response,
    shutdown_when_idle_status_response as _shutdown_when_idle_status_response,
    system_info_response as _system_info_response,
    system_logs_response as _system_logs_response,
    unload_models_response as _unload_models_response,
)
from ...system import collect_system_info


@api.get("/api/health")
def health() -> Response:
    return _health_response(
        config=current_app.config,
        worker=_worker(),
        ollama_client=_ollama_client(),
    )


@api.get("/api/system/info")
def system_info() -> Response:
    return _system_info_response(collect_system_info=collect_system_info)


@api.get("/api/system/logs")
def system_logs() -> Response:
    return _system_logs_response(request_args=request.args, log_store=_logs())


@api.get("/api/errors")
def list_errors() -> Response:
    return jsonify({"items": _errors().list_errors()})


@api.delete("/api/errors")
def clear_errors() -> Response:
    deleted = _errors().clear_errors()
    return jsonify({"deleted": deleted})


@api.get("/api/system/shutdown-when-idle")
def get_shutdown_when_idle() -> Response:
    return _shutdown_when_idle_status_response(worker=_worker())


@api.post("/api/system/shutdown-when-idle")
def request_shutdown_when_idle() -> Response:
    return _request_shutdown_when_idle_response(worker=_worker())


@api.delete("/api/system/shutdown-when-idle")
def clear_shutdown_when_idle() -> Response:
    return _clear_shutdown_when_idle_response(worker=_worker())


@api.get("/api/system/inter-job-delay")
def get_inter_job_delay() -> Response:
    return jsonify(_worker().stats())


@api.post("/api/system/inter-job-delay")
def set_inter_job_delay() -> Response:
    return _inter_job_delay_response(
        body=request.get_json(silent=True) or {},
        worker=_worker(),
    )


@api.post("/api/system/shutdown")
def shutdown_host() -> Response:
    return _shutdown_host_response(shutdown_controller=_shutdown())


@api.post("/api/system/restart-server")
def restart_server() -> Response:
    return _restart_server_response(
        shutdown_controller=_shutdown(),
        shutdown_callback=request.environ.get("werkzeug.server.shutdown"),
    )


@api.post("/api/system/unload-models")
def unload_models() -> Response:
    return _unload_models_response(worker=_worker())
