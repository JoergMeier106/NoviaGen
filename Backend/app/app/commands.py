from __future__ import annotations

import os
import shlex

_HOST_SHUTDOWN_ENV_VAR = "OBSCURE_HOST_SHUTDOWN_COMMAND"


def resolve_host_shutdown_command(raw_command: object) -> list[str]:
    if _HOST_SHUTDOWN_ENV_VAR in os.environ:
        return _coerce_command(os.environ[_HOST_SHUTDOWN_ENV_VAR])
    return _coerce_command(raw_command)


def resolve_server_restart_command(raw_command: object) -> list[str]:
    return _coerce_command(raw_command)


def _coerce_command(raw_command: object) -> list[str]:
    if isinstance(raw_command, str):
        return shlex.split(raw_command)
    if isinstance(raw_command, (list, tuple)):
        return [str(part) for part in raw_command]
    return []
