import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/shared/media_image_errors.dart';

typedef AppCrashReportDirectoryResolver = Future<Directory> Function();

class AppCrashReportStore {
  AppCrashReportStore({
    AppCrashReportDirectoryResolver? directoryResolver,
    DateTime Function()? now,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  static final AppCrashReportStore instance = AppCrashReportStore();

  final AppCrashReportDirectoryResolver _directoryResolver;
  final DateTime Function() _now;

  Directory? _reportsDirectory;
  String? _lastFingerprint;
  DateTime? _lastLoggedAt;

  Future<void> initialize() async {
    if (_reportsDirectory != null) {
      return;
    }
    final baseDirectory = await _directoryResolver();
    final reportsDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}crash_reports',
    );
    reportsDirectory.createSync(recursive: true);
    _reportsDirectory = reportsDirectory;
  }

  void recordFlutterError(FlutterErrorDetails details) {
    if (isRecoverableCachedImageLoadError(details.exception)) {
      return;
    }
    FlutterError.presentError(details);
    _writeReportSync(
      captureSource: 'flutter_framework',
      statusText: 'Unhandled Flutter framework exception',
      errorText: details.exceptionAsString(),
      stackTraceText: details.stack?.toString(),
      payload: <String, dynamic>{
        if ((details.library ?? '').trim().isNotEmpty)
          'library': details.library!.trim(),
        if (details.context != null)
          'context': details.context!.toDescription(),
        'silent': details.silent,
      },
    );
  }

  bool recordPlatformError(Object error, StackTrace stackTrace) {
    if (isRecoverableCachedImageLoadError(error)) {
      return true;
    }
    _writeReportSync(
      captureSource: 'platform_dispatcher',
      statusText: 'Unhandled platform dispatcher exception',
      errorText: error.toString(),
      stackTraceText: stackTrace.toString(),
    );
    return false;
  }

  void recordZoneError(Object error, StackTrace stackTrace) {
    if (isRecoverableCachedImageLoadError(error)) {
      return;
    }
    _writeReportSync(
      captureSource: 'zone',
      statusText: 'Unhandled zone exception',
      errorText: error.toString(),
      stackTraceText: stackTrace.toString(),
    );
  }

  Future<List<AppErrorRecord>> listReports() async {
    await initialize();
    final directory = _reportsDirectory;
    if (directory == null || !directory.existsSync()) {
      return <AppErrorRecord>[];
    }
    final reports = <AppErrorRecord>[];
    for (final entity in directory.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(entity.readAsStringSync(encoding: utf8));
        if (decoded is Map<String, dynamic>) {
          reports.add(AppErrorRecord.fromJson(decoded));
        }
      } catch (_) {
        continue;
      }
    }
    reports.sort((left, right) => right.loggedAt.compareTo(left.loggedAt));
    return reports;
  }

  Future<int> clearReports() async {
    await initialize();
    final directory = _reportsDirectory;
    if (directory == null || !directory.existsSync()) {
      return 0;
    }
    var deleted = 0;
    for (final entity in directory.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        entity.deleteSync();
        deleted += 1;
      } on FileSystemException {
        continue;
      }
    }
    return deleted;
  }

  void _writeReportSync({
    required String captureSource,
    required String statusText,
    required String errorText,
    String? stackTraceText,
    Map<String, dynamic>? payload,
  }) {
    final directory = _reportsDirectory;
    if (directory == null) {
      return;
    }

    final trimmedError = errorText.trim();
    final trimmedStack = stackTraceText?.trim();
    final fingerprint = '$captureSource\n$trimmedError\n${trimmedStack ?? ''}';
    final now = _now().toUtc();
    if (_isDuplicate(fingerprint, now)) {
      return;
    }

    final loggedAt = now.toIso8601String();
    final reportId =
        '${loggedAt.replaceAll(':', '').replaceAll('-', '')}_app_crash';
    final entry = <String, dynamic>{
      'id': reportId,
      'logged_at': loggedAt,
      'source': 'app',
      'report_type': 'crash',
      'error_text': trimmedError,
      if (trimmedStack != null && trimmedStack.isNotEmpty)
        'stack_trace': trimmedStack,
      'job': <String, dynamic>{
        'job_id': reportId,
        'type': 'app_crash',
        'status': 'crashed',
        'progress': 1.0,
        'status_text': statusText,
        'cancel_requested': false,
        'cancel_requested_at': null,
        'cancelled_at': null,
        'created_at': loggedAt,
        'updated_at': loggedAt,
        'payload': <String, dynamic>{
          'capture_source': captureSource,
          ...?payload,
        },
      },
    };

    try {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$reportId.json',
      );
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(entry),
        encoding: utf8,
        flush: true,
      );
      _lastFingerprint = fingerprint;
      _lastLoggedAt = now;
    } on FileSystemException {
      return;
    }
  }

  bool _isDuplicate(String fingerprint, DateTime now) {
    if (_lastFingerprint != fingerprint || _lastLoggedAt == null) {
      return false;
    }
    return now.difference(_lastLoggedAt!) <= const Duration(seconds: 2);
  }
}
