from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .commands import _run_command, _run_windows_powershell
from .parsing import _coerce_int, _parse_json_object


def _collect_memory_info(system_key: str) -> dict[str, Any]:
    if system_key.startswith("win"):
        return _collect_windows_memory_info()
    if system_key == "linux":
        return _collect_linux_memory_info()
    return {"total_bytes": None, "available_bytes": None}


def _collect_windows_memory_info() -> dict[str, Any]:
    result = _run_windows_powershell(
        "Get-CimInstance Win32_OperatingSystem | "
        "Select-Object TotalVisibleMemorySize,FreePhysicalMemory | "
        "ConvertTo-Json -Compress"
    )
    if result.ok:
        payload = _parse_json_object(result.stdout)
        if payload:
            total_kib = _coerce_int(payload.get("TotalVisibleMemorySize"))
            free_kib = _coerce_int(payload.get("FreePhysicalMemory"))
            return {
                "total_bytes": total_kib * 1024 if total_kib is not None else None,
                "available_bytes": free_kib * 1024 if free_kib is not None else None,
            }
    return {"total_bytes": None, "available_bytes": None}


def _collect_linux_memory_info() -> dict[str, Any]:
    result = _run_command(["free", "-b"])
    if result.ok:
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        for line in lines:
            if line.startswith("Mem:"):
                parts = re.split(r"\s+", line)
                if len(parts) >= 7:
                    return {
                        "total_bytes": _coerce_int(parts[1]),
                        "available_bytes": _coerce_int(parts[6]),
                    }

    meminfo_path = Path("/proc/meminfo")
    if meminfo_path.exists():
        values: dict[str, int] = {}
        for line in meminfo_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            key, _, rest = line.partition(":")
            match = re.search(r"(\d+)", rest)
            if match:
                values[key.strip()] = int(match.group(1)) * 1024
        return {
            "total_bytes": values.get("MemTotal"),
            "available_bytes": values.get("MemAvailable") or values.get("MemFree"),
        }

    return {"total_bytes": None, "available_bytes": None}
