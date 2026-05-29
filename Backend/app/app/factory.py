from __future__ import annotations

import logging
from pathlib import Path

from flask import Flask

from ..api import api
from ..chat.mcp_tools import ChatMcpToolProvider
from ..config import configure_test_defaults, ensure_data_directories, load_runtime_config
from ..generation import DiffusersImageGenerator
from ..job_queue import JobWorker
from ..job_queue.maintenance.temp_cleanup import TempCleanupService
from ..persistence import AppDatabase
from ..system import ErrorStore, ManagedLogStore, SystemShutdownController
from .assets import load_active_assets
from .commands import resolve_host_shutdown_command, resolve_server_restart_command
from .comfy_autostart import (
    can_recover_job,
    ensure_comfy_running,
    resume_recovered_comfy_jobs_when_ready,
)
from .logging import configure_console_logging, configure_request_logging


def create_app(test_config: dict | None = None, generator=None) -> Flask:
    package_dir = Path(__file__).resolve().parent.parent
    base_dir = package_dir.parent
    app = Flask("Backend", root_path=str(package_dir))
    app.config.from_mapping(load_runtime_config(base_dir))
    if test_config:
        app.config.update(test_config)
    configure_test_defaults(app.config, test_config)
    app.config["HOST_SHUTDOWN_COMMAND"] = resolve_host_shutdown_command(
        app.config["HOST_SHUTDOWN_COMMAND"]
    )
    app.config["SERVER_RESTART_COMMAND"] = resolve_server_restart_command(
        app.config["SERVER_RESTART_COMMAND"]
    )
    ensure_data_directories(app.config)

    formatter = logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")
    log_store = ManagedLogStore(
        logs_dir=app.config["LOGS_DIR"],
        max_bytes=int(app.config["LOG_MAX_BYTES"]),
        backup_count=int(app.config["LOG_BACKUP_COUNT"]),
        formatter=formatter,
    )
    app.extensions["log_store"] = log_store

    configure_console_logging(app, formatter)
    configure_request_logging(app)
    ensure_comfy_running(app)

    db = AppDatabase(
        db_path=app.config["DB_PATH"],
        temp_dir=app.config["TEMP_DIR"],
        stored_dir=app.config["STORED_DIR"],
        backups_dir=app.config["BACKUPS_DIR"],
        errors_dir=app.config["ERRORS_DIR"],
        data_dir=app.config["DATA_DIR"],
    )
    db.init_schema()
    db.migrate_media_paths_to_relative()
    db.cleanup_temp_images()

    cleaned_non_stored_images = db.cleanup_non_stored_images()
    if cleaned_non_stored_images:
        app.logger.info(
            "Deleted %s non-stored image record(s) during startup cleanup",
            cleaned_non_stored_images,
        )

    cleaned_deleted_images = db.cleanup_deleted_images(
        retention_days=int(app.config["DELETED_MEDIA_RETENTION_DAYS"])
    )
    if cleaned_deleted_images:
        app.logger.info(
            "Permanently deleted %s expired media record(s) during startup cleanup",
            cleaned_deleted_images,
        )

    error_store = ErrorStore(app.config["ERRORS_DIR"])
    cleaned_cancelled_jobs = db.cleanup_cancel_requested_jobs()
    if cleaned_cancelled_jobs:
        app.logger.info(
            "Marked %s cancel-requested job(s) as cancelled during startup cleanup",
            cleaned_cancelled_jobs,
        )

    assets = load_active_assets(app, db)

    image_generator = generator or DiffusersImageGenerator(
        assets=assets,
        comfy_url=str(app.config["COMFY_URL"]),
        comfy_i2v_workflow_path=app.config["COMFY_I2V_WORKFLOW_PATH"],
        comfy_i2v_loop_workflow_path=app.config["COMFY_I2V_LOOP_WORKFLOW_PATH"],
        comfy_i2v_prompt_workflow_path=app.config["COMFY_I2V_PROMPT_WORKFLOW_PATH"],
        comfy_video_upscaler_workflow_path=app.config["COMFY_VIDEO_UPSCALER_WORKFLOW_PATH"],
        comfy_video_to_audio_workflow_path=app.config["COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH"],
        comfy_t2v_workflow_path=app.config["COMFY_T2V_WORKFLOW_PATH"],
        ollama_url=str(app.config["OLLAMA_URL"]),
        ollama_prompt_model=str(app.config["OLLAMA_PROMPT_MODEL"]),
        ollama_prompt_timeout_seconds=float(app.config["OLLAMA_PROMPT_TIMEOUT_SECONDS"]),
    )

    shutdown_controller = SystemShutdownController(
        logger=app.logger,
        host_shutdown_command=app.config["HOST_SHUTDOWN_COMMAND"],
        server_restart_command=app.config["SERVER_RESTART_COMMAND"],
        server_restart_delay_seconds=float(app.config["SERVER_RESTART_DELAY_SECONDS"]),
        error_store=error_store,
    )
    mcp_tool_provider = ChatMcpToolProvider(app.config)
    app.extensions["mcp_tool_provider"] = mcp_tool_provider
    worker = JobWorker(
        db=db,
        error_store=error_store,
        generator=image_generator,
        mcp_tool_provider=mcp_tool_provider,
        temp_dir=app.config["TEMP_DIR"],
        shutdown_controller=shutdown_controller,
        inter_job_delay_seconds=int(app.config["INTER_JOB_DELAY_SECONDS"]),
        recovered_job_gate=lambda job_type: can_recover_job(app, job_type),
    )
    cleaned_interrupted_jobs = worker.cleanup_interrupted_jobs()
    if cleaned_interrupted_jobs:
        app.logger.info(
            "Processed %s interrupted running job(s) during startup cleanup",
            cleaned_interrupted_jobs,
        )

    pending_comfy_recovery = worker.has_recoverable_comfy_jobs()
    worker.start()
    resume_recovered_comfy_jobs_when_ready(app, worker, pending_comfy_recovery)

    cleanup = TempCleanupService(
        db=db,
        ttl_seconds=app.config["TEMP_TTL_SECONDS"],
        interval_seconds=app.config["CLEANUP_INTERVAL_SECONDS"],
    )
    cleanup.start()

    app.extensions["assets"] = assets
    app.extensions["db"] = db
    app.extensions["error_store"] = error_store
    app.extensions["shutdown_controller"] = shutdown_controller
    app.extensions["job_worker"] = worker
    app.extensions["cleanup_service"] = cleanup
    app.register_blueprint(api)
    return app
