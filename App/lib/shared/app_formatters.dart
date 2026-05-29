import 'dart:convert';

import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/system.dart';
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

String formatOptionalBytes(int? bytes) {
  if (bytes == null || bytes <= 0) {
    return 'Unknown';
  }
  return formatBytes(bytes);
}

String formatOptionalCount(int? value) {
  return value == null || value <= 0 ? 'Unknown' : '$value';
}

String formatOptionalPercent(double? value) {
  if (value == null || value < 0) {
    return 'Unknown';
  }
  final decimals = value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)}%';
}

String formatMemoryPair(int? availableBytes, int? totalBytes) {
  if (availableBytes == null || availableBytes <= 0) {
    return formatOptionalBytes(totalBytes);
  }
  if (totalBytes == null || totalBytes <= 0) {
    return formatBytes(availableBytes);
  }
  return '${formatBytes(availableBytes)} / ${formatBytes(totalBytes)}';
}

String systemInfoSettingsSubtitle(BackendSystemInfo info) {
  final gpuLabel = info.gpus.isEmpty
      ? 'No GPU detected'
      : '${info.gpus.length} GPU(s)';
  final ramLabel = info.totalRamBytes == null
      ? null
      : '${formatBytes(info.totalRamBytes!)} RAM';
  return ramLabel == null ? gpuLabel : '$gpuLabel • $ramLabel';
}

String formatTimestamp(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) {
    return raw;
  }
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day $hour:$minute';
}

String formatDurationLabel(double? seconds) {
  if (seconds == null || seconds <= 0) {
    return '--:--';
  }
  final totalSeconds = seconds.round();
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final remainingSeconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainingSeconds';
}

String formatGenerationDurationLabel(double? seconds) {
  if (seconds == null || seconds <= 0) {
    return '--';
  }
  if (seconds < 10) {
    return '${seconds.toStringAsFixed(1)}s';
  }
  final totalSeconds = seconds.round();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final remainingSeconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '${minutes}m ${remainingSeconds}s';
}

String jobFailureHelpText(JobStatus job) {
  final errorText = job.error?.trim();
  if (errorText != null && errorText.isNotEmpty) {
    return errorText;
  }
  return 'The server reported an error for this job.';
}

String formatJsonMap(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return '{}';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}
