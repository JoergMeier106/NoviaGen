import '../job_notifications.dart';
import '../models/jobs.dart';
class JobNotificationState {
  JobNotificationController? _notifications;
  String? _runningNotificationJobId;

  void attach(JobNotificationController notifications) {
    _notifications = notifications;
  }

  Future<void> ensurePermission() async {
    await _notifications?.ensurePermission();
  }

  Future<void> showRunningJob(JobStatus job) async {
    final notifications = _notifications;
    if (notifications == null) {
      return;
    }
    _runningNotificationJobId = job.jobId;
    await notifications.showRunningJob(job);
  }

  Future<void> showTerminalJob(JobStatus job) async {
    await _notifications?.showTerminalJob(job);
  }

  Future<void> cancelRunningJob({String? jobId}) async {
    if (jobId != null && _runningNotificationJobId != jobId) {
      return;
    }
    final notifications = _notifications;
    if (notifications == null) {
      return;
    }
    _runningNotificationJobId = null;
    await notifications.cancelRunningJob();
  }
}
