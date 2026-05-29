from __future__ import annotations

import logging
import re
from collections import deque
from datetime import UTC, datetime
from logging.handlers import RotatingFileHandler
from pathlib import Path
from threading import Thread
from typing import IO, Any

DEFAULT_LOG_LIMIT = 400
MAX_LOG_LIMIT = 2000

_LOG_LINE_PATTERN = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:,\d+)?) "
    r"(?P<level>[A-Z]+) "
    r"\[(?P<logger>[^\]]+)\] "
    r"(?P<message>.*)$"
)
_ANSI_ESCAPE_PATTERN = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
_EXPLICIT_LEVEL_PATTERN = re.compile(
    r"^\s*(?:\[[^\]]+\]\s*)?"
    r"(?P<level>CRITICAL|FATAL|ERROR|EXCEPTION|TRACEBACK|WARNING|WARN|INFO|DEBUG)"
    r"\b\s*[:\]-]?",
    re.IGNORECASE,
)
_ERROR_HINT_PATTERN = re.compile(
    r"(^\s*!!!\s*exception\b|"
    r"\btraceback \(most recent call last\)|"
    r"^\s*(?:unhandled\s+)?(?:critical|fatal|error|exception)\b)",
    re.IGNORECASE,
)
_WARNING_HINT_PATTERN = re.compile(r"\b(?:warning|warn)\b", re.IGNORECASE)


class ManagedLogStore:
    def __init__(
        self,
        *,
        logs_dir: str | Path,
        max_bytes: int,
        backup_count: int,
        formatter: logging.Formatter,
    ) -> None:
        self.logs_dir = Path(logs_dir)
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        self.max_bytes = max(1, int(max_bytes))
        self.backup_count = max(1, int(backup_count))
        self.server_log_path = self.logs_dir / "server.log"
        self.comfy_log_path = self.logs_dir / "comfy.log"
        self.server_handler = self._build_handler(
            self.server_log_path,
            formatter,
            marker="_noviagen_server_log_handler",
        )
        self.comfy_handler = self._build_handler(
            self.comfy_log_path,
            formatter,
            marker="_noviagen_comfy_log_handler",
        )
        self._comfy_logger = logging.getLogger("noviagen.comfy")
        self._comfy_logger.setLevel(logging.INFO)
        self._comfy_logger.propagate = False
        self._replace_managed_handler(
            self._comfy_logger,
            self.comfy_handler,
            marker="_noviagen_comfy_log_handler",
        )

    @property
    def comfy_logger(self) -> logging.Logger:
        return self._comfy_logger

    def attach_server_handler(self, logger: logging.Logger) -> None:
        self._replace_managed_handler(
            logger,
            self.server_handler,
            marker="_noviagen_server_log_handler",
        )

    def start_comfy_log_pumps(self, process: Any) -> list[Thread]:
        threads: list[Thread] = []
        thread = self._start_stream_pump(
            stream=getattr(process, "stdout", None),
            logger=self._comfy_logger,
            level=logging.INFO,
            name="comfy-stdout-log",
        )
        if thread is not None:
            threads.append(thread)
        thread = self._start_stream_pump(
            stream=getattr(process, "stderr", None),
            logger=self._comfy_logger,
            level=logging.WARNING,
            name="comfy-stderr-log",
        )
        if thread is not None:
            threads.append(thread)
        return threads

    def read_snapshot(self, source: str, *, limit: int | None = None) -> dict[str, Any]:
        normalized_source = str(source).strip().lower()
        if normalized_source not in {"server", "comfy"}:
            raise ValueError("source must be one of: server, comfy")

        effective_limit = DEFAULT_LOG_LIMIT if limit is None else int(limit)
        if effective_limit <= 0:
            raise ValueError("limit must be greater than 0")
        effective_limit = min(effective_limit, MAX_LOG_LIMIT)

        log_path = (
            self.server_log_path if normalized_source == "server" else self.comfy_log_path
        )
        rows: deque[dict[str, Any]] = deque(maxlen=effective_limit)
        total_rows = 0

        for path in self._iter_log_files(log_path):
            try:
                with path.open(encoding="utf-8", errors="replace") as handle:
                    for line in handle:
                        total_rows += 1
                        rows.append(_parse_log_line(line))
            except OSError:
                continue

        return {
            "source": normalized_source,
            "display_name": "Server" if normalized_source == "server" else "Comfy",
            "rows": list(rows),
            "truncated": total_rows > effective_limit,
            "limit": effective_limit,
            "refreshed_at": datetime.now(UTC).isoformat(),
        }

    def _build_handler(
        self,
        path: Path,
        formatter: logging.Formatter,
        *,
        marker: str,
    ) -> RotatingFileHandler:
        handler = RotatingFileHandler(
            path,
            maxBytes=self.max_bytes,
            backupCount=self.backup_count,
            encoding="utf-8",
            delay=True,
        )
        setattr(handler, marker, True)
        handler.setFormatter(formatter)
        handler.setLevel(logging.INFO)
        return handler

    def _iter_log_files(self, base_path: Path) -> list[Path]:
        backup_paths: list[tuple[int, Path]] = []
        base_name = re.escape(base_path.name)
        pattern = re.compile(rf"^{base_name}\.(\d+)$")
        try:
            candidates = list(base_path.parent.glob(f"{base_path.name}*"))
        except OSError:
            candidates = []
        for candidate in candidates:
            if candidate == base_path or not candidate.is_file():
                continue
            match = pattern.match(candidate.name)
            if match is None:
                continue
            backup_paths.append((int(match.group(1)), candidate))
        ordered = [path for _, path in sorted(backup_paths, reverse=True)]
        if base_path.exists():
            ordered.append(base_path)
        return ordered

    @staticmethod
    def _replace_managed_handler(
        logger: logging.Logger,
        handler: logging.Handler,
        *,
        marker: str,
    ) -> None:
        for existing in list(logger.handlers):
            if existing is handler:
                return
            if getattr(existing, marker, False):
                logger.removeHandler(existing)
                try:
                    existing.close()
                except Exception:
                    pass
        logger.addHandler(handler)

    @staticmethod
    def _start_stream_pump(
        *,
        stream: IO[str] | None,
        logger: logging.Logger,
        level: int,
        name: str,
    ) -> Thread | None:
        if stream is None:
            return None

        def _consume() -> None:
            try:
                for raw_line in stream:
                    line = raw_line.rstrip("\r\n")
                    if not line:
                        continue
                    logger.log(_infer_stream_level(line, default_level=level), line)
            finally:
                try:
                    stream.close()
                except Exception:
                    pass

        thread = Thread(target=_consume, daemon=True, name=name)
        thread.start()
        return thread


