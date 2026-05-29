from __future__ import annotations

import threading
import time

from ...persistence import AppDatabase


class TempCleanupService:
    def __init__(self, *, db: AppDatabase, ttl_seconds: int, interval_seconds: int) -> None:
        self.db = db
        self.ttl_seconds = ttl_seconds
        self.interval_seconds = interval_seconds
        self._thread = threading.Thread(target=self._run, daemon=True, name="temp-cleanup")
        self._started = False

    def start(self) -> None:
        if not self._started:
            self._thread.start()
            self._started = True

    def _run(self) -> None:
        while True:
            self.db.cleanup_temp_images(self.ttl_seconds)
            time.sleep(self.interval_seconds)
