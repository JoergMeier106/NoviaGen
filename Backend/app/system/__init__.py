"""System integration and operational helpers."""

from .error_store import ErrorStore
from .info import CommandResult, collect_system_info
from .log_store import ManagedLogStore
from .shutdown import (
    SystemShutdownController,
    UnsupportedRestartServerError,
    UnsupportedShutdownPlatformError,
    consume_server_restart_request,
)

__all__ = [
    "CommandResult",
    "ErrorStore",
    "ManagedLogStore",
    "SystemShutdownController",
    "UnsupportedRestartServerError",
    "UnsupportedShutdownPlatformError",
    "collect_system_info",
    "consume_server_restart_request",
]
