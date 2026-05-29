import 'dart:io';

import 'package:flutter/services.dart';

import 'package:noviagen/job_text.dart';
import 'package:noviagen/models/jobs.dart';
class JobNotificationController {
  static const MethodChannel _channel = MethodChannel(
    'noviagen/job_notifications',
  );

  bool _isInitialized = false;
  void Function()? _onOpenGeneratePage;
  void Function(String mediaId)? _onOpenMediaDetail;
  String? _lastRunningNotificationKey;

  Future<void> initialize({
    required void Function() onOpenGeneratePage,
    required void Function(String mediaId) onOpenMediaDetail,
  }) async {
    if (!Platform.isAndroid || _isInitialized) {
      _onOpenGeneratePage = onOpenGeneratePage;
      _onOpenMediaDetail = onOpenMediaDetail;
      return;
    }

    _onOpenGeneratePage = onOpenGeneratePage;
    _onOpenMediaDetail = onOpenMediaDetail;
    _channel.setMethodCallHandler(_handleMethodCall);
    _isInitialized = true;

    try {
      final pendingMediaId = await _channel.invokeMethod<String>(
        'consumePendingMediaDetailOpen',
      );
      if (pendingMediaId != null && pendingMediaId.trim().isNotEmpty) {
        _onOpenMediaDetail?.call(pendingMediaId.trim());
        return;
      }
      final shouldOpen =
          await _channel.invokeMethod<bool>('consumePendingGenerateOpen') ??
          false;
      if (shouldOpen) {
        _onOpenGeneratePage?.call();
      }
    } on PlatformException {
      // Notifications are optional. Ignore bridge failures.
    }
  }

  Future<void> ensurePermission() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('requestNotificationPermission');
    } on PlatformException {
      // Ignore permission bridge failures and keep the job flow running.
    }
  }

  Future<void> showRunningJob(JobStatus job) async {
    if (!Platform.isAndroid) {
      return;
    }
    final progress = (job.progress.clamp(0.0, 1.0) * 100).round();
    final startedAtMillis = jobStartedAt(job)?.millisecondsSinceEpoch;
    final notificationKey =
        '${job.jobId}|${job.status}|${jobStatusText(job)}|${jobProgressText(job)}|$progress|${startedAtMillis ?? 0}';
    if (_lastRunningNotificationKey == notificationKey) {
      return;
    }
    _lastRunningNotificationKey = notificationKey;
    try {
      await _channel.invokeMethod<void>('showJobProgress', <String, dynamic>{
        'title': jobTitleText(job),
        'status_text': jobStatusText(job),
        'progress_text': jobProgressText(job),
        'progress': progress,
        'started_at_millis': startedAtMillis,
      });
    } on PlatformException {
      // Ignore notification failures and keep the job flow running.
    }
  }

  Future<void> showTerminalJob(JobStatus job) async {
    if (!Platform.isAndroid) {
      return;
    }
    _lastRunningNotificationKey = null;
    try {
      final result = job.status == 'completed' ? job.result : null;
      await _channel.invokeMethod<void>('showJobCompletion', <String, dynamic>{
        'title': jobCompletionNotificationTitle(job),
        'body': jobCompletionNotificationBody(job),
        if (result?.id.trim().isNotEmpty ?? false) 'media_id': result!.id,
      });
    } on PlatformException {
      // Ignore notification failures and keep the job flow running.
    }
  }

  Future<void> cancelRunningJob() async {
    if (!Platform.isAndroid) {
      return;
    }
    _lastRunningNotificationKey = null;
    try {
      await _channel.invokeMethod<void>('cancelJobProgress');
    } on PlatformException {
      // Ignore notification failures and keep the job flow running.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'openGenerate') {
      _onOpenGeneratePage?.call();
    } else if (call.method == 'openMediaDetail') {
      final mediaId = _mediaIdFromArguments(call.arguments);
      if (mediaId != null) {
        _onOpenMediaDetail?.call(mediaId);
      }
    }
  }

  String? _mediaIdFromArguments(Object? arguments) {
    if (arguments is String && arguments.trim().isNotEmpty) {
      return arguments.trim();
    }
    if (arguments is Map) {
      final mediaId = arguments['media_id'];
      if (mediaId is String && mediaId.trim().isNotEmpty) {
        return mediaId.trim();
      }
    }
    return null;
  }
}
