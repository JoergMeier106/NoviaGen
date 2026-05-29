import '../../api_client.dart';
import '../../models/assets.dart';
import '../../models/jobs.dart';
import '../../models/media.dart';
import '../app_navigation_state.dart';
import '../auto_prompt_state.dart';
import '../generation_job_factory.dart';
import '../generation_source_state.dart';
import '../job_notification_state.dart';
import '../prompt_library_state.dart';
import '../request_errors.dart';
import '../video_asset_selection_state.dart';
import '../video_generation_settings_state.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';

class AppVideoGenerationDependencies {
  const AppVideoGenerationDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.jobNotifications,
    required this.navigation,
    required this.autoPrompts,
    required this.videoAssets,
    required this.videoSettings,
    required this.promptLibrary,
    required this.generationJobs,
    required this.generationSources,
    required this.registerQueuedJob,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final JobNotificationState jobNotifications;
  final AppNavigationState navigation;
  final AutoPromptState autoPrompts;
  final VideoAssetSelectionState videoAssets;
  final VideoGenerationSettingsState videoSettings;
  final PromptLibraryState promptLibrary;
  final GenerationJobFactory generationJobs;
  final GenerationSourceState generationSources;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function() notifyChanged;
}

class AppVideoGenerationController {
  AppVideoGenerationController(this.dependencies);

  final AppVideoGenerationDependencies dependencies;

  Future<ImageRecord?> submit(String prompt) async {
    final request = _validatedRequest();
    if (request == null) {
      return null;
    }

    _startJobRequest();
    try {
      await dependencies.jobNotifications.ensurePermission();
      final hasPendingPrompt = dependencies.autoPrompts.hasPendingPrompt(
        forVideo: true,
      );
      _announceQueuedBehindPrompt(hasPendingPrompt);
      final resolvedPrompt = await dependencies.autoPrompts
          .resolvePromptForQueuedGeneration(
            forVideo: true,
            submittedPrompt: prompt,
          );
      if (resolvedPrompt == null) {
        return null;
      }
      final queuedJob = await dependencies.generationJobs
          .queueVideoGenerationJob(
            client: request.client,
            prompt: resolvedPrompt,
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
            storedSource: dependencies.generationSources.videoSource,
            localSource: dependencies.generationSources.videoLocalSource,
          );
      return dependencies.registerQueuedJob(
        queuedJob,
        queuedMessage: hasPendingPrompt
            ? null
            : 'Video generation was added to the queue and will start soon.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the video job. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<ImageRecord?> generate(String prompt) {
    dependencies.generationSources.clearVideoSource();
    return submit(prompt);
  }

  Future<ImageRecord?> animateImage(ImageRecord image, String prompt) async {
    if (image.isVideo) {
      _setMessage('Only stored images or GIFs can be animated.');
      return null;
    }
    dependencies.generationSources.setStoredVideoSource(image);
    return submit(prompt);
  }

  _VideoGenerationRequest? _validatedRequest() {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    if (dependencies.videoAssets.videoModels.isEmpty) {
      _setMessage('No video model is available on the server.');
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
    return _VideoGenerationRequest(
      client: client,
      preset: preset,
      settings: settings,
    );
  }

  void _announceQueuedBehindPrompt(bool hasPendingPrompt) {
    if (!hasPendingPrompt) {
      return;
    }
    dependencies.navigation.announceQueuedJob(
      'Video generation was accepted and will queue after the pending auto-prompt job finishes.',
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

class _VideoGenerationRequest {
  const _VideoGenerationRequest({
    required this.client,
    required this.preset,
    required this.settings,
  });

  final ApiClient client;
  final VideoPresetOption preset;
  final Map<String, int> settings;
}
