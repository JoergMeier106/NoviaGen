class BackupRecord {
  BackupRecord({
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String name;
  final String createdAt;
  final int sizeBytes;

  factory BackupRecord.fromJson(Map<String, dynamic> json) {
    return BackupRecord(
      name: json['name'] as String,
      createdAt: json['created_at'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
    );
  }
}
