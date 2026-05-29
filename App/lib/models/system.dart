class BackendHealthStatus {
  BackendHealthStatus({required this.ok, required this.label, this.detail});

  final bool ok;
  final String label;
  final String? detail;

  factory BackendHealthStatus.fromJson(Map<String, dynamic> json) {
    return BackendHealthStatus(
      ok: json['ok'] as bool? ?? false,
      label: json['label'] as String? ?? '',
      detail: json['detail'] as String?,
    );
  }
}

class BackendHealth {
  BackendHealth({
    required this.status,
    required this.backend,
    required this.comfy,
    required this.ollama,
    required this.queue,
  });

  final String status;
  final BackendHealthStatus backend;
  final BackendHealthStatus comfy;
  final BackendHealthStatus ollama;
  final Map<String, dynamic> queue;

  factory BackendHealth.fromJson(Map<String, dynamic> json) {
    return BackendHealth(
      status: json['status'] as String? ?? 'unknown',
      backend: BackendHealthStatus.fromJson(
        json['backend'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      comfy: BackendHealthStatus.fromJson(
        json['comfy'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      ollama: BackendHealthStatus.fromJson(
        json['ollama'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      queue: Map<String, dynamic>.from(
        json['queue'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
    );
  }
}

class BackendLogRow {
  BackendLogRow({
    required this.raw,
    required this.message,
    this.timestamp,
    this.level,
    this.logger,
  });

  final String raw;
  final String message;
  final String? timestamp;
  final String? level;
  final String? logger;

  factory BackendLogRow.fromJson(Map<String, dynamic> json) {
    return BackendLogRow(
      raw: json['raw'] as String? ?? '',
      timestamp: json['timestamp'] as String?,
      level: json['level'] as String?,
      logger: json['logger'] as String?,
      message: json['message'] as String? ?? '',
    );
  }
}

class BackendLogSnapshot {
  BackendLogSnapshot({
    required this.source,
    required this.displayName,
    required this.rows,
    required this.truncated,
    required this.limit,
    required this.refreshedAt,
  });

  final String source;
  final String displayName;
  final List<BackendLogRow> rows;
  final bool truncated;
  final int limit;
  final String refreshedAt;

  factory BackendLogSnapshot.fromJson(Map<String, dynamic> json) {
    return BackendLogSnapshot(
      source: json['source'] as String? ?? 'server',
      displayName: json['display_name'] as String? ?? 'Logs',
      rows: ((json['rows'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(BackendLogRow.fromJson)
          .toList()),
      truncated: json['truncated'] as bool? ?? false,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      refreshedAt: json['refreshed_at'] as String? ?? '',
    );
  }
}

class BackendGpuInfo {
  BackendGpuInfo({
    required this.name,
    this.vendor,
    this.vramTotalBytes,
    this.vramFreeBytes,
    this.utilizationPercent,
    this.driverVersion,
    this.source,
  });

  final String name;
  final String? vendor;
  final int? vramTotalBytes;
  final int? vramFreeBytes;
  final double? utilizationPercent;
  final String? driverVersion;
  final String? source;

  factory BackendGpuInfo.fromJson(Map<String, dynamic> json) {
    return BackendGpuInfo(
      name: json['name'] as String? ?? 'Unknown GPU',
      vendor: json['vendor'] as String?,
      vramTotalBytes: (json['vram_total_bytes'] as num?)?.toInt(),
      vramFreeBytes: (json['vram_free_bytes'] as num?)?.toInt(),
      utilizationPercent: (json['utilization_percent'] as num?)?.toDouble(),
      driverVersion: json['driver_version'] as String?,
      source: json['source'] as String?,
    );
  }
}

class BackendSystemInfo {
  BackendSystemInfo({
    required this.system,
    required this.release,
    required this.version,
    required this.machine,
    required this.hostname,
    required this.cpuModel,
    required this.logicalCores,
    required this.gpus,
    required this.collectedAt,
    this.physicalCores,
    this.cpuUtilizationPercent,
    this.totalRamBytes,
    this.availableRamBytes,
  });

  final String system;
  final String release;
  final String version;
  final String machine;
  final String hostname;
  final String cpuModel;
  final int? physicalCores;
  final int? logicalCores;
  final double? cpuUtilizationPercent;
  final int? totalRamBytes;
  final int? availableRamBytes;
  final List<BackendGpuInfo> gpus;
  final String collectedAt;

  factory BackendSystemInfo.fromJson(Map<String, dynamic> json) {
    final platform =
        json['platform'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final cpu = json['cpu'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final memory =
        json['memory'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return BackendSystemInfo(
      system: platform['system'] as String? ?? 'Unknown',
      release: platform['release'] as String? ?? '',
      version: platform['version'] as String? ?? '',
      machine: platform['machine'] as String? ?? '',
      hostname: platform['hostname'] as String? ?? '',
      cpuModel: cpu['model'] as String? ?? 'Unknown CPU',
      physicalCores: (cpu['physical_cores'] as num?)?.toInt(),
      logicalCores: (cpu['logical_cores'] as num?)?.toInt(),
      cpuUtilizationPercent: (cpu['utilization_percent'] as num?)?.toDouble(),
      totalRamBytes: (memory['total_bytes'] as num?)?.toInt(),
      availableRamBytes: (memory['available_bytes'] as num?)?.toInt(),
      gpus: ((json['gpus'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(BackendGpuInfo.fromJson)
          .toList()),
      collectedAt: json['collected_at'] as String? ?? '',
    );
  }
}
