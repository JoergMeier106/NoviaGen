from __future__ import annotations

from typing import Any


class ComfyWorkflowGraphMixin:
    @staticmethod
    def _find_node_ids(workflow: dict[str, Any], class_type: str) -> list[str]:
        return [
            str(node_id)
            for node_id, node in workflow.items()
            if isinstance(node, dict) and node.get("class_type") == class_type
        ]

    @classmethod
    def _resolve_workflow_int(cls, workflow: dict[str, Any], value: Any) -> int | None:
        resolved = cls._resolve_workflow_value(workflow, value)
        if isinstance(resolved, bool):
            return int(resolved)
        if isinstance(resolved, (int, float)):
            return int(resolved)
        return None

    @classmethod
    def _resolve_workflow_value(cls, workflow: dict[str, Any], value: Any) -> Any:
        if isinstance(value, (int, float, bool)):
            return value
        if not (isinstance(value, list) and len(value) >= 1):
            return None

        node_id = str(value[0])
        node = workflow.get(node_id)
        if not isinstance(node, dict):
            return None
        inputs = node.get("inputs")
        if not isinstance(inputs, dict):
            return None

        class_type = str(node.get("class_type") or "")
        if class_type in {
            "PrimitiveInt",
            "PrimitiveFloat",
            "PrimitiveBoolean",
            "INTConstant",
            "FloatConstant",
        }:
            return inputs.get("value")
        if class_type == "mxSlider":
            return inputs.get("Xi")
        if class_type == "ComfySwitchNode":
            switch_value = bool(cls._resolve_workflow_value(workflow, inputs.get("switch")))
            selected_input = "on_true" if switch_value else "on_false"
            return cls._resolve_workflow_value(workflow, inputs.get(selected_input))
        return None

    @staticmethod
    def _node_sort_key(node_id: str) -> tuple[int, str]:
        try:
            return (0, f"{int(node_id):08d}")
        except ValueError:
            return (1, node_id)

    @staticmethod
    def _find_first_node_id(workflow: dict[str, Any], class_type: str) -> str:
        for node_id, node in workflow.items():
            if isinstance(node, dict) and node.get("class_type") == class_type:
                return str(node_id)
        raise KeyError(f"Could not find node with class_type={class_type!r}")

    @staticmethod
    def _find_optional_node_id(workflow: dict[str, Any], class_type: str) -> str | None:
        for node_id, node in workflow.items():
            if isinstance(node, dict) and node.get("class_type") == class_type:
                return str(node_id)
        return None

    @staticmethod
    def _find_first_node_id_by_title(
        workflow: dict[str, Any],
        title: str,
        *,
        class_type: str | None = None,
    ) -> str:
        wanted_title = title.strip().lower()
        for node_id, node in workflow.items():
            if not isinstance(node, dict):
                continue
            if class_type is not None and node.get("class_type") != class_type:
                continue
            current_title = str(node.get("_meta", {}).get("title", "")).strip().lower()
            if current_title == wanted_title:
                return str(node_id)
        raise KeyError(f"Could not find node with title={title!r}")

    @classmethod
    def _find_optional_node_id_by_title(
        cls,
        workflow: dict[str, Any],
        title: str,
        *,
        class_type: str | None = None,
    ) -> str | None:
        try:
            return cls._find_first_node_id_by_title(
                workflow,
                title,
                class_type=class_type,
            )
        except KeyError:
            return None

    @staticmethod
    def _linked_node_id(value: Any) -> str | None:
        if isinstance(value, list) and value:
            return str(value[0])
        return None

    @classmethod
    def _linked_input_node_ids(cls, value: Any) -> list[str]:
        linked_ids: list[str] = []
        if isinstance(value, dict):
            for child_value in value.values():
                linked_ids.extend(cls._linked_input_node_ids(child_value))
            return linked_ids
        if isinstance(value, list):
            if value and isinstance(value[0], (str, int)):
                linked_ids.append(str(value[0]))
            for child_value in value:
                linked_ids.extend(cls._linked_input_node_ids(child_value))
            return linked_ids
        return linked_ids

    @classmethod
    def _replace_workflow_links(
        cls,
        workflow: dict[str, Any],
        replacements: dict[tuple[str, int], Any],
    ) -> None:
        for node in workflow.values():
            if isinstance(node, dict):
                cls._replace_nested_workflow_links(node, replacements)

    @classmethod
    def _replace_nested_workflow_links(
        cls,
        value: Any,
        replacements: dict[tuple[str, int], Any],
    ) -> None:
        if isinstance(value, dict):
            for child_key, child_value in value.items():
                replacement = cls._replacement_for_link(child_value, replacements)
                if replacement is not None:
                    value[child_key] = replacement
                else:
                    cls._replace_nested_workflow_links(child_value, replacements)
            return
        if isinstance(value, list):
            for index, item in enumerate(value):
                replacement = cls._replacement_for_link(item, replacements)
                if replacement is not None:
                    value[index] = replacement
                else:
                    cls._replace_nested_workflow_links(item, replacements)

    @staticmethod
    def _replacement_for_link(
        value: Any,
        replacements: dict[tuple[str, int], Any],
    ) -> Any | None:
        if isinstance(value, list) and len(value) >= 2:
            replacement_key = (str(value[0]), int(value[1]))
            if replacement_key in replacements:
                return replacements[replacement_key]
        return None

    @classmethod
    def _workflow_references_node(cls, workflow: dict[str, Any], node_id: str) -> bool:
        target_id = str(node_id)
        for node in workflow.values():
            if isinstance(node, dict) and cls._value_references_node(node, target_id):
                return True
        return False

    @classmethod
    def _value_references_node(cls, value: Any, node_id: str) -> bool:
        if isinstance(value, dict):
            return any(
                cls._value_references_node(child_value, node_id)
                for child_value in value.values()
            )
        if isinstance(value, list):
            if value and str(value[0]) == node_id:
                return True
            return any(cls._value_references_node(item, node_id) for item in value)
        return False
