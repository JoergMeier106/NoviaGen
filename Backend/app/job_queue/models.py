from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class QueuedJob:
    job_id: str
    job_type: str
    payload: dict[str, Any]
    parent_job_id: str | None = None
    chain_step_id: str | None = None


class JobCancelledError(RuntimeError):
    pass
