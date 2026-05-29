from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass


@dataclass(slots=True)
class CommandResult:
    ok: bool
    stdout: str
    stderr: str


def _run_windows_powershell(script: str) -> CommandResult:
    powershell_path = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell_path:
        return CommandResult(ok=False, stdout="", stderr="powershell not found")
    return _run_command([powershell_path, "-NoProfile", "-Command", script])


def _run_command(args: list[str]) -> CommandResult:
    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="ignore",
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return CommandResult(ok=False, stdout="", stderr="")
    return CommandResult(
        ok=completed.returncode == 0,
        stdout=(completed.stdout or "").strip(),
        stderr=(completed.stderr or "").strip(),
    )
