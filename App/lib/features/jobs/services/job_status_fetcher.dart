import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/shared/request_errors.dart';


class JobStatusFetcher {
  const JobStatusFetcher();

  Future<JobStatus> fetchWithRetry(ApiClient client, String jobId) async {
    var consecutiveFailures = 0;
    while (true) {
      try {
        final job = await client.getJob(jobId);
        consecutiveFailures = 0;
        return job;
      } catch (error) {
        consecutiveFailures += 1;
        if (consecutiveFailures >= 8 ||
            !isConnectionError(error) && !isTimeoutError(error)) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 250 * consecutiveFailures),
        );
      }
    }
  }
}
