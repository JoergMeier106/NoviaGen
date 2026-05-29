from __future__ import annotations

import json
from typing import Any

from .records import (
    remap_job_payload_json as _remap_job_payload_json,
    remap_loras_json as _remap_loras_json,
)


class AssetPersistenceMixin:
    def remap_asset_ids(
        self,
        *,
        model_id_map: dict[str, str],
        lora_id_map: dict[str, str],
    ) -> None:
        if not model_id_map and not lora_id_map:
            return

        with self._write_lock(), self._connect() as conn:
            image_rows = conn.execute(
                "SELECT id, model_id, loras_json FROM images"
            ).fetchall()
            for row in image_rows:
                remapped_model_id = model_id_map.get(row["model_id"], row["model_id"])
                remapped_loras_json = _remap_loras_json(row["loras_json"], lora_id_map)
                conn.execute(
                    "UPDATE images SET model_id = ?, loras_json = ? WHERE id = ?",
                    (remapped_model_id, remapped_loras_json, row["id"]),
                )

            job_rows = conn.execute("SELECT id, payload_json FROM jobs").fetchall()
            for row in job_rows:
                remapped_payload_json = _remap_job_payload_json(
                    row["payload_json"],
                    model_id_map=model_id_map,
                    lora_id_map=lora_id_map,
                )
                conn.execute(
                    "UPDATE jobs SET payload_json = ? WHERE id = ?",
                    (remapped_payload_json, row["id"]),
                )

            asset_rows = conn.execute(
                "SELECT asset_type, asset_id, rating FROM asset_ratings"
            ).fetchall()
            for row in asset_rows:
                remapped_asset_id = row["asset_id"]
                if row["asset_type"] == "model":
                    remapped_asset_id = model_id_map.get(row["asset_id"], row["asset_id"])
                elif row["asset_type"] == "lora":
                    remapped_asset_id = lora_id_map.get(row["asset_id"], row["asset_id"])
                if remapped_asset_id == row["asset_id"]:
                    continue
                conn.execute(
                    """
                    INSERT INTO asset_ratings (asset_type, asset_id, rating)
                    VALUES (?, ?, ?)
                    ON CONFLICT(asset_type, asset_id) DO UPDATE SET rating = excluded.rating
                    """,
                    (row["asset_type"], remapped_asset_id, row["rating"]),
                )
                conn.execute(
                    "DELETE FROM asset_ratings WHERE asset_type = ? AND asset_id = ?",
                    (row["asset_type"], row["asset_id"]),
                )

            deleted_asset_rows = conn.execute(
                "SELECT asset_type, asset_id FROM deleted_assets"
            ).fetchall()
            for row in deleted_asset_rows:
                remapped_asset_id = row["asset_id"]
                if row["asset_type"] == "model":
                    remapped_asset_id = model_id_map.get(row["asset_id"], row["asset_id"])
                elif row["asset_type"] == "lora":
                    remapped_asset_id = lora_id_map.get(row["asset_id"], row["asset_id"])
                if remapped_asset_id == row["asset_id"]:
                    continue
                conn.execute(
                    """
                    INSERT INTO deleted_assets (asset_type, asset_id)
                    VALUES (?, ?)
                    ON CONFLICT(asset_type, asset_id) DO NOTHING
                    """,
                    (row["asset_type"], remapped_asset_id),
                )
                conn.execute(
                    "DELETE FROM deleted_assets WHERE asset_type = ? AND asset_id = ?",
                    (row["asset_type"], row["asset_id"]),
                )

    def list_asset_rating_stats(self, asset_type: str) -> dict[str, dict[str, float | int]]:
        normalized_type = str(asset_type).strip().lower()
        if normalized_type not in {"model", "lora"}:
            return {}

        with self._write_lock(), self._connect() as conn:
            if normalized_type == "model":
                rows = conn.execute(
                    """
                    SELECT model_id AS asset_id, AVG(rating) AS mean_rating, COUNT(*) AS rating_count
                    FROM images
                    WHERE status = 'stored' AND rating > 0 AND trim(model_id) != ''
                    GROUP BY model_id
                    """
                ).fetchall()
                return {
                    str(row["asset_id"]): {
                        "rating": round(float(row["mean_rating"] or 0.0), 2),
                        "rating_count": int(row["rating_count"] or 0),
                    }
                    for row in rows
                    if str(row["asset_id"] or "").strip()
                }

            rows = conn.execute(
                """
                SELECT loras_json, rating
                FROM images
                WHERE status = 'stored' AND rating > 0 AND trim(loras_json) != ''
                """
            ).fetchall()

        totals: dict[str, float] = {}
        counts: dict[str, int] = {}
        for row in rows:
            raw_loras = row["loras_json"]
            try:
                decoded = json.loads(raw_loras)
            except (TypeError, ValueError, json.JSONDecodeError):
                decoded = []
            if not isinstance(decoded, list):
                continue
            rating_value = float(row["rating"] or 0.0)
            if rating_value <= 0:
                continue
            seen_ids: set[str] = set()
            for item in decoded:
                if not isinstance(item, dict):
                    continue
                lora_id = str(item.get("lora_id") or "").strip()
                if not lora_id or lora_id in seen_ids:
                    continue
                seen_ids.add(lora_id)
                totals[lora_id] = totals.get(lora_id, 0.0) + rating_value
                counts[lora_id] = counts.get(lora_id, 0) + 1

        return {
            asset_id: {
                "rating": round(totals[asset_id] / counts[asset_id], 2),
                "rating_count": counts[asset_id],
            }
            for asset_id in totals
            if counts.get(asset_id, 0) > 0
        }

    def set_asset_rating(
        self,
        *,
        asset_type: str,
        asset_id: str,
        rating: int,
    ) -> int:
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO asset_ratings (asset_type, asset_id, rating)
                VALUES (?, ?, ?)
                ON CONFLICT(asset_type, asset_id) DO UPDATE SET rating = excluded.rating
                """,
                (asset_type, asset_id, rating),
            )
        return rating

    def delete_asset_rating(self, *, asset_type: str, asset_id: str) -> None:
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                "DELETE FROM asset_ratings WHERE asset_type = ? AND asset_id = ?",
                (asset_type, asset_id),
            )

    def list_deleted_asset_ids(self, asset_type: str) -> set[str]:
        with self._write_lock(), self._connect() as conn:
            rows = conn.execute(
                "SELECT asset_id FROM deleted_assets WHERE asset_type = ?",
                (asset_type,),
            ).fetchall()
        return {str(row["asset_id"]) for row in rows}

    def mark_asset_deleted(self, *, asset_type: str, asset_id: str) -> None:
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO deleted_assets (asset_type, asset_id)
                VALUES (?, ?)
                ON CONFLICT(asset_type, asset_id) DO NOTHING
                """,
                (asset_type, asset_id),
            )
