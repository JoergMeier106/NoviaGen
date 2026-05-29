import 'media.dart';

class JobChainBinding {
  JobChainBinding({required this.stepId, required this.output});

  final String stepId;
  final String output;

  Map<String, dynamic> toJson() {
    return {'step_id': stepId, 'output': output};
  }
}

class JobChainUpload {
  JobChainUpload({required this.path, required this.name});

  final String path;
  final String name;
}

class JobChainStep {
  JobChainStep({
    required this.id,
    required this.type,
    required this.payload,
    this.bindings = const <String, JobChainBinding>{},
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final Map<String, JobChainBinding> bindings;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      if (bindings.isNotEmpty)
        'bindings': bindings.map(
          (field, binding) => MapEntry(field, binding.toJson()),
        ),
    };
  }
}

class JobChainStateStep {
  JobChainStateStep({
    required this.id,
    required this.type,
    required this.status,
    this.childJobId,
    this.resultImageId,
    this.resultText,
  });

  final String id;
  final String type;
  final String status;
  final String? childJobId;
  final String? resultImageId;
  final String? resultText;

  factory JobChainStateStep.fromJson(Map<String, dynamic> json) {
    return JobChainStateStep(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      childJobId: json['child_job_id'] as String?,
      resultImageId: json['result_image_id'] as String?,
      resultText: json['result_text'] as String?,
    );
  }
}

class JobChainState {
  JobChainState({
    required this.currentStepId,
    required this.currentChildJobId,
    required this.steps,
  });

  final String? currentStepId;
  final String? currentChildJobId;
  final List<JobChainStateStep> steps;

  factory JobChainState.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? const <dynamic>[];
    return JobChainState(
      currentStepId: json['current_step_id'] as String?,
      currentChildJobId: json['current_child_job_id'] as String?,
      steps: rawSteps
          .whereType<Map>()
          .map(
            (item) => JobChainStateStep.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class JobStatus {
  JobStatus({
    required this.jobId,
    required this.type,
    required this.parentJobId,
    required this.chainStepId,
    required this.status,
    required this.progress,
    required this.statusText,
    required this.cancelRequested,
    required this.payload,
    this.cancelRequestedAt,
    this.cancelledAt,
    this.startedAt,
    this.createdAt,
    this.updatedAt,
    this.result,
    this.resultData,
    this.chain,
    this.error,
  });

  final String jobId;
  final String type;
  final String? parentJobId;
  final String? chainStepId;
  final String status;
  final double progress;
  final String statusText;
  final bool cancelRequested;
  final Map<String, dynamic> payload;
  final String? cancelRequestedAt;
  final String? cancelledAt;
  final String? startedAt;
  final String? createdAt;
  final String? updatedAt;
  final ImageRecord? result;
  final Map<String, dynamic>? resultData;
  final JobChainState? chain;
  final String? error;

  bool get isTerminal =>
      status == 'completed' || status == 'failed' || status == 'cancelled';
  bool get canCancel => status == 'queued' || status == 'running';
  bool get isChainParent => type == 'chain';
  bool get isChainChild => (parentJobId?.trim().isNotEmpty ?? false);
  bool get isPrimaryWorkflowJob => !isChainChild;

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return JobStatus(
      jobId: json['job_id'] as String,
      type: json['type'] as String,
      parentJobId: json['parent_job_id'] as String?,
      chainStepId: json['chain_step_id'] as String?,
      status: json['status'] as String,
      progress: (json['progress'] as num).toDouble(),
      statusText: json['status_text'] as String,
      cancelRequested: json['cancel_requested'] as bool? ?? false,
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      cancelRequestedAt: json['cancel_requested_at'] as String?,
      cancelledAt: json['cancelled_at'] as String?,
      startedAt: json['started_at'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      result: _imageRecordFromJson(json['result']),
      resultData: json['result_data'] is Map
          ? Map<String, dynamic>.from(json['result_data'] as Map)
          : null,
      chain: json['chain'] is Map
          ? JobChainState.fromJson(Map<String, dynamic>.from(json['chain'] as Map))
          : null,
      error: json['error'] as String?,
    );
  }
}

ImageRecord? _imageRecordFromJson(Object? value) {
  if (value is! Map) {
    return null;
  }
  try {
    return ImageRecord.fromJson(Map<String, dynamic>.from(value));
  } catch (_) {
    return null;
  }
}

class AppErrorRecord {
  AppErrorRecord({
    required this.id,
    required this.loggedAt,
    required this.source,
    required this.reportType,
    required this.errorText,
    required this.jobId,
    required this.jobType,
    required this.jobStatus,
    required this.jobProgress,
    required this.jobStatusText,
    required this.cancelRequested,
    required this.jobPayload,
    this.stackTraceText,
    this.jobCancelRequestedAt,
    this.jobCancelledAt,
    this.jobCreatedAt,
    this.jobUpdatedAt,
  });

  final String id;
  final String loggedAt;
  final String source;
  final String reportType;
  final String errorText;
  final String jobId;
  final String jobType;
  final String jobStatus;
  final double jobProgress;
  final String jobStatusText;
  final bool cancelRequested;
  final Map<String, dynamic> jobPayload;
  final String? stackTraceText;
  final String? jobCancelRequestedAt;
  final String? jobCancelledAt;
  final String? jobCreatedAt;
  final String? jobUpdatedAt;

  bool get isAppCrashReport => source == 'app' || reportType == 'crash';

  factory AppErrorRecord.fromJson(Map<String, dynamic> json) {
    final job = (json['job'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final payload = job['payload'];
    return AppErrorRecord(
      id: json['id'] as String,
      loggedAt: json['logged_at'] as String,
      source: json['source'] as String? ?? 'server',
      reportType: json['report_type'] as String? ?? 'error',
      errorText: json['error_text'] as String? ?? '',
      jobId: job['job_id'] as String? ?? '',
      jobType: job['type'] as String? ?? '',
      jobStatus: job['status'] as String? ?? '',
      jobProgress: (job['progress'] as num?)?.toDouble() ?? 0.0,
      jobStatusText: job['status_text'] as String? ?? '',
      cancelRequested: job['cancel_requested'] as bool? ?? false,
      jobPayload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      stackTraceText: json['stack_trace'] as String?,
      jobCancelRequestedAt: job['cancel_requested_at'] as String?,
      jobCancelledAt: job['cancelled_at'] as String?,
      jobCreatedAt: job['created_at'] as String?,
      jobUpdatedAt: job['updated_at'] as String?,
    );
  }
}
