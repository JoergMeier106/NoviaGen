from __future__ import annotations

from pathlib import Path

from flask import Response, current_app, request
from werkzeug.utils import send_file as werkzeug_send_file


def send_media_file(path: Path, *, mimetype: str) -> Response:
    # Bypass the server-provided file wrapper for media responses so Gunicorn
    # streams them in chunks instead of blocking a sync worker in one long send.
    environ = dict(request.environ)
    environ.pop("wsgi.file_wrapper", None)
    return werkzeug_send_file(
        path,
        environ=environ,
        mimetype=mimetype,
        conditional=True,
        max_age=current_app.get_send_file_max_age,
        use_x_sendfile=current_app.config["USE_X_SENDFILE"],
        response_class=current_app.response_class,
        _root_path=current_app.root_path,
    )
