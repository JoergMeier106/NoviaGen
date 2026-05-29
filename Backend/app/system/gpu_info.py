from __future__ import annotations

from pathlib import Path
from typing import Any

from .commands import _run_command, _run_windows_powershell
from .parsing import (
    _coerce_float,
    _coerce_int,
    _extract_first_float,
    _extract_first_numeric,
    _parse_json_value,
)


def _collect_gpu_info(system_key: str) -> list[dict[str, Any]]:
    nvidia_gpus = _collect_nvidia_gpu_info()
    if nvidia_gpus:
        return nvidia_gpus
    if system_key.startswith("win"):
        return _collect_windows_gpu_info()
    if system_key == "linux":
        amd_gpus = _collect_linux_rocm_gpu_info()
        if amd_gpus:
            return amd_gpus
        return _collect_linux_lspci_gpu_info()
    return []


def _collect_windows_gpu_info() -> list[dict[str, Any]]:
    utilization_by_index = _collect_windows_gpu_utilization()
    result = _run_windows_powershell(
        "Get-CimInstance Win32_VideoController | "
        "Select-Object Name,AdapterRAM,DriverVersion | ConvertTo-Json -Compress"
    )
    if not result.ok:
        return []
    payload = _parse_json_value(result.stdout)
    items = payload if isinstance(payload, list) else [payload] if isinstance(payload, dict) else []
    gpus: list[dict[str, Any]] = []
    for index, item in enumerate(items):
        name = str(item.get("Name") or "").strip()
        if not name:
            continue
        gpus.append(
            {
                "name": name,
                "vendor": _infer_gpu_vendor(name),
                "vram_total_bytes": _coerce_int(item.get("AdapterRAM")),
                "vram_free_bytes": None,
                "utilization_percent": utilization_by_index[index]
                if index < len(utilization_by_index)
                else None,
                "driver_version": str(item.get("DriverVersion") or "").strip() or None,
                "source": "cim",
            }
        )
    return gpus


def _collect_nvidia_gpu_info() -> list[dict[str, Any]]:
    result = _run_command(
        [
            "nvidia-smi",
            "--query-gpu=name,memory.total,memory.free,driver_version,utilization.gpu",
            "--format=csv,noheader,nounits",
        ]
    )
    if not result.ok:
        return []

    gpus: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        parts = [part.strip() for part in line.split(",")]
        if len(parts) < 5 or not parts[0]:
            continue
        total_mib = _coerce_int(parts[1])
        free_mib = _coerce_int(parts[2])
        gpus.append(
            {
                "name": parts[0],
                "vendor": "NVIDIA",
                "vram_total_bytes": total_mib * 1024 * 1024 if total_mib is not None else None,
                "vram_free_bytes": free_mib * 1024 * 1024 if free_mib is not None else None,
                "utilization_percent": _coerce_float(parts[4]),
                "driver_version": parts[3] or None,
                "source": "nvidia-smi",
            }
        )
    return gpus


def _collect_linux_rocm_gpu_info() -> list[dict[str, Any]]:
    result = _run_command(
        ["rocm-smi", "--showproductname", "--showuse", "--showmeminfo", "vram", "--json"]
    )
    if not result.ok:
        return []
    payload = _parse_json_value(result.stdout)
    if not isinstance(payload, dict):
        return []
    gpus: list[dict[str, Any]] = []
    for key, value in payload.items():
        if not isinstance(value, dict):
            continue
        name = str(value.get("Card series") or value.get("Device Name") or key).strip()
        used = _extract_first_numeric(value, ("VRAM Total Used Memory (B)", "VRAM Total Used Memory"))
        total = _extract_first_numeric(
            value,
            ("VRAM Total Memory (B)", "VRAM Total Memory", "VRAM Total"),
        )
        gpus.append(
            {
                "name": name or key,
                "vendor": "AMD",
                "vram_total_bytes": total,
                "vram_free_bytes": total - used if total is not None and used is not None else None,
                "utilization_percent": _extract_first_float(
                    value,
                    ("GPU use (%)", "GPU use", "GPU Utilization (%)", "GPU Utilization"),
                ),
                "driver_version": None,
                "source": "rocm-smi",
            }
        )
    return gpus


