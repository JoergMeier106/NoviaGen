from __future__ import annotations

import base64
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


@dataclass(frozen=True)
class PreparedChatContext:
    context_image_ids: list[str]
    uploaded_attachments: list[dict[str, Any]]
    message_attachments: list[dict[str, Any]]
    image_bytes: list[str]

    def cleanup_uploads(self) -> None:
        cleanup_uploaded_attachments(self.uploaded_attachments)


class ChatContextImageService:
    def __init__(
        self,
        *,
        db: Any,
        temp_dir: str | Path,
        is_still_media: Callable[[dict[str, Any]], bool],
    ) -> None:
        self._db = db
        self._temp_dir = Path(temp_dir)
        self._is_still_media = is_still_media

    def load_context_image_base64(self, image_id: str | None) -> str | None:
        image = self._get_context_image(image_id)
        if image is None:
            return None
        image_path = Path(str(image.get("file_path") or ""))
        if not image_path.exists():
            raise FileNotFoundError("The selected context image could not be read")
        return _read_base64(image_path)

    def load_attachment_base64(self, attachment: dict[str, Any]) -> str | None:
        context_image_id = str(attachment.get("context_image_id") or "").strip() or None
        if context_image_id:
            return self.load_context_image_base64(context_image_id)
        return self.load_uploaded_context_image_base64(
            str(attachment.get("context_image_path") or "")
        )

    def load_uploaded_context_image_base64(
        self,
        context_image_path: str | None,
    ) -> str | None:
        normalized_path = str(context_image_path or "").strip()
        if not normalized_path:
            return None
        image_path = Path(normalized_path)
        if not image_path.exists():
            raise FileNotFoundError("The selected context image could not be read")
        return _read_base64(image_path)

    def prepare_stream_context(
        self,
        *,
        context_image_ids: list[str],
        uploaded_files: list[Any],
    ) -> PreparedChatContext:
        image_bytes: list[str] = []
        message_attachments: list[dict[str, Any]] = []
        uploaded_attachments: list[dict[str, Any]] = []

        try:
            for image_id in context_image_ids:
                encoded_image = self.load_context_image_base64(image_id)
                if encoded_image:
                    image_bytes.append(encoded_image)
                    message_attachments.append({"context_image_id": image_id})

            for uploaded_file in uploaded_files:
                context_image_path, context_image_mime_type = self.store_uploaded_context(
                    uploaded_file
                )
                uploaded_attachment = {
                    "context_image_path": context_image_path,
                    "context_image_mime_type": context_image_mime_type,
                }
                uploaded_attachments.append(uploaded_attachment)
                encoded_image = self.load_uploaded_context_image_base64(
                    str(context_image_path)
                )
                if encoded_image:
                    image_bytes.append(encoded_image)
                    message_attachments.append(uploaded_attachment)
        except Exception:
            cleanup_uploaded_attachments(uploaded_attachments)
            raise

        return PreparedChatContext(
            context_image_ids=context_image_ids,
            uploaded_attachments=uploaded_attachments,
            message_attachments=message_attachments,
            image_bytes=image_bytes,
        )

    def prepare_job_context(
        self,
        *,
        context_image_ids: list[str],
        uploaded_files: list[Any],
    ) -> PreparedChatContext:
        uploaded_attachments: list[dict[str, Any]] = []
        try:
            for image_id in context_image_ids:
                if self._db.get_image(image_id) is None:
                    raise KeyError(f"Unknown context image_id: {image_id}")

            for uploaded_file in uploaded_files:
                context_image_path, context_image_mime_type = self.store_uploaded_context(
                    uploaded_file
                )
                uploaded_attachments.append(
                    {
                        "context_image_path": str(context_image_path),
                        "context_image_mime_type": context_image_mime_type,
                    }
                )
        except Exception:
            cleanup_uploaded_attachments(uploaded_attachments)
            raise

        return PreparedChatContext(
            context_image_ids=context_image_ids,
            uploaded_attachments=uploaded_attachments,
            message_attachments=list(uploaded_attachments),
            image_bytes=[],
        )

    def store_uploaded_context(self, uploaded_file: Any) -> tuple[Path, str]:
        if uploaded_file is None or not uploaded_file.filename:
            raise ValueError("image file is required")
        mimetype = str(getattr(uploaded_file, "mimetype", "") or "").strip() or "image/png"
        if not mimetype.startswith("image/"):
            raise ValueError("Only image files can be attached")
        uploads_dir = self._temp_dir / "chat_context"
        uploads_dir.mkdir(parents=True, exist_ok=True)
        suffix = Path(uploaded_file.filename or "chat-context.png").suffix or ".png"
        upload_path = uploads_dir / f"{uuid.uuid4()}{suffix}"
        uploaded_file.save(upload_path)
        return upload_path, mimetype

    def _get_context_image(self, image_id: str | None) -> dict[str, Any] | None:
        normalized_id = str(image_id or "").strip()
        if not normalized_id:
            return None
        image = self._db.get_image(normalized_id)
        if image is None:
            raise KeyError("Unknown context_image_id")
        if image.get("status") != "stored":
            raise ValueError("Only stored gallery images can be attached")
        if not self._is_still_media(image):
            raise ValueError("Only stored images or GIFs can be attached")
        return image


def cleanup_uploaded_attachments(attachments: list[dict[str, Any]]) -> None:
    for attachment in attachments:
        Path(str(attachment["context_image_path"])).unlink(missing_ok=True)


def _read_base64(image_path: Path) -> str:
    return base64.b64encode(image_path.read_bytes()).decode("ascii")
