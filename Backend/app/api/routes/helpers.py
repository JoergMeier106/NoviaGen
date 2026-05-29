from __future__ import annotations

import requests

from .context import (
    asset_payloads as _build_asset_payloads,
    ollama_client as _build_ollama_client,
)


def asset_payloads():
    return _build_asset_payloads(http_get=requests.get)


def ollama_client():
    return _build_ollama_client(
        http_get=requests.get,
        http_post=requests.post,
    )
