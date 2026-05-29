from __future__ import annotations

import mimetypes
import re
import uuid
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps, UnidentifiedImageError

from ...generation import DEFAULT_GUIDANCE_SCALE, DEFAULT_NUM_INFERENCE_STEPS


class UploadedImageImporter:
    def __init__(self, *, db: Any, temp_dir: str | Path) -> None:
        self._db = db
        self._temp_dir = Path(temp_dir)

    def import_upload(self, uploaded_file: Any) -> dict[str, Any]:
        if uploaded_file is None or not uploaded_file.filename:
            raise ValueError("image file is required")

        original_filename = Path(uploaded_file.filename).name or "image"
        upload_path = self._save_upload(uploaded_file, original_filename)
        try:
            metadata = self._read_image_metadata(uploaded_file, upload_path, original_filename)
        except UnidentifiedImageError as exc:
            upload_path.unlink(missing_ok=True)
            raise ValueError("Only readable image files can be imported.") from exc
        except Exception:
            upload_path.unlink(missing_ok=True)
            raise

        return self._db.create_imported_image(
            image_id=str(uuid.uuid4()),
            file_path=upload_path,
            original_filename=original_filename,
            mime_type=metadata["mime_type"],
            width=metadata["width"],
            height=metadata["height"],
            prompt="",
            default_positive_prompt=metadata["positive_prompt"],
            default_negative_prompt=metadata["negative_prompt"],
            final_positive_prompt=metadata["final_positive_prompt"],
            num_inference_steps=metadata["num_inference_steps"],
            guidance_scale=metadata["guidance_scale"],
        )

    def _save_upload(self, uploaded_file: Any, original_filename: str) -> Path:
        uploads_dir = self._temp_dir / "imports"
        uploads_dir.mkdir(parents=True, exist_ok=True)
        suffix = Path(original_filename).suffix or ".png"
        upload_path = uploads_dir / f"{uuid.uuid4()}{suffix}"
        uploaded_file.save(upload_path)
        return upload_path

    def _read_image_metadata(
        self,
        uploaded_file: Any,
        upload_path: Path,
        original_filename: str,
    ) -> dict[str, Any]:
        with Image.open(upload_path) as source_image:
            normalized = ImageOps.exif_transpose(source_image)
            width, height = normalized.size
            mime_type = (
                str(getattr(uploaded_file, "mimetype", "") or "").strip()
                or Image.MIME.get(source_image.format or "", "")
                or mimetypes.guess_type(original_filename)[0]
                or "image/png"
            )
            (
                positive_prompt,
                negative_prompt,
                final_positive_prompt,
                num_inference_steps,
                guidance_scale,
            ) = extract_import_prompt_metadata(source_image)
        return {
            "width": width,
            "height": height,
            "mime_type": mime_type,
            "positive_prompt": positive_prompt,
            "negative_prompt": negative_prompt,
            "final_positive_prompt": final_positive_prompt,
            "num_inference_steps": num_inference_steps,
            "guidance_scale": guidance_scale,
        }


def extract_import_prompt_metadata(
    image: Image.Image,
) -> tuple[str, str, str, int, float]:
    num_inference_steps = DEFAULT_NUM_INFERENCE_STEPS
    guidance_scale = DEFAULT_GUIDANCE_SCALE

    metadata_text = ""
    for key in ("parameters", "prompt"):
        value = image.info.get(key)
        if isinstance(value, str) and value.strip():
            metadata_text = value.strip()
            break

    if metadata_text:
        num_inference_steps, guidance_scale = _parse_generation_metadata(
            metadata_text,
            num_inference_steps=num_inference_steps,
            guidance_scale=guidance_scale,
        )

    return "", "", "", num_inference_steps, guidance_scale


def _parse_generation_metadata(
    metadata_text: str,
    *,
    num_inference_steps: int,
    guidance_scale: float,
) -> tuple[int, float]:
    lines = [line.rstrip() for line in metadata_text.splitlines()]
    metadata_line = next(
        (
            line
            for line in lines
            if re.search(r"\bSteps\s*:", line)
            or re.search(r"\bCFG scale\s*:", line, re.IGNORECASE)
        ),
        "",
    )
    if not metadata_line:
        return num_inference_steps, guidance_scale

    steps_match = re.search(r"\bSteps\s*:\s*(\d+)", metadata_line)
    if steps_match:
        try:
            num_inference_steps = max(1, int(steps_match.group(1)))
        except ValueError:
            num_inference_steps = DEFAULT_NUM_INFERENCE_STEPS

    cfg_match = re.search(
        r"\bCFG scale\s*:\s*([0-9]+(?:\.[0-9]+)?)",
        metadata_line,
        re.IGNORECASE,
    )
    if cfg_match:
        try:
            guidance_scale = max(0.0, float(cfg_match.group(1)))
        except ValueError:
            guidance_scale = DEFAULT_GUIDANCE_SCALE

    return num_inference_steps, guidance_scale

