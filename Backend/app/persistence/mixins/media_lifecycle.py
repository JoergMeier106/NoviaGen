from __future__ import annotations

import os
import shutil
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from ..records import utc_now_iso
from ...storage.files import remove_file_if_present


class MediaLifecyclePersistenceMixin:
    def update_image_poster(
        self,
        image_id: str,
        *,
        poster_path: str | None,
        poster_mime_type: str | None,
    ) -> dict[str, Any] | None:
        image = self.get_image(image_id)
        if image is None:
            return None

        stored_poster_path = self._move_artifact_file_to_stored(poster_path)
        previous_poster_path = image.get("poster_path")
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE images
                SET poster_path = ?, poster_mime_type = ?
                WHERE id = ?
                """,
                (
                    self._path_to_record_value(stored_poster_path),
                    poster_mime_type,
                    image_id,
                ),
            )

        if previous_poster_path and previous_poster_path != stored_poster_path:
            remove_file_if_present(Path(previous_poster_path))
        return self.get_image(image_id)

    def update_image_thumbnail(
        self,
        image_id: str,
        *,
        thumbnail_path: str | Path | None,
        thumbnail_mime_type: str | None,
    ) -> dict[str, Any] | None:
        image = self.get_image(image_id)
        if image is None:
            return None

        stored_thumbnail_path = self._move_artifact_file_to_stored(
            str(thumbnail_path) if thumbnail_path is not None else None
        )
        previous_thumbnail_path = image.get("thumbnail_path")
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE images
                SET thumbnail_path = ?, thumbnail_mime_type = ?
                WHERE id = ?
                """,
                (
                    self._path_to_record_value(stored_thumbnail_path),
                    thumbnail_mime_type,
                    image_id,
                ),
            )

        if (
            previous_thumbnail_path and
            previous_thumbnail_path != stored_thumbnail_path
        ):
            remove_file_if_present(Path(previous_thumbnail_path))
        return self.get_image(image_id)

    def store_image(self, image_id: str) -> dict[str, Any]:
        image = self.get_image(image_id)
        if image is None:
            raise KeyError(image_id)
        if image["status"] == "stored":
            return image

        source_path = Path(image["file_path"])
        destination_path = self.stored_dir / source_path.name
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(source_path), str(destination_path))
        poster_destination_path: Path | None = None
        thumbnail_destination_path: Path | None = None
        if image.get("poster_path"):
            poster_source_path = Path(image["poster_path"])
            poster_destination_path = self.stored_dir / poster_source_path.name
            shutil.copy2(str(poster_source_path), str(poster_destination_path))
        if image.get("thumbnail_path"):
            thumbnail_source_path = Path(image["thumbnail_path"])
            thumbnail_destination_path = self.stored_dir / thumbnail_source_path.name
            shutil.copy2(str(thumbnail_source_path), str(thumbnail_destination_path))
        try:
            os.remove(source_path)
        except PermissionError:
            pass
        if image.get("poster_path"):
            try:
                os.remove(Path(image["poster_path"]))
            except PermissionError:
                pass
        if image.get("thumbnail_path"):
            try:
                os.remove(Path(image["thumbnail_path"]))
            except PermissionError:
                pass

        stored_at = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE images
                SET status = 'stored', file_path = ?, poster_path = ?, thumbnail_path = ?, stored_at = ?
                WHERE id = ?
                """,
                (
                    self._path_to_record_value(destination_path),
                    self._path_to_record_value(poster_destination_path),
                    self._path_to_record_value(thumbnail_destination_path),
                    stored_at,
                    image_id,
                ),
            )
        if self._supports_thumbnail_generation(image.get("media_type")):
            self.ensure_image_thumbnail(image_id, force=True)
        updated = self.get_image(image_id)
        if updated is None:
            raise KeyError(image_id)
        return updated

    def _move_artifact_file_to_stored(self, path_value: str | None) -> str | None:
        if path_value is None:
            return None
        source_path = Path(path_value)
        destination_path = self.stored_dir / source_path.name
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        if source_path.resolve(strict=False) != destination_path.resolve(strict=False):
            shutil.move(str(source_path), str(destination_path))
        return str(destination_path)

    def cleanup_temp_images(
        self,
        ttl_seconds: int | None = None,
        *,
        keep_image_id: str | None = None,
    ) -> int:
        threshold = (
            datetime.now(UTC) - timedelta(seconds=ttl_seconds)
            if ttl_seconds is not None
            else None
        )
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, file_path, poster_path, thumbnail_path, created_at
                FROM images
                WHERE status = 'temp'
                ORDER BY created_at DESC, id DESC
                """
            ).fetchall()

        removed = 0
        keep_paths: set[Path] = set()
        keep_ids: set[str] = set()
        if rows:
            keep_ids.add(str(rows[0]["id"]))
        if keep_image_id is not None:
            keep_ids.add(keep_image_id)
        for row in rows:
            file_path = self._path_from_record_value(row["file_path"])
            if row["id"] in keep_ids:
                keep_paths.add(file_path)
                poster_path = row["poster_path"] if "poster_path" in row.keys() else None
                if poster_path:
                    keep_paths.add(self._path_from_record_value(poster_path))
                thumbnail_path = row["thumbnail_path"] if "thumbnail_path" in row.keys() else None
                if thumbnail_path:
                    keep_paths.add(self._path_from_record_value(thumbnail_path))
                continue
            created_at = datetime.fromisoformat(row["created_at"])
            if threshold is not None and created_at >= threshold:
                continue
            remove_file_if_present(file_path)
            poster_path = row["poster_path"] if "poster_path" in row.keys() else None
            if poster_path:
                remove_file_if_present(self._path_from_record_value(poster_path))
            thumbnail_path = row["thumbnail_path"] if "thumbnail_path" in row.keys() else None
            if thumbnail_path:
                remove_file_if_present(self._path_from_record_value(thumbnail_path))
            with self._write_lock(), self._connect() as conn:
                conn.execute("DELETE FROM images WHERE id = ?", (row["id"],))
            removed += 1

        self._cleanup_temp_directory(keep_paths=keep_paths)
        return removed

    def cleanup_all_temp_images(self) -> int:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, file_path, poster_path, thumbnail_path
                FROM images
                WHERE status = 'temp'
                """
            ).fetchall()
            conn.execute("DELETE FROM images WHERE status = 'temp'")

        for row in rows:
            remove_file_if_present(self._path_from_record_value(row["file_path"]))
            if row["poster_path"]:
                remove_file_if_present(self._path_from_record_value(row["poster_path"]))
            if row["thumbnail_path"]:
                remove_file_if_present(self._path_from_record_value(row["thumbnail_path"]))

        self._cleanup_temp_directory(keep_paths=set())
        return len(rows)

    def cleanup_non_stored_images(self) -> int:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, file_path, poster_path, thumbnail_path
                FROM images
                WHERE status NOT IN ('stored', 'temp', 'deleted')
                """
            ).fetchall()
            conn.execute(
                "DELETE FROM images WHERE status NOT IN ('stored', 'temp', 'deleted')"
            )

        for row in rows:
            remove_file_if_present(self._path_from_record_value(row["file_path"]))
            if row["poster_path"]:
                remove_file_if_present(
                    self._path_from_record_value(row["poster_path"])
                )
            if row["thumbnail_path"]:
                remove_file_if_present(
                    self._path_from_record_value(row["thumbnail_path"])
                )

        return len(rows)

    def cleanup_deleted_images(self, retention_days: int = 5) -> int:
        threshold = datetime.now(UTC) - timedelta(days=retention_days)
        threshold_iso = threshold.isoformat()
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, file_path, poster_path, thumbnail_path
                FROM images
                WHERE status = 'deleted'
                  AND deleted_at IS NOT NULL
                  AND deleted_at <= ?
                """,
                (threshold_iso,),
            ).fetchall()
            conn.execute(
                """
                DELETE FROM images
                WHERE status = 'deleted'
                  AND deleted_at IS NOT NULL
                  AND deleted_at <= ?
                """,
                (threshold_iso,),
            )

        for row in rows:
            remove_file_if_present(self._path_from_record_value(row["file_path"]))
            if row["poster_path"]:
                remove_file_if_present(
                    self._path_from_record_value(row["poster_path"])
                )
            if row["thumbnail_path"]:
                remove_file_if_present(
                    self._path_from_record_value(row["thumbnail_path"])
                )

        return len(rows)

    def delete_image(self, image_id: str) -> bool:
        image = self.get_image(image_id)
        if image is None:
            return False

        if image.get("status") == "stored":
            now = utc_now_iso()
            with self._write_lock(), self._connect() as conn:
                conn.execute(
                    """
                    UPDATE images
                    SET status = 'deleted', deleted_at = ?
                    WHERE id = ? AND status = 'stored'
                    """,
                    (now, image_id),
                )
            return True

        if image.get("status") == "deleted":
            return True

        file_path = Path(image["file_path"])
        remove_file_if_present(file_path)
        if image.get("poster_path"):
            remove_file_if_present(Path(image["poster_path"]))
        if image.get("thumbnail_path"):
            remove_file_if_present(Path(image["thumbnail_path"]))

        with self._write_lock(), self._connect() as conn:
            conn.execute("DELETE FROM images WHERE id = ?", (image_id,))
        return True

    def restore_image(self, image_id: str) -> dict[str, Any] | None:
        image = self.get_image(image_id)
        if image is None or image.get("status") != "deleted":
            return None

        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE images
                SET status = 'stored',
                    deleted_at = NULL,
                    stored_at = COALESCE(stored_at, ?)
                WHERE id = ? AND status = 'deleted'
                """,
                (utc_now_iso(), image_id),
            )
        return self.get_image(image_id)
