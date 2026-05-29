from __future__ import annotations

from pathlib import Path

from app.config import load_gunicorn_config

_BASE_DIR = Path(__file__).resolve().parent
_CONFIG = load_gunicorn_config(_BASE_DIR)

bind = str(_CONFIG["bind"])
workers = int(_CONFIG["workers"])
worker_class = str(_CONFIG["worker_class"])
threads = max(2, int(_CONFIG["threads"]))
timeout = max(30, int(_CONFIG["timeout"]))
graceful_timeout = max(30, int(_CONFIG["graceful_timeout"]))
keepalive = max(2, int(_CONFIG["keepalive"]))
accesslog = str(_CONFIG["accesslog"])
errorlog = str(_CONFIG["errorlog"])
capture_output = bool(_CONFIG["capture_output"])
