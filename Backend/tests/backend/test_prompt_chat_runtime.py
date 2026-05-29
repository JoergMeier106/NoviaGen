from __future__ import annotations

from .shared import *


class PromptChatRuntimeTests(BackendTestCase):
    def test_prompt_route_requires_non_blank_prompt(self) -> None:
        runtime_dir = self._workspace_dir("prompt_route_validation")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post("/api/prompt/generate", json={"prompt": "   "})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "prompt is required")

    def test_prompt_route_returns_generated_prompt(self) -> None:
        runtime_dir = self._workspace_dir("prompt_route_success")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        generator.prompt_response = "expanded cinematic prompt"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post(
            "/api/prompt/generate",
            json={"prompt": "base prompt extra detail"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["prompt"], "expanded cinematic prompt")
        self.assertEqual(generator.last_prompt_generation_input, "base prompt extra detail")
        self.assertIsNone(generator.last_prompt_generation_image_bytes)

    def test_i2v_prompt_route_passes_stored_source_image_to_generator(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_stored_image")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        stored_dir = data_dir / "stored"
        temp_dir = data_dir / "temp"
        backups_dir = data_dir / "backups"
        stored_dir.mkdir(parents=True)
        temp_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        db_path = data_dir / "app.db"
        seed_db = AppDatabase(db_path, temp_dir, stored_dir, backups_dir, data_dir=data_dir)
        seed_db.init_schema()
        source_path = stored_dir / "source-image.png"
        Image.new("RGB", (16, 16), color="purple").save(source_path)
        self._insert_image_record(
            seed_db,
            image_id="source-image",
            status="stored",
            file_path=source_path,
            created_at="2024-01-01T00:00:00",
            stored_at="2024-01-01T00:00:00",
        )
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "DB_PATH": str(db_path),
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post(
            "/api/prompt/generate-i2v",
            json={"prompt": "animate this image", "image_id": "source-image"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["prompt"], "generated i2v prompt")
        self.assertEqual(generator.last_i2v_prompt_generation_input, "animate this image")
        self.assertEqual(generator.last_i2v_prompt_generation_image_bytes, source_path.read_bytes())

    def test_i2v_prompt_route_passes_uploaded_source_image_to_generator(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_uploaded_image")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()
        upload_buffer = io.BytesIO()
        Image.new("RGB", (12, 12), color="orange").save(upload_buffer, format="PNG")
        upload_bytes = upload_buffer.getvalue()

        response = client.post(
            "/api/prompt/generate-i2v",
            data={
                "prompt": "animate this upload",
                "image": (io.BytesIO(upload_bytes), "source.png"),
            },
            content_type="multipart/form-data",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["prompt"], "generated i2v prompt")
        self.assertEqual(generator.last_i2v_prompt_generation_input, "animate this upload")
        self.assertEqual(generator.last_i2v_prompt_generation_image_bytes, upload_bytes)

    def test_i2v_prompt_route_requires_image_source(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_requires_source")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post("/api/prompt/generate-i2v", json={"prompt": ""})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "Either image_id or image file is required")

    def test_i2v_prompt_route_returns_not_found_for_unknown_image(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_unknown_image")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post(
            "/api/prompt/generate-i2v",
            json={"prompt": "", "image_id": "missing-image"},
        )

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.get_json()["error"], "Unknown image_id")

    def test_i2v_prompt_route_rejects_non_still_media(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_rejects_video")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        stored_dir = data_dir / "stored"
        temp_dir = data_dir / "temp"
        backups_dir = data_dir / "backups"
        stored_dir.mkdir(parents=True)
        temp_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        db_path = data_dir / "app.db"
        seed_db = AppDatabase(db_path, temp_dir, stored_dir, backups_dir, data_dir=data_dir)
        seed_db.init_schema()
        source_path = stored_dir / "source-video.mp4"
        source_path.write_bytes(b"fake-mp4")
        self._insert_image_record(
            seed_db,
            image_id="source-video",
            status="stored",
            file_path=source_path,
            created_at="2024-01-01T00:00:00",
            media_type="video",
            mime_type="video/mp4",
            stored_at="2024-01-01T00:00:00",
        )
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "DB_PATH": str(db_path),
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post(
            "/api/prompt/generate-i2v",
            json={"prompt": "animate this image", "image_id": "source-video"},
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "Only stored images or GIFs can be used")

    def test_i2v_prompt_route_allows_blank_prompt_text(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_blank_text")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()
        upload_buffer = io.BytesIO()
        Image.new("RGB", (12, 12), color="orange").save(upload_buffer, format="PNG")

        response = client.post(
            "/api/prompt/generate-i2v",
            data={
                "prompt": "   ",
                "image": (io.BytesIO(upload_buffer.getvalue()), "source.png"),
            },
            content_type="multipart/form-data",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["prompt"], "generated i2v prompt")
        self.assertEqual(generator.last_i2v_prompt_generation_input, "   ")

    def test_i2v_prompt_route_requires_configured_workflow(self) -> None:
        runtime_dir = self._workspace_dir("i2v_prompt_route_missing_workflow")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_I2V_PROMPT_WORKFLOW_PATH": "",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()
        upload_buffer = io.BytesIO()
        Image.new("RGB", (12, 12), color="orange").save(upload_buffer, format="PNG")

        response = client.post(
            "/api/prompt/generate-i2v",
            data={
                "prompt": "",
                "image": (io.BytesIO(upload_buffer.getvalue()), "source.png"),
            },
            content_type="multipart/form-data",
        )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.get_json()["error"],
            "Comfy image prompt workflow is not configured",
        )

    def test_prompt_route_maps_ollama_connection_failures_to_service_unavailable(self) -> None:
        runtime_dir = self._workspace_dir("prompt_route_failure")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
        generator.prompt_generation_error = OllamaUnavailableError("Ollama is not reachable")
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "VIDEO_MODELS_DIR": str(video_models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post("/api/prompt/generate", json={"prompt": "describe this"})

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.get_json()["error"], "Ollama is not reachable")

    def test_chat_stream_persists_messages_and_gallery_context(self) -> None:
        runtime_dir = self._workspace_dir("chat_stream_context")
        generator = MockGenerator()
        app = self._create_test_app(runtime_dir, generator=generator)
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])
        stored_dir.mkdir(parents=True, exist_ok=True)
        image_path = stored_dir / "chat-context.png"
        Image.new("RGB", (24, 24), color="white").save(image_path)
        self._insert_image_record(
            db,
            image_id="context-image",
            status="stored",
            file_path=image_path,
            created_at="2026-04-01T00:00:00+00:00",
        )
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={
                "content": "Describe the attached image.",
                "context_image_ids": ["context-image"],
            },
        )

        self.assertEqual(response.status_code, 200)
        events = [
            json.loads(line)
            for line in response.data.decode("utf-8").splitlines()
            if line.strip()
        ]
        self.assertEqual(
            [item["type"] for item in events],
            ["message_start", "thinking_delta", "content_delta", "done"],
        )
        self.assertEqual(generator.last_chat_model, "demo-chat-model")
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(generator.last_chat_messages[-1]["role"], "user")
        self.assertIn("images", generator.last_chat_messages[-1])

        messages_response = client.get(
            f"/api/chat/sessions/{session['id']}/messages"
        )
        payload = messages_response.get_json()
        self.assertEqual(len(payload["items"]), 2)
        self.assertEqual(payload["items"][0]["context_image_id"], "context-image")
        self.assertEqual(len(payload["items"][0]["attachments"]), 1)
        self.assertEqual(payload["items"][1]["thinking"], "thinking trace")

    def test_chat_resume_replays_previous_session_messages(self) -> None:
        runtime_dir = self._workspace_dir("chat_resume_context")
        generator = MockGenerator()
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        first_response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "Remember that my favorite color is teal."},
        )
        self.assertEqual(first_response.status_code, 200)
        self.assertTrue(first_response.data)

        second_response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "What color did I say I liked?"},
        )
        self.assertEqual(second_response.status_code, 200)
        self.assertTrue(second_response.data)
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(
            [item["role"] for item in generator.last_chat_messages],
            ["user", "assistant", "user"],
        )
        self.assertEqual(
            generator.last_chat_messages[0]["content"],
            "Remember that my favorite color is teal.",
        )
        self.assertEqual(
            generator.last_chat_messages[1]["content"],
            "generated chat response",
        )
        self.assertEqual(
            generator.last_chat_messages[1]["thinking"],
            "thinking trace",
        )

    def test_chat_stream_accepts_uploaded_context_image_and_replays_it(self) -> None:
        runtime_dir = self._workspace_dir("chat_uploaded_context")
        generator = MockGenerator()
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        upload_buffer = io.BytesIO()
        Image.new("RGB", (18, 10), color="green").save(upload_buffer, format="PNG")
        upload_response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            data={
                "content": "Look at this phone photo.",
                "model_name": "demo-chat-model",
                "image": (io.BytesIO(upload_buffer.getvalue()), "phone-photo.png"),
            },
            content_type="multipart/form-data",
        )

        self.assertEqual(upload_response.status_code, 200)
        self.assertTrue(upload_response.data)
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertIn("images", generator.last_chat_messages[-1])

        messages_payload = client.get(
            f"/api/chat/sessions/{session['id']}/messages"
        ).get_json()
        user_message = messages_payload["items"][0]
        self.assertIsNone(user_message["context_image_id"])
        self.assertIsNotNone(user_message["context_image_url"])
        self.assertEqual(len(user_message["attachments"]), 1)

        preview_path = user_message["context_image_url"].replace("http://localhost", "")
        preview_response = client.get(preview_path)
        self.assertEqual(preview_response.status_code, 200)
        self.assertEqual(preview_response.mimetype, "image/png")
        preview_response.close()

        second_response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "Use the earlier image too."},
        )
        self.assertEqual(second_response.status_code, 200)
        self.assertTrue(second_response.data)
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertIn("images", generator.last_chat_messages[0])

    def test_chat_stream_uses_generated_title_and_request_options(self) -> None:
        runtime_dir = self._workspace_dir("chat_title_and_options")
        generator = MockGenerator()
        generator.chat_title_response = "Trip ideas"
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={
                "content": "Plan me a long weekend in Lisbon.",
                "think": True,
                "context_window": 16384,
            },
        )

        self.assertEqual(response.status_code, 200)
        payload = [
            json.loads(line)
            for line in response.data.decode("utf-8").splitlines()
            if line.strip()
        ][-1]
        self.assertEqual(generator.last_chat_think, True)
        self.assertEqual(generator.last_chat_context_window, 16384)
        self.assertEqual(generator.last_chat_title_context_window, 16384)
        self.assertEqual(
            payload["session"]["title"],
            "Trip ideas",
        )

    def test_chat_stream_runs_enabled_mcp_tool_loop(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_stream")
        generator = MockGenerator()
        generator.chat_responses = [
            {
                "message": {
                    "content": "",
                    "tool_calls": [
                        {
                            "function": {
                                "name": "mcp__library__lookup",
                                "arguments": {"query": "fresh model release notes"},
                            }
                        }
                    ],
                },
                "done": True,
            },
            {
                "message": {"content": "Answer from tool result."},
                "done": True,
            },
        ]
        app = self._create_test_app(runtime_dir, generator=generator)
        mcp_tools = MockMcpToolProvider()
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch("app.api.routes.chat._mcp_tool_provider", return_value=mcp_tools), patch(
            "app.api.routes.chat._ollama_client",
            return_value=MockOllamaClient(),
        ):
            response = client.post(
                f"/api/chat/sessions/{session['id']}/stream",
                json={
                    "content": "Find the current release notes.",
                    "enabled_tool_ids": ["library.lookup"],
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data)
        self.assertEqual(
            mcp_tools.called_tools,
            [("library.lookup", {"query": "fresh model release notes"})],
        )
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(generator.last_chat_messages[-1]["role"], "tool")
        self.assertEqual(
            generator.last_chat_messages[-1]["content"],
            "Tool result for fresh model release notes",
        )
        self.assertIsNotNone(generator.last_chat_tools)
        self.assertEqual(
            generator.last_chat_tools[0]["function"]["name"],
            "mcp__library__lookup",
        )

    def test_chat_stream_rejects_tools_for_non_tool_model(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_non_tool_model")
        generator = MockGenerator()
        app = self._create_test_app(runtime_dir, generator=generator)
        mcp_tools = MockMcpToolProvider()
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch("app.api.routes.chat._mcp_tool_provider", return_value=mcp_tools), patch(
            "app.api.routes.chat._ollama_client",
            return_value=MockOllamaClient(supports_tools=False),
        ):
            response = client.post(
                f"/api/chat/sessions/{session['id']}/stream",
                json={"content": "Use a tool.", "enabled_tool_ids": ["library.lookup"]},
            )

        self.assertEqual(response.status_code, 503)
        self.assertIn("does not support tools", response.get_json()["error"])
        self.assertIsNone(generator.last_chat_messages)

    def test_chat_stream_uses_tool_result_when_final_tool_answer_is_empty(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_empty_final")
        generator = MockGenerator()
        generator.chat_responses = [
            {
                "message": {
                    "content": "",
                    "tool_calls": [
                        {
                            "function": {
                                "name": "mcp__library__lookup",
                                "arguments": {"query": "agent delegated answer"},
                            }
                        }
                    ],
                },
                "done": True,
            },
            {"message": {"content": ""}, "done": True},
        ]
        app = self._create_test_app(runtime_dir, generator=generator)
        mcp_tools = MockMcpToolProvider()
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch(
            "app.api.routes.chat._mcp_tool_provider",
            return_value=mcp_tools,
        ), patch("app.api.routes.chat._ollama_client", return_value=MockOllamaClient()):
            response = client.post(
                f"/api/chat/sessions/{session['id']}/stream",
                json={
                    "content": "Delegate this.",
                    "enabled_tool_ids": ["library.lookup"],
                },
            )

        self.assertEqual(response.status_code, 200)
        events = [
            json.loads(line)
            for line in response.data.decode("utf-8").splitlines()
            if line.strip()
        ]
        content_events = [
            event for event in events if event.get("type") == "content_delta"
        ]
        self.assertTrue(content_events)
        self.assertIn("Last tool result", content_events[-1]["delta"])
        self.assertIn(
            "Tool result for agent delegated answer",
            content_events[-1]["delta"],
        )

    def test_chat_stream_explains_when_model_never_calls_enabled_tools(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_empty_no_tool_call")
        generator = MockGenerator()
        generator.chat_responses = [{"message": {"content": ""}, "done": True}]
        app = self._create_test_app(runtime_dir, generator=generator)
        mcp_tools = MockMcpToolProvider()
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch(
            "app.api.routes.chat._mcp_tool_provider",
            return_value=mcp_tools,
        ), patch("app.api.routes.chat._ollama_client", return_value=MockOllamaClient()):
            response = client.post(
                f"/api/chat/sessions/{session['id']}/stream",
                json={
                    "content": "Delegate this.",
                    "enabled_tool_ids": ["library.lookup"],
                },
            )

        self.assertEqual(response.status_code, 200)
        events = [
            json.loads(line)
            for line in response.data.decode("utf-8").splitlines()
            if line.strip()
        ]
        content_events = [
            event for event in events if event.get("type") == "content_delta"
        ]
        self.assertTrue(content_events)
        self.assertIn("without calling any enabled MCP tool", content_events[-1]["delta"])
        self.assertEqual(mcp_tools.called_tools, [])

    def test_chat_message_job_runs_enabled_mcp_tool_loop(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_job")
        generator = MockGenerator()
        generator.chat_responses = [
            {
                "message": {
                    "content": "",
                    "tool_calls": [
                        {
                            "function": {
                                "name": "mcp__demo__lookup",
                                "arguments": {"query": "agent-selected query"},
                            }
                        }
                    ],
                },
                "done": True,
            },
            {"message": {"content": "Queued answer."}, "done": True},
        ]
        app = self._create_test_app(runtime_dir, generator=generator)
        mcp_tools = MockMcpToolProvider()
        app.extensions["job_worker"]._chat_executor._mcp_tool_provider = mcp_tools
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch("app.api.routes.jobs._mcp_tool_provider", return_value=mcp_tools), patch(
            "app.api.routes.jobs._ollama_client",
            return_value=MockOllamaClient(),
        ):
            response = client.post(
                "/api/jobs/chat-message",
                json={
                    "session_id": session["id"],
                    "content": "Find current model release news.",
                    "model_name": "demo-chat-model",
                    "enabled_tool_ids": ["demo.lookup"],
                },
            )

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["payload"]["enabled_tool_ids"], ["demo.lookup"])
        job = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(job["status"], "completed")
        self.assertEqual(mcp_tools.called_tools, [("demo.lookup", {"query": "agent-selected query"})])
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(generator.last_chat_messages[-1]["role"], "tool")

    def test_chat_message_job_completes_direct_mcp_tool_result(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_job_direct")
        generator = MockGenerator()
        generator.chat_responses = [
            {
                "message": {
                    "content": "",
                    "tool_calls": [
                        {
                            "function": {
                                "name": "mcp__agent__run",
                                "arguments": {"query": "write a file"},
                            }
                        }
                    ],
                },
                "done": True,
            },
            {"message": {"content": "This response should not be needed."}, "done": True},
        ]
        app = self._create_test_app(runtime_dir, generator=generator)
        mcp_tools = MockMcpToolProvider()
        app.extensions["job_worker"]._chat_executor._mcp_tool_provider = mcp_tools
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch("app.api.routes.jobs._mcp_tool_provider", return_value=mcp_tools), patch(
            "app.api.routes.jobs._ollama_client",
            return_value=MockOllamaClient(),
        ):
            response = client.post(
                "/api/jobs/chat-message",
                json={
                    "session_id": session["id"],
                    "content": "Ask the agent to write a file.",
                    "model_name": "demo-chat-model",
                    "enabled_tool_ids": ["agent.run"],
                },
            )

        self.assertEqual(response.status_code, 202)
        job = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(job["status"], "completed")
        assistant = job["result_data"]["assistant_message"]
        self.assertEqual(assistant["content"], "Agent completed write a file")
        self.assertEqual(assistant["tool_traces"][0]["tool_id"], "agent.run")
        self.assertEqual(generator.chat_call_count, 1)

    def test_chat_message_job_rejects_unknown_mcp_tool(self) -> None:
        runtime_dir = self._workspace_dir("chat_mcp_job_missing_tool")
        app = self._create_test_app(runtime_dir)
        mcp_tools = MockMcpToolProvider()
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        with patch("app.api.routes.jobs._mcp_tool_provider", return_value=mcp_tools), patch(
            "app.api.routes.jobs._ollama_client",
            return_value=MockOllamaClient(),
        ):
            response = client.post(
                "/api/jobs/chat-message",
                json={
                    "session_id": session["id"],
                    "content": "Find current model release news.",
                    "model_name": "demo-chat-model",
                    "enabled_tool_ids": ["missing.tool"],
                },
            )

        self.assertEqual(response.status_code, 503)
        self.assertIn("Unknown", response.get_json()["error"])

    def test_chat_stream_accepts_multiple_context_images_and_uploads(self) -> None:
        runtime_dir = self._workspace_dir("chat_multi_context")
        generator = MockGenerator()
        app = self._create_test_app(runtime_dir, generator=generator)
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])
        stored_dir.mkdir(parents=True, exist_ok=True)
        first_path = stored_dir / "chat-context-a.png"
        second_path = stored_dir / "chat-context-b.png"
        Image.new("RGB", (24, 24), color="white").save(first_path)
        Image.new("RGB", (24, 24), color="black").save(second_path)
        self._insert_image_record(
            db,
            image_id="context-image-a",
            status="stored",
            file_path=first_path,
            created_at="2026-04-01T00:00:00+00:00",
        )
        self._insert_image_record(
            db,
            image_id="context-image-b",
            status="stored",
            file_path=second_path,
            created_at="2026-04-01T00:00:01+00:00",
        )
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        upload_buffer = io.BytesIO()
        Image.new("RGB", (18, 10), color="green").save(upload_buffer, format="PNG")
        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            data={
                "content": "Compare these images.",
                "model_name": "demo-chat-model",
                "context_image_ids": json.dumps(
                    ["context-image-a", "context-image-b"]
                ),
                "images": [
                    (io.BytesIO(upload_buffer.getvalue()), "phone-photo.png"),
                ],
            },
            content_type="multipart/form-data",
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data)
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(len(generator.last_chat_messages[-1]["images"]), 3)
        messages_payload = client.get(
            f"/api/chat/sessions/{session['id']}/messages"
        ).get_json()
        user_message = messages_payload["items"][0]
        self.assertEqual(len(user_message["attachments"]), 3)
        self.assertEqual(
            [item["context_image_id"] for item in user_message["attachments"][:2]],
            ["context-image-a", "context-image-b"],
        )
        self.assertIsNotNone(user_message["attachments"][2]["context_image_url"])

    def test_chat_stream_splits_inline_wrapped_thinking(self) -> None:
        runtime_dir = self._workspace_dir("chat_inline_thinking")
        generator = MockGenerator()
        generator.chat_chunks = [
            {"message": {"content": "<|channel>thought"}, "done": False},
            {"message": {"content": "\nstep one\nstep two"}, "done": False},
            {
                "message": {"content": "\n<channel|>Final answer"},
                "total_duration": 100,
                "load_duration": 20,
                "prompt_eval_count": 30,
                "prompt_eval_duration": 40,
                "eval_count": 50,
                "eval_duration": 60,
                "done": True,
            },
        ]
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()

        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "Answer carefully."},
        )

        self.assertEqual(response.status_code, 200)
        events = [
            json.loads(line)
            for line in response.data.decode("utf-8").splitlines()
            if line.strip()
        ]
        self.assertEqual(events[0]["type"], "message_start")
        self.assertEqual(events[-2]["type"], "content_delta")
        self.assertEqual(events[-1]["type"], "done")
        thinking_events = [item for item in events if item["type"] == "thinking_delta"]
        self.assertGreaterEqual(len(thinking_events), 1)
        self.assertEqual(
            "".join(item["delta"] for item in thinking_events),
            "\nstep one\nstep two\n",
        )
        self.assertEqual(events[-2]["delta"], "Final answer")
        messages_payload = client.get(
            f"/api/chat/sessions/{session['id']}/messages"
        ).get_json()
        self.assertEqual(messages_payload["items"][1]["thinking"], "step one\nstep two")
        self.assertEqual(messages_payload["items"][1]["content"], "Final answer")

    def test_chat_stream_includes_session_system_message(self) -> None:
        runtime_dir = self._workspace_dir("chat_system_message")
        generator = MockGenerator()
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={
                "model_name": "demo-chat-model",
                "system_message": "You are a concise assistant who answers in bullet points.",
            },
        ).get_json()

        update_response = client.patch(
            f"/api/chat/sessions/{session['id']}",
            json={"system_message": "Always mention the saved preference first."},
        )
        self.assertEqual(update_response.status_code, 200)
        self.assertEqual(
            update_response.get_json()["system_message"],
            "Always mention the saved preference first.",
        )

        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "What should you keep in mind?"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data)
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(generator.last_chat_messages[0]["role"], "system")
        self.assertEqual(
            generator.last_chat_messages[0]["content"],
            "Always mention the saved preference first.",
        )
        messages_payload = client.get(
            f"/api/chat/sessions/{session['id']}/messages"
        ).get_json()
        self.assertEqual(
            messages_payload["session"]["system_message"],
            "Always mention the saved preference first.",
        )

    def test_chat_stream_summarizes_older_messages_before_sending(self) -> None:
        runtime_dir = self._workspace_dir("chat_summary")
        generator = MockGenerator()
        app = self._create_test_app(
            runtime_dir,
            generator=generator,
            CHAT_SUMMARY_KEEP_RECENT_MESSAGES=4,
            CHAT_SUMMARY_MAX_PENDING_CHARS=20,
        )
        db = app.extensions["db"]
        session = db.create_chat_session(title="New chat", model_name="demo-chat-model")
        db.create_chat_message(
            session_id=session["id"],
            role="user",
            content="First long message about preferences and plans.",
            model_name="demo-chat-model",
        )
        db.create_chat_message(
            session_id=session["id"],
            role="assistant",
            content="First response that should be summarized.",
            thinking="assistant thought one",
            model_name="demo-chat-model",
        )
        db.create_chat_message(
            session_id=session["id"],
            role="user",
            content="Second long message that should stay verbatim.",
            model_name="demo-chat-model",
        )
        db.create_chat_message(
            session_id=session["id"],
            role="assistant",
            content="Third response still in verbatim history.",
            thinking="assistant thought two",
            model_name="demo-chat-model",
        )
        db.create_chat_message(
            session_id=session["id"],
            role="user",
            content="Fourth user turn before the new message.",
            model_name="demo-chat-model",
        )
        client = app.test_client()

        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "Continue the chat."},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data)
        self.assertEqual(generator.last_summary_model, "demo-chat-model")
        self.assertIsNotNone(generator.last_summary_prompt)
        self.assertIsNotNone(generator.last_chat_messages)
        self.assertEqual(generator.last_chat_messages[0]["role"], "system")
        self.assertIn("rolling memory summary", generator.last_chat_messages[0]["content"])
        summary = db.get_chat_session_summary(session["id"])
        self.assertIsNotNone(summary)
        self.assertEqual(summary["summary_text"], "rolling memory summary")
        stored_messages = db.list_chat_messages(session["id"])
        self.assertTrue(stored_messages[0]["summarized_into_memory"])

    def test_chat_models_route_maps_tags_and_running_models(self) -> None:
        runtime_dir = self._workspace_dir("chat_models_route")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()

        class FakeResponse:
            def __init__(self, payload: dict[str, object]) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return self._payload

        def fake_get(url: str, timeout=None):
            if url.endswith("/api/tags"):
                return FakeResponse(
                    {
                        "models": [
                            {
                                "name": "vision-model",
                                "model": "vision-model",
                                "details": {"parameter_size": "4B"},
                            }
                        ]
                    }
                )
            if url.endswith("/api/ps"):
                return FakeResponse(
                    {
                        "models": [
                            {
                                "name": "vision-model",
                                "context_length": 8192,
                                "size_vram": 1234,
                                "expires_at": "2026-04-19T12:00:00Z",
                            }
                        ]
                    }
                )
            raise AssertionError(url)

        def fake_post(url: str, json=None, timeout=None):
            if url.endswith("/api/show"):
                return FakeResponse(
                    {
                        "capabilities": ["vision", "thinking"],
                        "details": {
                            "family": "vision-family",
                            "families": ["vision-family"],
                            "parameter_size": "4B",
                        },
                        "model_info": {
                            "vision.context_length": 32768,
                        },
                    }
                )
            raise AssertionError(url)

        with (
            patch("app.api.routes.requests.get", side_effect=fake_get),
            patch("app.api.routes.requests.post", side_effect=fake_post),
        ):
            response = client.get("/api/chat/models")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["items"][0]["name"], "vision-model")
        self.assertTrue(payload["items"][0]["is_loaded"])
        self.assertEqual(payload["items"][0]["context_length"], 8192)
        self.assertEqual(payload["items"][0]["model_context_length"], 32768)
        self.assertEqual(payload["items"][0]["capabilities"], ["vision", "thinking"])
        self.assertEqual(payload["items"][0]["thinking_mode"], "toggle")

    def test_chat_models_gracefully_skip_show_metadata_failures(self) -> None:
        runtime_dir = self._workspace_dir("chat_models_partial_show")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()

        class FakeResponse:
            def __init__(self, payload: dict[str, object]) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return self._payload

        def fake_get(url: str, timeout=None):
            if url.endswith("/api/tags"):
                return FakeResponse(
                    {
                        "models": [
                            {
                                "name": "gpt-oss-model",
                                "model": "gpt-oss-model",
                                "details": {"parameter_size": "20B"},
                            }
                        ]
                    }
                )
            if url.endswith("/api/ps"):
                return FakeResponse({"models": []})
            raise AssertionError(url)

        def fake_post(url: str, json=None, timeout=None):
            raise requests.RequestException("show failed")

        with (
            patch("app.api.routes.requests.get", side_effect=fake_get),
            patch("app.api.routes.requests.post", side_effect=fake_post),
        ):
            response = client.get("/api/chat/models")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["items"][0]["name"], "gpt-oss-model")
        self.assertEqual(payload["items"][0]["details"]["parameter_size"], "20B")
        self.assertEqual(payload["items"][0]["capabilities"], [])
        self.assertEqual(payload["items"][0]["thinking_mode"], "unsupported")

    def test_chat_stream_rejects_when_queue_is_busy(self) -> None:
        runtime_dir = self._workspace_dir("chat_queue_busy")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        session = client.post(
            "/api/chat/sessions",
            json={"model_name": "demo-chat-model"},
        ).get_json()
        app.extensions["job_worker"].stats = lambda: {"queue_idle": False}

        response = client.post(
            f"/api/chat/sessions/{session['id']}/stream",
            json={"content": "Hello while busy"},
        )

        self.assertEqual(response.status_code, 409)
        self.assertIn("Chat is paused", response.get_json()["error"])

    def test_deleting_chat_session_removes_messages_and_summary(self) -> None:
        runtime_dir = self._workspace_dir("chat_delete_session")
        app = self._create_test_app(runtime_dir)
        db = app.extensions["db"]
        session = db.create_chat_session(title="New chat", model_name="demo-chat-model")
        db.create_chat_message(
            session_id=session["id"],
            role="user",
            content="Hello",
            model_name="demo-chat-model",
        )
        db.upsert_chat_session_summary(
            session_id=session["id"],
            summary_text="summary",
            covered_through_message_id=None,
        )
        client = app.test_client()

        response = client.delete(f"/api/chat/sessions/{session['id']}")

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(db.get_chat_session(session["id"]))
        self.assertEqual(db.list_chat_messages(session["id"]), [])
        self.assertIsNone(db.get_chat_session_summary(session["id"]))

    def test_prompt_generation_evicts_local_models_and_releases_comfy_first(self) -> None:
        catalog = AssetCatalog(
            models=[
                AssetEntry(id="model-a", label="Model A", path="/fixtures/models/model-a.safetensors"),
            ],
            loras=[],
        )
        generator = DiffusersImageGenerator(
            catalog,
            ollama_prompt_model="demo-ollama-model",
        )
        generator._torch = FakeTorch()
        generator._text_pipelines = {"/fixtures/models/model-a.safetensors": FakePipeline()}
        generator._upscale_pipelines = {"/fixtures/models/model-a.safetensors": FakePipeline()}
        generator._active_runtime = "comfy"
        released: list[str] = []

        def fake_release() -> None:
            released.append("comfy")

        generator._comfy_video_manager.release_active_workflow = fake_release

        class FakeResponse:
            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return {"response": "prompt result"}

        with patch("app.generation.service.requests.post", return_value=FakeResponse()):
            result = generator.generate_prompt("expand prompt")

        self.assertEqual(result, "prompt result")
        self.assertEqual(generator._text_pipelines, {})
        self.assertEqual(generator._upscale_pipelines, {})
        self.assertEqual(released, ["comfy"])
        self.assertEqual(generator._active_runtime, "ollama")

    def test_preparing_local_generation_runtime_releases_active_comfy_workflow(self) -> None:
        catalog = AssetCatalog(models=[], loras=[])
        generator = DiffusersImageGenerator(
            catalog,
            ollama_prompt_model="demo-ollama-model",
        )
        generator._active_runtime = "comfy"
        released: list[str] = []

        def fake_release() -> None:
            released.append("comfy")

        generator._comfy_video_manager.release_active_workflow = fake_release

        generator._prepare_local_generation_runtime()

        self.assertEqual(released, ["comfy"])
        self.assertIsNone(generator._active_runtime)

    def test_starting_image_generation_after_prompt_generation_unloads_ollama(self) -> None:
        catalog = AssetCatalog(
            models=[
                AssetEntry(id="model-a", label="Model A", path="/fixtures/models/model-a.safetensors"),
            ],
            loras=[],
        )
        generator = DiffusersImageGenerator(
            catalog,
            ollama_prompt_model="demo-ollama-model",
        )
        generator._torch = FakeTorch()
        generator._weighted_embeddings = lambda *args, **kwargs: (None, None, None, None)
        generator._text_pipeline_cls = object()
        generator._active_runtime = "ollama"
        generated_image = Image.new("RGB", (64, 64), color="white")

        class FakeInferenceMode:
            def __enter__(self):
                return None

            def __exit__(self, exc_type, exc, tb):
                return False

        class FakeGeneratorState:
            def manual_seed(self, seed: int) -> "FakeGeneratorState":
                return self

        class FakePipelineInstance(FakePipeline):
            def __call__(self, **kwargs):
                return type("Result", (), {"images": [generated_image]})()

        class FakeTorchWithGeneration(FakeTorch):
            float16 = object()

            def inference_mode(self):
                return FakeInferenceMode()

            def Generator(self, device: str):
                return FakeGeneratorState()

            def seed(self) -> int:
                return 123

        generator._torch = FakeTorchWithGeneration()
        fake_pipe = FakePipelineInstance()
        generator._get_or_create_text_pipeline = lambda model_path: fake_pipe
        generator._optimize_pipeline = lambda pipe: None
        generator._selected_lora_trigger_words = lambda loras: ""
        generator._dimensions_for_orientation = lambda orientation: (64, 64)
        generator._progress_kwargs = lambda **kwargs: {}
        released_ollama: list[dict[str, object]] = []

        class FakeResponse:
            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return {"response": ""}

        def fake_post(url: str, json=None, timeout=None):
            released_ollama.append(json)
            return FakeResponse()

        output_dir = self._workspace_dir("prompt_runtime_image_switch")
        with patch("app.generation.service.requests.post", side_effect=fake_post):
            artifact = generator.generate(
                GenerationPayload(
                    prompt="portrait",
                    default_positive_prompt="best quality",
                    default_negative_prompt="bad anatomy",
                    model_id="model-a",
                    loras=[],
                ),
                output_dir,
            )

        self.assertEqual(artifact.prompt, "portrait")
        self.assertEqual(released_ollama[0]["keep_alive"], 0)
        self.assertEqual(generator._active_runtime, "local")

    def test_repeated_prompt_generation_reuses_ollama_until_another_runtime_takes_over(self) -> None:
        catalog = AssetCatalog(
            models=[
                AssetEntry(id="model-a", label="Model A", path="/fixtures/models/model-a.safetensors"),
            ],
            loras=[],
        )
        generator = DiffusersImageGenerator(
            catalog,
            ollama_prompt_model="demo-ollama-model",
        )
        generator._torch = FakeTorch()
        requests_payloads: list[dict[str, object]] = []

        class FakeResponse:
            def __init__(self, response_text: str) -> None:
                self._response_text = response_text

            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return {"response": self._response_text}

        def fake_post(url: str, json=None, timeout=None):
            requests_payloads.append(dict(json or {}))
            keep_alive = requests_payloads[-1].get("keep_alive")
            if keep_alive == 0:
                return FakeResponse("")
            return FakeResponse("generated prompt")

        with patch("app.generation.service.requests.post", side_effect=fake_post):
            first = generator.generate_prompt("first")
            second = generator.generate_prompt("second")
            generator._active_runtime = "ollama"
            generator._release_ollama_if_active()

        self.assertEqual(first, "generated prompt")
        self.assertEqual(second, "generated prompt")
        self.assertEqual(
            [payload["keep_alive"] for payload in requests_payloads],
            [-1, -1, 0],
        )

    def test_repeated_chat_stream_reuses_same_ollama_model_until_switch(self) -> None:
        catalog = AssetCatalog(models=[], loras=[])
        generator = DiffusersImageGenerator(
            catalog,
            ollama_prompt_model="prompt-model",
        )
        requests_payloads: list[dict[str, object]] = []

        class FakeGenerateResponse:
            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return {"response": ""}

        class FakeStreamResponse:
            def __enter__(self) -> "FakeStreamResponse":
                return self

            def __exit__(self, exc_type, exc, tb) -> bool:
                return False

            def raise_for_status(self) -> None:
                return None

            def iter_lines(self, decode_unicode: bool = False):
                payload = {
                    "message": {"content": "streamed"},
                    "done": True,
                }
                line = json.dumps(payload)
                yield line if decode_unicode else line.encode("utf-8")

        def fake_post(url: str, json=None, timeout=None, stream=False):
            requests_payloads.append(dict(json or {}))
            if stream:
                return FakeStreamResponse()
            return FakeGenerateResponse()

        with patch("app.generation.service.requests.post", side_effect=fake_post):
            list(
                generator.stream_chat(
                    model="chat-model-a",
                    messages=[{"role": "user", "content": "hi"}],
                )
            )
            list(
                generator.stream_chat(
                    model="chat-model-a",
                    messages=[{"role": "user", "content": "again"}],
                )
            )
            list(
                generator.stream_chat(
                    model="chat-model-b",
                    messages=[{"role": "user", "content": "switch"}],
                )
            )

        self.assertEqual(
            [payload["keep_alive"] for payload in requests_payloads],
            [-1, -1, 0, -1],
        )
        self.assertEqual(requests_payloads[2]["model"], "chat-model-a")
        self.assertEqual(requests_payloads[3]["model"], "chat-model-b")

    def test_ollama_prompt_sanitizer_removes_thinking_block(self) -> None:
        result = OllamaPromptRuntimeManager._sanitize_generated_prompt(
            "<think>hidden chain of thought</think>\ncinematic portrait, soft light"
        )

        self.assertEqual(result, "cinematic portrait, soft light")

    def test_ollama_prompt_sanitizer_removes_channel_thought_block(self) -> None:
        result = OllamaPromptRuntimeManager._sanitize_generated_prompt(
            "<|channel>thought\ninternal notes\n<channel|>\ncinematic portrait"
        )

        self.assertEqual(result, "cinematic portrait")

    def test_ollama_prompt_generation_includes_image_payload_when_present(self) -> None:
        manager = OllamaPromptRuntimeManager(
            base_url="http://127.0.0.1:11434",
            model="demo-ollama-model",
            timeout_seconds=30.0,
        )
        requests_payloads: list[dict[str, object]] = []

        class FakeResponse:
            def raise_for_status(self) -> None:
                return None

            def json(self) -> dict[str, object]:
                return {"message": {"content": "generated prompt"}}

        def fake_post(url: str, json=None, timeout=None):
            requests_payloads.append(dict(json or {}))
            return FakeResponse()

        with patch("app.generation.service.requests.post", side_effect=fake_post):
            result = manager.generate_prompt(
                "describe this image",
                keep_alive=-1,
                image_bytes=b"fake-image-bytes",
            )

        self.assertEqual(result, "generated prompt")
        self.assertEqual(
            requests_payloads[0]["messages"][0]["images"],
            ["ZmFrZS1pbWFnZS1ieXRlcw=="],
        )
