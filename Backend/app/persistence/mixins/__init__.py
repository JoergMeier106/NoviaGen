"""Database persistence mixins grouped by domain."""

from .assets import AssetPersistenceMixin
from .chat import ChatPersistenceMixin
from .chat_attachments import ChatAttachmentPersistenceMixin
from .gallery import GalleryPersistenceMixin
from .jobs import JobPersistenceMixin
from .media_lifecycle import MediaLifecyclePersistenceMixin
from .media_records import MediaRecordPersistenceMixin

__all__ = [
    "AssetPersistenceMixin",
    "ChatAttachmentPersistenceMixin",
    "ChatPersistenceMixin",
    "GalleryPersistenceMixin",
    "JobPersistenceMixin",
    "MediaLifecyclePersistenceMixin",
    "MediaRecordPersistenceMixin",
]
