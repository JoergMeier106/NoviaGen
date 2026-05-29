import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/app/navigation/app_navigation_controller.dart';
import 'package:noviagen/app/runtime/app_activity_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';
import 'package:noviagen/app/runtime/media_runtime_store.dart';
import 'package:noviagen/app/runtime/scaling_preferences_store.dart';
import 'package:noviagen/features/gallery/controllers/pending_media_refresh_controller.dart';
import 'package:noviagen/features/gallery/controllers/media_job_controller.dart';
import 'package:noviagen/features/gallery/controllers/gallery_selection_actions_controller.dart';
import 'package:noviagen/features/gallery/domain/gallery_selection_capabilities.dart';
import 'package:noviagen/features/gallery/gallery_view_model.dart';
import 'package:noviagen/features/jobs/controllers/job_polling_controller.dart';
import 'package:noviagen/features/jobs/controllers/job_queue_controller.dart';
import 'package:noviagen/features/jobs/domain/job_status_selectors.dart';
import 'package:noviagen/features/jobs/services/terminal_job_handler.dart';
import 'package:noviagen/features/chat/controllers/chat_job_message_controller.dart';
import 'package:noviagen/features/chat/state/chat_attachment_store.dart';
import 'package:noviagen/features/chat/state/chat_model_catalog_store.dart';
import 'package:noviagen/features/chat/state/chat_session_store.dart';
import 'package:noviagen/features/generate/controllers/auto_prompt_controller.dart';
import 'package:noviagen/features/generate/controllers/image_generation_controller.dart';
import 'package:noviagen/features/generate/controllers/video_result_preview_controller.dart';
import 'package:noviagen/features/generate/controllers/video_lucky_generation_controller.dart';
import 'package:noviagen/features/generate/domain/generation_settings.dart';
import 'package:noviagen/features/generate/services/generation_job_factory.dart';
import 'package:noviagen/features/generate/services/video_regeneration_job_factory.dart';
import 'package:noviagen/features/generate/state/generation_defaults_store.dart';
import 'package:noviagen/features/generate/state/generation_source_store.dart';
import 'package:noviagen/features/generate/state/image_model_selection_store.dart';
import 'package:noviagen/features/generate/state/video_asset_selection_store.dart';
import 'package:noviagen/features/generate/state/video_generation_settings_store.dart';
import 'package:noviagen/features/jobs/services/job_notification_service.dart';
import 'package:noviagen/features/prompts/state/prompt_library_store.dart';
import 'package:noviagen/models/assets.dart';
import 'package:noviagen/models/generation.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/models/prompts.dart';

class _FakeChainApiClient extends ApiClient {
  _FakeChainApiClient() : super('http://example.test');

  int createChainJobCallCount = 0;
  List<JobChainStep> lastSteps = const <JobChainStep>[];
  Map<String, JobChainUpload> lastUploads = const <String, JobChainUpload>{};
  String? lastClientRequestId;

  @override
  Future<JobStatus> createChainJob({
    required List<JobChainStep> steps,
    String? clientRequestId,
    Map<String, JobChainUpload> uploads = const <String, JobChainUpload>{},
  }) async {
    createChainJobCallCount += 1;
    lastSteps = List<JobChainStep>.from(steps);
    lastUploads = Map<String, JobChainUpload>.from(uploads);
    lastClientRequestId = clientRequestId;
    return _queuedChainJob('chain-$createChainJobCallCount');
  }
}

class _ThrowingChainApiClient extends _FakeChainApiClient {
  _ThrowingChainApiClient();

  @override
  Future<JobStatus> createChainJob({
    required List<JobChainStep> steps,
    String? clientRequestId,
    Map<String, JobChainUpload> uploads = const <String, JobChainUpload>{},
  }) async {
    createChainJobCallCount += 1;
    lastSteps = List<JobChainStep>.from(steps);
    lastUploads = Map<String, JobChainUpload>.from(uploads);
    lastClientRequestId = clientRequestId;
    throw StateError('response failed after enqueue');
  }
}

class _FailingPostApiClient extends ApiClient {
  _FailingPostApiClient(this.path) : super('http://example.test') {
    _dio = Dio(BaseOptions(baseUrl: 'http://example.test'))
      ..httpClientAdapter = _FailingPostAdapter(path);
  }

  final String path;
  late final Dio _dio;

  @override
  Dio get dio => _dio;
}

class _FailingPostAdapter implements HttpClientAdapter {
  _FailingPostAdapter(this.path);

