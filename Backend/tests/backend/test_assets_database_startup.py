from __future__ import annotations

import threading

from .shared import *


class AssetsDatabaseStartupTests(BackendTestCase):
    def test_compose_positive_prompt(self) -> None:
        self.assertEqual(
            compose_positive_prompt("best quality", "portrait of a fox"),
            "best quality, portrait of a fox",
        )
        self.assertEqual(compose_positive_prompt("", "portrait of a fox"), "portrait of a fox")
        self.assertEqual(compose_positive_prompt("best quality", ""), "best quality")
        self.assertEqual(
            compose_positive_prompt("best quality", "portrait of a fox", "retro, cyberpunk"),
            "best quality, portrait of a fox, retro, cyberpunk",
        )

    def test_asset_catalog_scans_directories(self) -> None:
        runtime_dir = self._workspace_dir("assets")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        (models_dir / "demo model.safetensors").write_bytes(b"")
        (models_dir / "demo_model.safetensors").write_bytes(b"")
        (lora_triggers_dir / "demo-lora.txt").write_text("retro, cyberpunk", encoding="utf-8")
        catalog = AssetCatalog.from_directories(
            models_dir,
            loras_dir,
            lora_triggers_dir=lora_triggers_dir,
        )

        self.assertIn("demo_model", [item["id"] for item in catalog.list_models()])
        self.assertEqual(catalog.list_loras()[0]["default_strength"], 0.85)
        self.assertEqual(normalize_asset_id("detail booster_XL_V1.0"), "detail_booster_XL_V1_0")
        self.assertIn("demo_model", [item["id"] for item in catalog.list_models()])
        self.assertIn("demo_model_2", [item["id"] for item in catalog.list_models()])
        self.assertEqual(catalog.get_lora("demo_lora").trigger_words, "retro, cyberpunk")

    def test_asset_catalog_filters_video_component_files(self) -> None:
        runtime_dir = self._workspace_dir("video_assets")
        models_dir, loras_dir, _, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_test_video_bundle_dir(runtime_dir)

        catalog = AssetCatalog.from_directories(
            models_dir,
            loras_dir,
            video_models_dir=video_models_dir,
        )

        self.assertEqual(
            [item["label"] for item in catalog.list_video_models()],
            [
                "test_video_variant_high",
                "test_video_variant_low",
            ],
        )

    def test_build_legacy_asset_id_maps_and_db_remap(self) -> None:
        runtime_dir = self._workspace_dir("remap")
        assets_path = runtime_dir / "assets.yaml"
        assets_path.write_text(ASSETS_YAML, encoding="utf-8")
        models_dir, loras_dir, _, _ = self._create_demo_asset_dirs(runtime_dir)
        legacy_catalog = AssetCatalog.from_file(assets_path)
        current_catalog = AssetCatalog.from_directories(models_dir, loras_dir)
        model_id_map, lora_id_map = build_legacy_asset_id_maps(legacy_catalog, current_catalog)

        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        temp_dir.mkdir()
        stored_dir.mkdir()
        backups_dir.mkdir()
        db = AppDatabase(":memory:", temp_dir, stored_dir, backups_dir)
        db.init_schema()
        file_path = temp_dir / "temp-image.png"
        Image.new("RGB", (10, 10)).save(file_path)
        db.create_image(
            GeneratedArtifact(
                image_id="img-1",
                file_path=str(file_path),
                width=10,
                height=10,
                prompt="prompt",
                default_positive_prompt="default pos",
                default_negative_prompt="default neg",
                final_positive_prompt="default pos, prompt",
                model_id="demo-model",
                loras=[{"lora_id": "demo-lora", "strength": 0.75}],
            )
        )
        db.insert_job(
            job_id="job-1",
            job_type="generate",
            payload={
                "model_id": "demo-model",
                "loras": [{"lora_id": "demo-lora", "strength": 0.75}],
            },
        )
        db.set_asset_rating(asset_type="model", asset_id="demo-model", rating=4)
        db.set_asset_rating(asset_type="lora", asset_id="demo-lora", rating=3)

        db.remap_asset_ids(model_id_map=model_id_map, lora_id_map=lora_id_map)
        image = db.get_image("img-1")
        job = db.get_job("job-1")

        self.assertIsNotNone(image)
        self.assertIsNotNone(job)
        self.assertEqual(image["model_id"], "demo_model")
        self.assertEqual(image["loras"][0]["lora_id"], "demo_lora")
        payload = json.loads(job["payload_json"])
        self.assertEqual(payload["model_id"], "demo_model")
        self.assertEqual(payload["loras"][0]["lora_id"], "demo_lora")
        with db._connect() as conn:
            asset_rating_rows = conn.execute(
                "SELECT asset_type, asset_id, rating FROM asset_ratings"
            ).fetchall()
        self.assertEqual(
            {
                (row["asset_type"], row["asset_id"]): row["rating"]
                for row in asset_rating_rows
            },
            {("model", "demo_model"): 4, ("lora", "demo_lora"): 3},
        )

    def test_temp_to_stored_transition(self) -> None:
        runtime_dir = self._workspace_dir("store")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        temp_dir.mkdir()
        stored_dir.mkdir()
        backups_dir.mkdir()
        db = AppDatabase(":memory:", temp_dir, stored_dir, backups_dir)
        db.init_schema()

        file_path = temp_dir / "temp-image.png"
        Image.new("RGB", (10, 10)).save(file_path)
        db.create_image(
            GeneratedArtifact(
                image_id="img-1",
                file_path=str(file_path),
                width=10,
                height=10,
                prompt="prompt",
                default_positive_prompt="default pos",
                default_negative_prompt="default neg",
                final_positive_prompt="default pos, prompt",
                model_id="demo-model",
                loras=[],
            )
        )

        stored = db.store_image("img-1")

        self.assertEqual(stored["status"], "stored")
        self.assertTrue(Path(stored["file_path"]).exists())
        with db._connect() as conn:
            row = conn.execute(
                "SELECT file_path, poster_path FROM images WHERE id = ?",
                ("img-1",),
            ).fetchone()
        self.assertEqual(row["file_path"], "stored/temp-image.png")
        self.assertIsNone(row["poster_path"])

    def test_create_image_stores_relative_db_paths(self) -> None:
        runtime_dir = self._workspace_dir("relative_paths")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        temp_dir.mkdir()
        stored_dir.mkdir()
        backups_dir.mkdir()
        db = AppDatabase(":memory:", temp_dir, stored_dir, backups_dir)
        db.init_schema()

        file_path = temp_dir / "temp-image.png"
        poster_path = temp_dir / "temp-image-poster.png"
        Image.new("RGB", (10, 10)).save(file_path)
        Image.new("RGB", (10, 10)).save(poster_path)
        db.create_image(
            GeneratedArtifact(
                image_id="img-1",
                file_path=str(file_path),
                width=10,
                height=10,
                prompt="prompt",
                default_positive_prompt="default pos",
                default_negative_prompt="default neg",
                final_positive_prompt="default pos, prompt",
                model_id="demo-model",
                loras=[],
                poster_path=str(poster_path),
                poster_mime_type="image/png",
            )
        )

        with db._connect() as conn:
            row = conn.execute(
                "SELECT file_path, poster_path FROM images WHERE id = ?",
                ("img-1",),
            ).fetchone()

        self.assertEqual(row["file_path"], "stored/temp-image.png")
        self.assertEqual(row["poster_path"], "stored/temp-image-poster.png")

        image = db.get_image("img-1")
        self.assertIsNotNone(image)
        self.assertEqual(Path(image["file_path"]), stored_dir / "temp-image.png")
        self.assertEqual(Path(image["poster_path"]), stored_dir / "temp-image-poster.png")
    def test_latest_temp_image_replaces_older_temp_images_and_cleans_temp_dir(self) -> None:
        runtime_dir = self._workspace_dir("cleanup")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        temp_dir.mkdir()
        stored_dir.mkdir()
        backups_dir.mkdir()
        db = AppDatabase(":memory:", temp_dir, stored_dir, backups_dir)
        db.init_schema()

        first_path = temp_dir / "first.png"
        second_path = temp_dir / "second.png"
        orphan_path = temp_dir / "orphan.png"
        Image.new("RGB", (10, 10)).save(first_path)
        self._insert_image_record(
            db,
            image_id="img-1",
            status="temp",
            file_path=first_path,
            created_at="2026-01-01T00:00:00+00:00",
        )
        Image.new("RGB", (10, 10)).save(second_path)
        Image.new("RGB", (10, 10)).save(orphan_path)
        self._insert_image_record(
            db,
            image_id="img-2",
            status="temp",
            file_path=second_path,
            created_at="2026-01-02T00:00:00+00:00",
        )

        removed = db.cleanup_temp_images()
        image_one = db.get_image("img-1")
        image_two = db.get_image("img-2")

        self.assertEqual(removed, 1)
        self.assertIsNone(image_one)
        self.assertIsNotNone(image_two)
        self.assertFalse(first_path.exists())
        self.assertTrue(second_path.exists())
        self.assertFalse(orphan_path.exists())

    def test_cleanup_temp_images_keeps_latest_expired_entry(self) -> None:
        runtime_dir = self._workspace_dir("cleanup_ttl")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        temp_dir.mkdir()
        stored_dir.mkdir()
        backups_dir.mkdir()
        db = AppDatabase(":memory:", temp_dir, stored_dir, backups_dir)
        db.init_schema()

        latest_path = temp_dir / "latest.png"
        Image.new("RGB", (10, 10)).save(latest_path)
        self._insert_image_record(
            db,
            image_id="img-1",
            status="temp",
            file_path=latest_path,
            created_at="2000-01-01T00:00:00+00:00",
        )

        removed = db.cleanup_temp_images(60)
        latest_image = db.get_image("img-1")

        self.assertEqual(removed, 0)
        self.assertIsNotNone(latest_image)
        self.assertTrue(latest_path.exists())

    def test_create_app_preserves_latest_temp_image_on_startup(self) -> None:
        runtime_dir = self._workspace_dir("startup_cleanup")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        temp_dir = data_dir / "temp"
        stored_dir = data_dir / "stored"
        backups_dir = data_dir / "backups"
        temp_dir.mkdir(parents=True)
        stored_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        db_uri = f"file:startup-cleanup-{uuid.uuid4().hex}?mode=memory&cache=shared"
        seed_db = AppDatabase(db_uri, temp_dir, stored_dir, backups_dir)
        seed_db.init_schema()
        file_path = temp_dir / "stale-temp.png"
        stray_path = temp_dir / "stray-temp.png"
        Image.new("RGB", (10, 10)).save(file_path)
        Image.new("RGB", (10, 10)).save(stray_path)
        self._insert_image_record(
            seed_db,
            image_id="img-1",
            status="temp",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
        )

        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "DB_PATH": db_uri,
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )

        db = app.extensions["db"]
        image = db.get_image("img-1")
        self.assertIsNotNone(image)
        self.assertTrue(file_path.exists())
        self.assertFalse(stray_path.exists())

    def test_create_app_cleans_up_cancel_requested_jobs_on_startup(self) -> None:
        runtime_dir = self._workspace_dir("startup_cancel_cleanup")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        temp_dir = data_dir / "temp"
        stored_dir = data_dir / "stored"
        backups_dir = data_dir / "backups"
        temp_dir.mkdir(parents=True)
        stored_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        db_uri = f"file:startup-cancel-{uuid.uuid4().hex}?mode=memory&cache=shared"
        seed_db = AppDatabase(db_uri, temp_dir, stored_dir, backups_dir)
        seed_db.init_schema()
        seed_db.insert_job(job_id="job-1", job_type="generate", payload={"prompt": "cancel me"})
        seed_db.update_job(
            "job-1",
            status="running",
            progress=0.5,
            status_text="Cancellation requested",
        )
        with seed_db._connect() as conn:
            conn.execute(
                """
                UPDATE jobs
                SET cancel_requested = 1,
                    cancel_requested_at = ?,
                    cancelled_at = NULL
                WHERE id = ?
                """,
                ("2026-01-01T00:00:00+00:00", "job-1"),
            )

        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "DB_PATH": db_uri,
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )

        job = app.extensions["db"].get_job("job-1")
        self.assertIsNotNone(job)
        self.assertEqual(job["status"], "cancelled")
        self.assertEqual(job["status_text"], "Cancelled")
        self.assertEqual(job["cancel_requested_at"], "2026-01-01T00:00:00+00:00")
        self.assertIsNotNone(job["cancelled_at"])

    def test_create_app_resumes_queued_jobs_on_startup(self) -> None:
        runtime_dir = self._workspace_dir("startup_resume_queued_jobs")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        temp_dir = data_dir / "temp"
        stored_dir = data_dir / "stored"
        backups_dir = data_dir / "backups"
        temp_dir.mkdir(parents=True)
        stored_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        db_uri = f"file:startup-queued-{uuid.uuid4().hex}?mode=memory&cache=shared"
        seed_db = AppDatabase(db_uri, temp_dir, stored_dir, backups_dir)
        seed_db.init_schema()
        payload = {
            "prompt": "resume me",
            "default_positive_prompt": "best quality",
            "default_negative_prompt": "bad anatomy",
            "model_id": "demo_model",
            "loras": [],
        }
        seed_worker = JobWorker(
            db=seed_db,
            error_store=ErrorStore(data_dir / "errors"),
            generator=MockGenerator(),
            temp_dir=temp_dir,
        )
        seed_db.create_image_placeholder(
            image_id="queued-result",
            status="queued",
            **seed_worker._build_placeholder(
                job_type="generate",
                payload=payload,
                image_id="queued-result",
            ),
        )
        seed_db.insert_job(
            job_id="queued-job",
            job_type="generate",
            payload=payload,
            result_image_id="queued-result",
        )

        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "DB_PATH": db_uri,
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )

        client = app.test_client()
        job = self._wait_for_status(client, "queued-job", {"completed"})
        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["result"]["status"], "stored")

    def test_create_app_waits_for_comfy_health_before_resuming_recovered_video_jobs(self) -> None:
        runtime_dir = self._workspace_dir("startup_resume_video_jobs_after_comfy_health")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        temp_dir = data_dir / "temp"
        stored_dir = data_dir / "stored"
        backups_dir = data_dir / "backups"
        temp_dir.mkdir(parents=True)
        stored_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        db_uri = f"file:startup-video-{uuid.uuid4().hex}?mode=memory&cache=shared"
        seed_db = AppDatabase(db_uri, temp_dir, stored_dir, backups_dir)
        seed_db.init_schema()
        payload = {
            "prompt": "resume video",
            "default_positive_prompt": "best quality",
            "default_negative_prompt": "bad anatomy",
            "video_model_id": "test-text-to-video-workflow",
            "width": 512,
            "height": 288,
            "num_frames": 25,
            "fps": 12,
            "num_inference_steps": 8,
            "guidance_scale": 2.0,
        }
        seed_worker = JobWorker(
            db=seed_db,
            error_store=ErrorStore(data_dir / "errors"),
            generator=MockGenerator(),
            temp_dir=temp_dir,
        )
        seed_db.create_image_placeholder(
            image_id="queued-video-result",
            status="queued",
            **seed_worker._build_placeholder(
                job_type="generate_video",
                payload=payload,
                image_id="queued-video-result",
            ),
        )
        seed_db.insert_job(
            job_id="queued-video-job",
            job_type="generate_video",
            payload=payload,
            result_image_id="queued-video-result",
        )

        ready_event = threading.Event()

        class GuardedVideoGenerator(MockGenerator):
            def __init__(self) -> None:
                super().__init__()
                self.started_before_ready = False

            def generate_video(
                self,
                payload,
                output_dir: Path,
                progress_callback=None,
                cancel_requested=None,
            ) -> GeneratedArtifact:
                if not ready_event.is_set():
                    self.started_before_ready = True
                    raise AssertionError("Video recovery started before ComfyUI became healthy")
                return super().generate_video(
                    payload,
                    output_dir,
                    progress_callback=progress_callback,
                    cancel_requested=cancel_requested,
                )

        generator = GuardedVideoGenerator()

        def _mark_ready() -> None:
            time.sleep(0.15)
            ready_event.set()

        health_thread = threading.Thread(target=_mark_ready, daemon=True)
        health_thread.start()

        class FakeHealthResponse:
            def __init__(self, ok: bool) -> None:
                self.ok = ok

        with patch(
            "app.comfy.health.requests.get",
            side_effect=lambda *args, **kwargs: FakeHealthResponse(ready_event.is_set()),
        ):
            app = create_app(
                test_config={
                    "TESTING": True,
                    "MODELS_DIR": str(models_dir),
                    "LORAS_DIR": str(loras_dir),
                    "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                    "DATA_DIR": str(data_dir),
                    "TEMP_DIR": str(temp_dir),
                    "STORED_DIR": str(stored_dir),
                    "BACKUPS_DIR": str(backups_dir),
                    "DB_PATH": db_uri,
                    "TEMP_TTL_SECONDS": 7200,
                    "CLEANUP_INTERVAL_SECONDS": 3600,
                    "COMFY_AUTOSTART_ENABLED": False,
                    "COMFY_AUTOSTART_WAIT_SECONDS": 1.0,
                    "COMFY_AUTOSTART_POLL_SECONDS": 0.02,
                },
                generator=generator,
            )
            client = app.test_client()
            job = self._wait_for_status(client, "queued-video-job", {"completed"})
            self.assertEqual(job["status"], "completed")
            self.assertEqual(job["result"]["media_type"], "video")
            self.assertFalse(generator.started_before_ready)

    def test_create_app_cleans_up_interrupted_running_jobs_on_startup(self) -> None:
        runtime_dir = self._workspace_dir("startup_running_cleanup")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        temp_dir = data_dir / "temp"
        stored_dir = data_dir / "stored"
        backups_dir = data_dir / "backups"
        errors_dir = data_dir / "errors"
        temp_dir.mkdir(parents=True)
        stored_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)
        errors_dir.mkdir(parents=True)
        db_uri = f"file:startup-running-{uuid.uuid4().hex}?mode=memory&cache=shared"
        seed_db = AppDatabase(db_uri, temp_dir, stored_dir, backups_dir, errors_dir)
        seed_db.init_schema()
        payload = {
            "prompt": "interrupted job",
            "default_positive_prompt": "best quality",
            "default_negative_prompt": "bad anatomy",
            "model_id": "demo_model",
            "loras": [],
        }
        seed_worker = JobWorker(
            db=seed_db,
            error_store=ErrorStore(errors_dir),
            generator=MockGenerator(),
            temp_dir=temp_dir,
        )
        seed_db.create_image_placeholder(
            image_id="running-result",
            status="running",
            **seed_worker._build_placeholder(
                job_type="generate",
                payload=payload,
                image_id="running-result",
            ),
        )
        seed_db.insert_job(
            job_id="running-job",
            job_type="generate",
            payload=payload,
            result_image_id="running-result",
        )
        seed_db.update_job(
            "running-job",
            status="running",
            progress=0.5,
            status_text="Generating image 4/8",
        )

        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "ERRORS_DIR": str(errors_dir),
                "DB_PATH": db_uri,
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )

        db = app.extensions["db"]
        error_store = app.extensions["error_store"]
        job = db.get_job("running-job")
        self.assertIsNotNone(job)
        self.assertEqual(job["status"], "failed")
        self.assertEqual(job["status_text"], "Interrupted by server restart")
        self.assertEqual(
            job["error"],
            "Job was interrupted because the server restarted or the worker stopped.",
        )
        self.assertIsNone(db.get_image("running-result"))
        errors = error_store.list_errors()
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0]["job"]["job_id"], "running-job")

    def test_create_app_migrates_windows_media_paths_to_relative(self) -> None:
        runtime_dir = self._workspace_dir("windows_path_migration")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        temp_dir = data_dir / "temp"
        stored_dir = data_dir / "stored"
        backups_dir = data_dir / "backups"
        temp_dir.mkdir(parents=True)
        stored_dir.mkdir(parents=True)
        backups_dir.mkdir(parents=True)

        file_path = stored_dir / "legacy-image.png"
        poster_path = stored_dir / "legacy-image-poster.png"
        Image.new("RGB", (10, 10), color="white").save(file_path)
        Image.new("RGB", (10, 10), color="black").save(poster_path)

        db_path = data_dir / "app.db"
        seed_db = AppDatabase(db_path, temp_dir, stored_dir, backups_dir, data_dir=data_dir)
        seed_db.init_schema()
        with seed_db._connect() as conn:
            conn.execute(
                """
                INSERT INTO images (
                    id, status, media_type, file_name, file_path, mime_type, poster_path,
                    poster_mime_type, width, height, prompt, default_positive_prompt,
                    default_negative_prompt, final_positive_prompt, model_id, loras_json,
                    tags_json, num_inference_steps, guidance_scale, image_orientation,
                    source_image_id, scale_factor, is_upscaled, duration_seconds, fps,
                    num_frames, loop_video, rating, created_at, stored_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "img-legacy",
                    "stored",
                    "image",
                    "legacy-image.png",
                    r"C:\NoviaGen\Backend\data\stored\legacy-image.png",
                    "image/png",
                    r"C:\NoviaGen\Backend\data\stored\legacy-image-poster.png",
                    "image/png",
                    10,
                    10,
                    "prompt",
                    "default pos",
                    "default neg",
                    "default pos, prompt",
                    "demo_model",
                    "[]",
                    "[]",
                    40,
                    5.0,
                    "landscape",
                    None,
                    None,
                    0,
                    None,
                    None,
                    None,
                    0,
                    0,
                    "2026-01-01T00:00:00+00:00",
                    "2026-01-01T00:00:00+00:00",
                ),
            )
            conn.commit()

        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(temp_dir),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(backups_dir),
                "DB_PATH": str(db_path),
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        listing_response = client.get("/api/images/stored")
        self.assertEqual(listing_response.status_code, 200)
        self.assertEqual(listing_response.get_json()["items"][0]["id"], "img-legacy")

        file_response = client.get("/api/files/img-legacy")
        self.assertEqual(file_response.status_code, 200)

        poster_response = client.get("/api/files/img-legacy/poster")
        self.assertEqual(poster_response.status_code, 200)

        with app.extensions["db"]._connect() as conn:
            row = conn.execute(
                "SELECT file_path, poster_path FROM images WHERE id = ?",
                ("img-legacy",),
            ).fetchone()
        self.assertEqual(row["file_path"], "stored/legacy-image.png")
        self.assertEqual(row["poster_path"], "stored/legacy-image-poster.png")

    def test_media_file_route_uses_chunked_wrapper_not_wsgi_file_wrapper(self) -> None:
        runtime_dir = self._workspace_dir("media_file_wrapper")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        stored_dir = data_dir / "stored"
        stored_dir.mkdir(parents=True)

        file_path = stored_dir / "served-image.png"
        Image.new("RGB", (16, 16), color="green").save(file_path)

        app = create_app(
            test_config={
                "TESTING": True,
                "MODELS_DIR": str(models_dir),
                "LORAS_DIR": str(loras_dir),
                "LORA_TRIGGERS_DIR": str(lora_triggers_dir),
                "DATA_DIR": str(data_dir),
                "TEMP_DIR": str(data_dir / "temp"),
                "STORED_DIR": str(stored_dir),
                "BACKUPS_DIR": str(data_dir / "backups"),
                "DB_PATH": ":memory:",
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )

        app.extensions["db"].create_image(
            GeneratedArtifact(
                image_id="streamed-image",
                file_path=str(file_path),
                width=16,
                height=16,
                prompt="prompt",
                default_positive_prompt="default pos",
                default_negative_prompt="default neg",
                final_positive_prompt="default pos, prompt",
                model_id="demo-model",
                loras=[],
            )
        )

        class FakeServerFileWrapper:
            def __init__(self, file, buffer_size=8192):
                self.file = file
                self.buffer_size = buffer_size

        with app.test_request_context(
            "/api/files/streamed-image",
            environ_overrides={"wsgi.file_wrapper": FakeServerFileWrapper},
        ):
            response = app.view_functions["api.get_file"]("streamed-image")

        self.assertEqual(response.status_code, 200)
        self.assertIsInstance(response.response, FileWrapper)
        self.assertNotIsInstance(response.response, FakeServerFileWrapper)

        client = app.test_client()
        range_response = client.get(
            "/api/files/streamed-image",
            headers={"Range": "bytes=0-31"},
        )
        self.assertEqual(range_response.status_code, 206)
        self.assertEqual(range_response.headers["Accept-Ranges"], "bytes")
        self.assertGreater(len(range_response.data), 0)

    def test_latest_temp_image_route_returns_newest_temp_result(self) -> None:
        runtime_dir = self._workspace_dir("latest_temp_route")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
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
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        temp_image_path = data_dir / "temp" / "older.png"
        temp_video_path = data_dir / "temp" / "newer.mp4"
        temp_poster_path = data_dir / "temp" / "newer_poster.png"
        Image.new("RGB", (10, 10)).save(temp_image_path)
        temp_video_path.write_bytes(b"fake-mp4")
        Image.new("RGB", (10, 10)).save(temp_poster_path)
        self._insert_image_record(
            app.extensions["db"],
            image_id="temp-image",
            status="temp",
            file_path=temp_image_path,
            created_at="2026-01-01T00:00:00+00:00",
        )
        self._insert_image_record(
            app.extensions["db"],
            image_id="temp-video",
            status="temp",
            file_path=temp_video_path,
            created_at="2026-01-02T00:00:00+00:00",
            media_type="video",
            mime_type="video/mp4",
            poster_path=temp_poster_path,
            poster_mime_type="image/png",
        )

        latest_response = client.get("/api/images/latest-temp")
        self.assertEqual(latest_response.status_code, 200)
        self.assertEqual(latest_response.get_json()["id"], "temp-video")
        self.assertEqual(latest_response.get_json()["media_type"], "video")

    def test_switching_models_evicts_stale_pipelines_and_cleans_cuda(self) -> None:
        catalog = AssetCatalog(
            models=[
                AssetEntry(id="model-a", label="Model A", path="/fixtures/models/model-a.safetensors"),
                AssetEntry(id="model-b", label="Model B", path="/fixtures/models/model-b.safetensors"),
            ],
            loras=[],
        )
        generator = DiffusersImageGenerator(catalog)
        generator._torch = FakeTorch()

        stale_text = FakePipeline()
        active_text = FakePipeline()
        stale_upscale = FakePipeline()
        generator._text_pipelines = {
            "/fixtures/models/model-a.safetensors": stale_text,
            "/fixtures/models/model-b.safetensors": active_text,
        }
        generator._upscale_pipelines = {
            "/fixtures/models/model-a.safetensors": stale_upscale,
        }

        generator._evict_stale_pipelines("/fixtures/models/model-b.safetensors")

        self.assertEqual(list(generator._text_pipelines.keys()), ["/fixtures/models/model-b.safetensors"])
        self.assertEqual(generator._upscale_pipelines, {})
        self.assertEqual(stale_text.unload_calls, 1)
        self.assertEqual(stale_text.to_calls, ["cpu"])
        self.assertEqual(stale_upscale.unload_calls, 1)
        self.assertEqual(stale_upscale.to_calls, ["cpu"])
        self.assertEqual(active_text.unload_calls, 0)
        self.assertEqual(generator._torch.cuda.empty_cache_calls, 1)
        self.assertEqual(generator._torch.cuda.ipc_collect_calls, 1)
        self.assertEqual(generator._torch.cuda.synchronize_calls, 1)
