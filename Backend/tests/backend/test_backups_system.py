from __future__ import annotations

from .shared import *


class BackupsSystemTests(BackendTestCase):
    def test_backup_routes_create_list_and_delete_archives(self) -> None:
        runtime_dir = self._workspace_dir("backups")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": f"file:backup-routes-{uuid.uuid4().hex}?mode=memory&cache=shared",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, response.get_json()["job_id"])
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        temp_dir = Path(app.config["TEMP_DIR"])
        Image.new("RGB", (5, 5)).save(temp_dir / "leftover-temp.png")
        errors_dir = Path(app.config["ERRORS_DIR"])
        errors_dir.mkdir(parents=True, exist_ok=True)
        (errors_dir / "sample-error.json").write_text(
            json.dumps(
                {
                    "id": "sample-error",
                    "logged_at": "2026-01-01T00:00:00+00:00",
                    "error_text": "Example failure",
                    "job": {"job_id": "job-1", "type": "generate", "payload": {}},
                }
            ),
            encoding="utf-8",
        )

        create_response = client.post("/api/backups")
        self.assertEqual(create_response.status_code, 201)
        backup_name = create_response.get_json()["name"]
        self.assertTrue(backup_name.startswith("noviagen-backup-"))

        listing_response = client.get("/api/backups")
        self.assertEqual(listing_response.status_code, 200)
        self.assertEqual(listing_response.get_json()["items"][0]["name"], backup_name)

        backup_path = Path(app.config["BACKUPS_DIR"]) / backup_name
        self.assertTrue(backup_path.exists())
        with zipfile.ZipFile(backup_path) as archive:
            names = archive.namelist()
        self.assertIn("app.db", names)
        self.assertTrue(any(name.startswith("stored/") for name in names))
        self.assertIn("errors/sample-error.json", names)
        self.assertFalse(any(name.startswith("temp/") for name in names))
        self.assertFalse(any("backups/" in name for name in names))

        delete_response = client.delete(f"/api/backups/{backup_name}")
        self.assertEqual(delete_response.status_code, 200)

    def test_app_backup_routes_create_list_get_and_delete(self) -> None:
        runtime_dir = self._workspace_dir("app_backups")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": f"file:app-backup-routes-{uuid.uuid4().hex}?mode=memory&cache=shared",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        payload = {
            "type": "noviagen_app_data_backup",
            "schema_version": 1,
            "created_at": "2026-01-01T00:00:00Z",
            "preferences": {
                "base_url": "http://example.invalid:5000",
                "theme_mode": "dark",
                "gallery_include_tags": ["portrait", "favorites"],
                "guidance_scale": 5.5,
                "video_loop_enabled": True,
            },
        }

        create_response = client.post("/api/app-backups", json=payload)
        self.assertEqual(create_response.status_code, 201)
        backup_name = create_response.get_json()["name"]
        self.assertTrue(backup_name.startswith("noviagen-app-backup-"))

        listing_response = client.get("/api/app-backups")
        self.assertEqual(listing_response.status_code, 200)
        self.assertEqual(listing_response.get_json()["items"][0]["name"], backup_name)

        fetch_response = client.get(f"/api/app-backups/{backup_name}")
        self.assertEqual(fetch_response.status_code, 200)
        self.assertEqual(fetch_response.get_json(), payload)

        backup_path = Path(app.config["BACKUPS_DIR"]) / backup_name
        self.assertTrue(backup_path.exists())

        delete_response = client.delete(f"/api/app-backups/{backup_name}")
        self.assertEqual(delete_response.status_code, 200)
        self.assertFalse(backup_path.exists())

    def test_app_backup_routes_accept_legacy_backup_filenames(self) -> None:
        runtime_dir = self._workspace_dir("legacy_app_backups")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": f"file:legacy-app-backup-routes-{uuid.uuid4().hex}?mode=memory&cache=shared",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        payload = {
            "type": "obscure_app_data_backup",
            "schema_version": 1,
            "created_at": "2026-01-01T00:00:00Z",
            "preferences": {"theme_mode": "dark"},
        }
        backup_name = "obscure-app-backup-2026-01-01T00-00-00Z.json"
        backup_path = Path(app.config["BACKUPS_DIR"]) / backup_name
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        backup_path.write_text(json.dumps(payload), encoding="utf-8")

        listing_response = client.get("/api/app-backups")
        self.assertEqual(listing_response.status_code, 200)
        listed_names = [item["name"] for item in listing_response.get_json()["items"]]
        self.assertIn(backup_name, listed_names)

        fetch_response = client.get(f"/api/app-backups/{backup_name}")
        self.assertEqual(fetch_response.status_code, 200)
        self.assertEqual(fetch_response.get_json(), payload)

        delete_response = client.delete(f"/api/app-backups/{backup_name}")
        self.assertEqual(delete_response.status_code, 200)
        self.assertFalse(backup_path.exists())

    def test_backup_routes_apply_archive(self) -> None:
        runtime_dir = self._workspace_dir("backup_apply")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": f"file:backup-apply-routes-{uuid.uuid4().hex}?mode=memory&cache=shared",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, response.get_json()["job_id"])
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        errors_dir = Path(app.config["ERRORS_DIR"])
        errors_dir.mkdir(parents=True, exist_ok=True)
        (errors_dir / "sample-error.json").write_text(
            json.dumps(
                {
                    "id": "sample-error",
                    "logged_at": "2026-01-01T00:00:00+00:00",
                    "error_text": "Example failure",
                    "job": {"job_id": "job-1", "type": "generate", "payload": {}},
                }
            ),
            encoding="utf-8",
        )

        create_response = client.post("/api/backups")
        self.assertEqual(create_response.status_code, 201)
        backup_name = create_response.get_json()["name"]

        client.delete(f"/api/images/{image_id}")
        self.assertEqual(client.get("/api/images/stored").get_json()["items"], [])
        (errors_dir / "sample-error.json").unlink()
        self.assertEqual(client.get("/api/errors").get_json()["items"], [])

        apply_response = client.post(f"/api/backups/{backup_name}/apply")
        self.assertEqual(apply_response.status_code, 200)

        restored_items = client.get("/api/images/stored").get_json()["items"]
        self.assertEqual(len(restored_items), 1)
        self.assertEqual(restored_items[0]["id"], image_id)
        self.assertTrue((errors_dir / "sample-error.json").exists())

    def test_backup_routes_merge_archive_ignores_duplicates(self) -> None:
        runtime_dir = self._workspace_dir("backup_merge")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": f"file:backup-merge-routes-{uuid.uuid4().hex}?mode=memory&cache=shared",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        first_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        first_job = self._wait_for_job(client, first_response.get_json()["job_id"])
        first_image_id = first_job["result"]["id"]
        client.post(f"/api/images/{first_image_id}/store")

        errors_dir = Path(app.config["ERRORS_DIR"])
        errors_dir.mkdir(parents=True, exist_ok=True)
        duplicate_error_path = errors_dir / "shared-error.json"
        duplicate_error_path.write_text(
            json.dumps({"source": "backup"}),
            encoding="utf-8",
        )

        create_response = client.post("/api/backups")
        self.assertEqual(create_response.status_code, 201)
        backup_name = create_response.get_json()["name"]

        second_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "landscape",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        second_job = self._wait_for_job(client, second_response.get_json()["job_id"])
        second_image_id = second_job["result"]["id"]
        client.post(f"/api/images/{second_image_id}/store")

        duplicate_error_path.write_text(
            json.dumps({"source": "current"}),
            encoding="utf-8",
        )

        apply_response = client.post(
            f"/api/backups/{backup_name}/apply",
            json={"mode": "merge"},
        )
        self.assertEqual(apply_response.status_code, 200)

        restored_items = client.get("/api/images/stored").get_json()["items"]
        restored_ids = [item["id"] for item in restored_items]
        self.assertEqual(len(restored_ids), 2)
        self.assertCountEqual(restored_ids, [first_image_id, second_image_id])
        self.assertEqual(
            json.loads(duplicate_error_path.read_text(encoding="utf-8"))["source"],
            "current",
        )

    def test_backup_routes_apply_requires_no_active_jobs(self) -> None:
        runtime_dir = self._workspace_dir("backup_apply_active_jobs")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": f"file:backup-apply-active-{uuid.uuid4().hex}?mode=memory&cache=shared",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        create_response = client.post("/api/backups")
        self.assertEqual(create_response.status_code, 201)
        backup_name = create_response.get_json()["name"]

        with app.app_context():
            app.extensions["db"].insert_job(
                job_id="job-queued",
                job_type="generate",
                payload={"prompt": "test"},
            )

        apply_response = client.post(f"/api/backups/{backup_name}/apply")
        self.assertEqual(apply_response.status_code, 409)

    def test_shutdown_route_uses_platform_specific_command(self) -> None:
        runtime_dir = self._workspace_dir("shutdown")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "SERVER_RESTART_COMMAND": ["python", "-m", "Backend"],
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Linux"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                return_value=subprocess.CompletedProcess(
                    args=["shutdown", "now"],
                    returncode=0,
                ),
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post("/api/system/shutdown")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["platform"], "Linux")
        run_mock.assert_called_once_with(
            ["shutdown", "now"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_shutdown_route_uses_windows_poweroff_command(self) -> None:
        runtime_dir = self._workspace_dir("shutdown_windows")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Windows"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                return_value=subprocess.CompletedProcess(
                    args=["shutdown", "/p", "/f"],
                    returncode=0,
                ),
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post("/api/system/shutdown")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["platform"], "Windows")
        run_mock.assert_called_once_with(
            ["shutdown", "/p", "/f"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_shutdown_route_honors_configured_host_shutdown_command(self) -> None:
        runtime_dir = self._workspace_dir("shutdown_custom_command")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "HOST_SHUTDOWN_COMMAND": ["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Linux"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                return_value=subprocess.CompletedProcess(
                    args=["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
                    returncode=0,
                ),
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post("/api/system/shutdown")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(
            response.get_json()["command"],
            ["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
        )
        run_mock.assert_called_once_with(
            ["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_shutdown_route_falls_back_to_systemctl_poweroff_command(self) -> None:
        runtime_dir = self._workspace_dir("shutdown_linux_systemctl_fallback")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Linux"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                side_effect=[
                    subprocess.CompletedProcess(
                        args=["shutdown", "now"],
                        returncode=1,
                        stderr="access denied",
                    ),
                    subprocess.CompletedProcess(
                        args=["systemctl", "poweroff"],
                        returncode=0,
                    ),
                ],
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post("/api/system/shutdown")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["command"], ["shutdown", "now"])
        self.assertEqual(
            [call.args[0] for call in run_mock.call_args_list],
            [["shutdown", "now"], ["systemctl", "poweroff"]],
        )

    def test_shutdown_route_falls_back_to_poweroff_command(self) -> None:
        runtime_dir = self._workspace_dir("shutdown_linux_poweroff_fallback")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Linux"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                side_effect=[
                    subprocess.CompletedProcess(
                        args=["shutdown", "now"],
                        returncode=1,
                        stderr="denied",
                    ),
                    subprocess.CompletedProcess(
                        args=["systemctl", "poweroff"],
                        returncode=1,
                        stderr="denied",
                    ),
                    subprocess.CompletedProcess(
                        args=["poweroff"],
                        returncode=0,
                    ),
                ],
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post("/api/system/shutdown")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["command"], ["shutdown", "now"])
        self.assertEqual(
            [call.args[0] for call in run_mock.call_args_list],
            [["shutdown", "now"], ["systemctl", "poweroff"], ["poweroff"]],
        )

    def test_restart_server_route_requests_in_process_restart(self) -> None:
        runtime_dir = self._workspace_dir("restart_server")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        shutdown_mock = unittest.mock.Mock()

        with (
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post(
                "/api/system/restart-server",
                environ_overrides={"werkzeug.server.shutdown": shutdown_mock},
            )

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["strategy"], "in_process_restart")
        shutdown_mock.assert_called_once_with()

    def test_restart_server_route_uses_service_command_restart(self) -> None:
        runtime_dir = self._workspace_dir("restart_server_service")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with patch.dict(os.environ, {}, clear=True):
            app = create_app(
                test_config={
                    "TESTING": True,
                    "MODELS_DIR": str(models_dir),
                    "LORAS_DIR": str(loras_dir),
                    "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                    "DATA_DIR": str(data_dir),
                    "TEMP_DIR": str(data_dir / "temp"),
                    "STORED_DIR": str(data_dir / "stored"),
                    "BACKUPS_DIR": str(data_dir / "backups"),
                    "DB_PATH": ":memory:",
                    "TEMP_TTL_SECONDS": 7200,
                    "CLEANUP_INTERVAL_SECONDS": 3600,
                    "SERVER_RESTART_COMMAND": ["python", "-m", "Backend"],
                },
                generator=MockGenerator(),
            )
        client = app.test_client()

        with (
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
            patch.object(
                app.extensions["shutdown_controller"],
                "_restartable_parent_pid",
                return_value=None,
            ),
            patch("app.system.shutdown.subprocess.Popen") as popen_mock,
        ):
            response = client.post("/api/system/restart-server")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["strategy"], "service_command_restart")
        self.assertEqual(response.get_json()["command"], ["python", "-m", "Backend"])
        popen_mock.assert_called_once_with(["python", "-m", "Backend"])

    def test_restart_server_route_honors_custom_service_command(self) -> None:
        runtime_dir = self._workspace_dir("restart_server_custom_service")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "SERVER_RESTART_COMMAND": ["service", "noviagen", "restart"],
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
            patch.object(
                app.extensions["shutdown_controller"],
                "_restartable_parent_pid",
                return_value=None,
            ),
            patch("app.system.shutdown.subprocess.Popen") as popen_mock,
        ):
            response = client.post("/api/system/restart-server")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["strategy"], "service_command_restart")
        self.assertEqual(response.get_json()["command"], ["service", "noviagen", "restart"])
        popen_mock.assert_called_once_with(["service", "noviagen", "restart"])

    def test_restart_server_route_rejects_invalid_service_command(self) -> None:
        runtime_dir = self._workspace_dir("restart_server_invalid_service")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "SERVER_RESTART_COMMAND": [],
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        with patch.object(
            app.extensions["shutdown_controller"],
            "_restartable_parent_pid",
            return_value=None,
        ):
            response = client.post("/api/system/restart-server")

        self.assertEqual(response.status_code, 501)
        self.assertIn("restart command", response.get_json()["error"])

    def test_restart_server_route_restarts_gunicorn_parent_process(self) -> None:
        runtime_dir = self._workspace_dir("restart_server_parent_process")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
            patch.object(
                app.extensions["shutdown_controller"],
                "_restartable_parent_pid",
                return_value=4321,
            ),
            patch("app.system.shutdown.os.kill") as kill_mock,
        ):
            response = client.post("/api/system/restart-server")

        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.get_json()["strategy"], "parent_process_restart")
        self.assertEqual(response.get_json()["pid"], 4321)
        self.assertEqual(response.get_json()["signal"], "SIGTERM")
        kill_mock.assert_called_once_with(4321, signal.SIGTERM)

    def test_system_logs_route_rejects_invalid_source(self) -> None:
        runtime_dir = self._workspace_dir("system_logs_invalid_source")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()

        response = client.get("/api/system/logs?source=nope")

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "source must be one of: server, comfy")

    def test_system_logs_route_uses_default_limit_and_reads_rotated_history(self) -> None:
        runtime_dir = self._workspace_dir("system_logs_rotated")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        logs_dir = Path(app.config["LOGS_DIR"])
        (logs_dir / "server.log.1").write_text(
            "2026-04-18 10:00:00,001 INFO [gunicorn.error] booting worker\n",
            encoding="utf-8",
        )
        (logs_dir / "server.log").write_text(
            "2026-04-18 10:00:01,002 WARNING [app] queue warming\n",
            encoding="utf-8",
        )

        response = client.get("/api/system/logs?source=server")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["source"], "server")
        self.assertEqual(payload["display_name"], "Server")
        self.assertEqual(payload["limit"], 400)
        self.assertFalse(payload["truncated"])
        self.assertEqual(
            [row["message"] for row in payload["rows"]],
            ["booting worker", "queue warming"],
        )
        self.assertEqual(payload["rows"][0]["logger"], "gunicorn.error")
        self.assertEqual(payload["rows"][1]["level"], "WARNING")

    def test_system_logs_route_caps_large_limit_and_parses_comfy_rows(self) -> None:
        runtime_dir = self._workspace_dir("system_logs_cap")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        logs_dir = Path(app.config["LOGS_DIR"])

        lines = []
        for index in range(2105):
            lines.append(
                f"2026-04-18 10:00:{index % 60:02d},000 INFO [noviagen.comfy] comfy line {index}\n"
            )
        (logs_dir / "comfy.log").write_text("".join(lines), encoding="utf-8")

        response = client.get("/api/system/logs?source=comfy&limit=99999")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["display_name"], "Comfy")
        self.assertEqual(payload["limit"], 2000)
        self.assertTrue(payload["truncated"])
        self.assertEqual(len(payload["rows"]), 2000)
        self.assertEqual(payload["rows"][0]["message"], "comfy line 105")
        self.assertEqual(payload["rows"][-1]["message"], "comfy line 2104")

    def test_system_logs_route_returns_empty_rows_for_missing_log_file(self) -> None:
        runtime_dir = self._workspace_dir("system_logs_empty")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()

        response = client.get("/api/system/logs?source=comfy&limit=200")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["source"], "comfy")
        self.assertEqual(payload["rows"], [])
        self.assertFalse(payload["truncated"])

    def test_managed_log_store_pumps_comfy_stdout_and_stderr(self) -> None:
        runtime_dir = self._workspace_dir("comfy_log_pump")
        logs_dir = runtime_dir / "logs"
        store = ManagedLogStore(
            logs_dir=logs_dir,
            max_bytes=1024 * 1024,
            backup_count=2,
            formatter=logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s"),
        )

        class FakeProcess:
            stdout = io.StringIO("booting comfy\nready\n")
            stderr = io.StringIO("gpu warning\n")

        threads = store.start_comfy_log_pumps(FakeProcess())
        for thread in threads:
            thread.join(timeout=2)

        snapshot = store.read_snapshot("comfy", limit=10)
        messages = [row["message"] for row in snapshot["rows"]]
        levels = {row["message"]: row["level"] for row in snapshot["rows"]}
        self.assertEqual(len(messages), 3)
        self.assertIn("booting comfy", messages)
        self.assertIn("ready", messages)
        self.assertIn("gpu warning", messages)
        self.assertEqual(levels["booting comfy"], "INFO")
        self.assertEqual(levels["ready"], "INFO")
        self.assertEqual(levels["gpu warning"], "WARNING")

    def test_request_logging_includes_method_path_and_status(self) -> None:
        runtime_dir = self._workspace_dir("request_logging")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        with self.assertLogs(app.logger.name, level="INFO") as captured_logs:
            response = client.get("/api/jobs?page=1&page_size=5")

        self.assertEqual(response.status_code, 200)
        request_logs = "\n".join(captured_logs.output)
        self.assertIn("GET /api/jobs?page=1&page_size=5", request_logs)
        self.assertIn(" 200 ", request_logs)

    def test_shutdown_when_idle_route_schedules_shutdown_after_queue_drains(self) -> None:
        runtime_dir = self._workspace_dir("shutdown_when_idle")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=SlowMockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        self.assertEqual(response.status_code, 202)
        job_id = response.get_json()["job_id"]

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Linux"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                return_value=subprocess.CompletedProcess(
                    args=["shutdown", "now"],
                    returncode=0,
                ),
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            self._wait_for_status(client, job_id, {"running"})
            enable_response = client.post("/api/system/shutdown-when-idle")
            self.assertEqual(enable_response.status_code, 200)
            self.assertTrue(enable_response.get_json()["shutdown_when_idle"])
            self.assertFalse(enable_response.get_json()["scheduled"])

            self._wait_for_status(client, job_id, {"completed"})
            deadline = time.time() + 1.0
            while run_mock.call_count == 0 and time.time() < deadline:
                time.sleep(0.01)

        run_mock.assert_called_once_with(
            ["shutdown", "now"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        status_response = client.get("/api/system/shutdown-when-idle")
        self.assertEqual(status_response.status_code, 200)
        self.assertFalse(status_response.get_json()["shutdown_when_idle"])

    def test_shutdown_when_idle_route_schedules_shutdown_immediately_when_idle(self) -> None:
        runtime_dir = self._workspace_dir("shutdown_when_idle_immediate")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "HOST_SHUTDOWN_COMMAND": ["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        class ImmediateThread:
            def __init__(self, *, target, **_: object) -> None:
                self._target = target

            def start(self) -> None:
                self._target()

        with (
            patch("app.system.shutdown.platform.system", return_value="Linux"),
            patch("app.system.shutdown.time.sleep", return_value=None),
            patch(
                "app.system.shutdown.subprocess.run",
                return_value=subprocess.CompletedProcess(
                    args=["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
                    returncode=0,
                ),
            ) as run_mock,
            patch("app.system.shutdown.threading.Thread", ImmediateThread),
        ):
            response = client.post("/api/system/shutdown-when-idle")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertFalse(payload["shutdown_when_idle"])
        self.assertTrue(payload["scheduled"])
        self.assertEqual(
            payload["shutdown"]["command"],
            ["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
        )
        run_mock.assert_called_once_with(
            ["sudo", "-n", "/usr/bin/systemctl", "poweroff"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_system_info_route_returns_backend_snapshot(self) -> None:
        runtime_dir = self._workspace_dir("system_info_route")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(data_dir / "stored"),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()
        expected = {
            "platform": {"system": "Linux"},
            "cpu": {
                "model": "Test CPU",
                "physical_cores": 8,
                "logical_cores": 16,
                "utilization_percent": 21.5,
            },
            "memory": {"total_bytes": 1024, "available_bytes": 512},
            "gpus": [
                {
                    "name": "Test GPU",
                    "vendor": "NVIDIA",
                    "vram_total_bytes": 2048,
                    "vram_free_bytes": 1024,
                    "utilization_percent": 84.0,
                    "driver_version": "1.0",
                    "source": "nvidia-smi",
                }
            ],
            "collected_at": "2026-04-15T12:00:00+00:00",
        }

        with patch("app.api.routes.system.collect_system_info", return_value=expected):
            response = client.get("/api/system/info")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), expected)

    def test_collect_system_info_uses_windows_commands(self) -> None:
        calls: list[list[str]] = []

        def fake_run_command(args: list[str]) -> CommandResult:
            calls.append(args)
            joined = " ".join(args)
            if args[0] == "powershell.exe" and "Win32_Processor" in joined:
                return CommandResult(
                    ok=True,
                    stdout='{"Name":"AMD Ryzen 7 7800X3D","NumberOfCores":8,"NumberOfLogicalProcessors":16}',
                    stderr="",
                )
            if args[0] == "powershell.exe" and "Win32_PerfFormattedData_PerfOS_Processor" in joined:
                return CommandResult(
                    ok=True,
                    stdout='{"PercentProcessorTime":37}',
                    stderr="",
                )
            if args[0] == "powershell.exe" and "Win32_OperatingSystem" in joined:
                return CommandResult(
                    ok=True,
                    stdout='{"TotalVisibleMemorySize":33554432,"FreePhysicalMemory":16777216}',
                    stderr="",
                )
            if args[0] == "nvidia-smi":
                return CommandResult(
                    ok=True,
                    stdout="NVIDIA GeForce RTX 4090, 24564, 20000, 555.99, 91",
                    stderr="",
                )
            return CommandResult(ok=False, stdout="", stderr="")

        with (
            patch("app.system.info.platform.system", return_value="Windows"),
            patch("app.system.info.platform.release", return_value="11"),
            patch("app.system.info.platform.version", return_value="10.0.26100"),
            patch("app.system.info.platform.machine", return_value="AMD64"),
            patch("app.system.info.platform.node", return_value="render-box"),
            patch("app.system.commands.shutil.which", return_value="powershell.exe"),
            patch("app.system.commands._run_command", side_effect=fake_run_command),
            patch("app.system.gpu_info._run_command", side_effect=fake_run_command),
        ):
            info = collect_system_info()

        self.assertEqual(info["platform"]["system"], "Windows")
        self.assertEqual(info["cpu"]["model"], "AMD Ryzen 7 7800X3D")
        self.assertEqual(info["cpu"]["physical_cores"], 8)
        self.assertEqual(info["cpu"]["logical_cores"], 16)
        self.assertEqual(info["cpu"]["utilization_percent"], 37.0)
        self.assertEqual(info["memory"]["total_bytes"], 33554432 * 1024)
        self.assertEqual(info["memory"]["available_bytes"], 16777216 * 1024)
        self.assertEqual(info["gpus"][0]["name"], "NVIDIA GeForce RTX 4090")
        self.assertEqual(info["gpus"][0]["vram_total_bytes"], 24564 * 1024 * 1024)
        self.assertEqual(info["gpus"][0]["vram_free_bytes"], 20000 * 1024 * 1024)
        self.assertEqual(info["gpus"][0]["utilization_percent"], 91.0)
        self.assertEqual(info["gpus"][0]["source"], "nvidia-smi")
        self.assertEqual(calls[0][0], "powershell.exe")
        self.assertIn("Win32_Processor", calls[0][-1])
        self.assertEqual(calls[1][0], "powershell.exe")
        self.assertIn("Win32_PerfFormattedData_PerfOS_Processor", calls[1][-1])
        self.assertEqual(calls[2][0], "powershell.exe")
        self.assertIn("Win32_OperatingSystem", calls[2][-1])
        self.assertEqual(calls[3][0], "nvidia-smi")

    def test_collect_system_info_uses_linux_commands(self) -> None:
        calls: list[list[str]] = []

        def fake_run_command(args: list[str]) -> CommandResult:
            calls.append(args)
            if args[:2] == ["lscpu", "-J"]:
                return CommandResult(
                    ok=True,
                    stdout=json.dumps(
                        {
                            "lscpu": [
                                {"field": "Model name:", "data": "AMD EPYC 7502P"},
                                {"field": "Socket(s):", "data": "1"},
                                {"field": "Core(s) per socket:", "data": "32"},
                                {"field": "CPU(s):", "data": "64"},
                            ]
                        }
                    ),
                    stderr="",
                )
            if args[:2] == ["free", "-b"]:
                return CommandResult(
                    ok=True,
                    stdout=(
                        "               total        used        free      shared  buff/cache   available\n"
                        "Mem:     270131314688 1234567890 9876543210           0  1000000000 260000000000\n"
                    ),
                    stderr="",
                )
            if args[0] == "nvidia-smi":
                return CommandResult(ok=False, stdout="", stderr="not found")
            if args[0] == "rocm-smi":
                return CommandResult(ok=False, stdout="", stderr="not found")
            if args[0] == "lspci":
                return CommandResult(
                    ok=True,
                    stdout="01:00.0 VGA compatible controller: NVIDIA Corporation AD102 [GeForce RTX 4090]",
                    stderr="",
                )
            return CommandResult(ok=False, stdout="", stderr="")

        with (
            patch("app.system.info.platform.system", return_value="Linux"),
            patch("app.system.info.platform.release", return_value="6.8.0"),
            patch("app.system.info.platform.version", return_value="#1 SMP"),
            patch("app.system.info.platform.machine", return_value="x86_64"),
            patch("app.system.info.platform.node", return_value="linux-box"),
            patch("app.system.cpu_info._run_command", side_effect=fake_run_command),
            patch("app.system.gpu_info._run_command", side_effect=fake_run_command),
            patch("app.system.memory_info._run_command", side_effect=fake_run_command),
            patch("app.system.cpu_info.os.cpu_count", return_value=64),
            patch(
                "app.system.cpu_info._read_linux_cpu_times",
                side_effect=[{"idle": 100, "total": 1000}, {"idle": 130, "total": 1100}],
            ),
            patch("app.system.cpu_info.time.sleep", return_value=None),
            patch("app.system.gpu_info._read_linux_sysfs_vram_total", return_value=None),
            patch("app.system.gpu_info._read_linux_sysfs_gpu_utilization", return_value=63.0),
        ):
            info = collect_system_info()

        self.assertEqual(info["platform"]["system"], "Linux")
        self.assertEqual(info["cpu"]["model"], "AMD EPYC 7502P")
        self.assertEqual(info["cpu"]["physical_cores"], 32)
        self.assertEqual(info["cpu"]["logical_cores"], 64)
        self.assertEqual(info["cpu"]["utilization_percent"], 70.0)
        self.assertEqual(info["memory"]["total_bytes"], 270131314688)
        self.assertEqual(info["memory"]["available_bytes"], 260000000000)
        self.assertEqual(info["gpus"][0]["name"], "NVIDIA Corporation AD102 [GeForce RTX 4090]")
        self.assertEqual(info["gpus"][0]["vendor"], "NVIDIA")
        self.assertEqual(info["gpus"][0]["utilization_percent"], 63.0)
        self.assertEqual(info["gpus"][0]["source"], "lspci")
        self.assertEqual(calls[0], ["lscpu", "-J"])
        self.assertEqual(calls[1], ["free", "-b"])
        self.assertEqual(calls[2][0], "nvidia-smi")
        self.assertEqual(calls[3][0], "rocm-smi")
        self.assertEqual(calls[4][0], "lspci")