  final String path;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path == path) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: StateError('response failed after enqueue'),
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingGenerationApiClient extends ApiClient {
  _RecordingGenerationApiClient() : super('http://example.test');

  Map<String, dynamic>? lastUploadedImageJob;
  Map<String, dynamic>? lastUploadedVideoJob;

  @override
  Future<JobStatus> createGenerateFromUploadedImageJob({
    required String imagePath,
    required String imageName,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String modelId,
    required List<SelectedLora> loras,
    required int numInferenceSteps,
    required double guidanceScale,
    required String imageOrientation,
    required bool autoMetadataEnabled,
    String? autoMetadataModelName,
    required double strength,
  }) async {
    lastUploadedImageJob = <String, dynamic>{
      'imagePath': imagePath,
      'imageName': imageName,
      'prompt': prompt,
      'defaultPositivePrompt': defaultPositivePrompt,
      'defaultNegativePrompt': defaultNegativePrompt,
      'modelId': modelId,
      'loras': loras,
      'numInferenceSteps': numInferenceSteps,
      'guidanceScale': guidanceScale,
      'imageOrientation': imageOrientation,
      'autoMetadataEnabled': autoMetadataEnabled,
      'autoMetadataModelName': autoMetadataModelName,
      'strength': strength,
    };
    return _jobStatus(
      jobId: 'uploaded-image-job',
      type: 'generate_from_image',
      status: 'queued',
      result: _queuedResultImage('uploaded-image-result'),
    );
  }

  @override
  Future<JobStatus> createAnimateUploadedImageJob({
    required String imagePath,
    required String imageName,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String preset,
    int? customWidth,
    int? customHeight,
    int? customFps,
    int? customNumFrames,
    String? highDiffusionModelName,
    String? lowDiffusionModelName,
    List<VideoWorkflowLoraStrength> workflowLoras =
        const <VideoWorkflowLoraStrength>[],
  }) async {
    lastUploadedVideoJob = <String, dynamic>{
      'imagePath': imagePath,
      'imageName': imageName,
      'prompt': prompt,
      'defaultPositivePrompt': defaultPositivePrompt,
      'defaultNegativePrompt': defaultNegativePrompt,
      'preset': preset,
      'customWidth': customWidth,
      'customHeight': customHeight,
      'customFps': customFps,
      'customNumFrames': customNumFrames,
      'highDiffusionModelName': highDiffusionModelName,
      'lowDiffusionModelName': lowDiffusionModelName,
      'workflowLoras': workflowLoras,
    };
    return _jobStatus(
      jobId: 'uploaded-video-job',
      type: 'animate_image',
      status: 'queued',
      result: _queuedResultImage('uploaded-video-result'),
    );
  }
}

class _ThrowingPollApiClient extends ApiClient {
  _ThrowingPollApiClient() : super('http://example.test');

