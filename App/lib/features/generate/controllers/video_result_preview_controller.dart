import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';


class VideoResultPreviewControllerDependencies {
  const VideoResultPreviewControllerDependencies({
    required this.connection,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.replaceJob,
    required this.replaceGalleryItem,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final void Function(JobStatus job) replaceJob;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function() notifyChanged;
}

class VideoResultPreviewController {
  const VideoResultPreviewController(this.dependencies);

  final VideoResultPreviewControllerDependencies dependencies;

  Future<void> refresh(String jobId) async {
    final client = dependencies.connection.api;
    if (client == null) {
      return;
    }
    for (var attempt = 0; attempt < 6; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final job = await client.getJob(jobId);
        final result = job.result;
        if (result == null) {
          continue;
        }
        dependencies.replaceJob(job);
        dependencies.replaceGalleryItem(result);
        if (result.isReady &&
            dependencies.mediaRuntime.latestImage?.id == result.id) {
          dependencies.mediaRuntime.latestImage = result;
        }
        if (dependencies.jobRuntime.latestJob?.jobId == job.jobId) {
          dependencies.jobRuntime.latestJob = job;
        }
        dependencies.notifyChanged();
        if (result.posterUrl != null) {
          break;
        }
      } catch (_) {
        break;
      }
    }
  }
}
