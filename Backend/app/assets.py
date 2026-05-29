from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import yaml


_ASSET_EXTENSIONS = {".safetensors", ".ckpt", ".pt", ".pth", ".gguf"}
_VIDEO_COMPONENT_TOKENS = (
    "vae",
    "text_encoder",
    "text-encoder",
    "clip",
    "t5",
    "umt5",
)


@dataclass(frozen=True, slots=True)
class AssetEntry:
    id: str
    label: str
    path: str
    default_strength: float = 0.85
    trigger_words: str = ""

    def to_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "id": self.id,
            "label": self.label,
            "path": self.path,
        }
        if self.default_strength is not None:
            payload["default_strength"] = self.default_strength
        if self.trigger_words:
            payload["trigger_words"] = self.trigger_words
        return payload


class AssetCatalog:
    def __init__(
        self,
        *,
        models: Iterable[AssetEntry],
        loras: Iterable[AssetEntry],
        video_models: Iterable[AssetEntry] | None = None,
    ) -> None:
        self.models = list(models)
        self.loras = list(loras)
        self.video_models = list(video_models or [])
        self._models_by_id = {item.id: item for item in self.models}
        self._loras_by_id = {item.id: item for item in self.loras}
        self._video_models_by_id = {item.id: item for item in self.video_models}

    @classmethod
    def from_file(cls, path: str | Path) -> "AssetCatalog":
        payload = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
        models = [
            _entry_from_mapping(item, default_strength=0.85)
            for item in payload.get("models", [])
            if isinstance(item, dict)
        ]
        loras = [
            _entry_from_mapping(item, default_strength=0.85)
            for item in payload.get("loras", [])
            if isinstance(item, dict)
        ]
        video_models = [
            _entry_from_mapping(item, default_strength=0.85)
            for item in payload.get("video_models", [])
            if isinstance(item, dict)
        ]
        return cls(models=models, loras=loras, video_models=video_models)

    @classmethod
    def from_directories(
        cls,
        models_dir: str | Path,
        loras_dir: str | Path,
        *,
        video_models_dir: str | Path | None = None,
        lora_default_strength: float = 0.85,
        lora_triggers_dir: str | Path | None = None,
    ) -> "AssetCatalog":
        models = _entries_from_directory(Path(models_dir), default_strength=0.85)
        loras = _entries_from_directory(
            Path(loras_dir),
            default_strength=lora_default_strength,
            triggers_dir=Path(lora_triggers_dir) if lora_triggers_dir else None,
        )
        video_models = (
            _entries_from_directory(
                Path(video_models_dir),
                default_strength=0.85,
                file_filter=is_video_generation_model_file,
            )
            if video_models_dir
            else []
        )
        return cls(models=models, loras=loras, video_models=video_models)

    def list_models(self) -> list[dict[str, Any]]:
        return [item.to_payload() for item in self.models]

    def list_loras(self) -> list[dict[str, Any]]:
        return [item.to_payload() for item in self.loras]

    def list_video_models(self) -> list[dict[str, Any]]:
        return [item.to_payload() for item in self.video_models]

    def get_model(self, asset_id: str) -> AssetEntry | None:
        return self._models_by_id.get(asset_id)

    def get_lora(self, asset_id: str) -> AssetEntry | None:
        return self._loras_by_id.get(asset_id)

    def get_video_model(self, asset_id: str) -> AssetEntry | None:
        return self._video_models_by_id.get(asset_id)

    def without_deleted(
        self,
        *,
        deleted_model_ids: Iterable[str] = (),
        deleted_lora_ids: Iterable[str] = (),
        deleted_video_model_ids: Iterable[str] = (),
    ) -> "AssetCatalog":
        deleted_models = set(deleted_model_ids)
        deleted_loras = set(deleted_lora_ids)
        deleted_video_models = set(deleted_video_model_ids)
        return AssetCatalog(
            models=[item for item in self.models if item.id not in deleted_models],
            loras=[item for item in self.loras if item.id not in deleted_loras],
            video_models=[
                item for item in self.video_models if item.id not in deleted_video_models
            ],
        )


