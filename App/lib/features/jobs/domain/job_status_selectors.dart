import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
JobStatus? firstActiveJob(Iterable<JobStatus> jobs) {
  return _firstMatchingActiveJob(
        jobs,
        predicate: (job) => job.isPrimaryWorkflowJob,
      ) ??
      _firstMatchingActiveJob(jobs);
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

JobStatus? firstPrimaryWorkflowJob(Iterable<JobStatus> jobs) {
  for (final job in jobs) {
    if (job.isPrimaryWorkflowJob) {
      return job;
    }
  }
  for (final job in jobs) {
    return job;
  }
  return null;
}

JobStatus? _firstMatchingActiveJob(
  Iterable<JobStatus> jobs, {
  bool Function(JobStatus job)? predicate,
}) {
  for (final job in jobs) {
    if (job.status == 'running' && (predicate == null || predicate(job))) {
      return job;
    }
  }
  for (final job in jobs) {
    if (job.status == 'queued' && (predicate == null || predicate(job))) {
      return job;
    }
  }
  return null;
}
