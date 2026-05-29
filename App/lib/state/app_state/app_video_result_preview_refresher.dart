import '../../models/jobs.dart';
import '../../models/media.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppVideoResultPreviewDependencies {
  const AppVideoResultPreviewDependencies({
    required this.connection,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.replaceJob,
    required this.replaceGalleryItem,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final void Function(JobStatus job) replaceJob;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function() notifyChanged;
}

class AppVideoResultPreviewRefresher {
  const AppVideoResultPreviewRefresher(this.dependencies);

  final AppVideoResultPreviewDependencies dependencies;

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
