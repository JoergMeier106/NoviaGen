from __future__ import annotations

from .shared import *

TEST_TEXT_TO_VIDEO_WORKFLOW_ID = "test-text-to-video-workflow"
TEST_IMAGE_TO_VIDEO_WORKFLOW_ID = "test-image-to-video-workflow"
TEST_LOOP_VIDEO_WORKFLOW_ID = "test-loop-video-workflow"


class ComfyVideoPipelineTests(BackendTestCase):
    def test_comfy_video_manager_finds_clip_text_nodes(self) -> None:
        workflow = {
            "1": {"class_type": "CLIPTextEncode", "_meta": {"title": "Positive Prompt"}},
            "2": {"class_type": "CLIPTextEncode", "_meta": {"title": "Negative Prompt"}},
            "3": {"class_type": "OtherNode", "_meta": {"title": "Ignored"}},
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_clip_text_nodes(workflow),
            ("1", "2"),
        )

    def test_comfy_video_manager_finds_clip_text_nodes_with_first_prompt_title(self) -> None:
        workflow = {
            "1": {"class_type": "CLIPTextEncode", "_meta": {"title": "first prompt"}},
            "2": {"class_type": "CLIPTextEncode", "_meta": {"title": "Negative Prompt"}},
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_clip_text_nodes(workflow),
            ("1", "2"),
        )

    def test_comfy_video_manager_finds_node_by_title(self) -> None:
        workflow = {
            "44": {"class_type": "StringConcatenate", "_meta": {"title": "Manual Prompter"}},
            "30": {"class_type": "PreviewAny", "_meta": {"title": "FINAL Prompt"}},
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_first_node_id_by_title(
                workflow,
                "Manual Prompter",
                class_type="StringConcatenate",
            ),
            "44",
        )

    def test_comfy_video_manager_finds_optional_node_by_title(self) -> None:
        workflow = {
            "40": {"class_type": "PreviewAny", "_meta": {"title": "SFX Prompt (Ollama)"}},
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_optional_node_id_by_title(
                workflow,
                "SFX Prompt (Ollama)",
                class_type="PreviewAny",
            ),
            "40",
        )
        self.assertIsNone(
            ComfyVideoWorkflowManager._find_optional_node_id_by_title(
                workflow,
                "FINAL Prompt",
                class_type="PreviewAny",
            )
        )

    def test_comfy_video_manager_applies_high_low_diffusion_model_overrides(self) -> None:
        workflow = {
            "917": {
                "class_type": "UNETLoader",
                "_meta": {"title": "Load Diffusion Model HIGH"},
                "inputs": {"unet_name": "workflow-high.safetensors"},
            },
            "918": {
                "class_type": "UNETLoader",
                "_meta": {"title": "Load Diffusion Model LOW"},
                "inputs": {"unet_name": "workflow-low.safetensors"},
            },
        }
        payload = VideoGenerationPayload(
            prompt="camera pans",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_TEXT_TO_VIDEO_WORKFLOW_ID,
            width=512,
            height=288,
            num_frames=25,
            fps=12,
            num_inference_steps=8,
            guidance_scale=2.0,
            high_diffusion_model_name="selected-high.safetensors",
            low_diffusion_model_name="selected-low.safetensors",
        )

        ComfyVideoWorkflowManager._apply_diffusion_model_overrides(workflow, payload)

        self.assertEqual(
            workflow["917"]["inputs"]["unet_name"],
            "selected-high.safetensors",
        )
        self.assertEqual(
            workflow["918"]["inputs"]["unet_name"],
            "selected-low.safetensors",
        )

    def test_comfy_video_manager_discovers_and_applies_workflow_lora_strengths(self) -> None:
        workflow = {
            "165": {
                "class_type": "LoraLoaderModelOnly",
                "_meta": {"title": "Load LoRA"},
                "inputs": {
                    "lora_name": "lightning-high.safetensors",
                    "strength_model": 1.0,
                },
            },
            "1292": {
                "class_type": "Power Lora Loader (rgthree)",
                "_meta": {"title": "1LORA LOW"},
                "inputs": {
                    "lora_1": {
                        "on": True,
                        "lora": "motion-low.safetensors",
                        "strength": 0.8,
                    },
                    "lora_2": {
                        "on": False,
                        "lora": "disabled-low.safetensors",
                        "strength": 0.6,
                    },
                },
            },
        }

        loras = ComfyVideoWorkflowManager.workflow_loras(workflow)

        self.assertEqual(
            [(item["id"], item["name"], item["default_strength"], item["enabled"]) for item in loras],
            [
                ("165:strength_model", "lightning-high.safetensors", 1.0, True),
                ("1292:lora_1", "motion-low.safetensors", 0.8, True),
                ("1292:lora_2", "disabled-low.safetensors", 0.6, False),
            ],
        )

        payload = VideoGenerationPayload(
            prompt="camera pans",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_TEXT_TO_VIDEO_WORKFLOW_ID,
            width=512,
            height=288,
            num_frames=25,
            fps=12,
            num_inference_steps=8,
            guidance_scale=2.0,
            workflow_loras=[
                VideoWorkflowLora(lora_id="165:strength_model", strength=0.35),
                VideoWorkflowLora(lora_id="1292:lora_1", strength=1.25),
            ],
        )

        ComfyVideoWorkflowManager._apply_workflow_lora_overrides(workflow, payload)

        self.assertEqual(workflow["165"]["inputs"]["strength_model"], 0.35)
        self.assertEqual(workflow["1292"]["inputs"]["lora_1"]["strength"], 1.25)
        self.assertEqual(workflow["1292"]["inputs"]["lora_2"]["strength"], 0.6)

    def test_comfy_video_manager_finds_text_output(self) -> None:
        job = {
            "outputs": {
                "39": {"text": ["intermediate caption"]},
                "30": {"ui": {"text": ["final generated prompt"]}},
            }
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_text_output(job, preferred_node_id="30"),
            "final generated prompt",
        )

    def test_comfy_video_manager_generates_i2v_prompt_from_workflow(self) -> None:
        runtime_dir = self._workspace_dir("synthetic_i2v_prompt_workflow")
        workflow_path = self._create_test_prompt_workflow_path(runtime_dir)
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            image_prompt_generator_workflow_path=workflow_path,
        )
        queued_workflows: list[dict[str, object]] = []

        manager._upload_image = lambda image_path: {"name": "uploaded-source.png"}

        def fake_queue_prompt(workflow, *, execution_plan=None):
            queued_workflows.append(json.loads(json.dumps(workflow)))
            return "prompt-1"

        manager._queue_prompt = fake_queue_prompt
        manager._wait_for_history = lambda *args, **kwargs: {
            "outputs": {
                "40": {"ui": {"text": ["generated prompt only"]}},
                "30": {"text": ["final generated prompt"]},
            }
        }

        result = manager.generate_i2v_prompt(
            source_image_path=Path("/tmp/source.png"),
            prompt="camera pans slowly",
        )

        queued_workflow = queued_workflows[0]
        manual_prompter_id = manager._find_first_node_id_by_title(
            queued_workflow,
            "Manual Prompter",
            class_type="StringConcatenate",
        )
        generated_prompt_id = manager._find_first_node_id_by_title(
            queued_workflow,
            "SFX Prompt (Ollama)",
            class_type="PreviewAny",
        )
        final_prompt_id = manager._find_first_node_id_by_title(
            queued_workflow,
            "FINAL Prompt",
            class_type="PreviewAny",
        )
        load_image_id = manager._find_first_node_id(queued_workflow, "LoadImage")

        self.assertEqual(result, "generated prompt only")
        self.assertEqual(queued_workflow[load_image_id]["inputs"]["image"], "uploaded-source.png")
        self.assertEqual(
            queued_workflow[manual_prompter_id]["inputs"]["string_a"],
            "camera pans slowly",
        )
        self.assertEqual(generated_prompt_id, "40")
        self.assertEqual(final_prompt_id, "30")

    def test_comfy_video_manager_tracks_ollama_models_for_active_workflow(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
        )

        workflow = {
            "10": {
                "class_type": "OllamaChat",
                "inputs": {"model": "test-workflow-model"},
            },
            "11": {
                "class_type": "PreviewAny",
                "inputs": {},
            },
        }

        manager._ensure_workflow_runtime("COMFY_I2V_WORKFLOW_PATH", workflow=workflow)

        self.assertEqual(manager._active_workflow_key, "COMFY_I2V_WORKFLOW_PATH")
        self.assertEqual(manager._active_ollama_models, {"test-workflow-model"})

    def test_comfy_video_manager_uses_saved_synthetic_t2v_output_fps_metadata(self) -> None:
        runtime_dir = self._workspace_dir("t2v_saved_fps_metadata")
        workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=workflow_path,
        )

        manager._queue_prompt = lambda workflow, *, execution_plan=None: "prompt-1"
        manager._wait_for_history = lambda *args, **kwargs: {
            "outputs": {
                "62": {
                    "gifs": [
                        {
                            "filename": "api_final.mp4",
                            "subfolder": "video",
                            "type": "output",
                        }
                    ]
                }
            }
        }
        manager._download_output_file = (
            lambda file_info, save_path: save_path.write_bytes(b"fake") or save_path
        )
        manager._probe_video_metadata = lambda path: {
            "width": 576,
            "height": 1024,
            "fps": 60,
            "num_frames": 49,
            "duration_seconds": 49 / 60,
        }

        payload = VideoGenerationPayload(
            prompt="camera pans slowly",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_TEXT_TO_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=False,
        )

        artifact = manager.generate_video(
            payload=payload,
            output_dir=runtime_dir,
        )

        self.assertEqual(artifact.fps, 60)
        self.assertEqual(artifact.num_frames, 49)
        self.assertAlmostEqual(artifact.duration_seconds or 0.0, 49 / 60, places=4)

    def test_comfy_video_manager_finds_supported_t2v_latent_node(self) -> None:
        workflow = {
            "10": {"class_type": "SomethingElse"},
            "11": {
                "class_type": "ExampleLatentVideo",
                "inputs": {"width": 512, "height": 512, "length": 16},
            },
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_t2v_latent_node_id(workflow),
            "11",
        )

    def test_comfy_video_manager_finds_first_history_output_file(self) -> None:
        job = {
            "outputs": {
                "preview": {"images": []},
                "final": {
                    "videos": [
                        {
                            "filename": "video/api_demo.mp4",
                            "subfolder": "video",
                            "type": "output",
                        }
                    ]
                },
            }
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_output(job),
            {
                "filename": "video/api_demo.mp4",
                "subfolder": "video",
                "type": "output",
            },
        )

    def test_comfy_video_manager_prefers_requested_history_output_node(self) -> None:
        job = {
            "outputs": {
                "1039": {
                    "videos": [
                        {
                            "filename": "video/api_base.mp4",
                            "subfolder": "video",
                            "type": "output",
                        }
                    ]
                },
                "1060": {
                    "videos": [
                        {
                            "filename": "video/api_final.mp4",
                            "subfolder": "video",
                            "type": "output",
                        }
                    ]
                },
            }
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_output(job, preferred_node_id="1060"),
            {
                "filename": "video/api_final.mp4",
                "subfolder": "video",
                "type": "output",
            },
        )

    def test_comfy_video_manager_prefers_requested_grouped_history_output_node(self) -> None:
        job = {
            "outputs": {
                "1252:1039": {
                    "videos": [
                        {
                            "filename": "video/api_base.mp4",
                            "subfolder": "video",
                            "type": "output",
                        }
                    ]
                },
                "1252:1060": {
                    "videos": [
                        {
                            "filename": "video/api_final.mp4",
                            "subfolder": "video",
                            "type": "output",
                        }
                    ]
                },
            }
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_output(job, preferred_node_id="1060"),
            {
                "filename": "video/api_final.mp4",
                "subfolder": "video",
                "type": "output",
            },
        )

    def test_comfy_video_manager_uses_download_extension_for_output_path(self) -> None:
        output_path = ComfyVideoWorkflowManager._output_path_for_download(
            Path("/tmp/output"),
            "video-id",
            {"filename": "nested/final.webm"},
        )

        self.assertEqual(output_path, Path("/tmp/output/video-id.webm"))

    def test_comfy_video_manager_creates_default_poster_with_clamped_dimensions(self) -> None:
        runtime_dir = self._workspace_dir("default_video_poster")
        poster_path = ComfyVideoWorkflowManager._create_default_video_poster(
            output_dir=runtime_dir,
            image_id="poster-demo",
            width=4096,
            height=32,
        )

        self.assertTrue(poster_path.exists())
        with Image.open(poster_path) as poster:
            self.assertEqual(poster.mode, "RGB")
            self.assertEqual(poster.size, (1280, 180))

    def test_comfy_video_manager_defaults_unknown_output_mimetype(self) -> None:
        self.assertEqual(
            ComfyVideoWorkflowManager._mime_type_for_path(Path("/tmp/output/result.unknownext")),
            "application/octet-stream",
        )

    def test_comfy_video_manager_random_seed_stays_within_comfy_safe_range(self) -> None:
        for _ in range(64):
            seed = ComfyVideoWorkflowManager._random_seed_value()
            self.assertGreaterEqual(seed, 1)
            self.assertLessEqual(seed, 1_125_899_906_842_624)

    def test_reuses_matching_lora_configuration_without_reloading(self) -> None:
        catalog = AssetCatalog(
            models=[],
            loras=[
                AssetEntry(
                    id="demo-lora",
                    label="Demo LoRA",
                    path="/fixtures/loras/demo-lora.safetensors",
                    default_strength=0.75,
                )
            ],
        )
        generator = DiffusersImageGenerator(catalog)
        pipe = FakePipeline()
        selected_loras = [SelectedLora(lora_id="demo-lora", strength=0.9)]

        generator._configure_pipeline(pipe, selected_loras)
        generator._configure_pipeline(pipe, selected_loras)

        self.assertEqual(pipe.unload_calls, 0)
        self.assertEqual(pipe.loaded_loras, [("/fixtures/loras/demo-lora.safetensors", 0.9)])

    def test_upscale_mode_releases_text_pipeline_on_mid_vram_gpu(self) -> None:
        catalog = AssetCatalog(
            models=[
                AssetEntry(id="model-a", label="Model A", path="/fixtures/models/model-a.safetensors")
            ],
            loras=[],
        )
        generator = DiffusersImageGenerator(catalog)
        generator._torch = FakeTorch()
        generator._keep_both_pipeline_modes = False

        text_pipe = FakePipeline()
        generator._text_pipelines = {"/fixtures/models/model-a.safetensors": text_pipe}

        generator._evict_opposite_pipeline_mode(
            "/fixtures/models/model-a.safetensors",
            keep_mode="upscale",
        )

        self.assertEqual(generator._text_pipelines, {})
        self.assertEqual(text_pipe.to_calls, ["cpu"])
        self.assertEqual(generator._torch.cuda.empty_cache_calls, 1)
        self.assertEqual(generator._torch.cuda.ipc_collect_calls, 1)
        self.assertEqual(generator._torch.cuda.synchronize_calls, 1)

    def test_high_vram_still_uses_single_local_pipeline_mode(self) -> None:
        generator = DiffusersImageGenerator(AssetCatalog(models=[], loras=[]))

        class DeviceProperties:
            name = "Demo GPU"
            total_memory = 24 * 1024**3

        class MatmulConfig:
            allow_tf32 = False

        class CudnnConfig:
            allow_tf32 = False
            benchmark = False

        class FakeCudaBackend(FakeCuda):
            @staticmethod
            def is_available() -> bool:
                return True

            @staticmethod
            def get_device_properties(_index: int) -> DeviceProperties:
                return DeviceProperties()

        class TorchBackends:
            cuda = type("CudaBackends", (), {"matmul": MatmulConfig()})()
            cudnn = CudnnConfig()

        class TorchStub:
            cuda = FakeCudaBackend()
            backends = TorchBackends()

            @staticmethod
            def set_float32_matmul_precision(_value: str) -> None:
                return None

        generator._torch = TorchStub()

        generator._configure_torch_backends()

        self.assertFalse(generator._keep_both_pipeline_modes)

    def test_generate_from_image_source_is_normalized_to_default_dimensions(self) -> None:
        source_image = Image.new("RGB", (2200, 900), color="white")

        prepared_landscape = DiffusersImageGenerator._prepare_generate_from_image_source(
            source_image,
            "landscape",
        )
        prepared_portrait = DiffusersImageGenerator._prepare_generate_from_image_source(
            source_image,
            "portrait",
        )

        self.assertEqual(prepared_landscape.size, (1024, 576))
        self.assertEqual(prepared_portrait.size, (576, 1024))

    def test_comfy_video_manager_finds_vhs_output_node(self) -> None:
        workflow = {
            "10": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"save_output": False, "filename_prefix": "temp"},
                "_meta": {"title": "Intermediate"},
            },
            "11": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"save_output": True, "filename_prefix": "final"},
                "_meta": {"title": "Output"},
            },
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_save_node_id(workflow),
            "11",
        )

    def test_comfy_video_manager_prefers_interpolated_vhs_output_node(self) -> None:
        workflow = {
            "80": {
                "class_type": "SaveVideo",
                "inputs": {"video": ["171", 0], "filename_prefix": "video/ComfyUI"},
                "_meta": {"title": "Save Video"},
            },
            "1039": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"save_output": True, "frame_rate": 16, "images": ["1249", 0]},
                "_meta": {"title": "16FPS"},
            },
            "1059": {
                "class_type": "FL_RIFE",
                "inputs": {"multiplier": 4, "images": ["1249", 0]},
                "_meta": {"title": "FL RIFE Frame Interpolation"},
            },
            "1060": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"save_output": True, "frame_rate": 64, "images": ["1059", 0]},
                "_meta": {"title": "60FPS"},
            },
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_save_node_id(workflow),
            "1060",
        )

    def test_synthetic_t2v_workflow_reports_interpolated_output_fps(self) -> None:
        runtime_dir = self._workspace_dir("synthetic_t2v_output_fps")
        workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=workflow_path,
            image_to_video_loop_workflow_path=workflow_path,
            video_upscaler_workflow_path=workflow_path,
            video_to_audio_workflow_path=workflow_path,
            image_prompt_generator_workflow_path=workflow_path,
            text_to_video_workflow_path=workflow_path,
        )

        self.assertEqual(
            manager.expected_output_fps(image_to_video=False, requested_fps=16),
            60,
        )

    def test_comfy_video_manager_prefers_interpolated_loop_workflow_output_node(self) -> None:
        workflow = {
            "398": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"save_output": True, "frame_rate": 16, "images": ["400", 0]},
                "_meta": {"title": "Output"},
            },
            "527": {
                "class_type": "RIFE VFI",
                "inputs": {"multiplier": ["538", 0], "frames": ["529", 0]},
                "_meta": {"title": "Interpolated RIFE VFI"},
            },
            "528": {
                "class_type": "ImageFromBatch+",
                "inputs": {"image": ["527", 0]},
                "_meta": {"title": "Image From Batch"},
            },
            "533": {
                "class_type": "easy batchAnything",
                "inputs": {"any_1": ["536", 0], "any_2": ["528", 0]},
                "_meta": {"title": "Batch Any"},
            },
            "538": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 2, "Xf": 2, "isfloatX": 0},
                "_meta": {"title": "Interpolation"},
            },
            "541": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"save_output": True, "frame_rate": 16, "images": ["533", 0]},
                "_meta": {"title": "Interpolated FPS"},
            },
        }

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_save_node_id(workflow),
            "541",
        )

    def test_comfy_video_upscaler_device_strategy_defaults_to_keep_loaded(self) -> None:
        self.assertEqual(
            ComfyVideoWorkflowManager._normalize_video_upscaler_device_strategy(None),
            "keep_loaded",
        )
        self.assertEqual(
            ComfyVideoWorkflowManager._normalize_video_upscaler_device_strategy("cpu_only"),
            "cpu_only",
        )

    def test_comfy_video_manager_updates_loop_workflow_sliders(self) -> None:
        workflow = {
            "1": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 8, "Xf": 8, "isfloatX": 0},
                "_meta": {"title": "Steps"},
            },
            "2": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 1, "Xf": 1, "isfloatX": 1},
                "_meta": {"title": "CFG"},
            },
            "3": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 3, "Xf": 3.5, "isfloatX": 1},
                "_meta": {"title": "Duration"},
            },
            "4": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 16, "Xf": 16, "isfloatX": 1},
                "_meta": {"title": "Frame rate"},
            },
            "5": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 1024, "Xf": 1024, "isfloatX": 0},
                "_meta": {"title": "Height"},
            },
        }
        payload = VideoGenerationPayload(
            prompt="loop it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_IMAGE_TO_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=True,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(workflow["1"]["inputs"]["Xi"], 12)
        self.assertEqual(workflow["1"]["inputs"]["Xf"], 12)
        self.assertEqual(workflow["2"]["inputs"]["Xi"], 2.5)
        self.assertEqual(workflow["2"]["inputs"]["Xf"], 2.5)
        self.assertEqual(workflow["3"]["inputs"]["Xi"], 49 / 16)
        self.assertEqual(workflow["3"]["inputs"]["Xf"], 49 / 16)
        self.assertEqual(workflow["4"]["inputs"]["Xi"], 16.0)
        self.assertEqual(workflow["4"]["inputs"]["Xf"], 16.0)
        self.assertEqual(workflow["5"]["inputs"]["Xi"], 1024)
        self.assertEqual(workflow["5"]["inputs"]["Xf"], 1024)

    def test_comfy_video_manager_updates_new_i2v_workflow_controls(self) -> None:
        workflow = {
            "607": {
                "class_type": "FindPerfectResolution",
                "inputs": {"desired_width": 720, "desired_height": 720},
                "_meta": {"title": "Find Perfect Resolution"},
            },
            "608": {
                "class_type": "INTConstant",
                "inputs": {"value": 81},
                "_meta": {"title": "lenght"},
            },
            "1238": {
                "class_type": "KSamplerAdvanced",
                "inputs": {"steps": 4, "cfg": 1, "start_at_step": 0, "end_at_step": 2},
                "_meta": {"title": "1-KSampler (Advanced) HIGH"},
            },
            "1239": {
                "class_type": "KSamplerAdvanced",
                "inputs": {"steps": 4, "cfg": 1, "start_at_step": 2, "end_at_step": 100},
                "_meta": {"title": "2-KSampler (Advanced) LOW"},
            },
            "1039": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"frame_rate": 16, "save_output": True, "images": ["1249", 0]},
                "_meta": {"title": "16FPS"},
            },
            "1059": {
                "class_type": "FL_RIFE",
                "inputs": {"multiplier": 4, "images": ["1249", 0]},
                "_meta": {"title": "FL RIFE Frame Interpolation"},
            },
            "1060": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"frame_rate": 64, "save_output": True, "images": ["1059", 0]},
                "_meta": {"title": "60FPS"},
            },
        }
        payload = VideoGenerationPayload(
            prompt="animate it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_IMAGE_TO_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=False,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(workflow["607"]["inputs"]["desired_width"], 576)
        self.assertEqual(workflow["607"]["inputs"]["desired_height"], 1024)
        self.assertEqual(workflow["608"]["inputs"]["value"], 49)
        self.assertEqual(workflow["1238"]["inputs"]["steps"], 4)
        self.assertEqual(workflow["1239"]["inputs"]["steps"], 4)
        self.assertEqual(workflow["1238"]["inputs"]["cfg"], 1)
        self.assertEqual(workflow["1239"]["inputs"]["cfg"], 1)
        self.assertEqual(workflow["1238"]["inputs"]["start_at_step"], 0)
        self.assertEqual(workflow["1238"]["inputs"]["end_at_step"], 2)
        self.assertEqual(workflow["1239"]["inputs"]["start_at_step"], 2)
        self.assertEqual(workflow["1239"]["inputs"]["end_at_step"], 100)
        self.assertEqual(workflow["1039"]["inputs"]["frame_rate"], 16)
        self.assertFalse(workflow["1039"]["inputs"]["save_output"])
        self.assertEqual(workflow["1060"]["inputs"]["frame_rate"], 60)
        self.assertTrue(workflow["1060"]["inputs"]["save_output"])

    def test_comfy_video_manager_prefers_fps_hint_for_interpolated_i2v_output(self) -> None:
        workflow = {
            "1039": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"frame_rate": 16, "save_output": True, "images": ["1249", 0]},
                "_meta": {"title": "16FPS"},
            },
            "1059": {
                "class_type": "FL_RIFE",
                "inputs": {"multiplier": 4, "images": ["1249", 0]},
                "_meta": {"title": "FL RIFE Frame Interpolation"},
            },
            "1060": {
                "class_type": "VHS_VideoCombine",
                "inputs": {
                    "frame_rate": 64,
                    "save_output": True,
                    "filename_prefix": "final-output-60-fps",
                    "images": ["1059", 0],
                },
                "_meta": {"title": "60FPS"},
            },
        }
        payload = VideoGenerationPayload(
            prompt="animate it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_IMAGE_TO_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=False,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(
            ComfyVideoWorkflowManager._expected_saved_video_fps(
                workflow,
                "1060",
                fallback_fps=payload.fps,
            ),
            60,
        )
        self.assertEqual(workflow["1060"]["inputs"]["frame_rate"], 60)

    def test_comfy_video_manager_updates_interpolated_loop_workflow_outputs(self) -> None:
        workflow = {
            "398": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"frame_rate": 16, "save_output": True, "images": ["400", 0]},
                "_meta": {"title": "Output"},
            },
            "527": {
                "class_type": "RIFE VFI",
                "inputs": {"multiplier": ["538", 0], "frames": ["529", 0]},
                "_meta": {"title": "Interpolated RIFE VFI"},
            },
            "528": {
                "class_type": "ImageFromBatch+",
                "inputs": {"image": ["527", 0]},
                "_meta": {"title": "Image From Batch"},
            },
            "533": {
                "class_type": "easy batchAnything",
                "inputs": {"any_1": ["536", 0], "any_2": ["528", 0]},
                "_meta": {"title": "Batch Any"},
            },
            "538": {
                "class_type": "mxSlider",
                "inputs": {"Xi": 2, "Xf": 2, "isfloatX": 0},
                "_meta": {"title": "Interpolation"},
            },
            "541": {
                "class_type": "VHS_VideoCombine",
                "inputs": {"frame_rate": 16, "save_output": True, "images": ["533", 0]},
                "_meta": {"title": "Interpolated FPS"},
            },
        }
        payload = VideoGenerationPayload(
            prompt="loop it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_LOOP_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=True,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(workflow["398"]["inputs"]["frame_rate"], 16)
        self.assertFalse(workflow["398"]["inputs"]["save_output"])
        self.assertEqual(workflow["541"]["inputs"]["frame_rate"], 32)
        self.assertTrue(workflow["541"]["inputs"]["save_output"])

    def test_comfy_video_manager_applies_controls_to_synthetic_i2v_workflow(self) -> None:
        runtime_dir = self._workspace_dir("synthetic_i2v_controls")
        workflow_path = self._create_test_image_to_video_workflow_path(runtime_dir)
        workflow = ComfyVideoWorkflowManager._load_workflow(workflow_path, "TEST_WORKFLOW_PATH")
        payload = VideoGenerationPayload(
            prompt="animate it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_IMAGE_TO_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=False,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(
            ComfyVideoWorkflowManager._find_clip_text_nodes(workflow),
            ("10", "11"),
        )
        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_save_node_id(workflow),
            "19",
        )
        self.assertEqual(workflow["12"]["inputs"]["desired_width"], 576)
        self.assertEqual(workflow["12"]["inputs"]["desired_height"], 1024)
        self.assertEqual(workflow["13"]["inputs"]["value"], 49)
        self.assertFalse(workflow["17"]["inputs"]["save_output"])
        self.assertTrue(workflow["19"]["inputs"]["save_output"])

    def test_comfy_video_manager_applies_controls_to_synthetic_t2v_workflow(self) -> None:
        runtime_dir = self._workspace_dir("synthetic_t2v_controls")
        workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        workflow = ComfyVideoWorkflowManager._load_workflow(workflow_path, "TEST_WORKFLOW_PATH")
        payload = VideoGenerationPayload(
            prompt="animate it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_TEXT_TO_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=False,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_save_node_id(workflow),
            "62",
        )
        self.assertEqual(workflow["20"]["inputs"]["width"], 576)
        self.assertEqual(workflow["20"]["inputs"]["height"], 1024)
        self.assertEqual(workflow["62"]["inputs"]["frame_rate"], 60)
        self.assertTrue(workflow["62"]["inputs"]["save_output"])

    def test_comfy_video_manager_prefers_interpolated_output_in_synthetic_loop_workflow(self) -> None:
        runtime_dir = self._workspace_dir("synthetic_loop_output")
        workflow_path = self._create_test_image_to_video_workflow_path(runtime_dir)
        workflow = ComfyVideoWorkflowManager._load_workflow(workflow_path, "TEST_WORKFLOW_PATH")
        payload = VideoGenerationPayload(
            prompt="loop it",
            default_positive_prompt="best quality",
            default_negative_prompt="bad quality",
            video_model_id=TEST_LOOP_VIDEO_WORKFLOW_ID,
            width=576,
            height=1024,
            num_frames=49,
            fps=16,
            num_inference_steps=12,
            guidance_scale=2.5,
            loop_video=True,
        )

        ComfyVideoWorkflowManager._apply_common_generation_controls(workflow, payload)

        self.assertEqual(
            ComfyVideoWorkflowManager._find_video_save_node_id(workflow),
            "19",
        )
        self.assertFalse(workflow["17"]["inputs"]["save_output"])
        self.assertEqual(workflow["19"]["inputs"]["frame_rate"], 60)
        self.assertTrue(workflow["19"]["inputs"]["save_output"])

    def test_comfy_video_manager_normalizes_replacement_i2v_helper_nodes(self) -> None:
        runtime_dir = self._workspace_dir("replacement_i2v_normalization")
        source_image_path = runtime_dir / "source.png"
        Image.new("RGB", (1024, 1024), color="white").save(source_image_path)

        workflow = {
            "97": {
                "class_type": "LoadImage",
                "inputs": {"image": "source.png"},
                "_meta": {"title": "Load Image"},
            },
            "1291": {
                "class_type": "ImageScaleBy",
                "inputs": {"scale_by": 0.5, "image": ["97", 0]},
                "_meta": {"title": "Upscale Image By"},
            },
            "604": {
                "class_type": "FloatConstant",
                "inputs": {"value": 1.15},
                "_meta": {"title": "motion amplitude"},
            },
            "606": {
                "class_type": "FloatConstant",
                "inputs": {"value": 0.05},
                "_meta": {"title": "color protect strength"},
            },
            "607": {
                "class_type": "FindPerfectResolution",
                "inputs": {
                    "desired_width": 576,
                    "desired_height": 1024,
                    "divisible_by": 16,
                    "image": ["1291", 0],
                },
                "_meta": {"title": "Find Perfect Resolution"},
            },
            "608": {
                "class_type": "INTConstant",
                "inputs": {"value": 49},
                "_meta": {"title": "lenght"},
            },
            "1250": {
                "class_type": "Seed (rgthree)",
                "inputs": {"seed": 123456},
                "_meta": {"title": "Seed"},
            },
            "1248": {
                "class_type": "PainterI2VAdvanced",
                "inputs": {
                    "width": ["607", 0],
                    "height": ["607", 1],
                    "length": ["608", 0],
                    "motion_amplitude": ["604", 0],
                    "correct_strength": ["606", 0],
                    "start_image": ["1291", 0],
                },
                "_meta": {"title": "PainterI2VAdvanced"},
            },
            "1238": {
                "class_type": "KSamplerAdvanced",
                "inputs": {"noise_seed": ["1250", 0]},
                "_meta": {"title": "1-KSampler (Advanced) HIGH"},
            },
        }

        ComfyVideoWorkflowManager._normalize_non_loop_i2v_workflow(
            workflow,
            source_image_path=source_image_path,
        )

        self.assertNotIn("604", workflow)
        self.assertNotIn("606", workflow)
        self.assertNotIn("607", workflow)
        self.assertNotIn("608", workflow)
        self.assertNotIn("1250", workflow)
        self.assertEqual(workflow["1248"]["inputs"]["width"], 768)
        self.assertEqual(workflow["1248"]["inputs"]["height"], 768)
        self.assertEqual(workflow["1248"]["inputs"]["length"], 49)
        self.assertEqual(workflow["1248"]["inputs"]["motion_amplitude"], 1.15)
        self.assertEqual(workflow["1248"]["inputs"]["correct_strength"], 0.05)
        self.assertEqual(workflow["1238"]["inputs"]["noise_seed"], 123456)

    def test_comfy_video_manager_reuses_same_workflow_and_unloads_on_switch(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )
        free_memory_calls: list[str] = []

        def fake_free_memory() -> None:
            free_memory_calls.append("free")

        manager.free_memory = fake_free_memory

        manager._ensure_workflow_runtime("COMFY_I2V_WORKFLOW_PATH")
        manager._ensure_workflow_runtime("COMFY_I2V_WORKFLOW_PATH")
        manager._ensure_workflow_runtime("video_to_audio")
        manager._ensure_workflow_runtime("COMFY_VIDEO_UPSCALER_WORKFLOW_PATH")
        manager.release_active_workflow()

        self.assertEqual(free_memory_calls, ["free", "free", "free"])
        self.assertIsNone(manager._active_workflow_key)

    def test_comfy_video_manager_unloads_embedded_ollama_models_on_workflow_switch(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
            ollama_url="http://127.0.0.1:11434",
        )
        free_memory_calls: list[str] = []
        ollama_unload_payloads: list[dict[str, object]] = []
        workflow_a = {
            "10": {
                "class_type": "OllamaChat",
                "inputs": {"model": "workflow-a-model"},
            }
        }
        workflow_b = {
            "20": {
                "class_type": "OllamaChat",
                "inputs": {"model": "workflow-b-model"},
            }
        }

        def fake_free_memory() -> None:
            free_memory_calls.append("free")

        class FakeResponse:
            def raise_for_status(self) -> None:
                return None

        def fake_post(url: str, json=None, timeout=None):
            ollama_unload_payloads.append(dict(json or {}))
            return FakeResponse()

        manager.free_memory = fake_free_memory

        with patch("app.comfy.workflow_manager.requests.post", side_effect=fake_post):
            manager._ensure_workflow_runtime("workflow-a", workflow=workflow_a)
            manager._ensure_workflow_runtime("workflow-a", workflow=workflow_a)
            manager._ensure_workflow_runtime("workflow-b", workflow=workflow_b)
            manager.release_active_workflow()

        self.assertEqual(free_memory_calls, ["free", "free"])
        self.assertEqual(
            [payload["model"] for payload in ollama_unload_payloads],
            ["workflow-a-model", "workflow-b-model"],
        )
        self.assertTrue(all(payload["keep_alive"] == 0 for payload in ollama_unload_payloads))
        self.assertIsNone(manager._active_workflow_key)
        self.assertEqual(manager._active_ollama_models, set())

    def test_comfy_video_manager_unloads_stale_ollama_models_when_same_workflow_changes(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
            ollama_url="http://127.0.0.1:11434",
        )
        first_workflow = {
            "10": {
                "class_type": "OllamaChat",
                "inputs": {"model": "workflow-a-model"},
            }
        }
        second_workflow = {
            "20": {
                "class_type": "OllamaChat",
                "inputs": {"model": "workflow-b-model"},
            }
        }
        ollama_unload_payloads: list[dict[str, object]] = []

        class FakeResponse:
            def raise_for_status(self) -> None:
                return None

        def fake_post(url: str, json=None, timeout=None):
            ollama_unload_payloads.append(dict(json or {}))
            return FakeResponse()

        with patch("app.comfy.workflow_manager.requests.post", side_effect=fake_post):
            manager._ensure_workflow_runtime("prompt-workflow", workflow=first_workflow)
            manager._ensure_workflow_runtime("prompt-workflow", workflow=second_workflow)

        self.assertEqual(
            [payload["model"] for payload in ollama_unload_payloads],
            ["workflow-a-model"],
        )
        self.assertEqual(manager._active_ollama_models, {"workflow-b-model"})

    def test_comfy_video_manager_randomizes_literal_seed_inputs(self) -> None:
        workflow = {
            "1": {
                "inputs": {
                    "noise_seed": 123,
                    "seed": 456,
                    "linked_seed": ["9", 0],
                    "nested": {
                        "random_seed": 789,
                        "switch_seed": -1,
                    },
                },
                "class_type": "KSamplerAdvanced",
            },
            "2": {
                "inputs": {
                    "seed": ["1", 0],
                    "enabled": True,
                },
                "class_type": "SomeNode",
            },
        }

        with patch("app.comfy.client.secrets.randbelow", side_effect=[1110, 2221, 3332, 4443]):
            ComfyVideoWorkflowManager._randomize_workflow_seeds(workflow)

        self.assertEqual(workflow["1"]["inputs"]["noise_seed"], 1111)
        self.assertEqual(workflow["1"]["inputs"]["seed"], 2222)
        self.assertEqual(workflow["1"]["inputs"]["nested"]["random_seed"], 3333)
        self.assertEqual(workflow["1"]["inputs"]["nested"]["switch_seed"], 4444)
        self.assertEqual(workflow["1"]["inputs"]["linked_seed"], ["9", 0])
        self.assertEqual(workflow["2"]["inputs"]["seed"], ["1", 0])
        self.assertTrue(workflow["2"]["inputs"]["enabled"])

    def test_comfy_video_manager_waits_for_remote_cancel_to_finish(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )
        with manager._state_lock:
            manager._active_prompt_id = "prompt-1"
            manager._client_id = "client-1"

        get_responses = {
            "http://127.0.0.1:8188/history/prompt-1": [
                {"prompt-1": {"status": {"status_str": "running"}}},
                {},
            ],
            "http://127.0.0.1:8188/queue": [
                {"queue_running": [["task", "prompt-1"]], "queue_pending": []},
                {"queue_running": [["task", "prompt-1"]], "queue_pending": []},
                {"queue_running": [], "queue_pending": []},
            ],
            "http://127.0.0.1:8188/progress": [
                {"prompt_id": "prompt-1", "value": 1, "max": 8},
                {"prompt_id": ""},
                {"prompt_id": ""},
            ],
        }
        post_calls: list[tuple[str, dict | None]] = []

        class FakeResponse:
            def __init__(self, payload) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self):
                return self._payload

        def fake_get(url, *args, **kwargs):
            responses = get_responses[url]
            if len(responses) > 1:
                payload = responses.pop(0)
            else:
                payload = responses[0]
            return FakeResponse(payload)

        def fake_post(url, *args, **kwargs):
            post_calls.append((url, kwargs.get("json")))
            return FakeResponse({})

        with patch("app.comfy.workflow_manager.requests.get", side_effect=fake_get), patch(
            "app.comfy.workflow_manager.requests.post",
            side_effect=fake_post,
        ):
            with self.assertRaises(ComfyPromptCancelledError):
                manager._wait_for_history(
                    "prompt-1",
                    cancel_requested=lambda: True,
                    timeout_seconds=1,
                    poll_seconds=0.01,
                )

        self.assertIn(
            ("http://127.0.0.1:8188/interrupt", {}),
            post_calls,
        )

    def test_comfy_video_manager_retries_transient_history_connection_errors(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )

        history_responses: list[object] = [
            requests.ConnectionError(
                "Max retries exceeded with url: /history/prompt-1 "
                "(Caused by NewConnectionError)"
            ),
            {"prompt-1": {"status": {"status_str": "running"}}},
            {"prompt-1": {"outputs": {"video": [{"filename": "clip.mp4"}]}}},
        ]

        class FakeResponse:
            def __init__(self, payload) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self):
                return self._payload

        def fake_get(url, *args, **kwargs):
            if url == "http://127.0.0.1:8188/history/prompt-1":
                payload = history_responses.pop(0)
                if isinstance(payload, Exception):
                    raise payload
                return FakeResponse(payload)
            if url == "http://127.0.0.1:8188/queue":
                return FakeResponse(
                    {"queue_running": [["task", "prompt-1"]], "queue_pending": []}
                )
            if url == "http://127.0.0.1:8188/progress":
                return FakeResponse({"prompt_id": "prompt-1", "value": 1, "max": 8})
            self.fail(f"Unexpected URL requested: {url}")

        with patch("app.comfy.workflow_manager.requests.get", side_effect=fake_get):
            job = manager._wait_for_history(
                "prompt-1",
                timeout_seconds=1,
                poll_seconds=0.01,
            )

        self.assertEqual(
            job["outputs"]["video"][0]["filename"],
            "clip.mp4",
        )

    def test_comfy_video_manager_waits_for_real_video_output(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )

        history_responses: list[dict[str, object]] = [
            {"prompt-1": {"status": {"status_str": "running"}, "outputs": {"531": {"value": [1]}}}},
            {
                "prompt-1": {
                    "status": {"status_str": "success"},
                    "outputs": {
                        "398": {
                            "gifs": [
                                {
                                    "filename": "video/final.mp4",
                                    "subfolder": "video",
                                    "type": "output",
                                }
                            ]
                        }
                    },
                }
            },
        ]

        class FakeResponse:
            def __init__(self, payload) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self):
                return self._payload

        def fake_get(url, *args, **kwargs):
            if url == "http://127.0.0.1:8188/history/prompt-1":
                payload = history_responses.pop(0)
                return FakeResponse(payload)
            if url == "http://127.0.0.1:8188/progress":
                return FakeResponse({"prompt_id": "prompt-1", "value": 4, "max": 8})
            if url == "http://127.0.0.1:8188/queue":
                return FakeResponse(
                    {"queue_running": [["task", "prompt-1"]], "queue_pending": []}
                )
            self.fail(f"Unexpected URL requested: {url}")

        with patch("app.comfy.workflow_manager.requests.get", side_effect=fake_get):
            job = manager._wait_for_history(
                "prompt-1",
                expected_output="video",
                timeout_seconds=1,
                poll_seconds=0.01,
            )

        self.assertEqual(
            job["outputs"]["398"]["gifs"][0]["filename"],
            "video/final.mp4",
        )

    def test_comfy_video_manager_waits_for_real_text_output(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )

        history_responses: list[dict[str, object]] = [
            {"prompt-1": {"status": {"status_str": "running"}, "outputs": {"531": {"value": [1]}}}},
            {
                "prompt-1": {
                    "status": {"status_str": "success"},
                    "outputs": {"30": {"ui": {"text": ["final generated prompt"]}}},
                }
            },
        ]

        class FakeResponse:
            def __init__(self, payload) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self):
                return self._payload

        def fake_get(url, *args, **kwargs):
            if url == "http://127.0.0.1:8188/history/prompt-1":
                payload = history_responses.pop(0)
                return FakeResponse(payload)
            if url == "http://127.0.0.1:8188/progress":
                return FakeResponse({"prompt_id": "prompt-1", "value": 2, "max": 4})
            if url == "http://127.0.0.1:8188/queue":
                return FakeResponse(
                    {"queue_running": [["task", "prompt-1"]], "queue_pending": []}
                )
            self.fail(f"Unexpected URL requested: {url}")

        with patch("app.comfy.workflow_manager.requests.get", side_effect=fake_get):
            job = manager._wait_for_history(
                "prompt-1",
                expected_output="text",
                timeout_seconds=1,
                poll_seconds=0.01,
            )

        self.assertEqual(
            ComfyVideoWorkflowManager._find_text_output(job, preferred_node_id="30"),
            "final generated prompt",
        )

    def test_comfy_video_manager_builds_two_pass_execution_plan_from_synthetic_workflow(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )
        runtime_dir = self._workspace_dir("synthetic_execution_plan")
        workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        workflow = ComfyVideoWorkflowManager._load_workflow(workflow_path, "TEST_WORKFLOW_PATH")

        execution_plan = manager._build_execution_plan(
            workflow,
            workflow_kind="t2v",
            preparing_progress=0.04,
            queue_progress=0.1,
            active_start_progress=0.14,
            active_end_progress=0.9,
            fallback_running_label="Generating frames",
        )

        sampler_labels = [
            label
            for label in execution_plan.node_labels.values()
            if label.startswith("Generating frames")
        ]
        self.assertEqual(sorted(sampler_labels), ["Generating frames 1/2", "Generating frames 2/2"])
        self.assertIn("Decoding frames", execution_plan.node_labels.values())
        self.assertIn("Encoding video", execution_plan.node_labels.values())
        self.assertIn("Saving video", execution_plan.node_labels.values())

    def test_comfy_video_manager_progress_snapshot_tracks_synthetic_execution_phases(self) -> None:
        manager = ComfyVideoWorkflowManager(
            comfy_url="http://127.0.0.1:8188",
            image_to_video_workflow_path=None,
            image_to_video_loop_workflow_path=None,
            video_upscaler_workflow_path=None,
            video_to_audio_workflow_path=None,
            text_to_video_workflow_path=None,
        )
        runtime_dir = self._workspace_dir("synthetic_progress_plan")
        workflow_path = self._create_test_text_to_video_workflow_path(runtime_dir)
        workflow = ComfyVideoWorkflowManager._load_workflow(workflow_path, "TEST_WORKFLOW_PATH")
        execution_plan = manager._build_execution_plan(
            workflow,
            workflow_kind="t2v",
            preparing_progress=0.04,
            queue_progress=0.1,
            active_start_progress=0.14,
            active_end_progress=0.9,
            fallback_running_label="Generating frames",
        )

        node_by_label = {
            label: node_id
            for node_id, label in execution_plan.node_labels.items()
        }
        manager._execution_plan_by_prompt_id["prompt-1"] = execution_plan
        manager._last_progress_by_prompt_id["prompt-1"] = execution_plan.queue_progress

        progress_payloads = [
            {"prompt_id": "prompt-1", "node": node_by_label["Generating frames 1/2"], "value": 4, "max": 10},
            {"prompt_id": "prompt-1", "node": node_by_label["Generating frames 2/2"], "value": 1, "max": 10},
            {"prompt_id": "prompt-1", "node": node_by_label["Decoding frames"], "value": 1, "max": 2},
            {"prompt_id": "prompt-1", "node": node_by_label["Encoding video"], "value": 1, "max": 2},
            {"prompt_id": "prompt-1", "node": node_by_label["Saving video"], "value": 1, "max": 2},
            {"prompt_id": "prompt-1", "node": "mystery-node", "value": 0, "max": 10},
        ]

        class FakeResponse:
            def __init__(self, payload) -> None:
                self._payload = payload

            def raise_for_status(self) -> None:
                return None

            def json(self):
                return self._payload

        def fake_get(url, *args, **kwargs):
            if url == "http://127.0.0.1:8188/queue":
                return FakeResponse(
                    {"queue_running": [["task", "prompt-1"]], "queue_pending": []}
                )
            if url == "http://127.0.0.1:8188/progress":
                return FakeResponse(progress_payloads.pop(0))
            self.fail(f"Unexpected URL requested: {url}")

        snapshots: list[tuple[float, str] | None] = []
        with patch("app.comfy.workflow_manager.requests.get", side_effect=fake_get):
            for _ in range(6):
                snapshots.append(
                    manager._fetch_progress_snapshot(
                        "prompt-1",
                        preparing_label="Preparing video generation",
                        active_label="Generating frames",
                    )
                )

        labels = [snapshot[1] for snapshot in snapshots if snapshot is not None]
        self.assertEqual(
            labels[:5],
            [
                "Generating frames 1/2 • step 1/2",
                "Generating frames 2/2 • step 1/2",
                "Decoding frames",
                "Encoding video",
                "Saving video",
            ],
        )
        self.assertTrue(all(snapshot is not None for snapshot in snapshots))
        progress_values = [snapshot[0] for snapshot in snapshots if snapshot is not None]
        self.assertEqual(progress_values, sorted(progress_values))
        self.assertEqual(labels[5], "Generating frames")
