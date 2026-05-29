from __future__ import annotations

import json
import sqlite3
import tempfile
import zipfile
from contextlib import AbstractContextManager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable

from ...storage.files import (
    extract_archive_subtree,
    merge_directory_contents,
    remove_file_if_present,
    replace_directory_contents,
)


MERGE_ORDER = (
    "images",
    "jobs",
    "asset_ratings",
    "deleted_assets",
    "chat_sessions",
    "chat_messages",
    "chat_message_attachments",
    "chat_session_summaries",
)

_APP_BACKUP_PREFIX = "noviagen-app-backup-"
_LEGACY_APP_BACKUP_PREFIX = "obscure-app-backup-"


class BackupStore:
    def __init__(
        self,
        *,
        connect: Callable[[], AbstractContextManager[sqlite3.Connection]],
        write_lock: Callable[[], AbstractContextManager[None]],
        backups_dir: Path,
        stored_dir: Path,
        errors_dir: Path | None,
        after_restore: Callable[[], None],
    ) -> None:
        self._connect = connect
        self._write_lock = write_lock
        self._backups_dir = backups_dir
        self._stored_dir = stored_dir
        self._errors_dir = errors_dir
        self._after_restore = after_restore

    def list_backups(self) -> list[dict[str, Any]]:
        self._backups_dir.mkdir(parents=True, exist_ok=True)
        return self._list_files("*.zip")

    def create_backup(self) -> dict[str, Any]:
        self._backups_dir.mkdir(parents=True, exist_ok=True)
        backup_name = f"noviagen-backup-{_timestamp()}.zip"
        backup_path = self._backups_dir / backup_name
        with zipfile.ZipFile(backup_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("app.db", self._database_snapshot_bytes())
            _write_directory(archive, self._stored_dir, archive_root="stored")
            if self._errors_dir is not None:
                _write_directory(archive, self._errors_dir, archive_root="errors")

        for item in self.list_backups():
            if item["name"] == backup_name:
                return item
        raise FileNotFoundError(backup_name)

    def apply_backup(self, backup_name: str, *, mode: str = "overwrite") -> dict[str, Any]:
        backup_path = self._resolve_backup_path(backup_name)
        if backup_path is None or not backup_path.exists():
            raise FileNotFoundError(backup_name)

        normalized_mode = str(mode or "overwrite").strip().lower()
        if normalized_mode not in {"overwrite", "merge"}:
            raise ValueError("Unsupported backup restore mode")

        with zipfile.ZipFile(backup_path) as archive:
            if "app.db" not in archive.namelist():
                raise ValueError("Backup archive is missing app.db")
            self._apply_archive(archive, mode=normalized_mode)

        self._after_restore()
        return _backup_record(backup_path)

    def list_app_backups(self) -> list[dict[str, Any]]:
        self._backups_dir.mkdir(parents=True, exist_ok=True)
        return self._list_files_for_patterns(
            f"{_APP_BACKUP_PREFIX}*.json",
            f"{_LEGACY_APP_BACKUP_PREFIX}*.json",
        )

    def create_app_backup(self, payload: dict[str, Any]) -> dict[str, Any]:
        self._backups_dir.mkdir(parents=True, exist_ok=True)
        backup_path = self._backups_dir / f"{_APP_BACKUP_PREFIX}{_timestamp()}.json"
        backup_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        return _backup_record(backup_path)

    def get_app_backup(self, backup_name: str) -> dict[str, Any]:
        backup_path = self._resolve_app_backup_path(backup_name)
        if backup_path is None or not backup_path.exists():
            raise FileNotFoundError(backup_name)
        return json.loads(backup_path.read_text(encoding="utf-8"))

    def delete_app_backup(self, backup_name: str) -> bool:
        backup_path = self._resolve_app_backup_path(backup_name)
        if backup_path is None or not backup_path.exists():
            return False
        remove_file_if_present(backup_path)
        return True

    def delete_backup(self, backup_name: str) -> bool:
        backup_path = self._resolve_backup_path(backup_name)
        if backup_path is None or not backup_path.exists():
            return False
        remove_file_if_present(backup_path)
        return True

    def _apply_archive(self, archive: zipfile.ZipFile, *, mode: str) -> None:
        with tempfile.TemporaryDirectory(dir=self._backups_dir) as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_snapshot_path = temp_dir / "app.db"
            db_snapshot_path.write_bytes(archive.read("app.db"))

            stored_restore_dir = temp_dir / "stored"
            errors_restore_dir = temp_dir / "errors"
            extract_archive_subtree(archive, "stored", stored_restore_dir)
            extract_archive_subtree(archive, "errors", errors_restore_dir)

            with self._write_lock():
                if mode == "merge":
                    self._merge_database_from_snapshot(db_snapshot_path)
                    merge_directory_contents(self._stored_dir, stored_restore_dir)
                    if self._errors_dir is not None:
                        merge_directory_contents(self._errors_dir, errors_restore_dir)
                else:
                    self._restore_database_from_snapshot(db_snapshot_path)
                    replace_directory_contents(self._stored_dir, stored_restore_dir)
                    if self._errors_dir is not None:
                        replace_directory_contents(self._errors_dir, errors_restore_dir)

    def _database_snapshot_bytes(self) -> bytes:
        with self._write_lock():
            with self._connect() as source_conn:
                source_conn.commit()
                return bytes(source_conn.serialize())

    def _restore_database_from_snapshot(self, snapshot_path: Path) -> None:
        source_conn = sqlite3.connect(snapshot_path, check_same_thread=False)
        source_conn.row_factory = sqlite3.Row
        try:
            with self._connect() as destination_conn:
                source_conn.backup(destination_conn)
                destination_conn.commit()
        finally:
            source_conn.close()

    def _merge_database_from_snapshot(self, snapshot_path: Path) -> None:
        with self._connect() as destination_conn:
            destination_conn.execute("ATTACH DATABASE ? AS backup", (str(snapshot_path),))
            try:
                self._merge_attached_database(destination_conn)
                destination_conn.commit()
            finally:
                destination_conn.execute("DETACH DATABASE backup")

    def _merge_attached_database(self, conn: sqlite3.Connection) -> None:
        source_tables = _list_table_names(conn, schema="backup")
        destination_tables = _list_table_names(conn, schema="main")
        merged_tables: set[str] = set()
        for table_name in MERGE_ORDER:
            if table_name not in source_tables or table_name not in destination_tables:
                continue
            _merge_table_from_attached_database(conn, table_name)
            merged_tables.add(table_name)

        remaining_tables = sorted((source_tables & destination_tables) - merged_tables)
        for table_name in remaining_tables:
            _merge_table_from_attached_database(conn, table_name)

    def _list_files(self, pattern: str) -> list[dict[str, Any]]:
        items = [_backup_record(file_path) for file_path in self._backups_dir.glob(pattern)]
        items.sort(key=lambda item: item["created_at"], reverse=True)
        return items

    def _list_files_for_patterns(self, *patterns: str) -> list[dict[str, Any]]:
        items: dict[Path, dict[str, Any]] = {}
        for pattern in patterns:
            for file_path in self._backups_dir.glob(pattern):
                items[file_path] = _backup_record(file_path)
        ordered = list(items.values())
        ordered.sort(key=lambda item: item["created_at"], reverse=True)
        return ordered

    def _resolve_backup_path(self, backup_name: str) -> Path | None:
        backup_path = self._backups_dir / Path(backup_name).name
        if backup_path.parent != self._backups_dir or backup_path.suffix.lower() != ".zip":
            return None
        return backup_path

    def _resolve_app_backup_path(self, backup_name: str) -> Path | None:
        backup_path = self._backups_dir / Path(backup_name).name
        if (
            backup_path.parent != self._backups_dir
            or backup_path.suffix.lower() != ".json"
            or not backup_path.name.startswith(
                (_APP_BACKUP_PREFIX, _LEGACY_APP_BACKUP_PREFIX)
            )
        ):
            return None
        return backup_path


def _write_directory(
    archive: zipfile.ZipFile,
    directory: Path,
    *,
    archive_root: str,
) -> None:
    if not directory.exists():
        return
    for file_path in sorted(directory.rglob("*")):
        if not file_path.is_file():
            continue
        archive.write(
            file_path,
            arcname=str(Path(archive_root) / file_path.relative_to(directory)),
        )


def _merge_table_from_attached_database(
    conn: sqlite3.Connection,
    table_name: str,
) -> None:
    destination_columns = _list_table_columns(conn, table_name, schema="main")
    if not destination_columns:
        return
    source_column_names = set(_list_table_columns(conn, table_name, schema="backup"))
    common_columns = [
        column_name
        for column_name in destination_columns
        if column_name in source_column_names
    ]
    if not common_columns:
        return

    columns_sql = ", ".join(_quote_sql_identifier(name) for name in common_columns)
    destination_table_sql = f'{_quote_sql_identifier("main")}.{_quote_sql_identifier(table_name)}'
    source_table_sql = f'{_quote_sql_identifier("backup")}.{_quote_sql_identifier(table_name)}'
    conn.execute(
        f"""
        INSERT OR IGNORE INTO {destination_table_sql} ({columns_sql})
        SELECT {columns_sql}
        FROM {source_table_sql}
        """
    )


def _list_table_names(conn: sqlite3.Connection, *, schema: str) -> set[str]:
    _validate_schema(schema)
    rows = conn.execute(
        f"""
        SELECT name
        FROM {_quote_sql_identifier(schema)}.sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        """
    ).fetchall()
    return {str(row["name"]) for row in rows}


def _list_table_columns(
    conn: sqlite3.Connection,
    table_name: str,
    *,
    schema: str,
) -> list[str]:
    _validate_schema(schema)
    rows = conn.execute(
        f"PRAGMA {_quote_sql_identifier(schema)}.table_info({_quote_sql_identifier(table_name)})"
    ).fetchall()
    return [str(row["name"]) for row in rows]


def _validate_schema(schema: str) -> None:
    if schema not in {"main", "backup"}:
        raise ValueError(f"Unsupported schema: {schema}")


def _quote_sql_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def _backup_record(file_path: Path) -> dict[str, Any]:
    stat = file_path.stat()
    return {
        "name": file_path.name,
        "created_at": datetime.fromtimestamp(stat.st_mtime, tz=UTC).isoformat(),
        "size_bytes": stat.st_size,
    }


def _timestamp() -> str:
    return datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
