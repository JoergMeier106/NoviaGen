from __future__ import annotations

import platform
from datetime import UTC, datetime
from typing import Any

from .commands import CommandResult
from .cpu_info import _collect_cpu_info
from .gpu_info import _collect_gpu_info
from .memory_info import _collect_memory_info


def collect_system_info() -> dict[str, Any]:
    system_name = platform.system()
    system_key = system_name.lower()
    cpu = _collect_cpu_info(system_key)
    memory = _collect_memory_info(system_key)
    gpus = _collect_gpu_info(system_key)
    return {
        "platform": {
            "system": system_name,
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
            "hostname": platform.node(),
        },
        "cpu": cpu,
        "memory": memory,
        "gpus": gpus,
        "collected_at": datetime.now(UTC).isoformat(),
    }


__all__ = ["CommandResult", "collect_system_info"]