def _collect_linux_lspci_gpu_info() -> list[dict[str, Any]]:
    result = _run_command(["lspci"])
    if not result.ok:
        return []

    gpus: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        lowered = line.lower()
        if "vga compatible controller" not in lowered and "3d controller" not in lowered:
            continue
        _, _, description = line.partition(": ")
        name = description.strip() or line.strip()
        gpus.append(
            {
                "name": name,
                "vendor": _infer_gpu_vendor(name),
                "vram_total_bytes": _read_linux_sysfs_vram_total(len(gpus)),
                "vram_free_bytes": None,
                "utilization_percent": _read_linux_sysfs_gpu_utilization(len(gpus)),
                "driver_version": None,
                "source": "lspci",
            }
        )
    return gpus


def _read_linux_sysfs_vram_total(index: int) -> int | None:
    candidates = [
        Path(f"/sys/class/drm/card{index}/device/mem_info_vram_total"),
        Path(f"/sys/class/drm/card{index}/device/mem_info_vis_vram_total"),
    ]
    for path in candidates:
        try:
            if path.exists():
                return int(path.read_text(encoding="utf-8", errors="ignore").strip())
        except (OSError, ValueError):
            continue
    return None


def _read_linux_sysfs_gpu_utilization(index: int) -> float | None:
    candidates = [
        Path(f"/sys/class/drm/card{index}/device/gpu_busy_percent"),
        Path(f"/sys/class/drm/card{index}/device/gt_cur_freq_mhz"),
    ]
    for path in candidates:
        try:
            if path.exists():
                raw = path.read_text(encoding="utf-8", errors="ignore").strip()
                value = _coerce_float(raw)
                if value is not None and path.name == "gpu_busy_percent":
                    return value
        except OSError:
            continue
    return None


def _collect_windows_gpu_utilization() -> list[float | None]:
    result = _run_windows_powershell(
        "$usageByGpu = @{}; "
        "$samples = (Get-Counter '\\GPU Engine(*)\\Utilization Percentage').CounterSamples; "
        "foreach ($sample in $samples) { "
        "  if ($sample.Path -match 'phys_(\\d+)') { "
        "    $index = [int]$matches[1]; "
        "    if (-not $usageByGpu.ContainsKey($index)) { $usageByGpu[$index] = 0.0 }; "
        "    $usageByGpu[$index] += [math]::Max([double]$sample.CookedValue, 0.0); "
        "  } "
        "}; "
        "$usageByGpu.GetEnumerator() | Sort-Object Name | ForEach-Object { "
        "  [PSCustomObject]@{ Index = [int]$_.Name; UtilizationPercent = [math]::Round([math]::Min([double]$_.Value, 100.0), 1) } "
        "} | ConvertTo-Json -Compress"
    )
    if not result.ok:
        return []
    payload = _parse_json_value(result.stdout)
    items = payload if isinstance(payload, list) else [payload] if isinstance(payload, dict) else []
    values: list[float | None] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        index = _coerce_int(item.get("Index"))
        utilization = _coerce_float(item.get("UtilizationPercent"))
        if index is None:
            continue
        while len(values) <= index:
            values.append(None)
        values[index] = utilization
    return values


def _infer_gpu_vendor(name: str) -> str | None:
    lowered = name.lower()
    if "nvidia" in lowered or "geforce" in lowered or "quadro" in lowered or "rtx" in lowered:
        return "NVIDIA"
    if "amd" in lowered or "radeon" in lowered:
        return "AMD"
    if "intel" in lowered or "arc" in lowered or "iris" in lowered:
        return "Intel"
    return None
