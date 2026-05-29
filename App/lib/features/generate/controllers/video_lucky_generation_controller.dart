import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/features/generate/controllers/auto_prompt_controller.dart';
import 'package:flutter_app/features/generate/services/generation_job_factory.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/features/jobs/services/job_notification_service.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';

class VideoLuckyGenerationDependencies {
  const VideoLuckyGenerationDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.jobNotifications,
    required this.navigation,
    required this.autoPrompts,
    required this.imageModels,
    required this.videoAssets,
    required this.videoSettings,
    required this.promptLibrary,
    required this.generationJobs,
    required this.registerQueuedJob,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final JobNotificationService jobNotifications;
  final AppNavigationController navigation;
  final AutoPromptController autoPrompts;
  final ImageModelSelectionStore imageModels;
  final VideoAssetSelectionStore videoAssets;
  final VideoGenerationSettingsStore videoSettings;
  final PromptLibraryStore promptLibrary;
  final GenerationJobFactory generationJobs;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function() notifyChanged;
}

class VideoLuckyGenerationController {
  VideoLuckyGenerationController(this.dependencies);

  final VideoLuckyGenerationDependencies dependencies;

  Future<ImageRecord?> generate() async {
    final request = _validatedRequest();
    if (request == null) {
      return null;
    }

    _startJobRequest();
    dependencies.navigation.announceQueuedJob(
      'Feeling Lucky video workflow was accepted and added to the queue.',
    );
    try {
      await dependencies.jobNotifications.ensurePermission();
      final promptStep = dependencies.autoPrompts.createLuckyPromptChainStep(
        stepId: 'lucky_prompt',
      );
      if (promptStep == null) {
        return null;
      }
      final videoPromptStep = dependencies.autoPrompts
          .createLuckyImageToVideoPromptChainStep(
            stepId: 'lucky_video_prompt',
            boundImageStepId: 'lucky_image',
          );
      if (videoPromptStep == null) {
        return null;
      }
      final imageStep = JobChainStep(
        id: 'lucky_image',
        type: 'generate',
        payload: dependencies.generationJobs.imageGenerationPayload(
          prompt: '',
          defaultPositivePrompt:
              dependencies.promptLibrary.selectedImagePreset?.positivePrompt ??
              '',
          defaultNegativePrompt:
              dependencies.promptLibrary.selectedImagePreset?.negativePrompt ??
              '',
          modelId: request.imageSelection.modelId,
          loras: request.imageSelection.loras,
        ),
        bindings: {
          'prompt': JobChainBinding(
            stepId: promptStep.id,
            output: 'result_text',
          ),
        },
      );
      final videoStep = JobChainStep(
        id: 'lucky_video',
        type: 'animate_image',
        payload: dependencies.generationJobs.videoGenerationPayload(
          prompt: '',
          defaultPositivePrompt:
              dependencies.promptLibrary.selectedVideoPreset?.positivePrompt ??
              '',
          defaultNegativePrompt:
              dependencies.promptLibrary.selectedVideoPreset?.negativePrompt ??
              '',
          presetId: request.preset.id,
          settings: request.settings,
          imageToVideo: true,
        ),
        bindings: {
          'image_id': JobChainBinding(
            stepId: imageStep.id,
            output: 'result_image_id',
          ),
          'prompt': JobChainBinding(
            stepId: videoPromptStep.id,
            output: 'result_text',
          ),
        },
      );
      final videoJob = await request.client.createChainJob(
        steps: <JobChainStep>[
          promptStep,
          imageStep,
          videoPromptStep,
          videoStep,
        ],
      );
      final queuedVideo = dependencies.registerQueuedJob(videoJob);
      _setMessage(
        'Feeling Lucky video workflow is queued and will continue automatically.',
      );
      return queuedVideo;
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the Feeling Lucky video workflow. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  _LuckyVideoRequest? _validatedRequest() {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    final imageSelection = dependencies.imageModels
        .createRandomGenerationSelection();
    if (imageSelection == null) {
      return null;
    }
    if (!_hasImageToVideoModel()) {
      _setMessage('Image-to-video is not available on the server.');
      return null;
    }
    final preset = dependencies.videoAssets.selectedPreset;
    if (preset == null) {
      _setMessage('No video preset is available from the server.');
      return null;
    }
    final settings = dependencies.videoSettings.currentSettings;
    if (settings == null) {
      _setMessage(
        dependencies.videoSettings.validationMessage ??
            'Enter valid width, height, FPS, and frame count.',
      );
      return null;
    }
    return _LuckyVideoRequest(
      client: client,
      imageSelection: imageSelection,
      preset: preset,
      settings: settings,
    );
  }

  bool _hasImageToVideoModel() {
    return dependencies.videoAssets.videoModels.any(
      (item) => item.id == 'comfy-image-to-video',
    );
  }

  void _startJobRequest() {
    dependencies.activity.runningJob = true;
    dependencies.jobRuntime.latestJob = null;
    dependencies.connection.message = null;
    dependencies.notifyChanged();
  }

  void _finishJobRequest() {
    dependencies.activity.runningJob =
        dependencies.jobRuntime.latestJob?.canCancel ?? false;
    dependencies.notifyChanged();
  }

  void _setMessage(String message) {
    dependencies.connection.message = message;
    dependencies.notifyChanged();
  }

  void _setRequestError(Object error, String generalMessage) {
    dependencies.connection.message = requestErrorMessage(
      error,
      generalMessage: generalMessage,
    );
  }
}

class _LuckyVideoRequest {
  const _LuckyVideoRequest({
    required this.client,
    required this.imageSelection,
    required this.preset,
    required this.settings,
  });

  final ApiClient client;
  final RandomImageGenerationSelection imageSelection;
  final VideoPresetOption preset;
  final Map<String, int> settings;
}
