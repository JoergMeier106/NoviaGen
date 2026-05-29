import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/generate/controllers/auto_prompt_controller.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/services/generation_job_factory.dart';
import 'package:flutter_app/features/jobs/services/job_notification_service.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/generate/services/video_regeneration_job_factory.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';
import 'package:flutter_app/app/runtime/scaling_preferences_store.dart';

class MediaJobDependencies {
  const MediaJobDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.scalingPreferences,
    required this.generationDefaults,
    required this.jobNotifications,
    required this.autoPrompts,
    required this.promptLibrary,
    required this.generationJobs,
    required this.videoAssets,
    required this.videoSettings,
    required this.videoRegenerationJobs,
    required this.registerQueuedJob,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final ScalingPreferencesStore scalingPreferences;
  final GenerationDefaultsStore generationDefaults;
  final JobNotificationService jobNotifications;
  final AutoPromptController autoPrompts;
  final PromptLibraryStore promptLibrary;
  final GenerationJobFactory generationJobs;
  final VideoAssetSelectionStore videoAssets;
  final VideoGenerationSettingsStore videoSettings;
  final VideoRegenerationJobFactory videoRegenerationJobs;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function() notifyChanged;
}

class MediaJobController {
  MediaJobController(this.dependencies);

  final MediaJobDependencies dependencies;

  Future<ImageRecord?> regenerateImage(ImageRecord image) async {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    if (!image.isImage) {
      _setMessage('Only images can be regenerated here.');
      return null;
    }

    _startJobRequest(clearLatestJob: true);
    try {
      await dependencies.jobNotifications.ensurePermission();
      final queuedJob = await client.createGenerateJobFromImage(image: image);
      return dependencies.registerQueuedJob(queuedJob);
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the new image job. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<ImageRecord?> upscaleLatest(double scaleFactor) async {
    final image = dependencies.mediaRuntime.latestImage;
    if (image == null) {
      return null;
    }
    return upscaleImage(image, scaleFactor);
  }

  Future<ImageRecord?> upscaleImage(
    ImageRecord image,
    double scaleFactor,
  ) async {
    final client = dependencies.connection.api;
    if (client == null) {
      return null;
    }
    if (!image.canScale) {
      _setMessage(
        'GIFs can be used as source media, but they can\'t be scaled.',
      );
      return null;
    }

    _startJobRequest(clearLatestJob: false);
    try {
      await dependencies.jobNotifications.ensurePermission();
      final queuedJob = image.isVideo
          ? await client.createUpscaleVideoJob(
              imageId: image.id,
              scaleFactor: scaleFactor,
              deleteSourceAfterFinish:
                  dependencies.scalingPreferences.deleteSourceAfterScaling,
            )
          : await client.createUpscaleJob(
              imageId: image.id,
              scaleFactor: scaleFactor,
              numInferenceSteps:
                  dependencies.generationDefaults.numInferenceSteps,
              guidanceScale: dependencies.generationDefaults.guidanceScale,
              deleteSourceAfterFinish:
                  dependencies.scalingPreferences.deleteSourceAfterScaling,
            );
      return dependencies.registerQueuedJob(queuedJob);
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the scaling job. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<ImageRecord?> regenerateVideo(ImageRecord image) async {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    if (!image.isVideo) {
      _setMessage('Only videos can be regenerated here.');
      return null;
    }
    if (image.fps == null || image.numFrames == null) {
      _setMessage(
        'This video is missing FPS or frame data, so it can\'t be regenerated.',
      );
      return null;
    }

    _startJobRequest(clearLatestJob: true);
    try {
      await dependencies.jobNotifications.ensurePermission();
      final queuedJob = await dependencies.videoRegenerationJobs.create(
        client: client,
        image: image,
      );
      return dependencies.registerQueuedJob(queuedJob);
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the new video job. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<ImageRecord?> convertVideoToGif(ImageRecord image) {
    return _queueVideoUtilityJob(
      image: image,
      validationMessage: 'Only videos can be converted to GIF.',
      createJob: (imageId) => dependencies.connection.api!
          .createConvertVideoToGifJob(imageId: imageId),
      failureMessage:
          'Couldn\'t start the GIF conversion right now. Please try again.',
    );
  }

  Future<ImageRecord?> generateAudioVideo(ImageRecord image) {
    return _queueVideoUtilityJob(
      image: image,
      validationMessage: 'Only videos can be used to generate audio video.',
      createJob: (imageId) => dependencies.connection.api!
          .createGenerateAudioVideoJob(imageId: imageId),
      failureMessage:
          'Couldn\'t start the audio video job right now. Please try again.',
    );
  }

  Future<ImageRecord?> createPromptAndAnimateImage(ImageRecord image) async {
    final client = dependencies.connection.api;
    if (client == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    if (!image.isStillImage || !image.isReady) {
      _setMessage('Only ready images or GIFs can be used here.');
      return null;
    }
    if (!dependencies.videoAssets.videoModels.any(
      (item) => item.id == 'comfy-image-to-video',
    )) {
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
    final promptStep = dependencies.autoPrompts
        .createLuckyImageToVideoPromptChainStep(
          stepId: 'gallery_i2v_prompt',
          imageId: image.id,
        );
    if (promptStep == null) {
      return null;
    }

    _startJobRequest(clearLatestJob: true);
    final videoStep = JobChainStep(
      id: 'gallery_i2v_video',
      type: 'animate_image',
      payload: dependencies.generationJobs.videoGenerationPayload(
        prompt: '',
        defaultPositivePrompt:
            dependencies.promptLibrary.selectedVideoPreset?.positivePrompt ??
            '',
        defaultNegativePrompt:
            dependencies.promptLibrary.selectedVideoPreset?.negativePrompt ??
            '',
        presetId: preset.id,
        settings: settings,
        storedSource: image,
      ),
      bindings: {
        'prompt': JobChainBinding(stepId: promptStep.id, output: 'result_text'),
      },
    );
    final chainSteps = <JobChainStep>[promptStep, videoStep];
    try {
      await dependencies.jobNotifications.ensurePermission();
      final queuedJob = await client.createChainJob(steps: chainSteps);
      return dependencies.registerQueuedJob(queuedJob);
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t start the prompt + video generation workflow right now. Please try again.',
      );
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  Future<ImageRecord?> _queueVideoUtilityJob({
    required ImageRecord image,
    required String validationMessage,
    required Future<JobStatus> Function(String imageId) createJob,
    required String failureMessage,
  }) async {
    if (dependencies.connection.api == null) {
      _setMessage('Set a backend URL first.');
      return null;
    }
    if (!image.isVideo) {
      _setMessage(validationMessage);
      return null;
    }

    _startJobRequest(clearLatestJob: true);
    try {
      await dependencies.jobNotifications.ensurePermission();
      final queuedJob = await createJob(image.id);
      return dependencies.registerQueuedJob(queuedJob);
    } catch (error) {
      _setRequestError(error, failureMessage);
      return null;
    } finally {
      _finishJobRequest();
    }
  }

  void _startJobRequest({required bool clearLatestJob}) {
    dependencies.activity.runningJob = true;
    if (clearLatestJob) {
      dependencies.jobRuntime.latestJob = null;
    }
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
