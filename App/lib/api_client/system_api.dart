import 'dart:async';
import '../models/jobs.dart';
import '../models/system.dart';
import 'transport.dart';

mixin SystemApi on ApiClientTransport {
  Future<BackendSystemInfo> fetchSystemInfo() async {
    final response = await dio.get<Map<String, dynamic>>('/api/system/info');
    return BackendSystemInfo.fromJson(response.data!);
  }

  Future<BackendHealth> fetchHealth() async {
    final response = await dio.get<Map<String, dynamic>>('/api/health');
    return BackendHealth.fromJson(response.data!);
  }

  Future<BackendLogSnapshot> fetchLogs({
    required String source,
    required int limit,
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/system/logs',
      queryParameters: {'source': source, 'limit': limit},
    );
    return BackendLogSnapshot.fromJson(response.data!);
  }

  Future<List<AppErrorRecord>> fetchErrors() async {
    final response = await dio.get<Map<String, dynamic>>('/api/errors');
    final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .cast<Map<String, dynamic>>()
        .map(AppErrorRecord.fromJson)
        .toList();
  }

  Future<int> clearErrors() async {
    final response = await dio.delete<Map<String, dynamic>>('/api/errors');
    return (response.data!['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<bool> fetchShutdownWhenIdle() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/system/shutdown-when-idle',
    );
    return response.data!['shutdown_when_idle'] as bool? ?? false;
  }

  Future<bool> setShutdownWhenIdle(bool value) async {
    final response = value
        ? await dio.post<Map<String, dynamic>>(
            '/api/system/shutdown-when-idle',
          )
        : await dio.delete<Map<String, dynamic>>(
            '/api/system/shutdown-when-idle',
          );
    return response.data!['shutdown_when_idle'] as bool? ?? false;
  }

  Future<int> fetchInterJobDelaySeconds() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/system/inter-job-delay',
    );
    return (response.data!['inter_job_delay_seconds'] as num?)?.toInt() ?? 0;
  }

  Future<int> setInterJobDelaySeconds(int seconds) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/system/inter-job-delay',
      data: {'seconds': seconds},
    );
    return (response.data!['inter_job_delay_seconds'] as num?)?.toInt() ?? 0;
  }

  Future<void> requestShutdown() async {
    await dio.post<void>('/api/system/shutdown');
  }

  Future<void> requestServerRestart() async {
    await dio.post<void>('/api/system/restart-server');
  }

  Future<void> forceUnloadAllModels() async {
    await dio.post<void>('/api/system/unload-models');
  }
}
