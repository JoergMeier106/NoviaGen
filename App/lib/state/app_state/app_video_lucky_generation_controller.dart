import 'dart:async';

import '../../api_client.dart';
import '../../models/assets.dart';
import '../../models/jobs.dart';
import '../../models/media.dart';
import '../app_navigation_state.dart';
import '../auto_prompt_state.dart';
import '../generation_job_factory.dart';
import '../image_model_selection_state.dart';
import '../job_notification_state.dart';
import '../prompt_library_state.dart';
import '../request_errors.dart';
import '../system_operations_state.dart';
import '../video_asset_selection_state.dart';
import '../video_generation_settings_state.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';


class AppVideoLuckyGenerationDependencies {
  const AppVideoLuckyGenerationDependencies({
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
    required this.system,
    required this.registerQueuedJob,
    required this.waitForTerminalState,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final JobNotificationState jobNotifications;
  final AppNavigationState navigation;
  final AutoPromptState autoPrompts;
  final ImageModelSelectionState imageModels;
  final VideoAssetSelectionState videoAssets;
  final VideoGenerationSettingsState videoSettings;
  final PromptLibraryState promptLibrary;
  final GenerationJobFactory generationJobs;
  final SystemOperationsState system;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final Future<JobStatus?> Function(String jobId) waitForTerminalState;
  final void Function() notifyChanged;
}

class AppVideoLuckyGenerationController {
  AppVideoLuckyGenerationController(this.dependencies);

  final AppVideoLuckyGenerationDependencies dependencies;

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
      final sourceImage = await _generateSourceImage(request);
      if (sourceImage == null) {
        return null;
      }

      final videoPrompt = await dependencies.autoPrompts
          .generateLuckyImageToVideoPrompt(imageId: sourceImage.id);
      if (videoPrompt == null) {
        return null;
      }

      final videoJob = await dependencies.generationJobs
          .queueVideoGenerationJob(
            client: request.client,
            prompt: videoPrompt,
            defaultPositivePrompt:
                dependencies
                    .promptLibrary
                    .selectedVideoPreset
                    ?.positivePrompt ??
                '',
            defaultNegativePrompt:
                dependencies
                    .promptLibrary
                    .selectedVideoPreset
                    ?.negativePrompt ??
                '',
            presetId: request.preset.id,
            settings: request.settings,
            storedSource: sourceImage,
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

  Future<ImageRecord?> _generateSourceImage(_LuckyVideoRequest request) async {
    final prompt = await dependencies.autoPrompts.generateLuckyPrompt();
    if (prompt == null) {
      return null;
    }

    final imageJob = await dependencies.generationJobs.queueImageGenerationJob(
      client: request.client,
      prompt: prompt,
      defaultPositivePrompt:
          dependencies.promptLibrary.selectedImagePreset?.positivePrompt ?? '',
      defaultNegativePrompt:
          dependencies.promptLibrary.selectedImagePreset?.negativePrompt ?? '',
      modelId: request.imageSelection.modelId,
      loras: request.imageSelection.loras,
    );
    dependencies.registerQueuedJob(imageJob);

    final completedJob = await dependencies.waitForTerminalState(
      imageJob.jobId,
    );
    return _completedSourceImage(completedJob);
  }

  ImageRecord? _completedSourceImage(JobStatus? completedJob) {
    final completedImage = completedJob?.result;
    if (completedJob?.status == 'completed' &&
        completedImage != null &&
        completedImage.isReady) {
      return completedImage;
    }
    _handleIncompleteSourceImage(completedJob);
    return null;
  }

  void _handleIncompleteSourceImage(JobStatus? completedJob) {
    if (completedJob?.status == 'failed') {
      unawaited(dependencies.system.loadErrors(silent: true));
    }
    dependencies.connection.message = completedJob?.status == 'cancelled'
        ? 'Feeling Lucky video was cancelled before the image stage finished.'
        : 'Feeling Lucky video couldn\'t continue because the image stage did not complete successfully.';
    dependencies.notifyChanged();
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
