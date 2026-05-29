import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/app/runtime/app_crash_report_store.dart';
import 'package:noviagen/features/settings/system/system_operations_controller.dart';
import 'package:noviagen/models/jobs.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.errorResponse, required this.deletedCount})
    : super('http://example.test');

  final List<AppErrorRecord> errorResponse;
  final int deletedCount;

  @override
  Future<List<AppErrorRecord>> fetchErrors() async => errorResponse;

  @override
  Future<int> clearErrors() async => deletedCount;
}

void main() {
  test('crash report store records and clears app crash reports', () async {
    final runtimeDirectory = Directory.systemTemp.createTempSync(
      'noviagen-crash-store-',
    );
    addTearDown(() => runtimeDirectory.deleteSync(recursive: true));
    final store = AppCrashReportStore(
      directoryResolver: () async => runtimeDirectory,
      now: () => DateTime.utc(2026, 5, 10, 12, 30, 0),
    );

    await store.initialize();
    store.recordZoneError(
      StateError('boom'),
      StackTrace.fromString('stack line 1\nstack line 2'),
    );

    final reports = await store.listReports();
    expect(reports, hasLength(1));
    expect(reports.single.isAppCrashReport, isTrue);
    expect(reports.single.errorText, contains('boom'));
    expect(reports.single.stackTraceText, contains('stack line 1'));

    final deleted = await store.clearReports();
    expect(deleted, 1);
    expect(await store.listReports(), isEmpty);
  });

  test(
    'crash report store treats empty cached image files as recoverable',
    () async {
      final runtimeDirectory = Directory.systemTemp.createTempSync(
        'noviagen-image-cache-error-',
      );
      addTearDown(() => runtimeDirectory.deleteSync(recursive: true));
      final store = AppCrashReportStore(
        directoryResolver: () async => runtimeDirectory,
        now: () => DateTime.utc(2026, 5, 10, 12, 30, 0),
      );
      await store.initialize();

      final handled = store.recordPlatformError(
        StateError(
          "LocalFile: '/data/user/0/com.noviagen.app/cache/"
          "libCachedImageData/image.png' is empty and cannot be loaded "
          'as an image.',
        ),
        StackTrace.fromString('stack'),
      );

      expect(handled, isTrue);
      expect(await store.listReports(), isEmpty);
    },
  );

  test(
    'system operations merges app crash reports with server errors',
    () async {
      final runtimeDirectory = Directory.systemTemp.createTempSync(
        'noviagen-system-errors-',
      );
      addTearDown(() => runtimeDirectory.deleteSync(recursive: true));
      final crashReports = AppCrashReportStore(
        directoryResolver: () async => runtimeDirectory,
        now: () => DateTime.utc(2026, 5, 10, 12, 30, 0),
      );
      await crashReports.initialize();
      crashReports.recordPlatformError(
        StateError('app crashed'),
        StackTrace.fromString('stack'),
      );

      final api = _FakeApiClient(
        deletedCount: 2,
        errorResponse: <AppErrorRecord>[
          AppErrorRecord(
            id: 'server-error',
            loggedAt: '2026-05-10T12:00:00Z',
            source: 'server',
            reportType: 'error',
            errorText: 'server boom',
            jobId: 'job-123',
            jobType: 'generate',
            jobStatus: 'failed',
            jobProgress: 1.0,
            jobStatusText: 'Generation failed',
            cancelRequested: false,
            jobPayload: const <String, dynamic>{'prompt': 'demo'},
          ),
        ],
      );

      String? message;
      var changedCount = 0;
      final controller = SystemOperationsController(
        api: () => api,
        crashReports: crashReports,
        setMessage: (value) => message = value,
        onChanged: () => changedCount += 1,
        refreshAssets: () async {},
        clearGenerationSources: () async {},
        setLatestJob: (_) {},
        setLatestImage: (_) {},
        resetLaunchJobRestore: () {},
        loadGalleryFirstPage: () async {},
        loadJobs: () async {},
        loadLatestResult: ({silent = false}) async {},
        loadSettings: () async {},
      );

      await controller.loadErrors();

      expect(changedCount, greaterThan(0));
      expect(controller.errors, hasLength(2));
      expect(controller.errors.first.isAppCrashReport, isTrue);
      expect(controller.errors.last.jobId, 'job-123');

      await controller.clearErrors();

      expect(controller.errors, isEmpty);
      expect(message, '3 reports cleared.');
      expect(await crashReports.listReports(), isEmpty);
    },
  );
}
