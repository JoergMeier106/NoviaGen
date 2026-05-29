import '../../models/jobs.dart';
import '../../models/media.dart';
import '../app_navigation_state.dart';
import '../auto_prompt_state.dart';
import '../generation_job_factory.dart';
import '../generation_source_state.dart';
import '../image_model_selection_state.dart';
import '../job_notification_state.dart';
import '../prompt_library_state.dart';
import '../request_errors.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';

class AppImageGenerationDependencies {
  const AppImageGenerationDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.jobNotifications,
    required this.navigation,
    required this.autoPrompts,
    required this.imageModels,
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
  final ImageModelSelectionState imageModels;
  final PromptLibraryState promptLibrary;
  final GenerationJobFactory generationJobs;
  final GenerationSourceState generationSources;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function() notifyChanged;
}

class AppImageGenerationController {
  AppImageGenerationController(this.dependencies);

  final AppImageGenerationDependencies dependencies;

  Future<ImageRecord?> generate(String prompt) async {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    final modelId = dependencies.imageModels.selectedModelId;
    if (modelId == null || modelId.isEmpty) {
      _setMessage('Select a model first.');
      return null;
    }

    _startJobRequest();
    try {
      await dependencies.jobNotifications.ensurePermission();
      final hasPendingPrompt = dependencies.autoPrompts.hasPendingPrompt(
        forVideo: false,
      );
      _announceQueuedBehindPrompt(hasPendingPrompt);
      final resolvedPrompt = await _resolvePrompt(prompt);
      if (resolvedPrompt == null) {
        return null;
      }
      final queuedJob = await dependencies.generationJobs
          .queueImageGenerationJob(
            client: client,
            prompt: resolvedPrompt,
            defaultPositivePrompt:
                dependencies
                    .promptLibrary
                    .selectedImagePreset
                    ?.positivePrompt ??
                '',
            defaultNegativePrompt:
                dependencies
                    .promptLibrary
                    .selectedImagePreset
                    ?.negativePrompt ??
                '',
            modelId: modelId,
            loras: dependencies.imageModels.selectedLoras,
            sourceImage: dependencies.generationSources.imageSource,
            localSource: dependencies.generationSources.imageLocalSource,
          );
      return dependencies.registerQueuedJob(
        queuedJob,
        queuedMessage: hasPendingPrompt
            ? null
            : 'Image generation was added to the queue and will start soon.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the image job. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<ImageRecord?> generateFeelingLucky() async {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    final luckySelection = dependencies.imageModels
        .createRandomGenerationSelection();
    if (luckySelection == null) {
      return null;
    }

    dependencies.navigation.announceQueuedJob(
      'Feeling Lucky image workflow was accepted and added to the queue.',
    );
    final luckyPrompt = await dependencies.autoPrompts.generateLuckyPrompt();
    if (luckyPrompt == null) {
      return null;
    }

    _startJobRequest();
    try {
      await dependencies.jobNotifications.ensurePermission();
      final queuedJob = await dependencies.generationJobs
          .queueImageGenerationJob(
            client: client,
            prompt: luckyPrompt,
            defaultPositivePrompt:
                dependencies
                    .promptLibrary
                    .selectedImagePreset
                    ?.positivePrompt ??
                '',
            defaultNegativePrompt:
                dependencies
                    .promptLibrary
                    .selectedImagePreset
                    ?.negativePrompt ??
                '',
            modelId: luckySelection.modelId,
            loras: luckySelection.loras,
            sourceImage: dependencies.generationSources.imageSource,
            localSource: dependencies.generationSources.imageLocalSource,
          );
      final result = dependencies.registerQueuedJob(queuedJob);
      _setMessage('Feeling Lucky image workflow is queued.');
      return result;
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the Feeling Lucky image job. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<String?> _resolvePrompt(String prompt) {
    return dependencies.autoPrompts.resolvePromptForQueuedGeneration(
      forVideo: false,
      submittedPrompt: prompt,
    );
  }

  void _announceQueuedBehindPrompt(bool hasPendingPrompt) {
    if (!hasPendingPrompt) {
      return;
    }
    dependencies.navigation.announceQueuedJob(
      'Image generation was accepted and will queue after the pending auto-prompt job finishes.',
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
