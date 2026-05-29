from __future__ import annotations

from .shared import *


class JobsGenerationTests(BackendTestCase):
    def test_job_worker_pauses_between_queued_jobs_when_configured(self) -> None:
        runtime_dir = self._workspace_dir("inter_job_delay_worker")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        errors_dir = runtime_dir / "errors"
        data_dir = runtime_dir / "data"
        for path in (temp_dir, stored_dir, backups_dir, errors_dir, data_dir):
            path.mkdir(parents=True, exist_ok=True)

        db = AppDatabase(
            runtime_dir / "app.db",
            temp_dir,
            stored_dir,
            backups_dir,
            errors_dir,
            data_dir=data_dir,
        )
        db.init_schema()
        worker = JobWorker(
            db=db,
            error_store=ErrorStore(errors_dir),
            generator=MockGenerator(),
            temp_dir=temp_dir,
            inter_job_delay_seconds=2,
        )

        sleep_calls: list[float] = []
        original_sleep = time.sleep

        def fake_sleep(seconds: float) -> None:
            sleep_calls.append(float(seconds))

        with patch("app.job_queue.worker.time.sleep", side_effect=fake_sleep):
            worker.start()
            first_job_id = worker.enqueue_generate(
                {
                    "prompt": "first",
                    "default_positive_prompt": "",
                    "default_negative_prompt": "",
                    "model_id": "demo_model",
                    "loras": [],
                }
            )
            second_job_id = worker.enqueue_generate(
                {
                    "prompt": "second",
                    "default_positive_prompt": "",
                    "default_negative_prompt": "",
                    "model_id": "demo_model",
                    "loras": [],
                }
            )

            deadline = time.time() + 5.0
            while time.time() < deadline:
                first_job = db.get_job(first_job_id)
                second_job = db.get_job(second_job_id)
                if (
                    first_job is not None
                    and second_job is not None
                    and first_job["status"] in {"completed", "failed", "cancelled"}
                    and second_job["status"] in {"completed", "failed", "cancelled"}
                ):
                    break
                original_sleep(0.02)
            else:
                self.fail("Timed out waiting for queued jobs to finish")

        self.assertIn(2.0, sleep_calls)
        self.assertEqual(worker.stats()["inter_job_delay_seconds"], 2)

    def test_cancel_marks_non_active_running_job_cancelled_immediately(self) -> None:
        runtime_dir = self._workspace_dir("stale_running_cancel")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        errors_dir = runtime_dir / "errors"
        data_dir = runtime_dir / "data"
        for path in (temp_dir, stored_dir, backups_dir, errors_dir, data_dir):
            path.mkdir(parents=True, exist_ok=True)

        db = AppDatabase(
            runtime_dir / "app.db",
            temp_dir,
            stored_dir,
            backups_dir,
            errors_dir,
            data_dir=data_dir,
        )
        db.init_schema()
        generator = CancelTrackingMockGenerator()
        worker = JobWorker(
            db=db,
            error_store=ErrorStore(errors_dir),
            generator=generator,
            temp_dir=temp_dir,
        )
        db.insert_job(job_id="job-1", job_type="generate", payload={"prompt": "stale"})
        db.update_job(
            "job-1",
            status="running",
            progress=0.5,
            status_text="Rendering",
        )

        cancelled_job = worker.cancel("job-1")

        self.assertIsNotNone(cancelled_job)
        self.assertEqual(cancelled_job["status"], "cancelled")
        self.assertEqual(cancelled_job["status_text"], "Cancelled")
        self.assertTrue(cancelled_job["cancel_requested"])
        self.assertIsNotNone(cancelled_job["cancel_requested_at"])
        self.assertIsNotNone(cancelled_job["cancelled_at"])
        self.assertEqual(generator.cancel_calls, 0)

    def test_inter_job_delay_route_reads_and_updates_worker_setting(self) -> None:
        runtime_dir = self._workspace_dir("inter_job_delay_route")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = MockGenerator()
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
                "INTER_JOB_DELAY_SECONDS": 3,
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        get_response = client.get("/api/system/inter-job-delay")
        self.assertEqual(get_response.status_code, 200)
        self.assertEqual(get_response.get_json()["inter_job_delay_seconds"], 3)

        update_response = client.post(
            "/api/system/inter-job-delay",
            json={"seconds": 9},
        )
        self.assertEqual(update_response.status_code, 200)
        self.assertEqual(update_response.get_json()["inter_job_delay_seconds"], 9)

        invalid_response = client.post(
            "/api/system/inter-job-delay",
            json={"seconds": -1},
        )
        self.assertEqual(invalid_response.status_code, 400)

    def test_queued_job_response_fails_when_result_payload_fails(self) -> None:
        runtime_dir = self._workspace_dir("queued_response_failure")
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
                "COMFY_AUTOSTART_ENABLED": False,
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        from app.api.responses import jobs as response_jobs

        original_response_job_payload = response_jobs.job_payload

        def flaky_response_job_payload(job, *, include_result: bool = False):
            if include_result:
                raise RuntimeError("placeholder payload failed")
            return original_response_job_payload(job, include_result=include_result)

        with patch(
            "app.api.responses.jobs.job_payload",
            side_effect=flaky_response_job_payload,
        ):
            with self.assertRaises(RuntimeError):
                client.post(
                    "/api/jobs/generate",
                    json={
                        "prompt": "portrait",
                        "default_positive_prompt": "best quality",
                        "default_negative_prompt": "bad anatomy",
                        "model_id": "demo_model",
                        "loras": [],
                    },
                )

    def test_job_worker_progress_updates_are_monotonic(self) -> None:
        runtime_dir = self._workspace_dir("job_progress_monotonic")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        errors_dir = runtime_dir / "errors"
        data_dir = runtime_dir / "data"
        for path in (temp_dir, stored_dir, backups_dir, errors_dir, data_dir):
            path.mkdir(parents=True, exist_ok=True)

        db = AppDatabase(
            runtime_dir / "app.db",
            temp_dir,
            stored_dir,
            backups_dir,
            errors_dir,
            data_dir=data_dir,
        )
        db.init_schema()
        worker = JobWorker(
            db=db,
            error_store=ErrorStore(errors_dir),
            generator=MockGenerator(),
            temp_dir=temp_dir,
        )
        db.insert_job(job_id="job-1", job_type="generate", payload={"prompt": "monotonic"})
        db.update_job(
            "job-1",
            status="running",
            progress=0.0,
            status_text="Preparing",
        )

        with patch("app.job_queue.worker.time.monotonic", side_effect=[10.0, 16.0]):
            worker._update_job_progress("job-1", progress=0.72, status_text="Generating frames 2/2")
            worker._update_job_progress("job-1", progress=0.31, status_text="Decoding frames")

        job = db.get_job("job-1")
        self.assertIsNotNone(job)
        self.assertAlmostEqual(job["progress"], 0.72)
        self.assertEqual(job["status_text"], "Decoding frames")
        self.assertIsNotNone(job["started_at"])

    def test_generate_and_upscale_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("app")
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
                "loras": [{"lora_id": "demo_lora", "strength": 0.9}],
            },
        )
        self.assertEqual(response.status_code, 202)
        queued_payload = response.get_json()
        job_id = queued_payload["job_id"]
        self.assertEqual(queued_payload["result"]["status"], "queued")
        self.assertEqual(queued_payload["result"]["media_type"], "image")

        result = self._wait_for_job(client, job_id)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["result"]["loras"][0]["lora_id"], "demo_lora")

        image_id = result["result"]["id"]
        store_response = client.post(f"/api/images/{image_id}/store")
        self.assertEqual(store_response.status_code, 200)
        self.assertEqual(store_response.get_json()["status"], "stored")

        gallery = client.get("/api/images/stored").get_json()
        self.assertEqual(gallery["total"], 1)

        no_lora_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "landscape",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        self.assertEqual(no_lora_response.status_code, 202)
        no_lora_job_id = no_lora_response.get_json()["job_id"]
        no_lora_result = self._wait_for_job(client, no_lora_job_id)
        self.assertEqual(no_lora_result["status"], "completed")
        self.assertEqual(no_lora_result["result"]["loras"], [])

        upscale_response = client.post(
            "/api/jobs/upscale",
            json={"image_id": image_id, "scale_factor": 2.0},
        )
        self.assertEqual(upscale_response.status_code, 202)
        upscale_job_id = upscale_response.get_json()["job_id"]

        upscale_result = self._wait_for_job(client, upscale_job_id)
        self.assertEqual(upscale_result["status"], "completed")
        self.assertEqual(upscale_result["result"]["source_image_id"], image_id)
        self.assertTrue(upscale_result["result"]["is_upscaled"])

        delete_response = client.delete(f"/api/images/{image_id}")
        self.assertEqual(delete_response.status_code, 200)
        self.assertTrue(delete_response.get_json()["deleted"])

        deleted_response = client.get(f"/api/images/{image_id}")
        self.assertEqual(deleted_response.status_code, 200)
        self.assertEqual(deleted_response.get_json()["status"], "deleted")

        delete_via_post_response = client.post(
            f"/api/images/{upscale_result['result']['id']}/delete"
        )
        self.assertEqual(delete_via_post_response.status_code, 200)
        self.assertTrue(delete_via_post_response.get_json()["deleted"])

    def test_latest_temp_result_can_be_upscaled_after_cleanup_pass(self) -> None:
        runtime_dir = self._workspace_dir("temp_upscale_after_cleanup")
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
        self.assertEqual(response.status_code, 202)
        job_id = response.get_json()["job_id"]
        result = self._wait_for_job(client, job_id)
        self.assertEqual(result["status"], "completed")
        image_id = result["result"]["id"]

        db = app.extensions["db"]
        with db._connect() as conn:
            conn.execute(
                "UPDATE images SET created_at = ? WHERE id = ?",
                ("2000-01-01T00:00:00+00:00", image_id),
            )
            conn.commit()

        removed = db.cleanup_temp_images(60)
        self.assertEqual(removed, 0)

        image_response = client.get(f"/api/images/{image_id}")
        self.assertEqual(image_response.status_code, 200)

        upscale_response = client.post(
            "/api/jobs/upscale",
            json={"image_id": image_id, "scale_factor": 2.0},
        )
        self.assertEqual(upscale_response.status_code, 202)
        upscale_result = self._wait_for_job(client, upscale_response.get_json()["job_id"])
        self.assertEqual(upscale_result["status"], "completed")
        self.assertEqual(upscale_result["result"]["source_image_id"], image_id)

    def test_generate_and_store_video_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("video_app")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        self.assertEqual(
            image_job["result"]["generation_duration_seconds"],
            1.25,
        )
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(response.status_code, 202)
        video_result = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(video_result["status"], "completed")
        self.assertEqual(video_result["result"]["media_type"], "video")
        self.assertIsNotNone(video_result["result"]["poster_url"])
        self.assertEqual(
            video_result["result"]["generation_duration_seconds"],
            3.75,
        )

        animate_response = client.post(
            "/api/jobs/animate-image",
            json={
                "image_id": image_id,
                "prompt": "camera zooms in",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "standard",
            },
        )
        self.assertEqual(animate_response.status_code, 202)
        animate_payload = animate_response.get_json()
        self.assertEqual(animate_payload["result"]["status"], "queued")
        self.assertEqual(animate_payload["result"]["media_type"], "video")
        self.assertEqual(animate_payload["result"]["source_image_id"], image_id)
        animated_result = self._wait_for_job(client, animate_payload["job_id"])
        self.assertEqual(animated_result["status"], "completed")
        self.assertEqual(animated_result["result"]["media_type"], "video")
        self.assertEqual(animated_result["result"]["source_image_id"], image_id)
        self.assertEqual(
            animated_result["result"]["generation_duration_seconds"],
            4.25,
        )

        store_response = client.post(f"/api/images/{animated_result['result']['id']}/store")
        self.assertEqual(store_response.status_code, 200)
        self.assertEqual(store_response.get_json()["status"], "stored")

        jobs_listing = client.get("/api/jobs").get_json()
        self.assertEqual(jobs_listing["total"], 3)
        completed_results = {
            item["type"]: item.get("result") for item in jobs_listing["items"]
        }
        self.assertEqual(
            completed_results["generate"]["generation_duration_seconds"],
            1.25,
        )
        self.assertEqual(
            completed_results["generate_video"]["generation_duration_seconds"],
            3.75,
        )
        self.assertEqual(
            completed_results["animate_image"]["generation_duration_seconds"],
            4.25,
        )

        gallery = client.get("/api/images/stored").get_json()
        self.assertEqual(gallery["total"], 3)
        self.assertTrue(any(item["media_type"] == "video" for item in gallery["items"]))

    def test_upscale_video_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("video_upscale_app")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(response.status_code, 202)
        video_job = self._wait_for_job(client, response.get_json()["job_id"])
        video_id = video_job["result"]["id"]

        upscale_response = client.post(
            "/api/jobs/upscale-video",
            json={"image_id": video_id, "scale_factor": 2.0},
        )
        self.assertEqual(upscale_response.status_code, 202)
        upscaled_job = self._wait_for_job(client, upscale_response.get_json()["job_id"])
        self.assertEqual(upscaled_job["status"], "completed")
        self.assertEqual(upscaled_job["type"], "upscale_video")
        self.assertEqual(upscaled_job["result"]["media_type"], "video")
        self.assertEqual(upscaled_job["result"]["source_image_id"], video_id)
        self.assertTrue(upscaled_job["result"]["is_upscaled"])
        self.assertEqual(upscaled_job["result"]["scale_factor"], 2.0)
        self.assertEqual(upscaled_job["result"]["fps"], video_job["result"]["fps"])
        self.assertEqual(
            upscaled_job["result"]["num_frames"],
            video_job["result"]["num_frames"],
        )
        self.assertIsNotNone(upscaled_job["result"]["poster_url"])

    def test_convert_video_to_gif_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("video_gif_app")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(response.status_code, 202)
        video_job = self._wait_for_job(client, response.get_json()["job_id"])
        video_id = video_job["result"]["id"]

        convert_response = client.post(
            "/api/jobs/convert-video-gif",
            json={"image_id": video_id},
        )
        self.assertEqual(convert_response.status_code, 202)
        gif_job = self._wait_for_job(client, convert_response.get_json()["job_id"])
        self.assertEqual(gif_job["status"], "completed")
        self.assertEqual(gif_job["type"], "convert_video_to_gif")
        self.assertEqual(gif_job["result"]["media_type"], "gif")
        self.assertEqual(gif_job["result"]["mime_type"], "image/gif")
        self.assertEqual(gif_job["result"]["source_image_id"], video_id)
        self.assertIsNone(gif_job["result"]["poster_url"])

        gif_id = gif_job["result"]["id"]
        gif_response = client.get(f"/api/files/{gif_id}")
        self.assertEqual(gif_response.status_code, 200)
        self.assertEqual(gif_response.mimetype, "image/gif")

    def test_generate_audio_video_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("audio_video_app")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(response.status_code, 202)
        video_job = self._wait_for_job(client, response.get_json()["job_id"])
        video_id = video_job["result"]["id"]

        audio_response = client.post(
            "/api/jobs/generate-audio-video",
            json={"image_id": video_id},
        )
        self.assertEqual(audio_response.status_code, 202)
        audio_job = self._wait_for_job(client, audio_response.get_json()["job_id"])
        self.assertEqual(audio_job["status"], "completed")
        self.assertEqual(audio_job["type"], "generate_audio_video")
        self.assertEqual(audio_job["result"]["media_type"], "video")
        self.assertEqual(audio_job["result"]["model_id"], "comfy-video-to-audio")
        self.assertEqual(audio_job["result"]["source_image_id"], video_id)
        self.assertIsNotNone(audio_job["result"]["poster_url"])

    def test_video_queue_response_does_not_query_generator_for_placeholder_fps(self) -> None:
        runtime_dir = self._workspace_dir("video_queue_placeholder_fps")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        data_dir = runtime_dir / "data"
        generator = TrackingVideoPlaceholderGenerator()
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
            },
            generator=generator,
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
            },
        )

        self.assertEqual(response.status_code, 202)
        payload = response.get_json()
        self.assertEqual(payload["result"]["fps"], 16)
        self.assertAlmostEqual(payload["result"]["duration_seconds"], 49 / 16, places=4)
        self.assertEqual(generator.expected_video_output_fps_calls, 0)

    def test_generate_audio_video_can_be_queued_from_video_placeholder(self) -> None:
        runtime_dir = self._workspace_dir("audio_video_chain")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        video_response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(video_response.status_code, 202)
        queued_video_payload = video_response.get_json()
        placeholder_video_id = queued_video_payload["result"]["id"]
        self.assertEqual(queued_video_payload["result"]["status"], "queued")

        audio_response = client.post(
            "/api/jobs/generate-audio-video",
            json={"image_id": placeholder_video_id},
        )
        self.assertEqual(audio_response.status_code, 202)
        audio_job = self._wait_for_job(client, audio_response.get_json()["job_id"])
        self.assertEqual(audio_job["status"], "completed")
        self.assertEqual(audio_job["result"]["source_image_id"], placeholder_video_id)
        self.assertEqual(audio_job["result"]["media_type"], "video")

    def test_generate_from_image_can_be_queued_from_image_placeholder(self) -> None:
        runtime_dir = self._workspace_dir("img2img_placeholder_chain")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        self.assertEqual(image_response.status_code, 202)
        queued_image_payload = image_response.get_json()
        placeholder_image_id = queued_image_payload["result"]["id"]
        self.assertEqual(queued_image_payload["result"]["status"], "queued")

        chained_response = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": placeholder_image_id,
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 0.4,
            },
        )
        self.assertEqual(chained_response.status_code, 202)
        chained_job = self._wait_for_job(client, chained_response.get_json()["job_id"])
        self.assertEqual(chained_job["status"], "completed")
        self.assertEqual(chained_job["result"]["source_image_id"], placeholder_image_id)
        self.assertEqual(chained_job["result"]["media_type"], "image")

    def test_animate_image_can_be_queued_from_image_placeholder(self) -> None:
        runtime_dir = self._workspace_dir("img2vid_placeholder_chain")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        self.assertEqual(image_response.status_code, 202)
        queued_image_payload = image_response.get_json()
        placeholder_image_id = queued_image_payload["result"]["id"]
        self.assertEqual(queued_image_payload["result"]["status"], "queued")

        chained_response = client.post(
            "/api/jobs/animate-image",
            json={
                "image_id": placeholder_image_id,
                "prompt": "camera zooms in",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
            },
        )
        self.assertEqual(chained_response.status_code, 202)
        chained_job = self._wait_for_job(client, chained_response.get_json()["job_id"])
        self.assertEqual(chained_job["status"], "completed")
        self.assertEqual(chained_job["result"]["source_image_id"], placeholder_image_id)
        self.assertEqual(chained_job["result"]["media_type"], "video")

    def test_generate_prompt_then_generate_chain_flow(self) -> None:
        runtime_dir = self._workspace_dir("prompt_then_generate_chain")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()

        response = client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "prompt",
                        "type": "generate_prompt",
                        "payload": {
                            "prompt": "describe something cinematic",
                            "model_name": "demo-prompt-model",
                        },
                    },
                    {
                        "id": "image",
                        "type": "generate",
                        "payload": {
                            "prompt": "",
                            "default_positive_prompt": "best quality",
                            "default_negative_prompt": "bad anatomy",
                            "model_id": "demo_model",
                            "loras": [],
                        },
                        "bindings": {
                            "prompt": {
                                "step_id": "prompt",
                                "output": "result_text",
                            }
                        },
                    },
                ]
            },
        )

        self.assertEqual(response.status_code, 202)
        queued_payload = response.get_json()
        self.assertEqual(queued_payload["type"], "chain")
        self.assertIsNotNone(queued_payload.get("chain"))
        self.assertEqual(len(queued_payload["chain"]["steps"]), 2)
        self.assertEqual(queued_payload["result"]["status"], "queued")

        completed = self._wait_for_job(client, queued_payload["job_id"])
        self.assertEqual(completed["status"], "completed")
        self.assertEqual(completed["result"]["media_type"], "image")
        self.assertEqual(completed["result"]["prompt"], "generated prompt")

        listed_jobs = client.get("/api/jobs").get_json()["items"]
        child_jobs = [
            item
            for item in listed_jobs
            if item.get("parent_job_id") == queued_payload["job_id"]
        ]
        self.assertEqual(len(child_jobs), 2)
        self.assertEqual(
            {item["chain_step_id"] for item in child_jobs},
            {"prompt", "image"},
        )

    def test_generate_prompt_then_image_then_i2v_prompt_then_animate_chain_flow(self) -> None:
        runtime_dir = self._workspace_dir("lucky_video_chain")
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        app = self._create_test_app(
            runtime_dir,
            VIDEO_MODELS_DIR=str(video_models_dir),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "prompt",
                        "type": "generate_prompt",
                        "payload": {
                            "prompt": "general base prompt",
                            "model_name": "demo-prompt-model",
                        },
                    },
                    {
                        "id": "image",
                        "type": "generate",
                        "payload": {
                            "prompt": "",
                            "default_positive_prompt": "best quality",
                            "default_negative_prompt": "bad anatomy",
                            "model_id": "demo_model",
                            "loras": [],
                        },
                        "bindings": {
                            "prompt": {
                                "step_id": "prompt",
                                "output": "result_text",
                            }
                        },
                    },
                    {
                        "id": "video_prompt",
                        "type": "generate_i2v_prompt",
                        "payload": {
                            "prompt": "animate this scene",
                            "model_name": "demo-i2v-model",
                        },
                        "bindings": {
                            "image_id": {
                                "step_id": "image",
                                "output": "result_image_id",
                            }
                        },
                    },
                    {
                        "id": "video",
                        "type": "animate_image",
                        "payload": {
                            "prompt": "",
                            "default_positive_prompt": "best quality",
                            "default_negative_prompt": "bad quality",
                            "preset": "preview",
                        },
                        "bindings": {
                            "image_id": {
                                "step_id": "image",
                                "output": "result_image_id",
                            },
                            "prompt": {
                                "step_id": "video_prompt",
                                "output": "result_text",
                            },
                        },
                    },
                ]
            },
        )

        self.assertEqual(response.status_code, 202)
        completed = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(completed["status"], "completed")
        self.assertEqual(completed["result"]["media_type"], "video")
        source_image_id = completed["result"]["source_image_id"]
        self.assertTrue(source_image_id)
        self.assertEqual(completed["result"]["prompt"], "generated i2v prompt")

        parent_chain = completed["chain"]
        self.assertEqual(parent_chain["current_step_id"], None)
        self.assertEqual(parent_chain["current_child_job_id"], None)
        self.assertEqual(
            [step["id"] for step in parent_chain["steps"]],
            ["prompt", "image", "video_prompt", "video"],
        )

    def test_stored_image_prompt_then_i2v_chain_flow(self) -> None:
        runtime_dir = self._workspace_dir("stored_image_prompt_then_i2v")
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        app = self._create_test_app(
            runtime_dir,
            VIDEO_MODELS_DIR=str(video_models_dir),
        )
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])
        source_path = stored_dir / "source-image.png"
        Image.new("RGB", (640, 360), color="orange").save(source_path)
        self._insert_image_record(
            db,
            image_id="stored-source",
            status="stored",
            file_path=source_path,
            created_at="2026-01-01T00:00:00Z",
            stored_at="2026-01-01T00:00:00Z",
            width=640,
            height=360,
        )

        response = client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "video_prompt",
                        "type": "generate_i2v_prompt",
                        "payload": {
                            "prompt": "animate this image",
                            "image_id": "stored-source",
                            "model_name": "demo-i2v-model",
                        },
                    },
                    {
                        "id": "video",
                        "type": "animate_image",
                        "payload": {
                            "prompt": "",
                            "image_id": "stored-source",
                            "default_positive_prompt": "best quality",
                            "default_negative_prompt": "bad quality",
                            "preset": "preview",
                        },
                        "bindings": {
                            "prompt": {
                                "step_id": "video_prompt",
                                "output": "result_text",
                            }
                        },
                    },
                ]
            },
        )

        self.assertEqual(response.status_code, 202)
        completed = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(completed["status"], "completed")
        self.assertEqual(completed["result"]["media_type"], "video")
        self.assertEqual(completed["result"]["source_image_id"], "stored-source")
        self.assertEqual(completed["result"]["prompt"], "generated i2v prompt")

    def test_chain_route_validates_duplicates_bindings_and_upload_refs(self) -> None:
        runtime_dir = self._workspace_dir("chain_route_validation")
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        app = self._create_test_app(
            runtime_dir,
            VIDEO_MODELS_DIR=str(video_models_dir),
        )
        client = app.test_client()

        duplicate_response = client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "dup",
                        "type": "generate_prompt",
                        "payload": {"prompt": "base", "model_name": "demo"},
                    },
                    {
                        "id": "dup",
                        "type": "generate",
                        "payload": {
                            "prompt": "",
                            "default_positive_prompt": "",
                            "default_negative_prompt": "",
                            "model_id": "demo_model",
                            "loras": [],
                        },
                    },
                ]
            },
        )
        self.assertEqual(duplicate_response.status_code, 400)

        bad_binding_response = client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "video",
                        "type": "animate_image",
                        "payload": {
                            "prompt": "camera move",
                            "default_positive_prompt": "",
                            "default_negative_prompt": "",
                            "preset": "preview",
                        },
                        "bindings": {
                            "image_id": {
                                "step_id": "future",
                                "output": "result_image_id",
                            }
                        },
                    },
                    {
                        "id": "future",
                        "type": "generate",
                        "payload": {
                            "prompt": "later",
                            "default_positive_prompt": "",
                            "default_negative_prompt": "",
                            "model_id": "demo_model",
                            "loras": [],
                        },
                    },
                ]
            },
        )
        self.assertEqual(bad_binding_response.status_code, 400)

        missing_upload_response = client.post(
            "/api/jobs/chain",
            data={
                "chain": json.dumps(
                    {
                        "steps": [
                            {
                                "id": "image",
                                "type": "generate_from_image",
                                "payload": {
                                    "prompt": "stylize it",
                                    "default_positive_prompt": "",
                                    "default_negative_prompt": "",
                                    "model_id": "demo_model",
                                    "loras": [],
                                    "strength": 0.35,
                                    "upload_ref": "missing-file",
                                },
                            }
                        ]
                    }
                )
            },
            content_type="multipart/form-data",
        )
        self.assertEqual(missing_upload_response.status_code, 400)

        upload_response = client.post(
            "/api/jobs/chain",
            data={
                "chain": json.dumps(
                    {
                        "steps": [
                            {
                                "id": "image",
                                "type": "generate_from_image",
                                "payload": {
                                    "prompt": "stylize it",
                                    "default_positive_prompt": "",
                                    "default_negative_prompt": "",
                                    "model_id": "demo_model",
                                    "loras": [],
                                    "strength": 0.35,
                                    "upload_ref": "source",
                                },
                            }
                        ]
                    }
                ),
                "source": (io.BytesIO(b"fake-image-bytes"), "source.png"),
            },
            content_type="multipart/form-data",
        )
        self.assertEqual(upload_response.status_code, 202)
        upload_payload = upload_response.get_json()
        self.assertEqual(upload_payload["result"]["status"], "queued")
        self.assertEqual(upload_payload["result"]["media_type"], "image")

    def test_chain_cancellation_and_failure_propagate_from_children(self) -> None:
        runtime_dir = self._workspace_dir("chain_cancel_and_failure")
        video_models_dir = self._create_demo_video_models_dir(runtime_dir)
        generator = InterruptibleMockGenerator()
        app = self._create_test_app(
            runtime_dir,
            generator=generator,
            VIDEO_MODELS_DIR=str(video_models_dir),
        )
        client = app.test_client()

        cancel_response = client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "prompt",
                        "type": "generate_prompt",
                        "payload": {"prompt": "base", "model_name": "demo"},
                    },
                    {
                        "id": "image",
                        "type": "generate",
                        "payload": {
                            "prompt": "",
                            "default_positive_prompt": "",
                            "default_negative_prompt": "",
                            "model_id": "demo_model",
                            "loras": [],
                        },
                        "bindings": {
                            "prompt": {
                                "step_id": "prompt",
                                "output": "result_text",
                            }
                        },
                    },
                ]
            },
        )
        parent_job_id = cancel_response.get_json()["job_id"]
        self._wait_for_status(client, parent_job_id, {"running"})
        deadline = time.time() + 2.0
        child_jobs = []
        while time.time() < deadline:
            child_jobs = app.extensions["db"].list_jobs_by_parent(parent_job_id)
            if len(child_jobs) == 2:
                break
            time.sleep(0.02)
        self.assertEqual(len(child_jobs), 2)
        image_child = next(item for item in child_jobs if item["chain_step_id"] == "image")
        cancel_job_response = client.post(f"/api/jobs/{image_child['id']}/cancel")
        self.assertEqual(cancel_job_response.status_code, 200)
        cancelled_parent = self._wait_for_job(client, parent_job_id)
        self.assertEqual(cancelled_parent["status"], "cancelled")

        failing_runtime_dir = self._workspace_dir("chain_child_failure")
        failing_video_models_dir = self._create_demo_video_models_dir(failing_runtime_dir)
        failing_generator = MockGenerator()
        failing_generator.i2v_prompt_generation_error = RuntimeError("i2v prompt failed")
        failing_app = self._create_test_app(
            failing_runtime_dir,
            generator=failing_generator,
            VIDEO_MODELS_DIR=str(failing_video_models_dir),
        )
        failing_client = failing_app.test_client()
        stored_dir = Path(failing_app.config["STORED_DIR"])
        source_path = stored_dir / "failure-source.png"
        Image.new("RGB", (640, 360), color="purple").save(source_path)
        self._insert_image_record(
            failing_app.extensions["db"],
            image_id="failure-source",
            status="stored",
            file_path=source_path,
            created_at="2026-01-01T00:00:00Z",
            stored_at="2026-01-01T00:00:00Z",
            width=640,
            height=360,
        )

        failure_response = failing_client.post(
            "/api/jobs/chain",
            json={
                "steps": [
                    {
                        "id": "video_prompt",
                        "type": "generate_i2v_prompt",
                        "payload": {
                            "prompt": "animate this image",
                            "image_id": "failure-source",
                            "model_name": "demo-i2v-model",
                        },
                    },
                    {
                        "id": "video",
                        "type": "animate_image",
                        "payload": {
                            "prompt": "",
                            "image_id": "failure-source",
                            "default_positive_prompt": "",
                            "default_negative_prompt": "",
                            "preset": "preview",
                        },
                        "bindings": {
                            "prompt": {
                                "step_id": "video_prompt",
                                "output": "result_text",
                            }
                        },
                    },
                ]
            },
        )
        failed_parent = self._wait_for_job(failing_client, failure_response.get_json()["job_id"])
        self.assertEqual(failed_parent["status"], "failed")
        self.assertIn("i2v prompt failed", failed_parent["error"])

    def test_generate_audio_video_route_rejects_invalid_sources_and_missing_config(self) -> None:
        runtime_dir = self._workspace_dir("audio_video_route")
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
                "COMFY_VIDEO_TO_AUDIO_WORKFLOW_PATH": "",
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        missing_response = client.post(
            "/api/jobs/generate-audio-video",
            json={"image_id": "missing"},
        )
        self.assertEqual(missing_response.status_code, 404)

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        self.assertEqual(image_response.status_code, 202)
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        image_id = image_job["result"]["id"]

        wrong_media_response = client.post(
            "/api/jobs/generate-audio-video",
            json={"image_id": image_id},
        )
        self.assertEqual(wrong_media_response.status_code, 400)

        video_response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(video_response.status_code, 202)
        video_job = self._wait_for_job(client, video_response.get_json()["job_id"])
        video_id = video_job["result"]["id"]

        missing_config_response = client.post(
            "/api/jobs/generate-audio-video",
            json={"image_id": video_id},
        )
        self.assertEqual(missing_config_response.status_code, 503)
    def test_gif_results_can_be_used_as_image_and_video_sources(self) -> None:
        runtime_dir = self._workspace_dir("gif_source_reuse")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        video_response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(video_response.status_code, 202)
        video_job = self._wait_for_job(client, video_response.get_json()["job_id"])
        video_id = video_job["result"]["id"]

        convert_response = client.post(
            "/api/jobs/convert-video-gif",
            json={"image_id": video_id},
        )
        self.assertEqual(convert_response.status_code, 202)
        gif_job = self._wait_for_job(client, convert_response.get_json()["job_id"])
        gif_id = gif_job["result"]["id"]
        self.assertEqual(gif_job["result"]["media_type"], "gif")

        generate_response = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": gif_id,
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 0.4,
            },
        )
        self.assertEqual(generate_response.status_code, 202)
        generated_job = self._wait_for_job(client, generate_response.get_json()["job_id"])
        self.assertEqual(generated_job["status"], "completed")
        self.assertEqual(generated_job["result"]["source_image_id"], gif_id)

        animate_response = client.post(
            "/api/jobs/animate-image",
            json={
                "image_id": gif_id,
                "prompt": "camera zooms in",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
            },
        )
        self.assertEqual(animate_response.status_code, 202)
        animated_job = self._wait_for_job(client, animate_response.get_json()["job_id"])
        self.assertEqual(animated_job["status"], "completed")
        self.assertEqual(animated_job["result"]["source_image_id"], gif_id)

    def test_convert_video_to_gif_rejects_non_video_source(self) -> None:
        runtime_dir = self._workspace_dir("video_gif_validation")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        self.assertEqual(image_response.status_code, 202)
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])

        convert_response = client.post(
            "/api/jobs/convert-video-gif",
            json={"image_id": image_job["result"]["id"]},
        )
        self.assertEqual(convert_response.status_code, 400)
        self.assertIn("Only videos can be converted to GIF", convert_response.get_json()["error"])

    def test_upscale_video_job_rejects_non_video_source(self) -> None:
        runtime_dir = self._workspace_dir("video_upscale_validation")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])

        response = client.post(
            "/api/jobs/upscale-video",
            json={"image_id": image_job["result"]["id"], "scale_factor": 2.0},
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"], "Only videos can be scaled")

    def test_animate_image_job_ignores_loop_video_flag(self) -> None:
        runtime_dir = self._workspace_dir("animate_image_ignores_loop_flag")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        animate_response = client.post(
            "/api/jobs/animate-image",
            json={
                "image_id": image_id,
                "prompt": "camera zooms in",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "loop_video": True,
            },
        )
        self.assertEqual(animate_response.status_code, 202)

        animated_result = self._wait_for_job(client, animate_response.get_json()["job_id"])
        self.assertEqual(animated_result["status"], "completed")
        self.assertNotIn("loop_video", animated_result["payload"])
        self.assertNotIn("loop_video", animated_result["result"])
        self.assertEqual(animated_result["result"]["source_image_id"], image_id)

    def test_animate_image_job_does_not_require_loop_workflow_when_flag_is_sent(self) -> None:
        runtime_dir = self._workspace_dir("animate_image_without_loop_workflow")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        source_path = runtime_dir / "source.png"
        Image.new("RGB", (640, 640), color="white").save(source_path)
        with source_path.open("rb") as handle:
            response = client.post(
                "/api/jobs/animate-image",
                data={
                    "image": handle,
                    "prompt": "loop it",
                    "default_positive_prompt": "best quality",
                    "default_negative_prompt": "bad quality",
                    "preset": "quick_test",
                    "loop_video": "true",
                },
                content_type="multipart/form-data",
            )

        self.assertEqual(response.status_code, 202)
        payload = response.get_json()
        self.assertEqual(payload["result"]["status"], "queued")
        self.assertEqual(payload["result"]["media_type"], "video")

    def test_video_job_completes_with_generated_poster_when_artifact_has_none(self) -> None:
        runtime_dir = self._workspace_dir("posterless_video_completion")
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
            generator=PosterlessVideoMockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        self.assertEqual(response.status_code, 202)

        job = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["result"]["media_type"], "video")
        self.assertIsNotNone(job["result"]["poster_url"])
        self.assertIn("/thumbnail", job["result"]["preview_url"])

    def test_video_jobs_hide_helper_components_and_expose_generic_workflow_loras(self) -> None:
        runtime_dir = self._workspace_dir("video_bundle_routes")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        video_models_dir = self._create_test_video_bundle_dir(runtime_dir)
        text_to_video_workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        image_to_video_workflow_path = self._create_test_image_to_video_workflow_path(runtime_dir)
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
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
                "COMFY_T2V_WORKFLOW_PATH": str(text_to_video_workflow_path),
                "COMFY_I2V_WORKFLOW_PATH": str(image_to_video_workflow_path),
            },
            generator=generator,
        )
        client = app.test_client()

        def fake_get(url, timeout=None):
            class FakeResponse:
                def raise_for_status(self):
                    return None

                def json(self):
                    return [
                        "video-high.safetensors",
                        "video-low.safetensors",
                    ]

            self.assertTrue(url.endswith("/models/diffusion_models"))
            return FakeResponse()

        with patch("app.api.routes.requests.get", side_effect=fake_get):
            assets_payload = client.get("/api/assets").get_json()
        self.assertEqual(
            [item["label"] for item in assets_payload["video_models"]],
            [
                "ComfyUI Text-to-Video",
                "ComfyUI Image-to-Video",
            ],
        )
        self.assertEqual(
            assets_payload["video_diffusion_models"],
            ["video-high.safetensors", "video-low.safetensors"],
        )
        self.assertIn(
            "test_t2v_adapter.safetensors",
            [
                item["name"]
                for item in assets_payload["video_models"][0]["workflow_loras"]
            ],
        )
        self.assertIn(
            "test_i2v_adapter.safetensors",
            [
                item["name"]
                for item in assets_payload["video_models"][1]["workflow_loras"]
            ],
        )
        self.assertNotIn(
            "demo_model",
            assets_payload["video_diffusion_models"],
        )
        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        video_response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
                "high_diffusion_model_name": "video-high.safetensors",
                "low_diffusion_model_name": "video-low.safetensors",
                "workflow_loras": [
                    {"lora_id": "70:strength_model", "strength": 0.75},
                ],
            },
        )
        video_result = self._wait_for_job(client, video_response.get_json()["job_id"])
        self.assertEqual(
            video_result["result"]["model_id"],
            "video-high.safetensors + video-low.safetensors",
        )
        self.assertEqual(
            generator.last_video_generation_payload.high_diffusion_model_name,
            "video-high.safetensors",
        )
        self.assertEqual(
            generator.last_video_generation_payload.low_diffusion_model_name,
            "video-low.safetensors",
        )
        self.assertEqual(
            generator.last_video_generation_payload.workflow_loras[0].lora_id,
            "70:strength_model",
        )
        self.assertEqual(
            generator.last_video_generation_payload.workflow_loras[0].strength,
            0.75,
        )

        animate_response = client.post(
            "/api/jobs/animate-image",
            json={
                "image_id": image_id,
                "prompt": "camera zooms in",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "high_diffusion_model_name": "video-high.safetensors",
                "low_diffusion_model_name": "video-low.safetensors",
                "workflow_loras": [
                    {"lora_id": "20:strength_model", "strength": 0.65},
                ],
            },
        )
        animate_result = self._wait_for_job(client, animate_response.get_json()["job_id"])
        self.assertEqual(
            animate_result["result"]["model_id"],
            "video-high.safetensors + video-low.safetensors",
        )
        self.assertEqual(
            generator.last_animation_payload.high_diffusion_model_name,
            "video-high.safetensors",
        )
        self.assertEqual(
            generator.last_animation_payload.low_diffusion_model_name,
            "video-low.safetensors",
        )
        self.assertEqual(
            generator.last_animation_payload.workflow_loras[0].lora_id,
            "20:strength_model",
        )
        self.assertEqual(
            generator.last_animation_payload.workflow_loras[0].strength,
            0.65,
        )

    def test_generate_video_job_accepts_custom_frame_counts_above_201(self) -> None:
        runtime_dir = self._workspace_dir("long_custom_video")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera glides through a canyon",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "standard",
                "image_orientation": "landscape",
                "width": 1024,
                "height": 576,
                "fps": 16,
                "num_frames": 257,
            },
        )
        self.assertEqual(response.status_code, 202)

        video_job = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(video_job["status"], "completed")
        self.assertEqual(video_job["result"]["media_type"], "video")
        self.assertEqual(video_job["result"]["num_frames"], 257)
        self.assertEqual(video_job["result"]["fps"], 16)

    def test_generate_from_stored_image_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("img2img_stored")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        response = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": image_id,
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [{"lora_id": "demo_lora", "strength": 0.8}],
                "num_inference_steps": 30,
                "guidance_scale": 6.5,
                "image_orientation": "portrait",
                "strength": 0.4,
            },
        )
        self.assertEqual(response.status_code, 202)
        payload = response.get_json()
        self.assertEqual(payload["result"]["status"], "queued")
        self.assertEqual(payload["result"]["media_type"], "image")
        result = self._wait_for_job(client, payload["job_id"])
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["result"]["source_image_id"], image_id)
        self.assertEqual(result["result"]["loras"][0]["lora_id"], "demo_lora")

    def test_generate_from_uploaded_image_job_flow(self) -> None:
        runtime_dir = self._workspace_dir("img2img_uploaded")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        source_path = runtime_dir / "source.png"
        Image.new("RGB", (640, 640), color="white").save(source_path)
        with source_path.open("rb") as handle:
            response = client.post(
                "/api/jobs/generate-from-image",
                data={
                    "image": handle,
                    "prompt": "turn it cinematic",
                    "default_positive_prompt": "best quality",
                    "default_negative_prompt": "bad anatomy",
                    "model_id": "demo_model",
                    "loras": json.dumps([]),
                    "num_inference_steps": "25",
                    "guidance_scale": "5.5",
                    "image_orientation": "landscape",
                    "strength": "0.35",
                },
                content_type="multipart/form-data",
            )
        self.assertEqual(response.status_code, 202)
        result = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(result["status"], "completed")
        self.assertIsNone(result["result"]["source_image_id"])

    def test_generate_from_image_validation(self) -> None:
        runtime_dir = self._workspace_dir("img2img_validation")
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
            },
            generator=MockGenerator(),
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        stored_image_id = image_job["result"]["id"]
        client.post(f"/api/images/{stored_image_id}/store")

        video_response = client.post(
            "/api/jobs/generate-video",
            json={
                "prompt": "camera pans slowly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad quality",
                "preset": "preview",
                "image_orientation": "landscape",
            },
        )
        video_job = self._wait_for_job(client, video_response.get_json()["job_id"])
        stored_video_id = video_job["result"]["id"]
        client.post(f"/api/images/{stored_video_id}/store")

        missing_source = client.post(
            "/api/jobs/generate-from-image",
            json={
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 0.4,
            },
        )
        self.assertEqual(missing_source.status_code, 400)

        invalid_strength = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": stored_image_id,
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 1.2,
            },
        )
        self.assertEqual(invalid_strength.status_code, 400)

        unknown_source = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": "missing-image",
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 0.4,
            },
        )
        self.assertEqual(unknown_source.status_code, 404)

        video_source = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": stored_video_id,
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 0.4,
            },
        )
        self.assertEqual(video_source.status_code, 400)

    def test_generate_from_image_passes_requested_strength(self) -> None:
        runtime_dir = self._workspace_dir("img2img_strength")
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
                "TEMP_TTL_SECONDS": 7200,
                "CLEANUP_INTERVAL_SECONDS": 3600,
            },
            generator=generator,
        )
        client = app.test_client()

        image_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, image_response.get_json()["job_id"])
        stored_image_id = image_job["result"]["id"]
        client.post(f"/api/images/{stored_image_id}/store")

        response = client.post(
            "/api/jobs/generate-from-image",
            json={
                "image_id": stored_image_id,
                "prompt": "make it painterly",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "strength": 0.7,
            },
        )
        self.assertEqual(response.status_code, 202)
        result = self._wait_for_job(client, response.get_json()["job_id"])
        self.assertEqual(result["status"], "completed")
        self.assertIsNotNone(generator.last_generate_from_image_payload)
        self.assertEqual(generator.last_generate_from_image_payload.strength, 0.7)

    def test_failed_jobs_are_logged_and_listed(self) -> None:
        runtime_dir = self._workspace_dir("errors")
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
            generator=FailingGenerator(),
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

        failed_job = self._wait_for_job(client, job_id)
        self.assertEqual(failed_job["status"], "failed")
        self.assertEqual(
            failed_job["error"],
            "Failed to load model weights for demo_model",
        )

        errors_response = client.get("/api/errors")
        self.assertEqual(errors_response.status_code, 200)
        error_items = errors_response.get_json()["items"]
        self.assertEqual(len(error_items), 1)
        self.assertEqual(error_items[0]["job"]["job_id"], job_id)
        self.assertEqual(
            error_items[0]["error_text"],
            "Failed to load model weights for demo_model",
        )
        self.assertEqual(error_items[0]["job"]["payload"]["model_id"], "demo_model")

        errors_dir = Path(app.config["ERRORS_DIR"])
        error_files = list(errors_dir.glob("*.json"))
        self.assertEqual(len(error_files), 1)
        self.assertIn(job_id, error_files[0].stem)

    def test_generate_job_applies_ollama_auto_caption_and_tags(self) -> None:
        runtime_dir = self._workspace_dir("auto_metadata_generate")
        generator = MockGenerator()
        generator.chat_response = json.dumps(
            {
                "caption": "A vivid red generated image.",
                "tags": ["portrait", "New Tag", "portrait"],
            }
        )
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        existing_path = stored_dir / "existing.png"
        Image.new("RGB", (128, 128), color="blue").save(existing_path)
        self._insert_image_record(
            db,
            image_id="existing-tag-source",
            status="stored",
            file_path=existing_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            tags=["Portrait"],
        )

        response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "auto_metadata_enabled": True,
                "auto_metadata_model_name": "llava:latest",
            },
        )
        self.assertEqual(response.status_code, 202)

        job = self._wait_for_job(client, response.get_json()["job_id"])

        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["result"]["caption"], "A vivid red generated image.")
        self.assertEqual(job["result"]["tags"], ["Portrait", "New Tag"])
        self.assertEqual(generator.last_chat_model, "llava:latest")
        system_prompt = generator.last_chat_messages[0]["content"]
        self.assertIn("canonical spelling reference", system_prompt)
        self.assertIn("Ignore unrelated existing tags", system_prompt)

    def test_auto_metadata_failure_keeps_job_completed_and_logs_error(self) -> None:
        runtime_dir = self._workspace_dir("auto_metadata_failure")
        generator = MockGenerator()
        generator.chat_generation_error = RuntimeError("vision model unavailable")
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()

        response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "portrait",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
                "auto_metadata_enabled": True,
                "auto_metadata_model_name": "llava:latest",
            },
        )
        self.assertEqual(response.status_code, 202)

        job = self._wait_for_job(client, response.get_json()["job_id"])

        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["result"]["caption"], "")
        self.assertEqual(job["result"]["tags"], [])
        errors_response = client.get("/api/errors")
        self.assertEqual(errors_response.status_code, 200)
        error_items = errors_response.get_json()["items"]
        matching_errors = [
            item
            for item in error_items
            if item.get("job", {}).get("payload", {}).get("mode") == "generate"
            and item.get("job", {}).get("payload", {}).get("model_name") == "llava:latest"
        ]
        self.assertTrue(matching_errors)
        self.assertEqual(matching_errors[0]["job"]["type"], "system")
        self.assertEqual(matching_errors[0]["error_text"], "vision model unavailable")

    def test_animate_image_copies_source_caption_and_tags(self) -> None:
        runtime_dir = self._workspace_dir("auto_metadata_i2v_copy")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        source_path = stored_dir / "source.png"
        Image.new("RGB", (512, 512), color="purple").save(source_path)
        self._insert_image_record(
            db,
            image_id="source-image",
            status="stored",
            file_path=source_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            caption="A purple source image.",
            tags=["source", "purple"],
            width=512,
            height=512,
        )

        response = client.post(
            "/api/jobs/animate-image",
            json={
                "image_id": "source-image",
                "prompt": "slow orbit",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "preset": "preview",
            },
        )
        self.assertEqual(response.status_code, 202)

        job = self._wait_for_job(client, response.get_json()["job_id"])

        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["result"]["caption"], "A purple source image.")
        self.assertEqual(job["result"]["tags"], ["source", "purple"])

    def test_list_jobs_recovers_queued_job_missing_from_worker_queue(self) -> None:
        runtime_dir = self._workspace_dir("recover_queued_job")
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
        db = app.extensions["db"]
        worker = app.extensions["job_worker"]

        job_id = "recovered-queued-job"
        result_image_id = "recovered-queued-result"
        payload = {
            "prompt": "recover queued job",
            "default_positive_prompt": "best quality",
            "default_negative_prompt": "bad anatomy",
            "model_id": "demo_model",
            "loras": [],
        }
        db.create_image_placeholder(
            image_id=result_image_id,
            status="queued",
            **worker._build_placeholder(
                job_type="generate",
                payload=payload,
                image_id=result_image_id,
            ),
        )
        db.insert_job(
            job_id=job_id,
            job_type="generate",
            payload=payload,
            result_image_id=result_image_id,
        )

        response = client.get("/api/jobs")
        self.assertEqual(response.status_code, 200)

        result = self._wait_for_status(client, job_id, {"completed"})
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["result"]["status"], "stored")

    def test_job_lookup_cleans_stale_running_job_missing_from_worker_queue(self) -> None:
        runtime_dir = self._workspace_dir("recover_running_job")
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
        db = app.extensions["db"]
        worker = app.extensions["job_worker"]

        job_id = "recovered-running-job"
        result_image_id = "recovered-running-result"
        payload = {
            "prompt": "recover running job",
            "default_positive_prompt": "best quality",
            "default_negative_prompt": "bad anatomy",
            "model_id": "demo_model",
            "loras": [],
        }
        db.create_image_placeholder(
            image_id=result_image_id,
            status="running",
            **worker._build_placeholder(
                job_type="generate",
                payload=payload,
                image_id=result_image_id,
            ),
        )
        db.insert_job(
            job_id=job_id,
            job_type="generate",
            payload=payload,
            result_image_id=result_image_id,
        )
        db.update_job(
            job_id,
            status="running",
            progress=0.5,
            status_text="Rendering",
        )

        response = client.get(f"/api/jobs/{job_id}")
        self.assertEqual(response.status_code, 200)
        result = response.get_json()
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["status_text"], "Interrupted by server restart")
        self.assertEqual(result["error"], "Job was interrupted because the server restarted or the worker stopped.")
        self.assertIsNone(result.get("result"))

    def test_interrupted_running_job_keeps_already_stored_result(self) -> None:
        runtime_dir = self._workspace_dir("recover_running_stored_result")
        temp_dir = runtime_dir / "temp"
        stored_dir = runtime_dir / "stored"
        backups_dir = runtime_dir / "backups"
        errors_dir = runtime_dir / "errors"
        data_dir = runtime_dir / "data"
        for path in (temp_dir, stored_dir, backups_dir, errors_dir, data_dir):
            path.mkdir(parents=True, exist_ok=True)

        db = AppDatabase(
            runtime_dir / "app.db",
            temp_dir,
            stored_dir,
            backups_dir,
            errors_dir,
            data_dir=data_dir,
        )
        db.init_schema()
        worker = JobWorker(
            db=db,
            error_store=ErrorStore(errors_dir),
            generator=MockGenerator(),
            temp_dir=temp_dir,
        )

        job_id = "stored-result-running-job"
        result_image_id = "stored-result-image"
        payload = {
            "prompt": "almost finished",
            "default_positive_prompt": "best quality",
            "default_negative_prompt": "bad anatomy",
            "model_id": "demo_model",
            "loras": [],
        }
        db.create_image_placeholder(
            image_id=result_image_id,
            status="running",
            **worker._build_placeholder(
                job_type="generate",
                payload=payload,
                image_id=result_image_id,
            ),
        )
        db.insert_job(
            job_id=job_id,
            job_type="generate",
            payload=payload,
            result_image_id=result_image_id,
        )
        db.update_job(
            job_id,
            status="running",
            progress=0.95,
            status_text="Finalizing",
        )
        artifact_path = temp_dir / "finished.png"
        Image.new("RGB", (64, 48), color="purple").save(artifact_path)
        db.finalize_image_placeholder(
            result_image_id,
            GeneratedArtifact(
                image_id="artifact-id",
                file_path=str(artifact_path),
                width=64,
                height=48,
                prompt=payload["prompt"],
                default_positive_prompt=payload["default_positive_prompt"],
                default_negative_prompt=payload["default_negative_prompt"],
                final_positive_prompt="best quality, almost finished",
                model_id=payload["model_id"],
                loras=[],
                num_inference_steps=40,
                guidance_scale=5.0,
                mime_type="image/png",
            ),
        )

        cleaned = worker.cleanup_interrupted_jobs()

        self.assertEqual(cleaned, 1)
        job = db.get_job(job_id)
        self.assertIsNotNone(job)
        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["status_text"], "Completed")
        self.assertIsNone(job["error"])
        image = db.get_image(result_image_id)
        self.assertIsNotNone(image)
        self.assertEqual(image["status"], "stored")
        self.assertTrue(Path(image["file_path"]).exists())
        self.assertEqual(ErrorStore(errors_dir).list_errors(), [])

    def test_clear_finished_jobs_keeps_running_and_queued_entries(self) -> None:
        runtime_dir = self._workspace_dir("clear_finished_jobs")
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
        db = app.extensions["db"]

        db.insert_job(job_id="queued-job", job_type="generate", payload={"prompt": "queued"})
        db.insert_job(job_id="running-job", job_type="generate", payload={"prompt": "running"})
        db.update_job(
            "running-job",
            status="running",
            progress=0.4,
            status_text="Rendering",
        )
        db.insert_job(
            job_id="completed-job",
            job_type="generate",
            payload={"prompt": "completed"},
        )
        db.update_job(
            "completed-job",
            status="completed",
            progress=1.0,
            status_text="Completed",
        )
        db.insert_job(job_id="failed-job", job_type="generate", payload={"prompt": "failed"})
        db.update_job(
            "failed-job",
            status="failed",
            progress=1.0,
            status_text="Failed",
            error="boom",
        )
        db.insert_job(
            job_id="cancelled-job",
            job_type="generate",
            payload={"prompt": "cancelled"},
        )
        db.mark_job_cancelled("cancelled-job")

        response = client.delete("/api/jobs?scope=finished")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["deleted"], 3)

        listing = db.list_jobs(page=1, page_size=50)
        self.assertEqual(listing["total"], 2)
        statuses = {item["id"]: item["status"] for item in listing["items"]}
        self.assertEqual(
            statuses,
            {
                "queued-job": "queued",
                "running-job": "running",
            },
        )

    def test_clear_errors_route_removes_all_logged_errors(self) -> None:
        runtime_dir = self._workspace_dir("clear_errors")
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
            generator=FailingGenerator(),
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
        failed_job = self._wait_for_job(client, job_id)
        self.assertEqual(failed_job["status"], "failed")

        clear_response = client.delete("/api/errors")
        self.assertEqual(clear_response.status_code, 200)
        self.assertEqual(clear_response.get_json()["deleted"], 1)

        errors_response = client.get("/api/errors")
        self.assertEqual(errors_response.status_code, 200)
        self.assertEqual(errors_response.get_json()["items"], [])

        errors_dir = Path(app.config["ERRORS_DIR"])
        self.assertEqual(list(errors_dir.glob("*.json")), [])

    def test_job_listing_cancellation_and_rating(self) -> None:
        runtime_dir = self._workspace_dir("job_cancel")
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

        listing = client.get("/api/jobs").get_json()
        self.assertEqual(listing["total"], 1)
        self.assertEqual(listing["items"][0]["job_id"], job_id)
        self.assertEqual(listing["items"][0]["payload"]["prompt"], "portrait")

        running_payload = self._wait_for_status(client, job_id, {"running"})
        self.assertEqual(running_payload["status"], "running")
        self.assertEqual(running_payload["payload"]["model_id"], "demo_model")
        self.assertIsNotNone(running_payload["started_at"])

        cancel_response = client.post(f"/api/jobs/{job_id}/cancel")
        self.assertEqual(cancel_response.status_code, 200)
        self.assertTrue(cancel_response.get_json()["cancel_requested"])
        self.assertIsNotNone(cancel_response.get_json()["cancel_requested_at"])
        self.assertIsNone(cancel_response.get_json()["cancelled_at"])

        cancelled_payload = self._wait_for_status(client, job_id, {"cancelled"})
        self.assertEqual(cancelled_payload["status"], "cancelled")
        self.assertIsNotNone(cancelled_payload["cancel_requested_at"])
        self.assertIsNotNone(cancelled_payload["cancelled_at"])

        generate_response = client.post(
            "/api/jobs/generate",
            json={
                "prompt": "landscape",
                "default_positive_prompt": "best quality",
                "default_negative_prompt": "bad anatomy",
                "model_id": "demo_model",
                "loras": [],
            },
        )
        image_job = self._wait_for_job(client, generate_response.get_json()["job_id"])
        image_id = image_job["result"]["id"]
        client.post(f"/api/images/{image_id}/store")

        rating_response = client.post(f"/api/images/{image_id}/rating", json={"rating": 4})
        self.assertEqual(rating_response.status_code, 200)
        self.assertEqual(rating_response.get_json()["rating"], 4)

        tags_response = client.post(
            f"/api/images/{image_id}/tags",
            json={"tags": ["favorite", "anime", "favorite"]},
        )
        self.assertEqual(tags_response.status_code, 200)
        self.assertEqual(tags_response.get_json()["tags"], ["favorite", "anime"])

        all_tags_response = client.get("/api/tags")
        self.assertEqual(all_tags_response.status_code, 200)
        self.assertEqual(all_tags_response.get_json()["tags"], ["anime", "favorite"])

        delete_tag_response = client.delete("/api/tags/favorite")
        self.assertEqual(delete_tag_response.status_code, 200)
        self.assertEqual(delete_tag_response.get_json()["removed_from_images"], 1)
        self.assertEqual(delete_tag_response.get_json()["tags"], ["anime"])

        image_after_delete = client.get(f"/api/images/{image_id}").get_json()
        self.assertEqual(image_after_delete["tags"], ["anime"])

    def test_running_job_cancel_interrupts_generation(self) -> None:
        runtime_dir = self._workspace_dir("job_interrupt_cancel")
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
            generator=InterruptibleMockGenerator(),
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

        self._wait_for_status(client, job_id, {"running"})
        cancel_response = client.post(f"/api/jobs/{job_id}/cancel")
        self.assertEqual(cancel_response.status_code, 200)
        self.assertTrue(cancel_response.get_json()["cancel_requested"])
        self.assertEqual(cancel_response.get_json()["status"], "running")
        self.assertIsNotNone(cancel_response.get_json()["cancel_requested_at"])
        self.assertIsNone(cancel_response.get_json()["cancelled_at"])

        cancelled_payload = self._wait_for_status(client, job_id, {"cancelled"})
        self.assertEqual(cancelled_payload["status"], "cancelled")
        self.assertIsNone(cancelled_payload.get("result"))
        self.assertIsNotNone(cancelled_payload["cancel_requested_at"])
        self.assertIsNotNone(cancelled_payload["cancelled_at"])
        result_image_id = app.extensions["db"].get_job(job_id)["result_image_id"]
        self.assertIsNotNone(result_image_id)
        self.assertIsNone(app.extensions["db"].get_image(result_image_id))

    def test_cancel_all_jobs_cancels_running_and_queued_entries(self) -> None:
        runtime_dir = self._workspace_dir("cancel_all_jobs")
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
            generator=InterruptibleMockGenerator(),
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
        self.assertEqual(first_response.status_code, 202)
        running_job_id = first_response.get_json()["job_id"]
        self._wait_for_status(client, running_job_id, {"running"})

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
        self.assertEqual(second_response.status_code, 202)
        queued_job_id = second_response.get_json()["job_id"]

        cancel_response = client.post("/api/jobs/cancel")
        self.assertEqual(cancel_response.status_code, 200)
        payload = cancel_response.get_json()
        self.assertEqual(payload["cancelled"], 2)
        self.assertEqual(len(payload["items"]), 2)
        returned_job_ids = {item["job_id"] for item in payload["items"]}
        self.assertEqual(returned_job_ids, {running_job_id, queued_job_id})

        running_payload = self._wait_for_status(client, running_job_id, {"cancelled"})
        queued_payload = self._wait_for_status(client, queued_job_id, {"cancelled"})
        self.assertEqual(running_payload["status"], "cancelled")
        self.assertEqual(queued_payload["status"], "cancelled")
        self.assertIsNotNone(running_payload["cancel_requested_at"])
        self.assertIsNotNone(queued_payload["cancelled_at"])

    def test_asset_rating_and_delete_routes(self) -> None:
        runtime_dir = self._workspace_dir("asset_routes")
        models_dir, loras_dir, lora_triggers_dir, _ = self._create_demo_asset_dirs(runtime_dir)
        (lora_triggers_dir / "demo-lora.txt").write_text("trigger words", encoding="utf-8")
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

        initial_assets = client.get("/api/assets")
        self.assertEqual(initial_assets.status_code, 200)
        self.assertEqual(initial_assets.get_json()["models"][0]["rating"], 0)
        self.assertEqual(initial_assets.get_json()["loras"][0]["rating"], 0)
        self.assertEqual(
            initial_assets.get_json()["video_presets"][0]["id"],
            "standard",
        )
        self.assertTrue(initial_assets.get_json()["video_presets"][0]["is_default"])
        self.assertEqual(initial_assets.get_json()["video_presets"][0]["num_inference_steps"], 8)

        model_rating_response = client.post(
            "/api/assets/model/demo_model/rating",
            json={"rating": 5},
        )
        self.assertEqual(model_rating_response.status_code, 405)
        self.assertIn("read-only", model_rating_response.get_json()["error"])

        lora_rating_response = client.post(
            "/api/assets/lora/demo_lora/rating",
            json={"rating": 2},
        )
        self.assertEqual(lora_rating_response.status_code, 405)
        self.assertIn("read-only", lora_rating_response.get_json()["error"])

        rated_assets = client.get("/api/assets").get_json()
        self.assertEqual(rated_assets["models"][0]["rating"], 0)
        self.assertEqual(rated_assets["loras"][0]["rating"], 0)

        delete_lora_response = client.delete("/api/assets/lora/demo_lora")
        self.assertEqual(delete_lora_response.status_code, 200)
        self.assertEqual(client.get("/api/assets").get_json()["loras"], [])

        delete_model_response = client.delete("/api/assets/model/demo_model")
        self.assertEqual(delete_model_response.status_code, 200)
        self.assertEqual(client.get("/api/assets").get_json()["models"], [])