  @override
  Future<JobStatus> getJob(String jobId) async {
    throw StateError('background poll failed');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('JobStatus parses parent and child chain metadata', () {
    final parent = JobStatus.fromJson(<String, dynamic>{
      'job_id': 'chain-parent',
      'type': 'chain',
      'status': 'running',
      'progress': 0.5,
      'status_text': 'Animating image',
      'cancel_requested': false,
      'payload': <String, dynamic>{'steps': <dynamic>[]},
      'chain': <String, dynamic>{
        'current_step_id': 'video',
        'current_child_job_id': 'child-2',
        'steps': <dynamic>[
          <String, dynamic>{
            'id': 'prompt',
            'type': 'generate_prompt',
            'status': 'completed',
            'child_job_id': 'child-1',
            'result_text': 'cinematic prompt',
          },
        ],
      },
    });
    final child = JobStatus.fromJson(<String, dynamic>{
      'job_id': 'child-2',
      'type': 'animate_image',
      'parent_job_id': 'chain-parent',
      'chain_step_id': 'video',
      'status': 'running',
      'progress': 0.25,
      'status_text': 'Preparing',
      'cancel_requested': false,
      'payload': <String, dynamic>{'prompt': 'demo'},
    });

    expect(parent.chain?.currentStepId, 'video');
    expect(parent.chain?.steps.single.resultText, 'cinematic prompt');
    expect(child.parentJobId, 'chain-parent');
    expect(child.chainStepId, 'video');
  });

  test('JobStatus keeps accepted jobs when result payload parsing fails', () {
    final job = JobStatus.fromJson(<String, dynamic>{
      'job_id': 'accepted-job',
      'type': 'chain',
      'status': 'queued',
      'progress': 0.0,
      'status_text': 'Queued',
      'cancel_requested': false,
      'payload': <String, dynamic>{'steps': <dynamic>[]},
      'result': <String, dynamic>{'id': 'partial-placeholder'},
    });

    expect(job.jobId, 'accepted-job');
    expect(job.result, isNull);
  });

  test('createChainJob surfaces response failures', () async {
    final api = _FailingPostApiClient('/api/jobs/chain');

    await expectLater(
      api.createChainJob(
        steps: <JobChainStep>[
          JobChainStep(
            id: 'prompt',
            type: 'generate_i2v_prompt',
            payload: <String, dynamic>{'image_id': 'image-1'},
          ),
        ],
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('createGenerateVideoJob surfaces response failures', () async {
    final api = _FailingPostApiClient('/api/jobs/generate-video');

    await expectLater(
      api.createGenerateVideoJob(
        prompt: 'plain video prompt',
        defaultPositivePrompt: 'cinematic lighting',
        defaultNegativePrompt: 'bad quality',
        preset: 'preview',
        customWidth: 640,
        customHeight: 384,
        customFps: 16,
        customNumFrames: 49,
      ),
      throwsA(isA<DioException>()),
    );
  });

  test(
    'generateFeelingLucky submits one chained backend job for uploads',
    () async {
      final api = _FakeChainApiClient();
      final harness = _GenerationHarness(api: api);
      harness.generationSources.imageLocalSource = LocalImageSource(
        path: '/tmp/lucky-source.png',
        name: 'lucky-source.png',
      );
      final controller = ImageGenerationController(
        ImageGenerationDependencies(
          connection: harness.connection,
          activity: harness.activity,
          jobRuntime: harness.jobRuntime,
          jobNotifications: JobNotificationService(),
          navigation: harness.navigation,
          autoPrompts: harness.autoPrompts,
          imageModels: harness.imageModels,
          promptLibrary: harness.promptLibrary,
          generationJobs: harness.generationJobs,
          generationSources: harness.generationSources,
          registerQueuedJob: harness.registerQueuedJob,
          notifyChanged: harness.notifyChanged,
        ),
      );

      final queuedImage = await controller.generateFeelingLucky();

      expect(queuedImage?.id, 'result-chain-1');
      expect(api.createChainJobCallCount, 1);
      expect(api.lastClientRequestId, isNull);
      expect(api.lastSteps.map((step) => step.id).toList(), <String>[
        'lucky_prompt',
        'lucky_image',
      ]);
      expect(api.lastSteps.first.type, 'generate_prompt');
      expect(api.lastSteps.last.type, 'generate_from_image');
      expect(api.lastSteps.last.payload['upload_ref'], 'lucky_source_image');
      expect(
        api.lastSteps.last.bindings['prompt']?.stepId,
        api.lastSteps.first.id,
      );
      expect(api.lastSteps.last.bindings['prompt']?.output, 'result_text');
      expect(api.lastUploads.keys.single, 'lucky_source_image');
      expect(
        api.lastUploads['lucky_source_image']?.path,
        '/tmp/lucky-source.png',
      );
      expect(api.lastUploads['lucky_source_image']?.name, 'lucky-source.png');
    },
  );

  test('Feeling Lucky video submits one chained backend workflow', () async {
    final api = _FakeChainApiClient();
    final harness = _GenerationHarness(api: api);
    final controller = VideoLuckyGenerationController(
      VideoLuckyGenerationDependencies(
        connection: harness.connection,
        activity: harness.activity,
        jobRuntime: harness.jobRuntime,
        jobNotifications: JobNotificationService(),
        navigation: harness.navigation,
        autoPrompts: harness.autoPrompts,
        imageModels: harness.imageModels,
        videoAssets: harness.videoAssets,
        videoSettings: harness.videoSettings,
        promptLibrary: harness.promptLibrary,
        generationJobs: harness.generationJobs,
        registerQueuedJob: harness.registerQueuedJob,
        notifyChanged: harness.notifyChanged,
      ),
    );

    final queuedVideo = await controller.generate();

    expect(queuedVideo?.id, 'result-chain-1');
    expect(api.createChainJobCallCount, 1);
    expect(api.lastClientRequestId, isNull);
    expect(api.lastSteps.map((step) => step.id).toList(), <String>[
      'lucky_prompt',
      'lucky_image',
      'lucky_video_prompt',
      'lucky_video',
    ]);
    expect(api.lastSteps[0].type, 'generate_prompt');
    expect(api.lastSteps[1].type, 'generate');
    expect(api.lastSteps[2].type, 'generate_i2v_prompt');
    expect(api.lastSteps[3].type, 'animate_image');
    expect(api.lastSteps[1].bindings['prompt']?.stepId, 'lucky_prompt');
    expect(api.lastSteps[2].bindings['image_id']?.stepId, 'lucky_image');
    expect(api.lastSteps[2].bindings['image_id']?.output, 'result_image_id');
    expect(api.lastSteps[3].bindings['image_id']?.stepId, 'lucky_image');
    expect(api.lastSteps[3].bindings['prompt']?.stepId, 'lucky_video_prompt');
    expect(api.lastSteps[3].payload['preset'], 'preview');
    expect(api.lastSteps[3].payload['width'], 640);
    expect(api.lastSteps[3].payload['height'], 384);
    expect(api.lastSteps[3].payload['workflow_loras'], <Map<String, dynamic>>[
      <String, dynamic>{'lora_id': 'i2v-lora', 'strength': 0.45},
    ]);
  });

  test(
    'createPromptAndAnimateImage submits i2v prompt plus animation chain',
    () async {
      final api = _FakeChainApiClient();
      final harness = _GenerationHarness(api: api);
      final controller = MediaJobController(
        MediaJobDependencies(
          connection: harness.connection,
          activity: harness.activity,
          jobRuntime: harness.jobRuntime,
          mediaRuntime: MediaRuntimeStore(),
          scalingPreferences: ScalingPreferencesStore(),
          generationDefaults: harness.defaults,
          jobNotifications: JobNotificationService(),
          autoPrompts: harness.autoPrompts,
          promptLibrary: harness.promptLibrary,
          generationJobs: harness.generationJobs,
          videoAssets: harness.videoAssets,
          videoSettings: harness.videoSettings,
          videoRegenerationJobs: VideoRegenerationJobFactory(
            videoAssets: harness.videoAssets,
            findKnownMedia: (_) => null,
          ),
          registerQueuedJob: harness.registerQueuedJob,
          notifyChanged: harness.notifyChanged,
        ),
      );
      final source = _storedImage('source-image');

      final queuedVideo = await controller.createPromptAndAnimateImage(source);

      expect(queuedVideo?.id, 'result-chain-1');
      expect(api.createChainJobCallCount, 1);
      expect(api.lastSteps.map((step) => step.id).toList(), <String>[
        'gallery_i2v_prompt',
        'gallery_i2v_video',
      ]);
      expect(api.lastSteps.first.type, 'generate_i2v_prompt');
      expect(api.lastSteps.first.payload['image_id'], source.id);
      expect(api.lastSteps.last.type, 'animate_image');
      expect(api.lastSteps.last.payload['image_id'], source.id);
      expect(
        api.lastSteps.last.bindings['prompt']?.stepId,
        'gallery_i2v_prompt',
      );
    },
  );

  test('createPromptAndAnimateImage surfaces response failures', () async {
    final api = _ThrowingChainApiClient();
    final harness = _GenerationHarness(api: api);
    final controller = MediaJobController(
      MediaJobDependencies(
        connection: harness.connection,
        activity: harness.activity,
        jobRuntime: harness.jobRuntime,
        mediaRuntime: MediaRuntimeStore(),
        scalingPreferences: ScalingPreferencesStore(),
        generationDefaults: harness.defaults,
        jobNotifications: JobNotificationService(),
        autoPrompts: harness.autoPrompts,
        promptLibrary: harness.promptLibrary,
        generationJobs: harness.generationJobs,
        videoAssets: harness.videoAssets,
        videoSettings: harness.videoSettings,
        videoRegenerationJobs: VideoRegenerationJobFactory(
          videoAssets: harness.videoAssets,
          findKnownMedia: (_) => null,
        ),
        registerQueuedJob: harness.registerQueuedJob,
        notifyChanged: harness.notifyChanged,
      ),
    );

    final queuedVideo = await controller.createPromptAndAnimateImage(
      _storedImage('source-image'),
    );

    expect(queuedVideo, isNull);
    expect(harness.jobRuntime.latestJob, isNull);
    expect(
      harness.connection.message,
      'Couldn\'t start the prompt + video generation workflow right now. Please try again.',
    );
  });

  test('generate surfaces response failures', () async {
    final api = _FailingPostApiClient('/api/jobs/generate');
    final harness = _GenerationHarness(api: api);
    final controller = ImageGenerationController(
      ImageGenerationDependencies(
        connection: harness.connection,
        activity: harness.activity,
        jobRuntime: harness.jobRuntime,
        jobNotifications: JobNotificationService(),
        navigation: harness.navigation,
        autoPrompts: harness.autoPrompts,
        imageModels: harness.imageModels,
        promptLibrary: harness.promptLibrary,
        generationJobs: harness.generationJobs,
        generationSources: harness.generationSources,
        registerQueuedJob: harness.registerQueuedJob,
        notifyChanged: harness.notifyChanged,
      ),
    );

    final queuedImage = await controller.generate('plain image prompt');

    expect(queuedImage, isNull);
    expect(harness.jobRuntime.latestJob, isNull);
    expect(
      harness.connection.message,
      'Couldn\'t start the image job. Please try again.',
    );
  });

  test('local image source queues uploaded i2i with i2i defaults', () async {
    final api = _RecordingGenerationApiClient();
    final harness = _GenerationHarness(api: api);

    final queuedImage = await harness.generationJobs.queueImageGenerationJob(
      client: api,
      prompt: 'remix this',
      defaultPositivePrompt: 'best quality',
      defaultNegativePrompt: 'bad anatomy',
      modelId: 'demo-model',
      loras: const <SelectedLora>[],
      localSource: LocalImageSource(
        path: '/tmp/source.png',
        name: 'source.png',
      ),
    );

    expect(queuedImage.jobId, 'uploaded-image-job');
    expect(api.lastUploadedImageJob?['imagePath'], '/tmp/source.png');
    expect(api.lastUploadedImageJob?['imageName'], 'source.png');
    expect(api.lastUploadedImageJob?['numInferenceSteps'], 20);
    expect(api.lastUploadedImageJob?['guidanceScale'], 4.0);
    expect(api.lastUploadedImageJob?['strength'], 0.42);
  });

  test('local video source queues uploaded i2v with i2v selections', () async {
    final api = _RecordingGenerationApiClient();
    final harness = _GenerationHarness(api: api);
    harness.videoAssets.diffusionModels = <VideoDiffusionModelAsset>[
      VideoDiffusionModelAsset(name: 'i2v-high.safetensors'),
      VideoDiffusionModelAsset(name: 'i2v-low.safetensors'),
    ];
    harness.videoAssets.setImageToVideoHighDiffusionModel(
      'i2v-high.safetensors',
    );
    harness.videoAssets.setImageToVideoLowDiffusionModel('i2v-low.safetensors');

    final queuedVideo = await harness.generationJobs.queueVideoGenerationJob(
      client: api,
      prompt: 'animate this',
      defaultPositivePrompt: 'cinematic lighting',
      defaultNegativePrompt: 'bad quality',
      presetId: 'preview',
      settings: <String, int>{
        'width': 640,
        'height': 384,
        'fps': 16,
        'num_frames': 49,
      },
      localSource: LocalImageSource(
        path: '/tmp/video-source.png',
        name: 'video-source.png',
      ),
    );

    expect(queuedVideo.jobId, 'uploaded-video-job');
    expect(api.lastUploadedVideoJob?['imagePath'], '/tmp/video-source.png');
    expect(api.lastUploadedVideoJob?['imageName'], 'video-source.png');
    expect(
      api.lastUploadedVideoJob?['highDiffusionModelName'],
      'i2v-high.safetensors',
    );
    expect(
      api.lastUploadedVideoJob?['lowDiffusionModelName'],
      'i2v-low.safetensors',
    );
    final workflowLoras =
        api.lastUploadedVideoJob?['workflowLoras']
            as List<VideoWorkflowLoraStrength>;
    expect(workflowLoras.single.loraId, 'i2v-lora');
    expect(workflowLoras.single.strength, 0.45);
  });

  test(
    'GallerySelectionCapabilities exposes prompt + video generation for ready still-image selections',
    () {
      final readyStill = _storedImage('ready');
      final anotherReadyStill = _storedImage('ready-2');
      final queuedStill = _storedImage('queued').copyWith(status: 'queued');
      final readyVideo = _storedVideo('video');

      final readySingle = GallerySelectionCapabilities.fromImages(<ImageRecord>[
        readyStill,
      ], jobForImage: (_) => null);
      final queuedSingle = GallerySelectionCapabilities.fromImages(
        <ImageRecord>[queuedStill],
        jobForImage: (_) => null,
      );
      final mixedSelection = GallerySelectionCapabilities.fromImages(
        <ImageRecord>[readyStill, readyVideo],
        jobForImage: (_) => null,
      );
      final readyBatch = GallerySelectionCapabilities.fromImages(<ImageRecord>[
        readyStill,
        anotherReadyStill,
      ], jobForImage: (_) => null);

      expect(readySingle.canCreatePromptAndVideo, isTrue);
      expect(readyBatch.canCreatePromptAndVideo, isTrue);
      expect(queuedSingle.canCreatePromptAndVideo, isFalse);
      expect(mixedSelection.canCreatePromptAndVideo, isFalse);
    },
  );

  test(
    'GallerySelectionActionsController queues prompt + video generation for every selected ready image',
    () async {
      final queuedImages = <ImageRecord>[];
      final messages = <String>[];
      var cleared = 0;
      final controller = GallerySelectionActionsController(
        viewModel: _GalleryViewModelStub(
          onCreatePromptAndAnimateImage: (image) async {
            queuedImages.add(image);
            return _queuedResultImage('queued-${image.id}');
          },
        ),
        showMessage: messages.add,
        showStateMessage: () => messages.add('state'),
        clearSelection: () => cleared += 1,
        isMounted: () => true,
      );
      final images = <ImageRecord>[
        _storedImage('batch-1'),
        _storedImage('batch-2'),
      ];

      await controller.createPromptAndVideo(images);

      expect(queuedImages.map((image) => image.id).toList(), <String>[
        'batch-1',
        'batch-2',
      ]);
      expect(messages, <String>[
        '2 prompt + video generation workflows added to the queue.',
      ]);
      expect(cleared, 1);
    },
  );

  test('firstActiveJob prefers the chain parent over running child jobs', () {
    final parent = _jobStatus(
      jobId: 'chain-parent',
      type: 'chain',
      status: 'running',
      progress: 0.4,
    );
    final child = _jobStatus(
      jobId: 'child-image',
      type: 'animate_image',
      status: 'running',
      progress: 0.7,
      parentJobId: parent.jobId,
      chainStepId: 'video',
    );

    final selected = firstActiveJob(<JobStatus>[child, parent]);

    expect(selected?.jobId, parent.jobId);
  });

  test(
    'TerminalJobHandler does not surface child chain failures as app errors',
    () async {
      final connection = AppConnectionStore();
      final activity = AppActivityStore();
      final mediaRuntime = MediaRuntimeStore();
      final handler = TerminalJobHandler(
        TerminalJobHandlerDependencies(
          connection: connection,
          activity: activity,
          mediaRuntime: mediaRuntime,
          jobNotifications: JobNotificationService(),
          chatJobMessages: _buildChatJobMessages,
          loadErrors: ({silent = false}) async {},
          replaceGalleryItem: (_) {},
          syncDeletedScalingSource: (_) {},
          latestCompletedGalleryItem: ([items]) => null,
          videoResultPreviewController: VideoResultPreviewController(
            VideoResultPreviewControllerDependencies(
              connection: connection,
              jobRuntime: JobRuntimeStore(),
              mediaRuntime: mediaRuntime,
              replaceJob: (_) {},
              replaceGalleryItem: (_) {},
              notifyChanged: () {},
            ),
          ),
          notifyChanged: () {},
        ),
      );

      await handler.handle(
        _jobStatus(
          jobId: 'child-failed',
          type: 'generate_i2v_prompt',
          status: 'failed',
          progress: 1.0,
          statusText: 'Failed',
          parentJobId: 'chain-parent',
          chainStepId: 'prompt',
          error: 'transient child failure',
        ),
      );

      expect(connection.message, isNull);
      expect(activity.runningJob, isFalse);
    },
  );

  test(
    'JobQueueController swallows background polling failures after queue acceptance',
    () async {
      final errors = <Object>[];
      await runZonedGuarded(
        () async {
          final controller = JobQueueController(
            JobQueueDependencies(
              connection: AppConnectionStore(),
              activity: AppActivityStore(),
              jobRuntime: JobRuntimeStore(),
              mediaRuntime: MediaRuntimeStore(),
              navigation: () => AppNavigationController(onChanged: () {}),
              replaceJob: (_) {},
              replaceGalleryItem: (_) {},
              syncMediaRefreshTimer: () {},
              pollJob: (_, {expectedResultImageId}) async {
                throw StateError('background poll failed');
              },
              notifyChanged: () {},
            ),
          );

          controller.registerQueuedJob(_queuedChainJob('queued-job'));
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) {
          errors.add(error);
        },
      );

      expect(errors, isEmpty);
    },
  );

  test(
    'JobPollingController swallows fire-and-forget polling failures when resuming active jobs',
    () async {
      final errors = <Object>[];
      await runZonedGuarded(
        () async {
          final connection = AppConnectionStore()
            ..overrideApiClient = _ThrowingPollApiClient();
          final activity = AppActivityStore();
          final jobRuntime = JobRuntimeStore();
          final mediaRuntime = MediaRuntimeStore();
          final controller = JobPollingController(
            JobPollingDependencies(
              connection: connection,
              activity: activity,
              jobRuntime: jobRuntime,
              mediaRuntime: mediaRuntime,
              jobNotifications: JobNotificationService(),
              pendingMediaRefreshController: PendingMediaRefreshController(
                PendingMediaRefreshControllerDependencies(
                  mediaRuntime: mediaRuntime,
                  jobRuntime: jobRuntime,
                  replaceGalleryItem: (_) {},
                  removeGalleryItemById: (_) {},
                  latestCompletedGalleryItem: ([items]) => null,
                ),
              ),
              chatJobMessages: _buildChatJobMessages,
              loadErrors: ({silent = false}) async {},
              replaceJob: (_) {},
              replaceGalleryItem: (_) {},
              syncDeletedScalingSource: (_) {},
              latestCompletedGalleryItem: ([items]) => null,
              videoResultPreviewController: VideoResultPreviewController(
                VideoResultPreviewControllerDependencies(
                  connection: connection,
                  jobRuntime: jobRuntime,
                  mediaRuntime: mediaRuntime,
                  replaceJob: (_) {},
                  replaceGalleryItem: (_) {},
                  notifyChanged: () {},
                ),
              ),
              notifyChanged: () {},
            ),
          );

          controller.schedulePollingForFirstActiveJob(<JobStatus>[
            _jobStatus(
              jobId: 'active-job',
              type: 'chain',
              status: 'running',
              progress: 0.4,
            ),
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        (error, stackTrace) {
          errors.add(error);
        },
      );

      expect(errors, isEmpty);
    },
  );
}

class _GenerationHarness {
  _GenerationHarness({required ApiClient api})
    : connection = AppConnectionStore()..overrideApiClient = api,
      activity = AppActivityStore(),
      jobRuntime = JobRuntimeStore(),
      navigation = AppNavigationController(onChanged: () {}),
      defaults = GenerationDefaultsStore(onChanged: () {}),
      imageModels = ImageModelSelectionStore(
        setMessage: (_) {},
        onChanged: () {},
      ),
      promptLibrary = PromptLibraryStore(),
      videoAssets = VideoAssetSelectionStore(onChanged: () {}),
      generationSources = GenerationSourceStore(
        setMessage: (_) {},
        setGenerateMode: (_) {},
        syncVideoDraftOrientation: () {},
        persistSource: ({required forVideo}) async {},
        setRequestError: (_, {required generalMessage}) {},
        onChanged: () {},
      ),
      changeCount = 0 {
    defaults.numInferenceSteps = 30;
    defaults.guidanceScale = 6.0;
    defaults.imageToImageNumInferenceSteps = 20;
    defaults.imageToImageGuidanceScale = 4.0;
    defaults.imageToImageStrength = 0.42;
    defaults.imageOrientation = ImageOrientationSetting.landscape;

    imageModels.applyAssets(
      models: <ModelAsset>[
        ModelAsset(id: 'demo-model', label: 'Demo model', rating: 5.0),
      ],
      loras: <LoraAsset>[
        LoraAsset(
          id: 'demo-lora',
          label: 'Demo LoRA',
          defaultStrength: 0.8,
          rating: 4.0,
        ),
      ],
    );

    promptLibrary.presets = <PromptPreset>[
      PromptPreset(
        id: 'image-preset',
        name: 'Image preset',
        positivePrompt: 'best quality',
        negativePrompt: 'bad anatomy',
      ),
      PromptPreset(
        id: 'video-preset',
        name: 'Video preset',
        positivePrompt: 'cinematic lighting',
        negativePrompt: 'bad quality',
      ),
    ];
    promptLibrary.selectedImagePresetId = 'image-preset';
    promptLibrary.selectedVideoPresetId = 'video-preset';

    videoAssets.applyAssets(
      videoModels: <VideoModelAsset>[
        VideoModelAsset(
          id: 'comfy-text-to-video',
          label: 'Text to video',
          workflowLoras: <VideoWorkflowLoraAsset>[
            VideoWorkflowLoraAsset(
              id: 't2v-lora',
              name: 'Text LoRA',
              label: 'Text LoRA',
              defaultStrength: 0.9,
              enabled: true,
            ),
          ],
        ),
        VideoModelAsset(
          id: 'comfy-image-to-video',
          label: 'Image to video',
          workflowLoras: <VideoWorkflowLoraAsset>[
            VideoWorkflowLoraAsset(
              id: 'i2v-lora',
              name: 'Image LoRA',
              label: 'Image LoRA',
              defaultStrength: 0.45,
              enabled: true,
            ),
          ],
        ),
      ],
      diffusionModels: const <VideoDiffusionModelAsset>[],
      presets: <VideoPresetOption>[
        VideoPresetOption(
          id: 'preview',
          label: 'Preview',
          maxWidth: 640,
          maxHeight: 384,
          numFrames: 49,
          fps: 16,
          numInferenceSteps: 8,
          isDefault: true,
        ),
      ],
    );
    videoSettings = VideoGenerationSettingsStore(
      selectedPreset: () => videoAssets.selectedPreset,
      sourceOrientation: () => generationSources.videoSourceOrientation,
      setMessage: (_) {},
      persistDraft: () async {},
      onChanged: () {},
    )..ensureInitialized(force: true);

    generationJobs = GenerationJobFactory(
      defaults: defaults,
      videoAssets: videoAssets,
      chatModelCatalog: ChatModelCatalogStore(
        api: () => null,
        setRequestError: (_, {required generalMessage}) {},
        onChanged: () {},
      ),
    );
    autoPrompts = AutoPromptController(
      api: () => connection.api,
      registerQueuedJob: registerQueuedJob,
      announceQueuedJob: navigation.announceQueuedJob,
      waitForJobToReachTerminalState: (_) async => null,
      loadErrors: ({silent = false}) async {},
      setMessage: (value) => connection.message = value,
      setRequestError: (_, {required generalMessage}) {
        connection.message = generalMessage;
      },
      onChanged: notifyChanged,
      saveImagePromptDraft: (_) async {},
      saveVideoPromptDraft: (_) async {},
      hasImageSource: () => generationSources.hasImageSource,
      videoSource: () => generationSources.videoSource,
      videoLocalSource: () => generationSources.videoLocalSource,
      textToImageModelName: () => 'prompt-model',
      imageToImageModelName: () => 'image-prompt-model',
      textToVideoModelName: () => 'video-prompt-model',
      imageToVideoModelName: () => 'i2v-prompt-model',
      textToImageBasePrompt: () => 'lucky image base',
      imageToImageBasePrompt: () => 'image remix base',
      textToVideoBasePrompt: () => 'lucky video base',
      imageToVideoBasePrompt: () => 'i2v base prompt',
    );
  }

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final AppNavigationController navigation;
  final GenerationDefaultsStore defaults;
  final ImageModelSelectionStore imageModels;
  final PromptLibraryStore promptLibrary;
  final VideoAssetSelectionStore videoAssets;
  late final VideoGenerationSettingsStore videoSettings;
  final GenerationSourceStore generationSources;
  late final GenerationJobFactory generationJobs;
  late final AutoPromptController autoPrompts;
  int changeCount;

  ImageRecord? registerQueuedJob(JobStatus job, {String? queuedMessage}) {
    jobRuntime.latestJob = job;
    if (queuedMessage != null) {
      connection.message = queuedMessage;
    }
    return job.result;
  }

  void notifyChanged() {
    changeCount += 1;
  }
}

JobStatus _queuedChainJob(
  String jobId, {
  Map<String, dynamic> payload = const <String, dynamic>{'steps': <dynamic>[]},
}) {
  return _jobStatus(
    jobId: jobId,
    type: 'chain',
    status: 'queued',
    payload: payload,
    result: _queuedResultImage('result-$jobId'),
    chain: JobChainState(
      currentStepId: null,
      currentChildJobId: null,
      steps: const <JobChainStateStep>[],
    ),
  );
}

JobStatus _jobStatus({
  required String jobId,
  required String type,
  required String status,
  double progress = 0.0,
  String statusText = 'Queued',
  String? parentJobId,
  String? chainStepId,
  Map<String, dynamic> payload = const <String, dynamic>{},
  ImageRecord? result,
  JobChainState? chain,
  String? error,
}) {
  return JobStatus(
    jobId: jobId,
    type: type,
    parentJobId: parentJobId,
    chainStepId: chainStepId,
    status: status,
    progress: progress,
    statusText: statusText,
    cancelRequested: false,
    payload: payload,
    result: result,
    chain: chain,
    error: error,
  );
}

ImageRecord _queuedResultImage(String id) {
  return ImageRecord(
    id: id,
    status: 'queued',
    mediaType: 'image',
    mimeType: 'image/png',
    width: 640,
    height: 384,
    prompt: '',
    defaultPositivePrompt: '',
    defaultNegativePrompt: '',
    finalPositivePrompt: '',
    modelId: 'demo-model',
    loras: const <SelectedLora>[],
    tags: const <String>[],
    caption: '',
    numInferenceSteps: 30,
    guidanceScale: 6.0,
    imageOrientation: 'landscape',
    fileUrl: 'http://example.test/files/$id',
    previewUrl: 'http://example.test/preview/$id',
    createdAt: '2026-05-10T12:00:00Z',
    rating: 0,
  );
}

ImageRecord _storedImage(String id) {
  return ImageRecord(
    id: id,
    status: 'stored',
    mediaType: 'image',
    mimeType: 'image/png',
    width: 640,
    height: 384,
    prompt: 'prompt',
    defaultPositivePrompt: 'best quality',
    defaultNegativePrompt: 'bad quality',
    finalPositivePrompt: 'prompt',
    modelId: 'demo-model',
    loras: const <SelectedLora>[],
    tags: const <String>[],
    caption: '',
    numInferenceSteps: 30,
    guidanceScale: 6.0,
    imageOrientation: 'landscape',
    fileUrl: 'http://example.test/files/$id',
    previewUrl: 'http://example.test/preview/$id',
    createdAt: '2026-05-10T12:00:00Z',
    rating: 0,
    storedAt: '2026-05-10T12:05:00Z',
  );
}

ImageRecord _storedVideo(String id) {
  return ImageRecord(
    id: id,
    status: 'stored',
    mediaType: 'video',
    mimeType: 'video/mp4',
    width: 640,
    height: 384,
    prompt: 'prompt',
    defaultPositivePrompt: 'best quality',
    defaultNegativePrompt: 'bad quality',
    finalPositivePrompt: 'prompt',
    modelId: 'comfy-image-to-video',
    loras: const <SelectedLora>[],
    tags: const <String>[],
    caption: '',
    numInferenceSteps: 8,
    guidanceScale: 0.0,
    imageOrientation: 'landscape',
    fileUrl: 'http://example.test/files/$id',
    previewUrl: 'http://example.test/preview/$id',
    createdAt: '2026-05-10T12:00:00Z',
    rating: 0,
    storedAt: '2026-05-10T12:05:00Z',
    posterUrl: 'http://example.test/poster/$id',
    fps: 16,
    numFrames: 49,
  );
}

ChatJobMessageController _buildChatJobMessages() {
  final attachments = ChatAttachmentStore(
    api: () => null,
    setMessage: (_) {},
    setRequestError: (_, {required generalMessage}) {},
    onChanged: () {},
  );
  final modelCatalog = ChatModelCatalogStore(
    api: () => null,
    setRequestError: (_, {required generalMessage}) {},
    onChanged: () {},
  );
  final sessions = ChatSessionStore(
    api: () => null,
    modelCatalog: modelCatalog,
    context: attachments,
    loadModels: () async {},
    selectedModelName: () => '',
    setMessage: (_) {},
    setRequestError: (_, {required generalMessage}) {},
    onChanged: () {},
  );
  return ChatJobMessageController(
    chat: sessions,
    context: attachments,
    gallery: () => const <ImageRecord>[],
    isActiveJob: (_) => false,
    setDraft: (_) {},
    setMessage: (_) {},
    loadErrors: ({silent = false}) async {},
    selectedModelName: () => '',
    requestScrollToMessage: (_) {},
  );
}

class _GalleryViewModelStub extends ChangeNotifier implements GalleryViewModel {
  _GalleryViewModelStub({required this.onCreatePromptAndAnimateImage});

  final Future<ImageRecord?> Function(ImageRecord image)
  onCreatePromptAndAnimateImage;

  @override
  Future<ImageRecord?> createPromptAndAnimateImage(ImageRecord image) {
    return onCreatePromptAndAnimateImage(image);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
