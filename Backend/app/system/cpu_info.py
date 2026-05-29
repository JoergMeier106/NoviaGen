from __future__ import annotations

import os
import platform
import time
from pathlib import Path
from typing import Any

from .commands import _run_command, _run_windows_powershell
from .parsing import _coerce_float, _coerce_int, _parse_json_object


def _collect_cpu_info(system_key: str) -> dict[str, Any]:
    if system_key.startswith("win"):
        return _collect_windows_cpu_info()
    if system_key == "linux":
        return _collect_linux_cpu_info()
    return {
        "model": platform.processor() or "Unknown CPU",
        "physical_cores": None,
        "logical_cores": os.cpu_count(),
    }


def _collect_windows_cpu_info() -> dict[str, Any]:
    result = _run_windows_powershell(
        "Get-CimInstance Win32_Processor | "
        "Select-Object -First 1 Name,NumberOfCores,NumberOfLogicalProcessors | "
        "ConvertTo-Json -Compress"
    )
    if result.ok:
        payload = _parse_json_object(result.stdout)
        if payload:
            return {
                "model": str(payload.get("Name") or "Unknown CPU").strip(),
                "physical_cores": _coerce_int(payload.get("NumberOfCores")),
                "logical_cores": _coerce_int(payload.get("NumberOfLogicalProcessors")),
                "utilization_percent": _collect_windows_cpu_utilization(),
            }
    return {
        "model": platform.processor() or "Unknown CPU",
        "physical_cores": None,
        "logical_cores": os.cpu_count(),
        "utilization_percent": _collect_windows_cpu_utilization(),
    }


def _collect_linux_cpu_info() -> dict[str, Any]:
    model = "Unknown CPU"
    physical_cores: int | None = None
    logical_cores = os.cpu_count()

    lscpu_result = _run_command(["lscpu", "-J"])
    if lscpu_result.ok:
        payload = _parse_json_object(lscpu_result.stdout)
        if payload:
            entries = payload.get("lscpu")
            if isinstance(entries, list):
                values = {
                    str(item.get("field") or "").strip().rstrip(":"): item.get("data")
                    for item in entries
                    if isinstance(item, dict)
                }
                model = str(values.get("Model name") or model).strip() or model
                cores_per_socket = _coerce_int(values.get("Core(s) per socket"))
                sockets = _coerce_int(values.get("Socket(s)"))
                if cores_per_socket is not None and sockets is not None:
                    physical_cores = cores_per_socket * sockets
                logical_cores = _coerce_int(values.get("CPU(s)")) or logical_cores

    if model == "Unknown CPU":
        cpuinfo_path = Path("/proc/cpuinfo")
        if cpuinfo_path.exists():
            for line in cpuinfo_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.lower().startswith("model name"):
                    _, _, value = line.partition(":")
                    model = value.strip() or model
                    break

    if physical_cores is None:
        physical_pairs: set[tuple[str, str]] = set()
        physical_id = "0"
        core_id = ""
        cpuinfo_path = Path("/proc/cpuinfo")
        if cpuinfo_path.exists():
            for line in cpuinfo_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                lowered = line.lower()
                if lowered.startswith("physical id"):
                    _, _, value = line.partition(":")
                    physical_id = value.strip()
                elif lowered.startswith("core id"):
                    _, _, value = line.partition(":")
                    core_id = value.strip()
                elif not line.strip():
                    if core_id:
                        physical_pairs.add((physical_id, core_id))
                    physical_id = "0"
                    core_id = ""
        if core_id:
            physical_pairs.add((physical_id, core_id))
        if physical_pairs:
            physical_cores = len(physical_pairs)

    return {
        "model": model,
        "physical_cores": physical_cores,
        "logical_cores": logical_cores,
        "utilization_percent": _collect_linux_cpu_utilization(),
    }


def _collect_windows_cpu_utilization() -> float | None:
    result = _run_windows_powershell(
        "Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | "
        "Where-Object { $_.Name -eq '_Total' } | "
        "Select-Object -First 1 PercentProcessorTime | ConvertTo-Json -Compress"
    )
    if not result.ok:
        return None
    payload = _parse_json_object(result.stdout)
    if not payload:
        return None
    return _coerce_float(payload.get("PercentProcessorTime"))


def _collect_linux_cpu_utilization() -> float | None:
    first = _read_linux_cpu_times()
    if first is None:
        return None
    time.sleep(0.2)
    second = _read_linux_cpu_times()
    if second is None:
        return None
    idle_delta = second["idle"] - first["idle"]
    total_delta = second["total"] - first["total"]
    if total_delta <= 0:
        return None
    busy_percent = (1.0 - (idle_delta / total_delta)) * 100.0
    return round(max(0.0, min(busy_percent, 100.0)), 1)


def _read_linux_cpu_times() -> dict[str, int] | None:
    cpu_stat_path = Path("/proc/stat")
    try:
        content = cpu_stat_path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    for line in content.splitlines():
        if not line.startswith("cpu "):
            continue
        parts = [part for part in line.split() if part]
        if len(parts) < 5:
            return None
        values = [_coerce_int(part) or 0 for part in parts[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        total = sum(values)
        return {"idle": idle, "total": total}
    return None
