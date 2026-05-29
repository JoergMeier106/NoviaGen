from __future__ import annotations

import json
from typing import Any

from ..records import normalize_tags


class GalleryPersistenceMixin:
    def get_image(self, image_id: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute("SELECT * FROM images WHERE id = ?", (image_id,)).fetchone()
        return self._decode_media_row(row) if row else None

    def get_latest_temp_image(self) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            row = conn.execute(
                """
                SELECT * FROM images
                WHERE status = 'temp'
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """
            ).fetchone()
        return self._decode_media_row(row) if row else None

    def list_stored_images(self, page: int, page_size: int) -> dict[str, Any]:
        offset = (page - 1) * page_size
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM images
                WHERE status = 'stored'
                ORDER BY stored_at DESC, created_at DESC
                LIMIT ? OFFSET ?
                """,
                (page_size, offset),
            ).fetchall()
            total = conn.execute(
                "SELECT COUNT(*) AS total FROM images WHERE status = 'stored'"
            ).fetchone()["total"]

        items = [self._decode_media_row(row) for row in rows]
        return {
            "items": items,
            "page": page,
            "page_size": page_size,
            "total": total,
            "has_more": offset + len(items) < total,
        }

    def list_gallery_images(
        self,
        page: int,
        page_size: int,
        *,
        search: str = "",
        media_type: str | None = None,
        model_id: str | None = None,
        include_tags: list[str] | None = None,
        exclude_tags: list[str] | None = None,
        min_rating: int = 0,
        sort: str = "newest",
        include_deleted: bool = False,
        include_placeholders: bool = True,
    ) -> dict[str, Any]:
        offset = (page - 1) * page_size
        where_clauses = ["status != 'temp'"]
        where_clauses.append("status = 'deleted'" if include_deleted else "status != 'deleted'")
        if not include_placeholders:
            where_clauses.append("status NOT IN ('queued', 'running')")
        params: list[Any] = []

        normalized_search = search.strip().lower()
        if normalized_search:
            like_query = f"%{normalized_search}%"
            where_clauses.append(
                """
                (
                    lower(prompt) LIKE ?
                    OR lower(final_positive_prompt) LIKE ?
                    OR lower(caption) LIKE ?
                    OR lower(model_id) LIKE ?
                )
                """.strip()
            )
            params.extend([like_query, like_query, like_query, like_query])

        normalized_media_type = self._normalize_gallery_media_type_filter(media_type)
        if normalized_media_type is not None:
            where_clauses.append("media_type = ?")
            params.append(normalized_media_type)

        normalized_model_id = str(model_id or "").strip()
        if normalized_model_id and normalized_model_id != "All models":
            where_clauses.append("model_id = ?")
            params.append(normalized_model_id)

        for tag in normalize_tags(include_tags or []):
            where_clauses.append("lower(tags_json) LIKE ?")
            params.append(f'%"{tag.lower()}"%')

        for tag in normalize_tags(exclude_tags or []):
            where_clauses.append("lower(tags_json) NOT LIKE ?")
            params.append(f'%"{tag.lower()}"%')

        if min_rating > 0:
            where_clauses.append("rating >= ?")
            params.append(min_rating)

        order_clause = self._gallery_order_clause(sort)
        where_sql = " AND ".join(where_clauses)
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT *
                FROM images
                WHERE {where_sql}
                ORDER BY {order_clause}
                LIMIT ? OFFSET ?
                """,
                (*params, page_size, offset),
            ).fetchall()
            total = conn.execute(
                f"SELECT COUNT(*) AS total FROM images WHERE {where_sql}",
                tuple(params),
            ).fetchone()["total"]

        items = [self._decode_media_row(row) for row in rows]
        return {
            "items": items,
            "page": page,
            "page_size": page_size,
            "total": total,
            "has_more": offset + len(items) < total,
        }

    def list_gallery_filters(self, *, include_deleted: bool = False) -> dict[str, list[str]]:
        where_sql = (
            "status = 'deleted'" if include_deleted else "status != 'temp' AND status != 'deleted'"
        )
        with self._write_lock(), self._connect() as conn:
            model_rows = conn.execute(
                f"""
                SELECT DISTINCT model_id
                FROM images
                WHERE {where_sql}
                ORDER BY lower(model_id), model_id
                """
            ).fetchall()
        return {
            "models": [str(row["model_id"]) for row in model_rows if str(row["model_id"]).strip()],
            "tags": self.list_tags(include_deleted=include_deleted),
        }

    def set_image_rating(self, image_id: str, rating: int) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            conn.execute("UPDATE images SET rating = ? WHERE id = ?", (rating, image_id))
        return self.get_image(image_id)

    def set_image_tags(self, image_id: str, tags: list[str]) -> dict[str, Any] | None:
        normalized_tags = normalize_tags(tags)
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                "UPDATE images SET tags_json = ? WHERE id = ?",
                (json.dumps(normalized_tags), image_id),
            )
        return self.get_image(image_id)

    def set_image_caption_and_tags(
        self,
        image_id: str,
        *,
        caption: str,
        tags: list[str],
    ) -> dict[str, Any] | None:
        normalized_tags = normalize_tags(tags)
        normalized_caption = str(caption or "").strip()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                "UPDATE images SET caption = ?, tags_json = ? WHERE id = ?",
                (normalized_caption, json.dumps(normalized_tags), image_id),
            )
        return self.get_image(image_id)

    def list_tags(self, *, include_deleted: bool = False) -> list[str]:
        where_sql = (
            "status = 'deleted'" if include_deleted else "status != 'temp' AND status != 'deleted'"
        )
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                f"SELECT tags_json FROM images WHERE {where_sql}"
            ).fetchall()

        tags: list[str] = []
        for row in rows:
            try:
                decoded = json.loads(row["tags_json"])
            except (TypeError, ValueError, json.JSONDecodeError):
                decoded = []
            if isinstance(decoded, list):
                tags.extend(str(item) for item in decoded)
        return sorted(normalize_tags(tags), key=str.lower)

    def delete_tag(self, tag: str) -> int:
        normalized_target = tag.strip().lower()
        if not normalized_target:
            return 0

        updated_count = 0
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute("SELECT id, tags_json FROM images").fetchall()
            for row in rows:
                try:
                    decoded = json.loads(row["tags_json"])
                except (TypeError, ValueError, json.JSONDecodeError):
                    decoded = []
                if not isinstance(decoded, list):
                    continue
                filtered = [
                    str(item).strip()
                    for item in decoded
                    if str(item).strip().lower() != normalized_target
                ]
                normalized_filtered = normalize_tags(filtered)
                if normalized_filtered == normalize_tags(
                    [str(item).strip() for item in decoded]
                ):
                    continue
                conn.execute(
                    "UPDATE images SET tags_json = ? WHERE id = ?",
                    (json.dumps(normalized_filtered), row["id"]),
                )
                updated_count += 1
        return updated_count

    def _normalize_gallery_media_type_filter(self, media_type: str | None) -> str | None:
        normalized = str(media_type or "").strip().lower()
        if normalized in {"", "all"}:
            return None
        if normalized == "images":
            return "image"
        if normalized == "gifs":
            return "gif"
        if normalized == "videos":
            return "video"
        if normalized in {"image", "gif", "video"}:
            return normalized
        return None

    @staticmethod
    def _gallery_order_clause(sort: str | None) -> str:
        normalized = str(sort or "newest").strip()
        if normalized == "oldest":
            return "created_at ASC, id ASC"
        if normalized == "ratingHigh":
            return "rating DESC, created_at DESC, id DESC"
        if normalized == "ratingLow":
            return "rating ASC, created_at DESC, id DESC"
        if normalized == "resolutionHigh":
            return "(width * height) DESC, created_at DESC, id DESC"
        if normalized == "durationHigh":
            return "COALESCE(duration_seconds, 0) DESC, created_at DESC, id DESC"
        if normalized == "durationLow":
            return "COALESCE(duration_seconds, 0) ASC, created_at DESC, id DESC"
        if normalized == "generationDurationHigh":
            return (
                "COALESCE(generation_duration_seconds, 0) DESC, "
                "created_at DESC, id DESC"
            )
        if normalized == "generationDurationLow":
            return (
                "COALESCE(generation_duration_seconds, 0) ASC, "
                "created_at DESC, id DESC"
            )
        return "created_at DESC, id DESC"
