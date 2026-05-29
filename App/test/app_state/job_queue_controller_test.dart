import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/state/app_navigation_state.dart';
import 'package:flutter_app/state/app_state/app_job_queue_controller.dart';
import 'package:flutter_app/state/app_state/runtime/app_activity_state.dart';
import 'package:flutter_app/state/app_state/runtime/app_connection_state.dart';
import 'package:flutter_app/state/app_state/runtime/app_job_runtime_state.dart';
import 'package:flutter_app/state/app_state/runtime/app_media_runtime_state.dart';

void main() {
  test('legacy queue registration swallows accepted-job polling failures', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final controller = AppJobQueueController(
        AppJobQueueDependencies(
          connection: AppConnectionState(),
          activity: AppActivityState(),
          jobRuntime: AppJobRuntimeState(),
          mediaRuntime: AppMediaRuntimeState(),
          navigation: () => AppNavigationState(onChanged: () {}),
          replaceJob: (_) {},
          replaceGalleryItem: (_) {},
          syncMediaRefreshTimer: () {},
          pollJob: (_, {expectedResultImageId}) async {
            throw StateError('background poll failed');
          },
          notifyChanged: () {},
        ),
      );

      controller.registerQueuedJob(_jobStatus());
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) {
      errors.add(error);
    });

    expect(errors, isEmpty);
  });
}

JobStatus _jobStatus() {
  return JobStatus(
    jobId: 'queued-job',
    type: 'generate_video',
    parentJobId: null,
    chainStepId: null,
    status: 'queued',
    progress: 0,
    statusText: 'Queued',
    cancelRequested: false,
    payload: const <String, dynamic>{},
  );
}
