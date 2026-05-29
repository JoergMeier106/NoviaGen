from __future__ import annotations

from typing import Any


class ComfyOutputMixin:
    @staticmethod
    def _find_output_item(node_output: dict[str, Any]) -> dict[str, Any] | None:
        nested_ui = node_output.get("ui")
        if isinstance(nested_ui, dict):
            nested_item = ComfyOutputMixin._find_output_item(nested_ui)
            if nested_item is not None:
                return nested_item
        for key in ("gifs", "videos", "files", "images"):
            items = node_output.get(key)
            if isinstance(items, list) and items:
                first = items[0]
                if isinstance(first, dict) and "filename" in first:
                    return first
        for items in node_output.values():
            if isinstance(items, list) and items:
                first = items[0]
                if isinstance(first, dict) and "filename" in first:
                    return first
        return None

    @classmethod
    def _history_has_expected_output(cls, job: dict[str, Any], expected_output: str) -> bool:
        outputs = job.get("outputs", {})
        if not isinstance(outputs, dict) or not outputs:
            return False
        if expected_output == "text":
            output_text = cls._extract_text_output_value(outputs)
            if output_text is not None and output_text.strip():
                return True
            for node_output in outputs.values():
                if not isinstance(node_output, dict):
                    continue
                output_text = cls._extract_text_output_value(node_output)
                if output_text is not None and output_text.strip():
                    return True
            return False
        if cls._find_output_item(outputs) is not None:
            return True
        for node_output in outputs.values():
            if isinstance(node_output, dict) and cls._find_output_item(node_output) is not None:
                return True
        return False

    @classmethod
    def _find_video_output(
        cls,
        job: dict[str, Any],
        preferred_node_id: str | None = None,
    ) -> dict[str, Any]:
        outputs = job.get("outputs", {})
        if not isinstance(outputs, dict):
            raise RuntimeError(f"Unexpected ComfyUI history outputs: {outputs}")
        if preferred_node_id is not None:
            for node_id, node_output in outputs.items():
                output_node_id = str(node_id)
                if (
                    output_node_id != preferred_node_id
                    and not output_node_id.endswith(f":{preferred_node_id}")
                ) or not isinstance(node_output, dict):
                    continue
                preferred_output = cls._find_output_item(node_output)
                if preferred_output is not None:
                    return preferred_output
        for node_output in outputs.values():
            if not isinstance(node_output, dict):
                continue
            output_item = cls._find_output_item(node_output)
            if output_item is not None:
                return output_item
        raise RuntimeError(f"Could not locate output video in ComfyUI history: {outputs}")

    @classmethod
    def _find_text_output(
        cls,
        job: dict[str, Any],
        preferred_node_id: str | None = None,
    ) -> str:
        outputs = job.get("outputs", {})
        if not isinstance(outputs, dict):
            raise RuntimeError(f"Unexpected ComfyUI history outputs: {outputs}")
        if preferred_node_id is not None:
            preferred_output = outputs.get(str(preferred_node_id))
            if isinstance(preferred_output, dict):
                preferred_text = cls._extract_text_output_value(preferred_output)
                if preferred_text is not None and preferred_text.strip():
                    return preferred_text
        for node_output in outputs.values():
            if not isinstance(node_output, dict):
                continue
            output_text = cls._extract_text_output_value(node_output)
            if output_text is not None and output_text.strip():
                return output_text
        raise RuntimeError(f"Could not locate output text in ComfyUI history: {outputs}")

    @classmethod
    def _extract_text_output_value(cls, value: Any) -> str | None:
        if isinstance(value, str):
            return value
        if isinstance(value, (list, tuple)):
            for item in value:
                extracted = cls._extract_text_output_value(item)
                if extracted is not None:
                    return extracted
            return None
        if isinstance(value, dict):
            for key in ("text", "result", "string", "value"):
                if key in value:
                    extracted = cls._extract_text_output_value(value[key])
                    if extracted is not None:
                        return extracted
            for item in value.values():
                extracted = cls._extract_text_output_value(item)
                if extracted is not None:
                    return extracted
        return None
