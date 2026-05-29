import 'dart:async';
import '../models/backups.dart';
import 'transport.dart';

mixin BackupApi on ApiClientTransport {
  Future<List<BackupRecord>> fetchBackups() async {
    final response = await dio.get<Map<String, dynamic>>('/api/backups');
    final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .cast<Map<String, dynamic>>()
        .map(BackupRecord.fromJson)
        .toList();
  }

  Future<List<BackupRecord>> fetchAppBackups() async {
    final response = await dio.get<Map<String, dynamic>>('/api/app-backups');
    final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .cast<Map<String, dynamic>>()
        .map(BackupRecord.fromJson)
        .toList();
  }

  Future<BackupRecord> createBackup() async {
    final response = await dio.post<Map<String, dynamic>>('/api/backups');
    return BackupRecord.fromJson(response.data!);
  }

  Future<BackupRecord> applyBackup(
    String backupName, {
    bool merge = false,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/backups/${Uri.encodeComponent(backupName)}/apply',
      data: <String, dynamic>{'mode': merge ? 'merge' : 'overwrite'},
    );
    return BackupRecord.fromJson(response.data!);
  }

  Future<BackupRecord> createAppBackup(Map<String, dynamic> payload) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/app-backups',
      data: payload,
    );
    return BackupRecord.fromJson(response.data!);
  }

  Future<Map<String, dynamic>> fetchAppBackup(String backupName) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/app-backups/${Uri.encodeComponent(backupName)}',
    );
    return response.data!;
  }

  Future<void> deleteBackup(String backupName) async {
    await dio.delete<void>('/api/backups/$backupName');
  }

  Future<void> deleteAppBackup(String backupName) async {
    await dio.delete<void>(
      '/api/app-backups/${Uri.encodeComponent(backupName)}',
    );
  }
}