def normalize_asset_id(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9]+", "_", value.strip())
    normalized = re.sub(r"_+", "_", normalized).strip("_")
    return normalized or "asset"


def is_video_generation_model_file(path: str | Path) -> bool:
    candidate = Path(path)
    if candidate.suffix.lower() not in _ASSET_EXTENSIONS:
        return False
    lowered = candidate.stem.lower()
    return not any(token in lowered for token in _VIDEO_COMPONENT_TOKENS)


def build_legacy_asset_id_maps(
    legacy_catalog: AssetCatalog,
    current_catalog: AssetCatalog,
) -> tuple[dict[str, str], dict[str, str]]:
    return (
        _legacy_id_map(legacy_catalog.models, current_catalog.models),
        _legacy_id_map(legacy_catalog.loras, current_catalog.loras),
    )


def _entry_from_mapping(item: dict[str, Any], *, default_strength: float) -> AssetEntry:
    raw_id = str(item.get("id") or item.get("label") or item.get("path") or "asset")
    return AssetEntry(
        id=raw_id,
        label=str(item.get("label") or raw_id),
        path=str(item.get("path") or ""),
        default_strength=float(item.get("default_strength", default_strength)),
        trigger_words=str(item.get("trigger_words") or ""),
    )


def _entries_from_directory(
    directory: Path,
    *,
    default_strength: float,
    triggers_dir: Path | None = None,
    file_filter=None,
) -> list[AssetEntry]:
    if not directory.exists():
        return []
    files = [
        path
        for path in directory.rglob("*")
        if path.is_file()
        and path.suffix.lower() in _ASSET_EXTENSIONS
        and (file_filter(path) if file_filter else True)
    ]
    entries: list[AssetEntry] = []
    used_ids: set[str] = set()
    for path in sorted(files, key=lambda item: str(item.relative_to(directory)).lower()):
        asset_id = _unique_asset_id(normalize_asset_id(path.stem), used_ids)
        trigger_words = _trigger_words_for(path, triggers_dir)
        entries.append(
            AssetEntry(
                id=asset_id,
                label=path.stem,
                path=str(path),
                default_strength=default_strength,
                trigger_words=trigger_words,
            )
        )
    return entries


def _unique_asset_id(base_id: str, used_ids: set[str]) -> str:
    if base_id not in used_ids:
        used_ids.add(base_id)
        return base_id
    index = 2
    while f"{base_id}_{index}" in used_ids:
        index += 1
    asset_id = f"{base_id}_{index}"
    used_ids.add(asset_id)
    return asset_id


def _trigger_words_for(path: Path, triggers_dir: Path | None) -> str:
    if triggers_dir is None:
        return ""
    trigger_path = triggers_dir / f"{path.stem}.txt"
    if not trigger_path.exists():
        trigger_path = triggers_dir / f"{normalize_asset_id(path.stem)}.txt"
    if not trigger_path.exists():
        return ""
    return trigger_path.read_text(encoding="utf-8", errors="ignore").strip()


def _legacy_id_map(
    legacy_entries: Iterable[AssetEntry],
    current_entries: Iterable[AssetEntry],
) -> dict[str, str]:
    current_by_path = {_path_key(item.path): item.id for item in current_entries}
    current_by_normalized_id = {normalize_asset_id(item.id): item.id for item in current_entries}
    result: dict[str, str] = {}
    for legacy in legacy_entries:
        mapped = current_by_path.get(_path_key(legacy.path))
        if mapped is None:
            mapped = current_by_normalized_id.get(normalize_asset_id(legacy.id))
        if mapped is not None and mapped != legacy.id:
            result[legacy.id] = mapped
    return result


def _path_key(value: str) -> str:
    return Path(value).name.lower()
