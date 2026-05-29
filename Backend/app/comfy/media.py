from __future__ import annotations

import logging
import mimetypes
from pathlib import Path

from PIL import Image, ImageDraw

logger = logging.getLogger(__name__)


class ComfyMediaMixin:
    def create_video_poster(
        self,
        *,
        video_path: Path,
        output_dir: Path,
        image_id: str,
        fallback_source_image_path: Path | None = None,
        width: int | None = None,
        height: int | None = None,
    ) -> tuple[Path | None, str | None]:
        poster_path, _poster_size = self._extract_video_poster(
            video_path,
            output_dir,
            image_id,
        )
        if poster_path is not None:
            return poster_path, "image/png"
        if fallback_source_image_path is None:
            poster_path = self._create_default_video_poster(
                output_dir=output_dir,
                image_id=image_id,
                width=width,
                height=height,
            )
            return poster_path, "image/png"
        try:
            with Image.open(fallback_source_image_path) as source_image:
                poster = source_image.convert("RGB")
                if width and height:
                    poster.thumbnail((width, height))
                poster_path = output_dir / f"{image_id}_poster.png"
                poster.save(poster_path)
                return poster_path, "image/png"
        except Exception:
            logger.warning("Failed to build fallback video poster", exc_info=True)
            return None, None

    @staticmethod
    def _output_path_for_download(output_dir: Path, image_id: str, file_info: dict) -> Path:
        filename = str(file_info.get("filename") or "")
        suffix = Path(filename).suffix or ".mp4"
        return output_dir / f"{image_id}{suffix}"

    @staticmethod
    def _probe_video_metadata(path: Path) -> dict[str, int | float] | None:
        try:
            import imageio_ffmpeg

            reader = imageio_ffmpeg.read_frames(str(path))
            meta = next(reader)
            size = meta.get("size") or ()
            width = int(size[0]) if len(size) >= 2 else None
            height = int(size[1]) if len(size) >= 2 else None

            fps_raw = meta.get("fps")
            fps = (
                max(1, int(round(float(fps_raw))))
                if isinstance(fps_raw, (int, float)) and float(fps_raw) > 0
                else None
            )

            duration_raw = meta.get("duration")
            duration_seconds = (
                float(duration_raw)
                if isinstance(duration_raw, (int, float)) and float(duration_raw) > 0
                else None
            )

            num_frames = None
            try:
                counted_frames, counted_duration = imageio_ffmpeg.count_frames_and_secs(
                    str(path)
                )
                num_frames = max(1, int(counted_frames))
                if duration_seconds is None and counted_duration > 0:
                    duration_seconds = float(counted_duration)
            except Exception:
                pass

            if fps is None and num_frames is not None and duration_seconds:
                fps = max(1, int(round(float(num_frames) / float(duration_seconds))))
            if duration_seconds is None and fps is not None and num_frames is not None:
                duration_seconds = float(num_frames) / float(fps)

            result: dict[str, int | float] = {}
            if width is not None:
                result["width"] = width
            if height is not None:
                result["height"] = height
            if fps is not None:
                result["fps"] = fps
            if num_frames is not None:
                result["num_frames"] = num_frames
            if duration_seconds is not None:
                result["duration_seconds"] = duration_seconds
            return result or None
        except Exception:
            logger.warning("Failed to probe output video metadata for %s", path, exc_info=True)
            return None

    @staticmethod
    def _mime_type_for_path(path: Path) -> str:
        return mimetypes.guess_type(str(path))[0] or "application/octet-stream"

    @staticmethod
    def _extract_video_poster(
        saved_path: Path,
        output_dir: Path,
        image_id: str,
    ) -> tuple[Path | None, tuple[int, int] | None]:
        try:
            import imageio.v3 as iio

            frame = iio.imread(saved_path, index=0)
            poster = Image.fromarray(frame).convert("RGB")
            poster_path = output_dir / f"{image_id}_poster.png"
            poster.save(poster_path)
            return poster_path, poster.size
        except Exception:
            logger.warning("Failed to extract video poster", exc_info=True)
            return None, None

    @staticmethod
    def _create_default_video_poster(
        *,
        output_dir: Path,
        image_id: str,
        width: int | None,
        height: int | None,
    ) -> Path:
        poster_width = min(max(int(width or 640), 320), 1280)
        poster_height = min(max(int(height or 360), 180), 1280)
        poster = Image.new("RGB", (poster_width, poster_height), color=(18, 24, 33))
        draw = ImageDraw.Draw(poster)

        max_index = max(poster_height - 1, 1)
        for y in range(poster_height):
            blend = y / max_index
            color = (
                int(22 + (44 * blend)),
                int(34 + (58 * blend)),
                int(48 + (84 * blend)),
            )
            draw.line((0, y, poster_width, y), fill=color)

        icon_size = min(poster_width, poster_height) * 0.22
        center_x = poster_width / 2
        center_y = poster_height / 2
        triangle = [
            (center_x - icon_size * 0.35, center_y - icon_size * 0.55),
            (center_x - icon_size * 0.35, center_y + icon_size * 0.55),
            (center_x + icon_size * 0.65, center_y),
        ]
        draw.rounded_rectangle(
            (
                center_x - icon_size * 0.95,
                center_y - icon_size * 0.95,
                center_x + icon_size * 0.95,
                center_y + icon_size * 0.95,
            ),
            radius=24,
            fill=None,
            outline=(220, 232, 244),
            width=max(2, int(icon_size * 0.08)),
        )
        draw.polygon(triangle, fill=(236, 241, 247))

        poster_path = output_dir / f"{image_id}_poster.png"
        poster.save(poster_path)
        return poster_path
