from __future__ import annotations

import logging
import sys
import time

from flask import Flask, g, request
from flask.logging import default_handler

from ..system import ManagedLogStore


def configure_console_logging(app: Flask, formatter: logging.Formatter) -> None:
    log_store: ManagedLogStore = app.extensions["log_store"]
    if default_handler in app.logger.handlers:
        app.logger.removeHandler(default_handler)
    _attach_console_handler(app.logger, formatter)
    log_store.attach_server_handler(app.logger)
    app.logger.setLevel(logging.INFO)
    app.logger.propagate = False

    werkzeug_logger = logging.getLogger("werkzeug")
    _attach_console_handler(werkzeug_logger, formatter)
    log_store.attach_server_handler(werkzeug_logger)
    werkzeug_logger.setLevel(logging.INFO)
    werkzeug_logger.propagate = False

    for logger_name in ("gunicorn.error", "gunicorn.access"):
        gunicorn_logger = logging.getLogger(logger_name)
        log_store.attach_server_handler(gunicorn_logger)
        gunicorn_logger.setLevel(logging.INFO)


def configure_request_logging(app: Flask) -> None:
    @app.before_request
    def _start_request_timer() -> None:
        g._noviagen_request_started_at = time.perf_counter()

    @app.after_request
    def _log_request(response):
        if _is_internal_log_poll_request(request.path):
            return response

        started_at = getattr(g, "_noviagen_request_started_at", None)
        duration_ms = 0.0
        if started_at is not None:
            duration_ms = (time.perf_counter() - started_at) * 1000.0

        path = request.full_path if request.query_string else request.path
        app.logger.info(
            '%s "%s %s" %s %.1fms',
            request.remote_addr or "-",
            request.method,
            path,
            response.status_code,
            duration_ms,
        )
        return response


def _is_internal_log_poll_request(path: str) -> bool:
    """Avoid making the logs page create a new server-log row on every poll."""

    return path.rstrip("/") == "/api/system/logs"


def _attach_console_handler(
    logger: logging.Logger,
    formatter: logging.Formatter,
) -> None:
    for handler in logger.handlers:
        if getattr(handler, "_noviagen_console_handler", False):
            return

    handler = logging.StreamHandler(sys.stdout)
    handler._noviagen_console_handler = True  # type: ignore[attr-defined]
    handler.setFormatter(formatter)
    handler.setLevel(logging.INFO)
    logger.addHandler(handler)
