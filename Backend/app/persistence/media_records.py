from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ..generation import GeneratedArtifact
from ..storage.files import remove_file_if_present
from .records import derive_image_orientation, utc_now_iso


class MediaRecordPersistenceMixin:
    def create_image(self, artifact: GeneratedArtifact) -> None:
        now = utc_now_iso()
        stored_file_path = self._move_artifact_file_to_stored(artifact.file_path)
        stored_poster_path = self._move_artifact_file_to_stored(artifact.poster_path)
        thumbnail_path: Path | None = None
        thumbnail_mime_type: str | None = None
        if self._supports_thumbnail_generation(artifact.media_type):
            thumbnail_path = self._thumbnail_path_for_image(artifact.image_id)
            thumbnail_mime_type = "image/png"
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO images (
                    id, status, media_type, file_name, file_path, mime_type, poster_path,
                    poster_mime_type, thumbnail_path, thumbnail_mime_type, width, height, prompt,
                    default_positive_prompt, default_negative_prompt, final_positive_prompt,
                    model_id, loras_json, tags_json, num_inference_steps, guidance_scale,
                    image_orientation, source_image_id, scale_factor, is_upscaled,
                    duration_seconds, generation_duration_seconds, fps, num_frames, loop_video, created_at, stored_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    artifact.image_id,
                    "stored",
                    artifact.media_type,
                    Path(stored_file_path).name,
                    self._path_to_record_value(stored_file_path),
                    artifact.mime_type,
                    self._path_to_record_value(stored_poster_path),
                    artifact.poster_mime_type,
                    self._path_to_record_value(thumbnail_path),
                    thumbnail_mime_type,
                    artifact.width,
                    artifact.height,
                    artifact.prompt,
                    artifact.default_positive_prompt,
                    artifact.default_negative_prompt,
                    artifact.final_positive_prompt,
                    artifact.model_id,
                    json.dumps(artifact.loras),
                    json.dumps([]),
                    artifact.num_inference_steps,
                    artifact.guidance_scale,
                    derive_image_orientation(
                        artifact.width,
                        artifact.height,
                        fallback=artifact.image_orientation,
                    ),
                    artifact.source_image_id,
                    artifact.scale_factor,
                    1 if artifact.is_upscaled else 0,
                    artifact.duration_seconds,
                    artifact.generation_duration_seconds,
                    artifact.fps,
                    artifact.num_frames,
                    1 if artifact.loop_video else 0,
                    now,
                    now,
                ),
            )
        if self._supports_thumbnail_generation(artifact.media_type):
            self.ensure_image_thumbnail(artifact.image_id, force=True)

    def create_imported_image(
        self,
        *,
        image_id: str,
        file_path: str | Path,
        original_filename: str,
        mime_type: str,
        width: int,
        height: int,
        prompt: str = "",
        default_positive_prompt: str = "",
        default_negative_prompt: str = "",
        final_positive_prompt: str = "",
        num_inference_steps: int = 40,
        guidance_scale: float = 5.0,
        image_orientation: str = "landscape",
    ) -> dict[str, Any]:
        source_path = Path(file_path)
        suffix = Path(original_filename).suffix or source_path.suffix
        if suffix and source_path.suffix.lower() != suffix.lower():
            renamed_path = source_path.with_name(f"{source_path.stem}{suffix}")
            if renamed_path != source_path:
                source_path = source_path.rename(renamed_path)
        stored_file_path = self._move_artifact_file_to_stored(str(source_path))
        thumbnail_path: Path | None = None
        thumbnail_mime_type: str | None = None
        if self._supports_thumbnail_generation("image"):
            thumbnail_path = self._thumbnail_path_for_image(image_id)
            thumbnail_mime_type = "image/png"
        now = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO images (
                    id, status, media_type, file_name, file_path, mime_type, poster_path,
                    poster_mime_type, thumbnail_path, thumbnail_mime_type, width, height, prompt,
                    default_positive_prompt, default_negative_prompt, final_positive_prompt,
                    model_id, loras_json, tags_json, num_inference_steps, guidance_scale,
                    image_orientation, source_image_id, scale_factor, is_upscaled,
                    duration_seconds, generation_duration_seconds, fps, num_frames, loop_video, created_at, stored_at
                )
                VALUES (?, 'stored', 'image', ?, ?, ?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, 'Imported', '[]', '[]', ?, ?, ?, NULL, NULL, 0, NULL, NULL, NULL, NULL, 0, ?, ?)
                """,
                (
                    image_id,
                    original_filename,
                    self._path_to_record_value(stored_file_path),
                    mime_type,
                    self._path_to_record_value(thumbnail_path),
                    thumbnail_mime_type,
                    width,
                    height,
                    prompt,
                    default_positive_prompt,
                    default_negative_prompt,
                    final_positive_prompt,
                    num_inference_steps,
                    guidance_scale,
                    derive_image_orientation(width, height, fallback=image_orientation),
                    now,
                    now,
                ),
            )
        self.ensure_image_thumbnail(image_id, force=True)
        created = self.get_image(image_id)
        if created is None:
            raise KeyError(image_id)
        return created

    def create_image_placeholder(
        self,
        *,
        image_id: str,
        status: str,
        media_type: str,
        mime_type: str,
        width: int,
        height: int,
        prompt: str,
        default_positive_prompt: str,
        default_negative_prompt: str,
        final_positive_prompt: str,
        model_id: str,
        loras: list[dict[str, Any]],
        num_inference_steps: int,
        guidance_scale: float,
        image_orientation: str,
        source_image_id: str | None = None,
        scale_factor: float | None = None,
        is_upscaled: bool = False,
        duration_seconds: float | None = None,
        fps: int | None = None,
        num_frames: int | None = None,
        loop_video: bool = False,
        file_extension: str | None = None,
        poster_extension: str | None = None,
    ) -> None:
        now = utc_now_iso()
        normalized_media_type = self._normalize_media_type(media_type, mime_type)
        normalized_extension = self._normalize_media_extension(
            media_type=normalized_media_type,
            mime_type=mime_type,
            extension=file_extension,
        )
        reserved_file_name = f"{image_id}{normalized_extension}"
        reserved_file_path = self.stored_dir / reserved_file_name
        reserved_poster_path: Path | None = None
        normalized_poster_mime_type: str | None = None
        if normalized_media_type == "video":
            normalized_poster_extension = self._normalize_poster_extension(poster_extension)
            reserved_poster_path = self.stored_dir / f"{image_id}_poster{normalized_poster_extension}"
            normalized_poster_mime_type = self._mime_type_for_extension(
                normalized_poster_extension,
                fallback="image/png",
            )

        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                INSERT INTO images (
                    id, status, media_type, file_name, file_path, mime_type, poster_path,
                    poster_mime_type, thumbnail_path, thumbnail_mime_type, width, height, prompt,
                    default_positive_prompt, default_negative_prompt, final_positive_prompt,
                    model_id, loras_json, tags_json, num_inference_steps, guidance_scale,
                    image_orientation, source_image_id, scale_factor, is_upscaled,
                    duration_seconds, generation_duration_seconds, fps, num_frames, loop_video, created_at, stored_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    image_id,
                    status,
                    normalized_media_type,
                    reserved_file_name,
                    self._path_to_record_value(reserved_file_path),
                    mime_type,
                    self._path_to_record_value(reserved_poster_path),
                    normalized_poster_mime_type,
                    None,
                    None,
                    width,
                    height,
                    prompt,
                    default_positive_prompt,
                    default_negative_prompt,
                    final_positive_prompt,
                    model_id,
                    json.dumps(loras),
                    json.dumps([]),
                    num_inference_steps,
                    guidance_scale,
                    derive_image_orientation(width, height, fallback=image_orientation),
                    source_image_id,
                    scale_factor,
                    1 if is_upscaled else 0,
                    duration_seconds,
                    None,
                    fps,
                    num_frames,
                    1 if loop_video else 0,
                    now,
                    None,
                ),
            )

    def update_image_status(self, image_id: str, status: str) -> dict[str, Any] | None:
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                "UPDATE images SET status = ? WHERE id = ?",
                (status, image_id),
            )
        return self.get_image(image_id)

    def finalize_image_placeholder(
        self,
        image_id: str,
        artifact: GeneratedArtifact,
    ) -> dict[str, Any] | None:
        image = self.get_image(image_id)
        if image is None:
            return None

        target_file_path = Path(image["file_path"])
        target_file_path.parent.mkdir(parents=True, exist_ok=True)
        self._replace_file(target_file_path, Path(artifact.file_path))

        target_poster_path: Path | None = None
        existing_poster_path = image.get("poster_path")
        if existing_poster_path:
            target_poster_path = Path(existing_poster_path)
        elif artifact.poster_path:
            target_poster_path = self.stored_dir / Path(artifact.poster_path).name

        if artifact.poster_path and target_poster_path is not None:
            target_poster_path.parent.mkdir(parents=True, exist_ok=True)
            self._replace_file(target_poster_path, Path(artifact.poster_path))
        elif target_poster_path is not None and not target_poster_path.exists():
            target_poster_path = target_poster_path

        thumbnail_path = image.get("thumbnail_path")
        stored_thumbnail_path = (
            self._thumbnail_path_for_image(image_id)
            if self._supports_thumbnail_generation(artifact.media_type)
            else None
        )
        if thumbnail_path and stored_thumbnail_path is None:
            remove_file_if_present(Path(thumbnail_path))

        stored_at = utc_now_iso()
        with self._write_lock(), self._connect() as conn:
            conn.execute(
                """
                UPDATE images
                SET status = 'stored',
                    file_name = ?,
                    file_path = ?,
                    mime_type = ?,
                    poster_path = ?,
                    poster_mime_type = ?,
                    thumbnail_path = ?,
                    thumbnail_mime_type = ?,
                    width = ?,
                    height = ?,
                    prompt = ?,
                    default_positive_prompt = ?,
                    default_negative_prompt = ?,
                    final_positive_prompt = ?,
                    model_id = ?,
                    loras_json = ?,
                    num_inference_steps = ?,
                    guidance_scale = ?,
                    image_orientation = ?,
                    source_image_id = ?,
                    scale_factor = ?,
                    is_upscaled = ?,
                    duration_seconds = ?,
                    generation_duration_seconds = ?,
                    fps = ?,
                    num_frames = ?,
                    loop_video = ?,
                    stored_at = ?
                WHERE id = ?
                """,
                (
                    target_file_path.name,
                    self._path_to_record_value(target_file_path),
                    artifact.mime_type,
                    self._path_to_record_value(target_poster_path),
                    artifact.poster_mime_type,
                    self._path_to_record_value(stored_thumbnail_path),
                    "image/png" if stored_thumbnail_path is not None else None,
                    artifact.width,
                    artifact.height,
                    artifact.prompt,
                    artifact.default_positive_prompt,
                    artifact.default_negative_prompt,
                    artifact.final_positive_prompt,
                    artifact.model_id,
                    json.dumps(artifact.loras),
                    artifact.num_inference_steps,
                    artifact.guidance_scale,
                    derive_image_orientation(
                        artifact.width,
                        artifact.height,
                        fallback=artifact.image_orientation,
                    ),
                    artifact.source_image_id,
                    artifact.scale_factor,
                    1 if artifact.is_upscaled else 0,
                    artifact.duration_seconds,
                    artifact.generation_duration_seconds,
                    artifact.fps,
                    artifact.num_frames,
                    1 if artifact.loop_video else 0,
                    stored_at,
                    image_id,
                ),
            )
        if self._supports_thumbnail_generation(artifact.media_type):
            self.ensure_image_thumbnail(image_id, force=True)
        return self.get_image(image_id)
