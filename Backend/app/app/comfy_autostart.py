from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path
from threading import Lock, Thread

from flask import Flask

from ..comfy import is_comfy_healthy
from ..job_queue import JobWorker

_COMFY_AUTOSTART_LOCK = Lock()
_COMFY_AUTOSTART_PROCESS: subprocess.Popen[str] | None = None


def ensure_comfy_running(app: Flask) -> None:
    if not bool(app.config["COMFY_AUTOSTART_ENABLED"]):
        return
    if is_comfy_healthy_for_app(app):
        return

    with _COMFY_AUTOSTART_LOCK:
        global _COMFY_AUTOSTART_PROCESS
        if is_comfy_healthy_for_app(app):
            return
        if (
            _COMFY_AUTOSTART_PROCESS is not None
            and _COMFY_AUTOSTART_PROCESS.poll() is None
        ):
            return

        workdir = Path(str(app.config["COMFY_AUTOSTART_WORKDIR"]))
        executable = str(app.config["COMFY_AUTOSTART_EXECUTABLE"])
        args = [str(part) for part in app.config["COMFY_AUTOSTART_ARGS"]]
        command = str(app.config["COMFY_AUTOSTART_COMMAND"])

        env = os.environ.copy()
        env.setdefault("PYTHONUNBUFFERED", "1")

        app.logger.info("Starting ComfyUI automatically from %s", workdir)
        _COMFY_AUTOSTART_PROCESS = subprocess.Popen(
            [executable, *args, command],
            cwd=str(workdir),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=1,
        )
        app.extensions["log_store"].start_comfy_log_pumps(_COMFY_AUTOSTART_PROCESS)

    Thread(
        target=_wait_for_comfy_startup,
        args=(app,),
        daemon=True,
        name="comfy-autostart",
    ).start()


def _wait_for_comfy_startup(app: Flask) -> None:
    if wait_for_comfy_health(app):
        app.logger.info("ComfyUI is healthy")
        return
    app.logger.warning("Timed out waiting for ComfyUI health after auto-start")


def is_comfy_healthy_for_app(app: Flask) -> bool:
    return is_comfy_healthy(
        comfy_url=str(app.config["COMFY_URL"]),
        health_path=str(app.config["COMFY_AUTOSTART_HEALTH_PATH"]),
        timeout_seconds=float(app.config["COMFY_AUTOSTART_HEALTH_TIMEOUT_SECONDS"]),
    )


def wait_for_comfy_health(app: Flask) -> bool:
    deadline = time.time() + float(app.config["COMFY_AUTOSTART_WAIT_SECONDS"])
    poll_seconds = float(app.config["COMFY_AUTOSTART_POLL_SECONDS"])
    while time.time() < deadline:
        if is_comfy_healthy_for_app(app):
            return True
        with _COMFY_AUTOSTART_LOCK:
            process = _COMFY_AUTOSTART_PROCESS
            if process is not None and process.poll() is not None:
                app.logger.warning(
                    "ComfyUI exited during startup with code %s",
                    process.returncode,
                )
                return False
        time.sleep(poll_seconds)
    return False


def can_recover_job(app: Flask, job_type: str) -> bool:
    if job_type not in JobWorker.COMFY_DEPENDENT_JOB_TYPES:
        return True
    return is_comfy_healthy_for_app(app)


def resume_recovered_comfy_jobs_when_ready(
    app: Flask,
    worker: JobWorker,
    pending_comfy_recovery: bool,
) -> None:
    if not pending_comfy_recovery:
        return
    if is_comfy_healthy_for_app(app):
        worker.ensure_processing()
        return

    app.logger.info("Waiting for ComfyUI health before resuming recovered queued jobs")

    def _wait_and_resume() -> None:
        if not wait_for_comfy_health(app):
            app.logger.warning(
                "Recovered ComfyUI jobs remain queued because ComfyUI did not become healthy in time"
            )
            return
        app.logger.info("Resuming recovered queued ComfyUI jobs after health check passed")
        worker.ensure_processing()

    Thread(target=_wait_and_resume, daemon=True, name="comfy-recovery-gate").start()
