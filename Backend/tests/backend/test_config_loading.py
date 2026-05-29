from __future__ import annotations

import os
from pathlib import Path
from unittest.mock import patch

import yaml

from app.config import load_runtime_config

from .shared import BackendTestCase


class ConfigLoadingTests(BackendTestCase):
    def test_load_runtime_config_reads_inline_mcp_servers(self) -> None:
        backend_dir = Path(__file__).resolve().parents[2]
        template = yaml.safe_load((backend_dir / "config.yaml").read_text(encoding="utf-8"))
        self.assertIsInstance(template, dict)

        runtime_dir = self._workspace_dir("config_loader")
        config_path = runtime_dir / "config.yaml"
        env_path = runtime_dir / "mcp.env"
        env_path.write_text("DEMO_TOKEN=local-demo-token\n", encoding="utf-8")

        template["chat"]["mcp"]["local_env_path"] = "${CONFIG_DIR}/mcp.env"
        template["chat"]["mcp"]["servers"] = {
            "demo": {
                "command": "npx",
                "args": ["-y", "demo-mcp-server"],
                "env": {"API_TOKEN": "${DEMO_TOKEN}"},
            }
        }
        config_path.write_text(yaml.safe_dump(template, sort_keys=False), encoding="utf-8")

        with patch.dict(os.environ, {"NOVIAGEN_CONFIG_PATH": str(config_path)}, clear=False):
            config = load_runtime_config(backend_dir)

        self.assertEqual(config["CONFIG_PATH"], str(config_path.resolve()))
        self.assertEqual(config["CHAT_MCP_LOCAL_ENV"]["DEMO_TOKEN"], "local-demo-token")
        self.assertEqual(
            config["CHAT_MCP_SERVERS"],
            {
                "demo": {
                    "command": "npx",
                    "args": ["-y", "demo-mcp-server"],
                    "env": {"API_TOKEN": "${DEMO_TOKEN}"},
                }
            },
        )

    def test_load_runtime_config_falls_back_to_legacy_local_env_file(self) -> None:
        backend_dir = Path(__file__).resolve().parents[2]
        template = yaml.safe_load((backend_dir / "config.yaml").read_text(encoding="utf-8"))
        self.assertIsInstance(template, dict)

        runtime_dir = self._workspace_dir("config_loader_legacy_env")
        config_path = runtime_dir / "config.yaml"
        legacy_env_path = runtime_dir / "obscure.env"
        legacy_env_path.write_text("LEGACY_TOKEN=legacy-demo-token\n", encoding="utf-8")

        template["chat"]["mcp"]["local_env_path"] = "${CONFIG_DIR}/noviagen.env"
        config_path.write_text(yaml.safe_dump(template, sort_keys=False), encoding="utf-8")

        with patch.dict(os.environ, {"NOVIAGEN_CONFIG_PATH": str(config_path)}, clear=False):
            config = load_runtime_config(backend_dir)

        self.assertEqual(
            config["CHAT_MCP_LOCAL_ENV"],
            {"LEGACY_TOKEN": "legacy-demo-token"},
        )
