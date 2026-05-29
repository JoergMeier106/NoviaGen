from __future__ import annotations

from .shared import *


class GalleryMediaTests(BackendTestCase):
    def test_gallery_listing_supports_filters_sorting_and_has_more(self) -> None:
        runtime_dir = self._workspace_dir("gallery_filters")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        first_path = stored_dir / "gallery-first.png"
        second_path = stored_dir / "gallery-second.png"
        third_path = stored_dir / "gallery-third.png"
        Image.new("RGB", (300, 200), color="red").save(first_path)
        Image.new("RGB", (640, 480), color="green").save(second_path)
        Image.new("RGB", (512, 512), color="blue").save(third_path)

        self._insert_image_record(
            db,
            image_id="img-1",
            status="stored",
            file_path=first_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            model_id="model-a",
            tags=["portrait", "favorites"],
            rating=5,
            width=300,
            height=200,
            prompt="bright portrait",
            final_positive_prompt="best quality, bright portrait",
        )
        self._insert_image_record(
            db,
            image_id="img-2",
            status="stored",
            file_path=second_path,
            created_at="2026-01-02T00:00:00+00:00",
            stored_at="2026-01-02T00:00:00+00:00",
            model_id="model-b",
            tags=["landscape"],
            rating=3,
            width=640,
            height=480,
            prompt="wide view",
            final_positive_prompt="best quality, wide view",
            generation_duration_seconds=8.5,
        )
        self._insert_image_record(
            db,
            image_id="img-3",
            status="stored",
            file_path=third_path,
            created_at="2026-01-03T00:00:00+00:00",
            stored_at="2026-01-03T00:00:00+00:00",
            model_id="model-a",
            tags=["portrait"],
            rating=4,
            width=512,
            height=512,
            prompt="night portrait",
            final_positive_prompt="best quality, night portrait",
            generation_duration_seconds=3.0,
        )

        response = client.get(
            "/api/images",
            query_string={
                "page": 1,
                "page_size": 1,
                "include_tags": "portrait",
                "model_id": "model-a",
                "min_rating": 4,
                "sort": "ratingHigh",
            },
        )
        payload = response.get_json()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(payload["total"], 2)
        self.assertTrue(payload["has_more"])
        self.assertEqual([item["id"] for item in payload["items"]], ["img-1"])

        second_page = client.get(
            "/api/images",
            query_string={
                "page": 2,
                "page_size": 1,
                "include_tags": "portrait",
                "model_id": "model-a",
                "min_rating": 4,
                "sort": "ratingHigh",
            },
        ).get_json()
        self.assertFalse(second_page["has_more"])
        self.assertEqual([item["id"] for item in second_page["items"]], ["img-3"])

        search_response = client.get(
            "/api/images",
            query_string={
                "page": 1,
                "page_size": 10,
                "search": "night",
                "sort": "generationDurationLow",
            },
        ).get_json()
        self.assertEqual([item["id"] for item in search_response["items"]], ["img-3"])

    def test_gallery_listing_can_hide_placeholders(self) -> None:
        runtime_dir = self._workspace_dir("gallery_hide_placeholders")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        stored_path = stored_dir / "gallery-stored.png"
        queued_path = stored_dir / "gallery-queued.png"
        running_path = stored_dir / "gallery-running.png"
        Image.new("RGB", (128, 128), color="red").save(stored_path)
        Image.new("RGB", (128, 128), color="green").save(queued_path)
        Image.new("RGB", (128, 128), color="blue").save(running_path)

        self._insert_image_record(
            db,
            image_id="img-stored",
            status="stored",
            file_path=stored_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
        )
        self._insert_image_record(
            db,
            image_id="img-queued",
            status="queued",
            file_path=queued_path,
            created_at="2026-01-02T00:00:00+00:00",
        )
        self._insert_image_record(
            db,
            image_id="img-running",
            status="running",
            file_path=running_path,
            created_at="2026-01-03T00:00:00+00:00",
        )

        default_payload = client.get(
            "/api/images",
            query_string={"page": 1, "page_size": 10},
        ).get_json()
        self.assertEqual(default_payload["total"], 3)
        self.assertEqual(
            [item["id"] for item in default_payload["items"]],
            ["img-running", "img-queued", "img-stored"],
        )

        hidden_payload = client.get(
            "/api/images",
            query_string={
                "page": 1,
                "page_size": 10,
                "include_placeholders": "false",
            },
        ).get_json()
        self.assertEqual(hidden_payload["total"], 1)
        self.assertFalse(hidden_payload["has_more"])
        self.assertEqual(
            [item["id"] for item in hidden_payload["items"]],
            ["img-stored"],
        )

    def test_gallery_filters_endpoint_returns_models_and_tags(self) -> None:
        runtime_dir = self._workspace_dir("gallery_filter_metadata")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        first_path = stored_dir / "filters-first.png"
        second_path = stored_dir / "filters-second.png"
        Image.new("RGB", (128, 128), color="red").save(first_path)
        Image.new("RGB", (128, 128), color="blue").save(second_path)

        self._insert_image_record(
            db,
            image_id="img-1",
            status="stored",
            file_path=first_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            model_id="z-model",
            tags=["Portrait", "Favorites"],
        )
        self._insert_image_record(
            db,
            image_id="img-2",
            status="stored",
            file_path=second_path,
            created_at="2026-01-02T00:00:00+00:00",
            stored_at="2026-01-02T00:00:00+00:00",
            model_id="a-model",
            tags=["favorites", "Night"],
        )

        payload = client.get("/api/images/filters").get_json()

        self.assertEqual(payload["models"], ["a-model", "z-model"])
        self.assertEqual(payload["tags"], ["Favorites", "Night", "Portrait"])

    def test_image_payload_includes_caption_metadata(self) -> None:
        runtime_dir = self._workspace_dir("gallery_caption_payload")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        file_path = stored_dir / "captioned.png"
        Image.new("RGB", (128, 128), color="red").save(file_path)
        self._insert_image_record(
            db,
            image_id="captioned-image",
            status="stored",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            caption="A generated red square.",
            tags=["abstract"],
        )

        response = client.get("/api/images/captioned-image")

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["caption"], "A generated red square.")
        self.assertEqual(payload["tags"], ["abstract"])

    def test_generate_image_tags_route_uses_vision_metadata_model(self) -> None:
        runtime_dir = self._workspace_dir("gallery_generate_tags")
        generator = MockGenerator()
        generator.chat_response = json.dumps(
            {
                "caption": "Ignored for manual tag generation.",
                "tags": ["portrait", "New Tag", "portrait"],
            }
        )
        app = self._create_test_app(runtime_dir, generator=generator)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        file_path = stored_dir / "tag-source.png"
        Image.new("RGB", (128, 128), color="red").save(file_path)
        self._insert_image_record(
            db,
            image_id="tag-source",
            status="stored",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            caption="Keep this caption.",
            tags=["Manual", "Portrait"],
        )

        response = client.post(
            "/api/images/tag-source/generate-tags",
            json={"model_name": "llava:latest"},
        )

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["caption"], "Keep this caption.")
        self.assertEqual(payload["tags"], ["Manual", "Portrait", "New Tag"])
        self.assertEqual(generator.last_chat_model, "llava:latest")

    def test_thumbnail_route_lazily_persists_still_image_thumbnail(self) -> None:
        runtime_dir = self._workspace_dir("lazy_thumbnail")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        file_path = stored_dir / "lazy-thumb-source.png"
        Image.new("RGB", (1024, 768), color="purple").save(file_path)
        self._insert_image_record(
            db,
            image_id="img-1",
            status="stored",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
        )

        image_before = db.get_image("img-1")
        self.assertIsNotNone(image_before)
        self.assertIsNone(image_before["thumbnail_path"])

        listing = client.get(
            "/api/images",
            query_string={"page": 1, "page_size": 1},
        ).get_json()
        thumbnail_url = listing["items"][0]["thumbnail_url"]
        thumbnail_path = thumbnail_url.replace("http://localhost", "")

        thumbnail_response = client.get(thumbnail_path)
        self.assertEqual(thumbnail_response.status_code, 200)
        self.assertEqual(thumbnail_response.mimetype, "image/png")

        image_after = db.get_image("img-1")
        self.assertIsNotNone(image_after)
        self.assertIsNotNone(image_after["thumbnail_path"])
        self.assertTrue(Path(image_after["thumbnail_path"]).exists())

    def test_thumbnail_route_lazily_persists_square_video_thumbnail(self) -> None:
        runtime_dir = self._workspace_dir("lazy_video_thumbnail")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        file_path = stored_dir / "lazy-thumb-video.mp4"
        file_path.write_bytes(b"video")
        poster_path = stored_dir / "lazy-thumb-video-poster.png"
        Image.new("RGB", (1280, 720), color="teal").save(poster_path)
        self._insert_image_record(
            db,
            image_id="vid-1",
            status="stored",
            media_type="video",
            mime_type="video/mp4",
            file_path=file_path,
            poster_path=poster_path,
            poster_mime_type="image/png",
            width=1280,
            height=720,
            duration_seconds=4.5,
            fps=24,
            num_frames=108,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
        )

        image_before = db.get_image("vid-1")
        self.assertIsNotNone(image_before)
        self.assertIsNone(image_before["thumbnail_path"])

        listing = client.get(
            "/api/images",
            query_string={"page": 1, "page_size": 1},
        ).get_json()
        thumbnail_url = listing["items"][0]["thumbnail_url"]
        thumbnail_path = thumbnail_url.replace("http://localhost", "")

        thumbnail_response = client.get(thumbnail_path)
        self.assertEqual(thumbnail_response.status_code, 200)
        self.assertEqual(thumbnail_response.mimetype, "image/png")

        image_after = db.get_image("vid-1")
        self.assertIsNotNone(image_after)
        self.assertIsNotNone(image_after["thumbnail_path"])
        persisted_thumbnail_path = Path(image_after["thumbnail_path"])
        self.assertTrue(persisted_thumbnail_path.exists())
        with Image.open(persisted_thumbnail_path) as thumbnail:
            self.assertEqual(
                thumbnail.size,
                (db._THUMBNAIL_MAX_DIMENSION, db._THUMBNAIL_MAX_DIMENSION),
            )

    def test_delete_image_flags_media_and_keeps_thumbnail_until_retention(self) -> None:
        runtime_dir = self._workspace_dir("thumbnail_cleanup_backup")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        file_path = stored_dir / "cleanup-thumb-source.png"
        Image.new("RGB", (512, 512), color="orange").save(file_path)
        self._insert_image_record(
            db,
            image_id="img-1",
            status="stored",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
        )
        image_with_thumbnail = db.ensure_image_thumbnail("img-1", force=True)
        self.assertIsNotNone(image_with_thumbnail)
        thumbnail_path = Path(image_with_thumbnail["thumbnail_path"])
        self.assertTrue(thumbnail_path.exists())

        backup = db.create_backup()
        backup_path = Path(app.config["BACKUPS_DIR"]) / backup["name"]
        with zipfile.ZipFile(backup_path) as archive:
            self.assertIn("stored/cleanup-thumb-source.png", archive.namelist())
            self.assertIn(f"stored/{thumbnail_path.name}", archive.namelist())

        delete_response = client.delete("/api/images/img-1")
        self.assertEqual(delete_response.status_code, 200)
        deleted_image = db.get_image("img-1")
        self.assertIsNotNone(deleted_image)
        self.assertEqual(deleted_image["status"], "deleted")
        self.assertIsNotNone(deleted_image["deleted_at"])
        self.assertTrue(thumbnail_path.exists())

        kept_path = stored_dir / "kept-source.png"
        Image.new("RGB", (128, 128), color="green").save(kept_path)
        self._insert_image_record(
            db,
            image_id="img-2",
            status="stored",
            file_path=kept_path,
            created_at="2026-01-02T00:00:00+00:00",
            stored_at="2026-01-02T00:00:00+00:00",
        )

        default_gallery = client.get("/api/images").get_json()
        self.assertEqual([item["id"] for item in default_gallery["items"]], ["img-2"])

        deleted_gallery = client.get(
            "/api/images",
            query_string={"include_deleted": "1"},
        ).get_json()
        self.assertEqual([item["id"] for item in deleted_gallery["items"]], ["img-1"])

        with db._connect() as conn:
            conn.execute(
                """
                UPDATE images
                SET deleted_at = ?
                WHERE id = ?
                """,
                ("2025-12-20T00:00:00+00:00", "img-1"),
            )
            conn.commit()

        self.assertEqual(db.cleanup_deleted_images(retention_days=5), 1)
        self.assertIsNone(db.get_image("img-1"))
        self.assertFalse(file_path.exists())
        self.assertFalse(thumbnail_path.exists())

    def test_deleted_media_can_be_restored(self) -> None:
        runtime_dir = self._workspace_dir("deleted_media_restore")
        app = self._create_test_app(runtime_dir)
        client = app.test_client()
        db = app.extensions["db"]
        stored_dir = Path(app.config["STORED_DIR"])

        file_path = stored_dir / "restore-source.png"
        Image.new("RGB", (128, 128), color="orange").save(file_path)
        self._insert_image_record(
            db,
            image_id="img-restore",
            status="stored",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
        )

        self.assertEqual(client.delete("/api/images/img-restore").status_code, 200)
        self.assertEqual(db.get_image("img-restore")["status"], "deleted")

        restore_response = client.post("/api/images/img-restore/restore")
        self.assertEqual(restore_response.status_code, 200)
        restored_payload = restore_response.get_json()
        self.assertEqual(restored_payload["status"], "stored")
        self.assertIsNone(restored_payload["deleted_at"])
        self.assertTrue(file_path.exists())

        default_gallery = client.get("/api/images").get_json()
        self.assertEqual(
            [item["id"] for item in default_gallery["items"]],
            ["img-restore"],
        )
        deleted_gallery = client.get(
            "/api/images",
            query_string={"include_deleted": "1"},
        ).get_json()
        self.assertEqual(deleted_gallery["items"], [])

        second_restore_response = client.post("/api/images/img-restore/restore")
        self.assertEqual(second_restore_response.status_code, 409)

    def test_startup_permanently_deletes_expired_deleted_media(self) -> None:
        runtime_dir = self._workspace_dir("startup_deleted_media_cleanup")
        data_dir = runtime_dir / "data"
        stored_dir = data_dir / "stored"
        stored_dir.mkdir(parents=True, exist_ok=True)
        file_path = stored_dir / "expired.png"
        Image.new("RGB", (32, 32), color="red").save(file_path)

        db = AppDatabase(
            db_path=data_dir / "app.db",
            temp_dir=data_dir / "temp",
            stored_dir=stored_dir,
            backups_dir=data_dir / "backups",
            errors_dir=data_dir / "errors",
            data_dir=data_dir,
        )
        db.init_schema()
        self._insert_image_record(
            db,
            image_id="expired",
            status="deleted",
            file_path=file_path,
            created_at="2026-01-01T00:00:00+00:00",
            stored_at="2026-01-01T00:00:00+00:00",
            deleted_at="2025-12-20T00:00:00+00:00",
        )

        self._create_test_app(
            runtime_dir,
            DATA_DIR=str(data_dir),
            DB_PATH=str(data_dir / "app.db"),
        )

        self.assertFalse(file_path.exists())
        check_db = AppDatabase(
            db_path=data_dir / "app.db",
            temp_dir=data_dir / "temp",
            stored_dir=stored_dir,
            backups_dir=data_dir / "backups",
            errors_dir=data_dir / "errors",
            data_dir=data_dir,
        )
        check_db.init_schema()
        self.assertIsNone(check_db.get_image("expired"))
