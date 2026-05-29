import 'package:flutter/material.dart';


enum LogSource { server, comfy }

enum LogSeverityFilter { all, info, warn, error }

String logSourceKey(LogSource source) {
  return source == LogSource.comfy ? 'comfy' : 'server';
}

LogSource logSourceFromName(String value) {
  return value == 'comfy' ? LogSource.comfy : LogSource.server;
}

LogSeverityFilter logSeverityFilterFromName(String value) {
  switch (value) {
    case 'info':
      return LogSeverityFilter.info;
    case 'warn':
      return LogSeverityFilter.warn;
    case 'error':
      return LogSeverityFilter.error;
    default:
      return LogSeverityFilter.all;
  }
}

String logSeverityFilterLabel(LogSeverityFilter filter) {
  switch (filter) {
    case LogSeverityFilter.all:
      return 'All';
    case LogSeverityFilter.info:
      return 'Info';
    case LogSeverityFilter.warn:
      return 'Warn';
    case LogSeverityFilter.error:
      return 'Error';
  }
}

String normalizedLogLevel(String? level) {
  final normalized = (level ?? '').trim().toLowerCase();
  if (normalized == 'warning') {
    return 'warn';
  }
  if (normalized == 'fatal' ||
      normalized == 'critical' ||
      normalized == 'exception' ||
      normalized == 'traceback') {
    return 'error';
  }
  return normalized;
}

String logLevelLabel(String? level) {
  switch (normalizedLogLevel(level)) {
    case 'warn':
      return 'Warn';
    case 'error':
      return 'Error';
    case 'debug':
      return 'Debug';
    case 'info':
      return 'Info';
    default:
      final trimmed = (level ?? '').trim();
      return trimmed.isEmpty ? 'Unknown' : trimmed.toUpperCase();
  }
}

Color logLevelColor(BuildContext context, String? level) {
  final scheme = Theme.of(context).colorScheme;
  switch (normalizedLogLevel(level)) {
    case 'warn':
      return const Color(0xFFC47A00);
    case 'error':
      return scheme.error;
    case 'debug':
      return scheme.secondary;
    case 'info':
      return scheme.primary;
    default:
      return scheme.onSurfaceVariant;
  }
}
