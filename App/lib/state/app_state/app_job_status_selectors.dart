import '../../models/jobs.dart';
import '../../models/media.dart';
JobStatus? firstActiveJob(Iterable<JobStatus> jobs) {
  for (final job in jobs) {
    if (job.status == 'running') {
      return job;
    }
  }
  for (final job in jobs) {
    if (job.status == 'queued') {
      return job;
    }
  }
  return null;
}

ImageRecord? latestReadyJobResult(Iterable<JobStatus> jobs) {
  for (final job in jobs) {
    final result = job.result;
    if (result?.isReady ?? false) {
      return result;
    }
  }
  return null;
}
