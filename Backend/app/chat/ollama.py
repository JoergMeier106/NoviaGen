from __future__ import annotations

import json
from typing import Any, Mapping

import requests

from ..generation import OllamaResponseError, OllamaUnavailableError


class OllamaClient:
    def __init__(
        self,
        config: Mapping[str, Any],
        *,
        http_get=requests.get,
        http_post=requests.post,
    ) -> None:
        self._config = config
        self._http_get = http_get
        self._http_post = http_post

    def collect_model_items(self, *, vision_only: bool = False) -> list[dict[str, Any]]:
        tags_payload = self.request_json("/api/tags")
        running_payload = self.request_json("/api/ps")
        running_models_by_name = _running_models_by_name(running_payload)

        items: list[dict[str, Any]] = []
        tags_models = tags_payload.get("models")
        if isinstance(tags_models, list):
            for item in tags_models:
                if not isinstance(item, dict):
                    continue
                model_item = self._model_item(
                    item,
                    running_models_by_name=running_models_by_name,
                    vision_only=vision_only,
                )
                if model_item is not None:
                    items.append(model_item)

        items.sort(
            key=lambda item: (
                not bool(item.get("is_loaded")),
                str(item.get("name") or "").lower(),
            )
        )
        return items

    def select_default_model(self) -> str:
        fallback = str(self._config["OLLAMA_PROMPT_MODEL"]).strip()
        try:
            tags = self.request_json("/api/tags")
        except (OllamaUnavailableError, OllamaResponseError):
            return fallback
        models = tags.get("models")
        if isinstance(models, list):
            for item in models:
                if not isinstance(item, dict):
                    continue
                model_name = str(item.get("name") or item.get("model") or "").strip()
                if model_name:
                    return model_name
        return fallback

    def health(self) -> dict[str, Any]:
        base_url = self._base_url()
        if not base_url:
            return {"ok": False, "label": "Not configured", "detail": None}
        try:
            response = self._http_get(f"{base_url}/api/version", timeout=5.0)
            if response.status_code == 404:
                response = self._http_get(f"{base_url}/api/tags", timeout=5.0)
            response.raise_for_status()
            return {"ok": True, "label": "Online", "detail": base_url}
        except requests.RequestException as exc:
            return {"ok": False, "label": "Offline", "detail": str(exc)}

    def request_json(
        self,
        path: str,
        *,
        method: str = "GET",
        json_body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        try:
            response = self._request(path, method=method, json_body=json_body)
            response.raise_for_status()
        except requests.RequestException as exc:
            raise OllamaUnavailableError("Ollama is not reachable") from exc
        try:
            response_json = response.json()
        except json.JSONDecodeError as exc:
            raise OllamaResponseError("Ollama returned invalid JSON") from exc
        if not isinstance(response_json, dict):
            raise OllamaResponseError("Ollama returned an invalid response payload")
        return response_json

    def show_model(self, model_name: str) -> dict[str, Any]:
        return self.request_json(
            "/api/show",
            method="POST",
            json_body={"model": model_name},
        )

    def _model_item(
        self,
        item: dict[str, Any],
        *,
        running_models_by_name: dict[str, dict[str, Any]],
        vision_only: bool,
    ) -> dict[str, Any] | None:
        model_name = str(item.get("name") or item.get("model") or "").strip()
        if not model_name:
            return None
        running = running_models_by_name.get(model_name, {})
        try:
            show_payload = self.show_model(model_name)
        except (OllamaUnavailableError, OllamaResponseError):
            show_payload = {}
        show_details = (
            show_payload.get("details")
            if isinstance(show_payload.get("details"), dict)
            else {}
        )
        merged_details = {
            **(item.get("details") if isinstance(item.get("details"), dict) else {}),
            **show_details,
        }
        capabilities = [
            str(value).strip()
            for value in show_payload.get("capabilities", [])
            if str(value).strip()
        ]
        if vision_only and "vision" not in {
            capability.lower() for capability in capabilities
        }:
            return None
        return {
            "name": model_name,
            "model": str(item.get("model") or model_name),
            "modified_at": item.get("modified_at"),
            "size": item.get("size"),
            "digest": item.get("digest"),
            "details": merged_details,
            "capabilities": capabilities,
            "thinking_mode": _thinking_mode(
                model_name=model_name,
                capabilities=capabilities,
                details=merged_details,
            ),
            "is_loaded": bool(running),
            "context_length": running.get("context_length"),
            "model_context_length": _context_length(show_payload),
            "size_vram": running.get("size_vram"),
            "expires_at": running.get("expires_at"),
        }

    def _request(
        self,
        path: str,
        *,
        method: str,
        json_body: dict[str, Any] | None,
    ) -> requests.Response:
        base_url = self._base_url()
        if method.upper() == "POST":
            return self._http_post(
                f"{base_url}{path}",
                json=json_body,
                timeout=self._timeout_seconds(),
            )
        return self._http_get(
            f"{base_url}{path}",
            timeout=self._timeout_seconds(),
        )

    def _base_url(self) -> str:
        return str(self._config["OLLAMA_URL"]).rstrip("/")

    def _timeout_seconds(self) -> float:
        return float(self._config["OLLAMA_PROMPT_TIMEOUT_SECONDS"])


def _running_models_by_name(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    running_models_by_name: dict[str, dict[str, Any]] = {}
    running_models = payload.get("models")
    if isinstance(running_models, list):
        for item in running_models:
            if not isinstance(item, dict):
                continue
            model_name = str(item.get("name") or item.get("model") or "").strip()
            if model_name:
                running_models_by_name[model_name] = item
    return running_models_by_name


def _context_length(show_payload: dict[str, Any]) -> int | None:
    model_info = show_payload.get("model_info")
    if not isinstance(model_info, dict):
        return None
    for key, value in model_info.items():
        if not isinstance(key, str) or not key.endswith(".context_length"):
            continue
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
    return None


def _thinking_mode(
    *,
    model_name: str,
    capabilities: list[str],
    details: dict[str, Any],
) -> str:
    normalized_capabilities = {str(item).strip().lower() for item in capabilities}
    if "thinking" not in normalized_capabilities:
        return "unsupported"
    families = details.get("families")
    family_candidates: list[str] = [str(details.get("family") or ""), model_name]
    if isinstance(families, list):
        family_candidates.extend(str(item) for item in families)
    normalized_families = {
        item.strip().lower() for item in family_candidates if item.strip()
    }
    if any("gpt-oss" in item for item in normalized_families):
        return "level_only"
    return "toggle"
