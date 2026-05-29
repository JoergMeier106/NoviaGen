from __future__ import annotations

from flask import Response, request

from .backup_responses import (
    apply_backup_response as _apply_backup_response,
    create_app_backup_response as _create_app_backup_response,
    create_backup_response as _create_backup_response,
    delete_app_backup_response as _delete_app_backup_response,
    delete_backup_response as _delete_backup_response,
    get_app_backup_response as _get_app_backup_response,
    list_app_backups_response as _list_app_backups_response,
    list_backups_response as _list_backups_response,
)
from .blueprint import api
from .route_context import db as _db


@api.get("/api/backups")
def list_backups() -> Response:
    return _list_backups_response(db=_db())


@api.post("/api/backups")
def create_backup() -> Response:
    return _create_backup_response(db=_db())


@api.post("/api/backups/<backup_name>/apply")
def apply_backup(backup_name: str) -> Response:
    return _apply_backup_response(
        backup_name=backup_name,
        body=request.get_json(silent=True),
        db=_db(),
    )


@api.get("/api/app-backups")
def list_app_backups() -> Response:
    return _list_app_backups_response(db=_db())


@api.post("/api/app-backups")
def create_app_backup() -> Response:
    return _create_app_backup_response(
        body=request.get_json(silent=True),
        db=_db(),
    )


@api.get("/api/app-backups/<backup_name>")
def get_app_backup(backup_name: str) -> Response:
    return _get_app_backup_response(backup_name=backup_name, db=_db())


@api.delete("/api/app-backups/<backup_name>")
def delete_app_backup(backup_name: str) -> Response:
    return _delete_app_backup_response(backup_name=backup_name, db=_db())


@api.delete("/api/backups/<backup_name>")
def delete_backup(backup_name: str) -> Response:
    return _delete_backup_response(backup_name=backup_name, db=_db())
