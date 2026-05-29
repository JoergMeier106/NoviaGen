"""Compatibility entry point for the NoviaGen backend."""

from .app import create_app, load_active_assets

__all__ = ["create_app", "load_active_assets"]
