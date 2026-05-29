import 'package:flutter_app/models/jobs.dart';
class JobRuntimeStore {
  List<JobStatus> jobs = <JobStatus>[];
  JobStatus? latestJob;
  int interJobDelaySeconds = 0;

  JobStatus? get activeRunningJob {
    for (final job in jobs) {
      if (job.status == 'running' && job.isPrimaryWorkflowJob) {
        return job;
      }
    }
    final job = latestJob;
    return job?.status == 'running' ? job : null;
  }

  JobStatus? jobForImage(String imageId) {
    final latest = latestJob;
    if (latest?.result?.id == imageId) {
      return latest;
    }
    for (final job in jobs) {
      if (job.result?.id == imageId) {
        return job;
      }
    }
    return null;
  }
}
