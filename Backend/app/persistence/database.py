from __future__ import annotations

import json
import os
import shutil
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path, PureWindowsPath
from typing import Any, Iterator

from PIL import Image, ImageOps

from .mixins.assets import AssetPersistenceMixin
from .backups.store import BackupStore
from .mixins.chat import ChatPersistenceMixin
from .mixins.gallery import GalleryPersistenceMixin
from .mixins.jobs import JobPersistenceMixin
from .mixins.media_lifecycle import MediaLifecyclePersistenceMixin
from .mixins.media_records import MediaRecordPersistenceMixin
from .schema import initialize_schema
from ..storage.files import remove_file_if_present


class AppDatabase(
    JobPersistenceMixin,
    ChatPersistenceMixin,
    AssetPersistenceMixin,
    GalleryPersistenceMixin,
    MediaLifecyclePersistenceMixin,
    MediaRecordPersistenceMixin,
):
    _THUMBNAIL_MAX_DIMENSION = 384

    def __init__(
        self,
        db_path: str | Path,
        temp_dir: str | Path,
        stored_dir: str | Path,
        backups_dir: str | Path,
        errors_dir: str | Path | None = None,
        data_dir: str | Path | None = None,
    ) -> None:
        self.db_path = str(db_path)
        self.temp_dir = Path(temp_dir)
        self.stored_dir = Path(stored_dir)
        self.backups_dir = Path(backups_dir)
        self.errors_dir = Path(errors_dir) if errors_dir is not None else None
        if data_dir is not None:
            self.data_dir = Path(data_dir)
        else:
            self.data_dir = Path(
                os.path.commonpath(
                    [
                        str(self.temp_dir.resolve(strict=False)),
                        str(self.stored_dir.resolve(strict=False)),
                        str(self.backups_dir.resolve(strict=False)),
                    ]
                )
            )
        self._lock = threading.Lock()
        self._memory_conn: sqlite3.Connection | None = None
        self._memory_anchor: sqlite3.Connection | None = None

        if self.db_path.startswith("file:") and "mode=memory" in self.db_path:
            self._memory_anchor = sqlite3.connect(
                self.db_path,
                uri=True,
                check_same_thread=False,
            )
            self._memory_anchor.row_factory = sqlite3.Row

    def init_schema(self) -> None:
        with self._write_lock(), self._connect() as conn:
            initialize_schema(conn)

    def list_backups(self) -> list[dict[str, Any]]:
        return self._backup_store().list_backups()

    def create_backup(self) -> dict[str, Any]:
        return self._backup_store().create_backup()

    def apply_backup(self, backup_name: str, *, mode: str = "overwrite") -> dict[str, Any]:
        return self._backup_store().apply_backup(backup_name, mode=mode)

    def list_app_backups(self) -> list[dict[str, Any]]:
        return self._backup_store().list_app_backups()

    def create_app_backup(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._backup_store().create_app_backup(payload)

    def get_app_backup(self, backup_name: str) -> dict[str, Any]:
        return self._backup_store().get_app_backup(backup_name)

    def delete_app_backup(self, backup_name: str) -> bool:
        return self._backup_store().delete_app_backup(backup_name)

    def delete_backup(self, backup_name: str) -> bool:
        return self._backup_store().delete_backup(backup_name)

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        if self.db_path == ":memory:":
            if self._memory_conn is None:
                self._memory_conn = sqlite3.connect(":memory:", check_same_thread=False)
                self._memory_conn.row_factory = sqlite3.Row
            yield self._memory_conn
            return

        if self.db_path.startswith("file:") and "mode=memory" in self.db_path:
            conn = sqlite3.connect(self.db_path, uri=True, check_same_thread=False)
            conn.row_factory = sqlite3.Row
            try:
                yield conn
                conn.commit()
            except Exception:
                conn.rollback()
                raise
            finally:
                conn.close()
            return

        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    @staticmethod
    def _row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
        return dict(row)

    def _decode_media_row(self, row: sqlite3.Row) -> dict[str, Any]:
        item = self._row_to_dict(row)
        item["loras"] = json.loads(item.pop("loras_json"))
        item["tags"] = json.loads(item.pop("tags_json"))
        item["media_type"] = self._normalize_media_type(
            item.get("media_type"),
            item.get("mime_type"),
        )
        item["file_path"] = str(self._path_from_record_value(item["file_path"]))
        item["poster_path"] = self._path_from_record_value(item.get("poster_path"))
        if item["poster_path"] is not None:
            item["poster_path"] = str(item["poster_path"])
        item["thumbnail_path"] = self._path_from_record_value(
            item.get("thumbnail_path")
        )
        if item["thumbnail_path"] is not None:
            item["thumbnail_path"] = str(item["thumbnail_path"])
        return item

    def _replace_file(self, destination_path: Path, source_path: Path) -> None:
        if destination_path.resolve(strict=False) == source_path.resolve(strict=False):
            return
        if destination_path.exists():
            remove_file_if_present(destination_path)
        shutil.move(str(source_path), str(destination_path))

    @staticmethod
    def _normalize_media_type(media_type: Any, mime_type: Any) -> str:
        normalized_type = str(media_type or "image").strip().lower()
        normalized_mime = str(mime_type or "").strip().lower()
        if normalized_type == "video":
            return "video"
        if normalized_type == "gif" or normalized_mime == "image/gif":
            return "gif"
        return "image"

    @staticmethod
    def _mime_type_for_extension(extension: str, *, fallback: str) -> str:
        normalized = str(extension or "").strip().lower()
        if normalized == ".png":
            return "image/png"
        if normalized == ".gif":
            return "image/gif"
        if normalized == ".mp4":
            return "video/mp4"
        return fallback

    def _normalize_media_extension(
        self,
        *,
        media_type: str,
        mime_type: str,
        extension: str | None,
    ) -> str:
        normalized_extension = str(extension or "").strip().lower()
        if normalized_extension.startswith(".") and len(normalized_extension) > 1:
            return normalized_extension
        normalized_type = self._normalize_media_type(media_type, mime_type)
        if normalized_type == "video":
            return ".mp4"
        if normalized_type == "gif":
            return ".gif"
        return ".png"

    def _normalize_poster_extension(self, extension: str | None) -> str:
        normalized_extension = str(extension or "").strip().lower()
        if normalized_extension.startswith(".") and len(normalized_extension) > 1:
            return normalized_extension
        return ".png"

    @staticmethod
    def _supports_thumbnail_generation(media_type: Any) -> bool:
        return str(media_type or "").strip().lower() in {"image", "gif", "video"}

    def _thumbnail_path_for_image(self, image_id: str) -> Path:
        return self.stored_dir / f"{image_id}_thumb.png"

    def ensure_image_thumbnail(
        self,
        image_id: str,
        *,
        force: bool = False,
    ) -> dict[str, Any] | None:
        image = self.get_image(image_id)
        if image is None:
            return None
        if image.get("status") != "stored":
            return image
        if not self._supports_thumbnail_generation(image.get("media_type")):
            return image

        existing_thumbnail_path = image.get("thumbnail_path")
        if (
            not force and
            existing_thumbnail_path and
            Path(existing_thumbnail_path).exists()
        ):
            return image

        media_type = str(image.get("media_type") or "").strip().lower()
        if media_type == "video":
            source_path_raw = image.get("poster_path")
        else:
            source_path_raw = image.get("file_path")
        if not source_path_raw:
            return image

        source_path = Path(source_path_raw)
        if not source_path.exists():
            return image

        thumbnail_path = self._thumbnail_path_for_image(image_id)
        thumbnail_path.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(source_path) as source_image:
            if getattr(source_image, "is_animated", False):
                source_image.seek(0)
            frame = ImageOps.exif_transpose(source_image.copy())
            if frame.mode not in {"RGB", "RGBA"}:
                frame = frame.convert("RGBA" if "A" in frame.getbands() else "RGB")
            if media_type == "video":
                frame = ImageOps.fit(
                    frame,
                    (self._THUMBNAIL_MAX_DIMENSION, self._THUMBNAIL_MAX_DIMENSION),
                    method=Image.Resampling.LANCZOS,
                )
            else:
                frame.thumbnail(
                    (self._THUMBNAIL_MAX_DIMENSION, self._THUMBNAIL_MAX_DIMENSION),
                    Image.Resampling.LANCZOS,
                )
            frame.save(thumbnail_path, format="PNG", optimize=True)
        return self.update_image_thumbnail(
            image_id,
            thumbnail_path=thumbnail_path,
            thumbnail_mime_type="image/png",
        )

    def migrate_media_paths_to_relative(self) -> int:
        migrated = 0
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, status, file_name, file_path, poster_path, thumbnail_path
                FROM images
                """
            ).fetchall()
            for row in rows:
                file_path = self._migrate_record_path(
                    row["file_path"],
                    status=row["status"],
                    file_name=row["file_name"],
                )
                poster_path = self._migrate_record_path(
                    row["poster_path"],
                    status=row["status"],
                )
                thumbnail_path = self._migrate_record_path(
                    row["thumbnail_path"],
                    status=row["status"],
                )
                if (
                    file_path == row["file_path"] and
                    poster_path == row["poster_path"] and
                    thumbnail_path == row["thumbnail_path"]
                ):
                    continue
                conn.execute(
                    """
                    UPDATE images
                    SET file_path = ?, poster_path = ?, thumbnail_path = ?
                    WHERE id = ?
                    """,
                    (file_path, poster_path, thumbnail_path, row["id"]),
                )
                migrated += 1
        return migrated

    @contextmanager
    def _write_lock(self) -> Iterator[None]:
        self._lock.acquire()
        try:
            yield
        finally:
            self._lock.release()

    def _backup_store(self) -> BackupStore:
        return BackupStore(
            connect=self._connect,
            write_lock=self._write_lock,
            backups_dir=self.backups_dir,
            stored_dir=self.stored_dir,
            errors_dir=self.errors_dir,
            after_restore=self._after_backup_restore,
        )

    def _after_backup_restore(self) -> None:
        self.migrate_media_paths_to_relative()
        self.cleanup_all_temp_images()

    def _cleanup_temp_directory(self, *, keep_paths: set[Path]) -> None:
        if not self.temp_dir.exists():
            return
        normalized_keep = {path.resolve(strict=False) for path in keep_paths}
        for file_path in self.temp_dir.iterdir():
            if file_path.is_dir():
                continue
            if file_path.resolve(strict=False) in normalized_keep:
                continue
            remove_file_if_present(file_path)

    def _path_from_record_value(self, path_value: str | Path | None) -> Path | None:
        if not path_value:
            return None
        normalized = str(path_value).replace("\\", "/").strip()
        if not normalized:
            return None
        path = Path(normalized)
        if path.is_absolute():
            return path
        return self.data_dir / path

    def _path_to_record_value(self, path_value: str | Path | None) -> str | None:
        if not path_value:
            return None
        path = Path(path_value).resolve(strict=False)
        try:
            return path.relative_to(self.data_dir.resolve(strict=False)).as_posix()
        except ValueError:
            return str(path)

    def _migrate_record_path(
        self,
        path_value: str | None,
        *,
        status: str,
        file_name: str | None = None,
    ) -> str | None:
        if not path_value:
            return None

        resolved_path = self._path_from_record_value(path_value)
        if resolved_path is not None and resolved_path.exists():
            try:
                return self._path_to_record_value(resolved_path)
            except ValueError:
                pass

        candidate_name = self._path_name(path_value)
        if file_name:
            candidate_name = file_name
        for base_dir in self._candidate_media_dirs(status):
            candidate_path = base_dir / candidate_name
            if candidate_path.exists():
                return self._path_to_record_value(candidate_path)

        normalized = str(path_value).replace("\\", "/").strip()
        path = Path(normalized)
        if not path.is_absolute() and not self._looks_like_windows_absolute(normalized):
            return Path(normalized).as_posix()
        return path_value

    @staticmethod
    def _path_name(path_value: str) -> str:
        raw_value = str(path_value)
        windows_name = PureWindowsPath(raw_value).name
        if windows_name:
            return windows_name
        return Path(raw_value).name

    def _candidate_media_dirs(self, status: str) -> tuple[Path, ...]:
        if status == "stored":
            return (self.stored_dir, self.temp_dir)
        return (self.temp_dir, self.stored_dir)

    @staticmethod
    def _looks_like_windows_absolute(path_value: str) -> bool:
        return (
            len(path_value) >= 3
            and path_value[1] == ":"
            and path_value[2] == "/"
            and path_value[0].isalpha()
        ) or path_value.startswith("//")
