import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/models/system.dart';
import 'package:flutter_app/app/persistence/settings_codecs.dart';
import 'package:flutter_app/shared/request_errors.dart';


class LogStore {
  LogStore({this.api, this.setMessage, this.onChanged});

  static const selectedSourceKey = 'logs_selected_source';
  static const severityFilterKey = 'logs_severity_filter';
  static const rowLimitKey = 'logs_row_limit';
  static const followLatestKey = 'logs_follow_latest';

  final ApiClient? Function()? api;
  final void Function(String? message)? setMessage;
  final void Function()? onChanged;

  bool loadingServer = false;
  bool loadingComfy = false;
  BackendLogSnapshot? server;
  BackendLogSnapshot? comfy;

  String selectedSource = 'server';
  String severityFilter = 'all';
  int rowLimit = 500;
  bool followLatest = true;

  bool isLoading(String source) {
    return _isComfySource(source) ? loadingComfy : loadingServer;
  }

  void setLoading(String source, bool value) {
    if (_isComfySource(source)) {
      loadingComfy = value;
      return;
    }
    loadingServer = value;
  }

  BackendLogSnapshot? snapshotForSource(String source) {
    return _isComfySource(source) ? comfy : server;
  }

  void setSnapshot(BackendLogSnapshot snapshot) {
    if (_isComfySource(snapshot.source)) {
      comfy = snapshot;
      return;
    }
    server = snapshot;
  }

  void loadPreferences(SharedPreferences prefs) {
    selectedSource = logSourceFromString(prefs.getString(selectedSourceKey));
    severityFilter = logSeverityFilterFromString(
      prefs.getString(severityFilterKey),
    );
    rowLimit = logRowLimitFromInt(prefs.getInt(rowLimitKey));
    followLatest = prefs.getBool(followLatestKey) ?? true;
  }

  Future<void> savePreferences({
    String? selectedSource,
    String? severityFilter,
    int? rowLimit,
    bool? followLatest,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (selectedSource != null) {
      this.selectedSource = logSourceFromString(selectedSource);
      await prefs.setString(selectedSourceKey, this.selectedSource);
    }
    if (severityFilter != null) {
      this.severityFilter = logSeverityFilterFromString(severityFilter);
      await prefs.setString(severityFilterKey, this.severityFilter);
    }
    if (rowLimit != null) {
      this.rowLimit = logRowLimitFromInt(rowLimit);
      await prefs.setInt(rowLimitKey, this.rowLimit);
    }
    if (followLatest != null) {
      this.followLatest = followLatest;
      await prefs.setBool(followLatestKey, this.followLatest);
    }
  }

  Future<void> load({
    required String source,
    required int limit,
    bool silent = false,
  }) async {
    final client = api?.call();
    if (client == null) {
      if (!silent) {
        setMessage?.call('Set a backend URL first.');
        onChanged?.call();
      }
      return;
    }

    final normalizedSource = _normalizeSource(source);
    if (!silent) {
      setLoading(normalizedSource, true);
      onChanged?.call();
    }

    try {
      final snapshot = await client.fetchLogs(
        source: normalizedSource,
        limit: limit,
      );
      setSnapshot(snapshot);
    } catch (error) {
      if (!silent || snapshotForSource(normalizedSource) == null) {
        setMessage?.call(
          requestErrorMessage(
            error,
            generalMessage:
                'Couldn\'t load the ${normalizedSource == 'comfy' ? 'Comfy' : 'server'} log right now. Please try again.',
          ),
        );
      }
    } finally {
      if (!silent) {
        setLoading(normalizedSource, false);
      }
      onChanged?.call();
    }
  }

  bool _isComfySource(String source) {
    return _normalizeSource(source) == 'comfy';
  }

  String _normalizeSource(String source) {
    return source.trim().toLowerCase() == 'comfy' ? 'comfy' : 'server';
  }
}
