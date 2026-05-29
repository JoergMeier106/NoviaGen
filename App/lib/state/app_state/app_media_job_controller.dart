import '../../models/jobs.dart';
import '../../models/media.dart';
import '../generation_defaults_state.dart';
import '../job_notification_state.dart';
import '../request_errors.dart';
import '../video_regeneration_job_factory.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';
import 'runtime/app_scaling_preferences_state.dart';

class AppMediaJobDependencies {
  const AppMediaJobDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.scalingPreferences,
    required this.generationDefaults,
    required this.jobNotifications,
    required this.videoRegenerationJobs,
    required this.registerQueuedJob,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final AppScalingPreferencesState scalingPreferences;
  final GenerationDefaultsState generationDefaults;
  final JobNotificationState jobNotifications;
  final VideoRegenerationJobFactory videoRegenerationJobs;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function() notifyChanged;
}

class AppMediaJobController {
  AppMediaJobController(this.dependencies);

  final AppMediaJobDependencies dependencies;

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
