from __future__ import annotations

import os
import platform
import signal
import subprocess
import threading
import time
from logging import Logger
from typing import Any, Callable, Sequence

from .error_store import ErrorStore


class UnsupportedShutdownPlatformError(RuntimeError):
    pass


class UnsupportedRestartServerError(RuntimeError):
    pass


_RESTART_REQUESTED = False
_RESTART_LOCK = threading.Lock()


class SystemShutdownController:
    def __init__(
        self,
        *,
        logger: Logger,
        host_shutdown_command: Sequence[str] | None,
        server_restart_command: Sequence[str],
        server_restart_delay_seconds: float,
        error_store: ErrorStore | None = None,
    ) -> None:
        self._logger = logger
        self._host_shutdown_command = (
            [str(part) for part in host_shutdown_command] if host_shutdown_command else []
        )
        self._server_restart_command = [str(part) for part in server_restart_command]
        self._server_restart_delay_seconds = float(server_restart_delay_seconds)
        self._error_store = error_store

    def request_shutdown(self) -> dict[str, Any]:
        platform_name, commands = self.describe_shutdown_commands(self._host_shutdown_command)
        command = list(commands[0])
        self._start_delayed_background_action(
            name="system-shutdown",
            delay_seconds=1.0,
            action=lambda: self._run_shutdown_commands(platform_name, commands),
        )
        return {"scheduled": True, "platform": platform_name, "command": command}

    def request_server_restart(
        self,
        *,
        shutdown_callback: Callable[[], None] | None,
    ) -> dict[str, Any]:
        if shutdown_callback is None:
            parent_pid = self._restartable_parent_pid()
            if parent_pid is not None:
                self._start_delayed_background_action(
                    name="backend-parent-restart",
                    delay_seconds=self._server_restart_delay_seconds,
                    action=lambda: self._signal_parent_for_restart(parent_pid),
                )
                return {
                    "scheduled": True,
                    "strategy": "parent_process_restart",
                    "pid": parent_pid,
                    "signal": "SIGTERM",
                }

            restart_command = self._validated_server_restart_command()
            self._start_delayed_background_action(
                name="backend-service-restart",
                delay_seconds=self._server_restart_delay_seconds,
                action=lambda: self._launch_restart_command(restart_command),
            )
            return {
                "scheduled": True,
                "strategy": "service_command_restart",
                "command": restart_command,
            }

        with _RESTART_LOCK:
            global _RESTART_REQUESTED
            _RESTART_REQUESTED = True

        self._start_delayed_background_action(
            name="backend-server-restart",
            delay_seconds=self._server_restart_delay_seconds,
            action=lambda: self._invoke_shutdown_callback(shutdown_callback),
        )
        return {"scheduled": True, "strategy": "in_process_restart"}

    def _validated_server_restart_command(self) -> list[str]:
        if not self._server_restart_command or not self._server_restart_command[0].strip():
            raise UnsupportedRestartServerError(
                "The current server does not have a valid restart command configured."
            )
        return list(self._server_restart_command)

    def _restartable_parent_pid(self) -> int | None:
        parent_pid = os.getppid()
        if parent_pid <= 1:
            return None
        if not self._is_gunicorn_parent_process(parent_pid):
            return None
        return parent_pid

    def _start_delayed_background_action(
        self,
        *,
        name: str,
        delay_seconds: float,
        action: Callable[[], None],
    ) -> None:
        def _run_later() -> None:
            time.sleep(max(0.0, float(delay_seconds)))
            action()

        threading.Thread(
            target=_run_later,
            daemon=True,
            name=name,
        ).start()

    def _signal_parent_for_restart(self, parent_pid: int) -> None:
        try:
            os.kill(parent_pid, signal.SIGTERM)
        except OSError:
            self._logger.exception("Failed to signal parent process for backend restart")

    def _launch_restart_command(self, restart_command: Sequence[str]) -> None:
        try:
            subprocess.Popen([str(part) for part in restart_command])
        except OSError:
            self._logger.exception("Failed to execute backend service restart command")

    def _invoke_shutdown_callback(self, shutdown_callback: Callable[[], None]) -> None:
        try:
            shutdown_callback()
        except Exception:
            self._logger.exception("Failed to trigger backend server restart")

    @staticmethod
    def _is_gunicorn_parent_process(parent_pid: int) -> bool:
        try:
            command = (
                open(f"/proc/{parent_pid}/cmdline", "rb").read().replace(b"\x00", b" ").decode(
                    "utf-8",
                    errors="ignore",
                )
            )
        except OSError:
            return False
        return "gunicorn" in command.lower()

    @staticmethod
    def describe_shutdown() -> tuple[str, list[str]]:
        platform_name, commands = SystemShutdownController.describe_shutdown_commands()
        return platform_name, list(commands[0])

    @staticmethod
    def describe_shutdown_commands(
        configured_command: Sequence[str] | None = None,
    ) -> tuple[str, list[list[str]]]:
        platform_name = platform.system()
        if configured_command:
            return platform_name, [[str(part) for part in configured_command]]
        return platform_name, SystemShutdownController._default_shutdown_commands(platform_name)

    @staticmethod
    def _default_shutdown_commands(platform_name: str) -> list[list[str]]:
        normalized = platform_name.lower()
        if normalized.startswith("win"):
            # Use an explicit local power-off command on Windows to avoid
            # drifting into restart-oriented shutdown modes.
            return [["shutdown", "/p", "/f"]]
        if normalized == "linux":
            # Keep Linux fallback behavior intentionally small. Service
            # installs should prefer the configured host_shutdown command,
            # while the defaults cover the most common local power-off
            # entry points.
            return [
                ["shutdown", "now"],
                ["systemctl", "poweroff"],
                ["poweroff"],
            ]
        raise UnsupportedShutdownPlatformError(f"Unsupported platform: {platform_name}")

    def _run_shutdown_commands(
        self,
        platform_name: str,
        commands: Sequence[Sequence[str]],
    ) -> None:
        failure_details: list[dict[str, Any]] = []
        for index, command in enumerate(commands):
            command_parts = [str(part) for part in command]
            try:
                completed = subprocess.run(
                    command_parts,
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False,
                )
            except OSError:
                self._logger.exception(
                    "Failed to execute %s shutdown command %s",
                    platform_name,
                    command_parts,
                )
                failure_details.append(
                    {
                        "command": command_parts,
                        "error": "Failed to execute command",
                    }
                )
                continue
            except subprocess.TimeoutExpired:
                self._logger.info(
                    "Shutdown command did not exit before timeout; assuming shutdown is in progress: %s",
                    command_parts,
                )
                return

            if completed.returncode == 0:
                self._logger.info(
                    "Issued %s shutdown command: %s",
                    platform_name,
                    command_parts,
                )
                return

            stderr_text = (completed.stderr or "").strip()
            stdout_text = (completed.stdout or "").strip()
            self._logger.warning(
                "Shutdown command failed with exit code %s: %s%s%s",
                completed.returncode,
                command_parts,
                f" stderr={stderr_text!r}" if stderr_text else "",
                f" stdout={stdout_text!r}" if stdout_text else "",
            )
            failure_details.append(
                {
                    "command": command_parts,
                    "returncode": completed.returncode,
                    "stderr": stderr_text,
                    "stdout": stdout_text,
                }
            )

            if index + 1 < len(commands):
                self._logger.info(
                    "Trying fallback shutdown command after failure: %s",
                    [str(part) for part in commands[index + 1]],
                )

        failed_commands = [[str(part) for part in command] for command in commands]
        self._logger.error(
            "All %s shutdown commands failed: %s",
            platform_name,
            failed_commands,
        )
        if self._error_store is not None:
            self._error_store.log_system_error(
                operation="host_shutdown",
                status_text="Host shutdown failed",
                error_text=(
                    f"All {platform_name} shutdown commands failed. "
                    f"Failures: {failure_details}"
                ),
                payload={
                    "platform": platform_name,
                    "commands": failed_commands,
                    "failures": failure_details,
                },
            )


def consume_server_restart_request() -> bool:
    with _RESTART_LOCK:
        global _RESTART_REQUESTED
        requested = _RESTART_REQUESTED
        _RESTART_REQUESTED = False
        return requested
