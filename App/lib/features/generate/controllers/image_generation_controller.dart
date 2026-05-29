import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/app/navigation/app_navigation_controller.dart';
import 'package:noviagen/features/generate/controllers/auto_prompt_controller.dart';
import 'package:noviagen/features/generate/services/generation_job_factory.dart';
import 'package:noviagen/features/generate/state/generation_source_store.dart';
import 'package:noviagen/features/generate/state/image_model_selection_store.dart';
import 'package:noviagen/features/jobs/services/job_notification_service.dart';
import 'package:noviagen/features/prompts/state/prompt_library_store.dart';
import 'package:noviagen/shared/request_errors.dart';
import 'package:noviagen/app/runtime/app_activity_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';

class ImageGenerationDependencies {
  const ImageGenerationDependencies({
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

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final JobNotificationService jobNotifications;
  final AppNavigationController navigation;
  final AutoPromptController autoPrompts;
  final ImageModelSelectionStore imageModels;
  final PromptLibraryStore promptLibrary;
  final GenerationJobFactory generationJobs;
  final GenerationSourceStore generationSources;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function() notifyChanged;
}

class ImageGenerationController {
  ImageGenerationController(this.dependencies);

  final ImageGenerationDependencies dependencies;

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
    final promptStep = dependencies.autoPrompts.createLuckyPromptChainStep(
      stepId: 'lucky_prompt',
    );
    if (promptStep == null) {
      return null;
    }

    _startJobRequest();
    try {
      await dependencies.jobNotifications.ensurePermission();
      final localSource = dependencies.generationSources.imageLocalSource;
      final uploadAlias = localSource == null ? null : 'lucky_source_image';
      final imageStep = JobChainStep(
        id: 'lucky_image',
        type:
            dependencies.generationSources.imageSource != null ||
                localSource != null
            ? 'generate_from_image'
            : 'generate',
        payload: dependencies.generationJobs.imageGenerationPayload(
          prompt: '',
          defaultPositivePrompt:
              dependencies.promptLibrary.selectedImagePreset?.positivePrompt ??
              '',
          defaultNegativePrompt:
              dependencies.promptLibrary.selectedImagePreset?.negativePrompt ??
              '',
          modelId: luckySelection.modelId,
          loras: luckySelection.loras,
          sourceImage: dependencies.generationSources.imageSource,
          uploadRef: uploadAlias,
        ),
        bindings: {
          'prompt': JobChainBinding(
            stepId: promptStep.id,
            output: 'result_text',
          ),
        },
      );
      final queuedJob = await client.createChainJob(
        steps: <JobChainStep>[promptStep, imageStep],
        uploads: localSource == null
            ? const <String, JobChainUpload>{}
            : <String, JobChainUpload>{
                uploadAlias!: JobChainUpload(
                  path: localSource.path,
                  name: localSource.name,
                ),
              },
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
