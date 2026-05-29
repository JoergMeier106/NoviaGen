from __future__ import annotations

from flask import Flask

from ..assets import AssetCatalog
from ..persistence import AppDatabase


def load_active_assets(app: Flask, db: AppDatabase) -> AssetCatalog:
    catalog = AssetCatalog.from_directories(
        app.config["MODELS_DIR"],
        app.config["LORAS_DIR"],
        video_models_dir=app.config["VIDEO_MODELS_DIR"],
        lora_default_strength=float(app.config["LORA_DEFAULT_STRENGTH"]),
        lora_triggers_dir=app.config["LORA_TRIGGERS_DIR"],
    )
    return catalog.without_deleted(
        deleted_model_ids=db.list_deleted_asset_ids("model"),
        deleted_lora_ids=db.list_deleted_asset_ids("lora"),
        deleted_video_model_ids=db.list_deleted_asset_ids("video_model"),
    )
