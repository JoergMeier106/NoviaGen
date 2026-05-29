import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/jobs.dart';
import 'transport.dart';

mixin JobQueueApi on ApiClientTransport {
  Future<JobStatus> createChainJob({
    required List<JobChainStep> steps,
    String? clientRequestId,
    Map<String, JobChainUpload> uploads = const <String, JobChainUpload>{},
  }) async {
    final encodedSteps = steps.map((step) => step.toJson()).toList();
    final chainPayload = {
      'steps': encodedSteps,
      if (clientRequestId?.trim().isNotEmpty ?? false)
        'client_request_id': clientRequestId!.trim(),
    };
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/chain',
      data: uploads.isEmpty
          ? chainPayload
          : FormData.fromMap({
              'chain': jsonEncode(chainPayload),
              for (final entry in uploads.entries)
                entry.key: await MultipartFile.fromFile(
                  entry.value.path,
                  filename: entry.value.name,
                ),
            }),
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> getJob(String jobId) async {
    final response = await dio.get<Map<String, dynamic>>('/api/jobs/$jobId');
    return JobStatus.fromJson(response.data!);
  }

  Future<List<JobStatus>> fetchJobs({String? status}) async {
    final jobs = <JobStatus>[];
    var page = 1;
    var total = 1;
    while (jobs.length < total) {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/jobs',
        queryParameters: {
          'page': page,
          'page_size': 100,
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
      total = (response.data!['total'] as num?)?.toInt() ?? items.length;
      jobs.addAll(items.cast<Map<String, dynamic>>().map(JobStatus.fromJson));
      if (items.isEmpty) {
        break;
      }
      page += 1;
    }
    return jobs;
  }

  Future<int> clearFinishedJobs() async {
    final response = await dio.delete<Map<String, dynamic>>(
      '/api/jobs',
      queryParameters: {'scope': 'finished'},
    );
    return (response.data!['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<JobStatus> cancelJob(String jobId) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/$jobId/cancel',
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<int> cancelAllJobs() async {
    final response = await dio.post<Map<String, dynamic>>('/api/jobs/cancel');
    return (response.data!['cancelled'] as num?)?.toInt() ?? 0;
  }
}