def _infer_stream_level(line: str, *, default_level: int) -> int:
    """Infer a severity for unstructured process output before writing it.

    Many ML/CUDA/Python libraries write ordinary warnings or progress text to
    stderr. Treating every stderr line as ERROR makes the log page look much
    noisier than the underlying process state.
    """

    cleaned = _ANSI_ESCAPE_PATTERN.sub("", line).strip()
    if not cleaned:
        return default_level

    explicit = _EXPLICIT_LEVEL_PATTERN.match(cleaned)
    if explicit is not None:
        return _level_name_to_logging_level(explicit.group("level"))

    if _ERROR_HINT_PATTERN.search(cleaned):
        return logging.ERROR
    if _WARNING_HINT_PATTERN.search(cleaned):
        return logging.WARNING
    return default_level


def _level_name_to_logging_level(level_name: str) -> int:
    normalized = level_name.strip().upper()
    if normalized in {"CRITICAL", "FATAL"}:
        return logging.CRITICAL
    if normalized in {"ERROR", "EXCEPTION", "TRACEBACK"}:
        return logging.ERROR
    if normalized in {"WARNING", "WARN"}:
        return logging.WARNING
    if normalized == "DEBUG":
        return logging.DEBUG
    return logging.INFO


def _parse_log_line(raw_line: str) -> dict[str, Any]:
    raw = raw_line.rstrip("\r\n")
    match = _LOG_LINE_PATTERN.match(raw)
    if match is None:
        return {
            "raw": raw,
            "timestamp": None,
            "level": None,
            "logger": None,
            "message": raw,
        }
    return {
        "raw": raw,
        "timestamp": match.group("timestamp"),
        "level": match.group("level"),
        "logger": match.group("logger"),
        "message": match.group("message"),
    }
