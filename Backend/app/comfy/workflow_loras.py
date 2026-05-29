from __future__ import annotations

from typing import Any


class ComfyWorkflowLoraMixin:
    @classmethod
    def _find_unet_loader_node_id(cls, workflow: dict[str, Any], model_role: str) -> str:
        role = model_role.strip().lower()
        for node_id in cls._find_node_ids(workflow, "UNETLoader"):
            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue
            title = str(node.get("_meta", {}).get("title", "")).strip().lower()
            if role in title:
                return node_id

        node_id = cls._find_unet_loader_node_id_by_current_model_name(
            workflow,
            role,
        )
        if node_id is not None:
            return node_id

        raise KeyError(f"Could not find {model_role} UNETLoader node")

    @classmethod
    def _find_unet_loader_node_id_by_current_model_name(
        cls,
        workflow: dict[str, Any],
        role: str,
    ) -> str | None:
        candidates: list[tuple[int, str, str]] = []
        nodes = cls._unet_loader_nodes_with_model_names(workflow)
        for left_index, (left_node_id, left_model_name) in enumerate(nodes):
            for right_node_id, right_model_name in nodes[left_index + 1 :]:
                pair = cls._diffusion_model_name_pair(
                    left_model_name,
                    right_model_name,
                )
                if pair is None:
                    continue
                left_role, right_role, rank = pair
                if left_role == "high":
                    high_node_id = left_node_id
                    low_node_id = right_node_id
                else:
                    high_node_id = right_node_id
                    low_node_id = left_node_id
                candidates.append((rank, high_node_id, low_node_id))

        if not candidates:
            return None

        candidates.sort(key=lambda item: item[0])
        _, high_node_id, low_node_id = candidates[0]
        return high_node_id if role == "high" else low_node_id

    @classmethod
    def _unet_loader_nodes_with_model_names(
        cls,
        workflow: dict[str, Any],
    ) -> list[tuple[str, str]]:
        nodes: list[tuple[str, str]] = []
        for node_id in cls._find_node_ids(workflow, "UNETLoader"):
            node = workflow.get(node_id)
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            model_name = str(inputs.get("unet_name") or "").strip()
            if not model_name:
                continue
            nodes.append((node_id, model_name))
        return nodes

    @staticmethod
    def _diffusion_model_name_pair(
        left_name: str,
        right_name: str,
    ) -> tuple[str, str, int] | None:
        if left_name == right_name:
            return None

        left_lower = left_name.lower()
        right_lower = right_name.lower()
        shortest_length = min(len(left_lower), len(right_lower))
        prefix_length = 0
        while (
            prefix_length < shortest_length
            and left_lower[prefix_length] == right_lower[prefix_length]
        ):
            prefix_length += 1

        left_suffix_index = len(left_name) - 1
        right_suffix_index = len(right_name) - 1
        while (
            left_suffix_index >= prefix_length
            and right_suffix_index >= prefix_length
            and left_lower[left_suffix_index] == right_lower[right_suffix_index]
        ):
            left_suffix_index -= 1
            right_suffix_index -= 1

        left_diff = left_name[prefix_length : left_suffix_index + 1]
        right_diff = right_name[prefix_length : right_suffix_index + 1]
        left_role = ComfyWorkflowLoraMixin._diffusion_model_variant_role(left_diff)
        right_role = ComfyWorkflowLoraMixin._diffusion_model_variant_role(right_diff)
        if left_role is None or right_role is None or left_role == right_role:
            return None
        if not ComfyWorkflowLoraMixin._matching_diffusion_variant_width(
            left_diff,
            right_diff,
        ):
            return None
        return left_role, right_role, len(left_diff) + len(right_diff)

    @staticmethod
    def _diffusion_model_variant_role(diff: str) -> str | None:
        normalized = diff.lower()
        if normalized in {"high", "h"}:
            return "high"
        if normalized in {"low", "l"}:
            return "low"
        return None

    @staticmethod
    def _matching_diffusion_variant_width(left_diff: str, right_diff: str) -> bool:
        left = left_diff.lower()
        right = right_diff.lower()
        return (
            {left, right} == {"high", "low"}
            or {left, right} == {"h", "l"}
        )

    @classmethod
    def _apply_diffusion_model_overrides(
        cls,
        workflow: dict[str, Any],
        payload: Any,
    ) -> None:
        overrides = {
            "high": str(payload.high_diffusion_model_name or "").strip(),
            "low": str(payload.low_diffusion_model_name or "").strip(),
        }
        node_ids = {
            model_role: cls._find_unet_loader_node_id(workflow, model_role)
            for model_role, model_name in overrides.items()
            if model_name
        }

        for model_role, model_name in overrides.items():
            if not model_name:
                continue
            node_id = node_ids[model_role]
            inputs = workflow[node_id].get("inputs")
            if not isinstance(inputs, dict):
                raise KeyError(f"UNETLoader node {node_id} has no inputs")
            inputs["unet_name"] = model_name

    @classmethod
    def workflow_loras(cls, workflow: dict[str, Any]) -> list[dict[str, Any]]:
        loras: list[dict[str, Any]] = []
        for node_id, node in workflow.items():
            if not isinstance(node, dict):
                continue
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue
            node_title = str(node.get("_meta", {}).get("title", "")).strip()
            class_type = str(node.get("class_type", "")).strip()
            if class_type == "LoraLoaderModelOnly":
                lora_name = str(inputs.get("lora_name", "")).strip()
                if not lora_name:
                    continue
                loras.append(
                    {
                        "id": f"{node_id}:strength_model",
                        "name": lora_name,
                        "label": lora_name,
                        "node_title": node_title,
                        "default_strength": cls._safe_float(
                            inputs.get("strength_model"),
                            1.0,
                        ),
                        "enabled": True,
                    }
                )
                continue
            if "Lora Loader" not in class_type and "LoraLoader" not in class_type:
                continue
            for input_name, input_value in inputs.items():
                if not str(input_name).startswith("lora_") or not isinstance(
                    input_value,
                    dict,
                ):
                    continue
                lora_name = str(input_value.get("lora", "")).strip()
                if not lora_name:
                    continue
                loras.append(
                    {
                        "id": f"{node_id}:{input_name}",
                        "name": lora_name,
                        "label": lora_name,
                        "node_title": node_title,
                        "default_strength": cls._safe_float(
                            input_value.get("strength"),
                            1.0,
                        ),
                        "enabled": bool(input_value.get("on", True)),
                    }
                )
        return loras

    @classmethod
    def _apply_workflow_lora_overrides(
        cls,
        workflow: dict[str, Any],
        payload: Any,
    ) -> None:
        for item in getattr(payload, "workflow_loras", []) or []:
            lora_id = str(item.lora_id).strip()
            if not lora_id:
                continue
            cls._set_workflow_lora_strength(
                workflow,
                lora_id=lora_id,
                strength=float(item.strength),
            )

    @classmethod
    def _set_workflow_lora_strength(
        cls,
        workflow: dict[str, Any],
        *,
        lora_id: str,
        strength: float,
    ) -> None:
        node_id, separator, input_name = lora_id.partition(":")
        if not separator:
            return
        node = workflow.get(node_id)
        if not isinstance(node, dict):
            return
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            return
        if input_name == "strength_model":
            inputs["strength_model"] = float(strength)
            return
        lora_input = inputs.get(input_name)
        if isinstance(lora_input, dict):
            lora_input["strength"] = float(strength)

    @staticmethod
    def _safe_float(value: Any, fallback: float) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return fallback
