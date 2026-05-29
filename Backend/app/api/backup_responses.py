from __future__ import annotations

from typing import Any

from flask import Response, jsonify


def list_backups_response(*, db: Any) -> Response:
    return jsonify({"items": db.list_backups()})


def create_backup_response(*, db: Any) -> tuple[Response, int]:
    return jsonify(db.create_backup()), 201


def apply_backup_response(
    *,
    backup_name: str,
    body: Any,
    db: Any,
) -> Response | tuple[Response, int]:
    if db.has_active_jobs():
        return jsonify({"error": "Stop all queued and running jobs before applying a backup"}), 409
    mode = body.get("mode") if isinstance(body, dict) else "overwrite"
    try:
        return jsonify(db.apply_backup(backup_name, mode=str(mode or "overwrite")))
    except FileNotFoundError:
        return jsonify({"error": "Backup not found"}), 404
    except ValueError as error:
        return jsonify({"error": str(error)}), 400


def list_app_backups_response(*, db: Any) -> Response:
    return jsonify({"items": db.list_app_backups()})


def create_app_backup_response(*, body: Any, db: Any) -> Response | tuple[Response, int]:
    if not isinstance(body, dict):
        return jsonify({"error": "Invalid app backup payload"}), 400
    return jsonify(db.create_app_backup(body)), 201


def get_app_backup_response(
    *,
    backup_name: str,
    db: Any,
) -> Response | tuple[Response, int]:
    try:
        return jsonify(db.get_app_backup(backup_name))
    except FileNotFoundError:
        return jsonify({"error": "App backup not found"}), 404


def delete_app_backup_response(
    *,
    backup_name: str,
    db: Any,
) -> Response | tuple[Response, int]:
    deleted = db.delete_app_backup(backup_name)
    if not deleted:
        return jsonify({"error": "App backup not found"}), 404
    return jsonify({"deleted": True, "name": backup_name})


def delete_backup_response(
    *,
    backup_name: str,
    db: Any,
) -> Response | tuple[Response, int]:
    deleted = db.delete_backup(backup_name)
    if not deleted:
        return jsonify({"error": "Backup not found"}), 404
    return jsonify({"deleted": True, "name": backup_name})
