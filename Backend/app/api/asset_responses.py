from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping

from flask import Response, jsonify


def readonly_asset_rating_response() -> tuple[Response, int]:
    return jsonify(
        {
            "error": "Asset ratings are read-only and are derived from the mean rating of generated images.",
        }
    ), 405


def delete_asset_response(
    *,
    asset_type: str,
    asset_id: str,
    catalog: Any,
    db: Any,
    config: Mapping[str, Any],
    refresh_catalog,
) -> Response | tuple[Response, int]:
    try:
        normalized_asset_type = _normalized_asset_type(asset_type)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    asset = _find_asset(catalog, normalized_asset_type, asset_id)
    if asset is None:
        return jsonify({"error": "Asset not found"}), 404

    db.mark_asset_deleted(asset_type=normalized_asset_type, asset_id=asset_id)
    _delete_path(Path(asset.path))
    if normalized_asset_type == "lora":
        _delete_lora_trigger(asset, config)

    refresh_catalog()
    return jsonify(
        {
            "deleted": True,
            "asset_type": normalized_asset_type,
            "asset_id": asset_id,
        }
    )


def _normalized_asset_type(asset_type: str) -> str:
    normalized = asset_type.strip().lower()
    if normalized in {"model", "models"}:
        return "model"
    if normalized in {"lora", "loras"}:
        return "lora"
    raise ValueError("Unsupported asset type")


def _find_asset(catalog: Any, asset_type: str, asset_id: str) -> Any | None:
    if asset_type == "model":
        return catalog.get_model(asset_id)
    return catalog.get_lora(asset_id)


def _delete_lora_trigger(asset: Any, config: Mapping[str, Any]) -> None:
    trigger_path = Path(config["LORA_TRIGGERS_DIR"]) / f"{asset.label}.txt"
    _delete_path(trigger_path)


def _delete_path(path: Path) -> None:
    try:
        if path.exists():
            path.unlink(missing_ok=True)
    except OSError:
        pass
