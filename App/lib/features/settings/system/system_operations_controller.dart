import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/app/runtime/app_crash_report_store.dart';
import 'package:flutter_app/models/backups.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/models/system.dart';
import 'package:flutter_app/features/settings/backups/app_data_backup.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/settings/system/wake_on_lan_settings.dart';

class SystemOperationsController {
  SystemOperationsController({
    required this.api,
    required this.crashReports,
    required this.setMessage,
    required this.onChanged,
    required this.refreshAssets,
    required this.clearGenerationSources,
    required this.setLatestJob,
    required this.setLatestImage,
    required this.resetLaunchJobRestore,
    required this.loadGalleryFirstPage,
    required this.loadJobs,
    required this.loadLatestResult,
    required this.loadSettings,
  });

  final ApiClient? Function() api;
  final AppCrashReportStore crashReports;
  final void Function(String? message) setMessage;
  final void Function() onChanged;
  final Future<void> Function() refreshAssets;
  final Future<void> Function() clearGenerationSources;
  final void Function(JobStatus? value) setLatestJob;
  final void Function(ImageRecord? value) setLatestImage;
  final VoidCallback resetLaunchJobRestore;
  final Future<void> Function() loadGalleryFirstPage;
  final Future<void> Function() loadJobs;
  final Future<void> Function({bool silent}) loadLatestResult;
  final Future<void> Function() loadSettings;

  bool loadingErrors = false;
  bool loadingBackups = false;
  bool loadingAppBackups = false;
  bool loadingSystemInfo = false;
  bool loadingHealth = false;
  bool clearingErrors = false;
  bool creatingBackup = false;
  bool creatingAppBackup = false;
  bool applyingBackup = false;
  bool applyingAppBackup = false;
  final WakeOnLanSettings wakeOnLan = WakeOnLanSettings();

  List<AppErrorRecord> errors = <AppErrorRecord>[];
  List<BackupRecord> backups = <BackupRecord>[];
  List<BackupRecord> appBackups = <BackupRecord>[];
  BackendSystemInfo? systemInfo;
  BackendHealth? backendHealth;

  void loadWakeOnLanPreferences(SharedPreferences prefs) {
    wakeOnLan.macAddress = prefs.getString(wakeOnLanMacAddressKey) ?? '';
    wakeOnLan.broadcastAddress =
        prefs.getString(wakeOnLanBroadcastAddressKey) ?? '';
    wakeOnLan.port = prefs.getString(wakeOnLanPortKey) ?? '9';
  }

  Future<void> saveWakeOnLanPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(wakeOnLanMacAddressKey, wakeOnLan.macAddress);
    await prefs.setString(
      wakeOnLanBroadcastAddressKey,
      wakeOnLan.broadcastAddress,
    );
    await prefs.setString(wakeOnLanPortKey, wakeOnLan.port);
  }

  static const wakeOnLanMacAddressKey = 'wake_on_lan_mac_address';
  static const wakeOnLanBroadcastAddressKey = 'wake_on_lan_broadcast_address';
  static const wakeOnLanPortKey = 'wake_on_lan_port';

  Future<void> loadErrors({bool silent = false}) async {
    if (!silent) {
      loadingErrors = true;
      onChanged();
    }
    try {
      final localReports = await crashReports.listReports();
      final client = api();
      final serverErrors = client == null
          ? <AppErrorRecord>[]
          : await client.fetchErrors();
      errors = <AppErrorRecord>[...localReports, ...serverErrors]
        ..sort((left, right) => right.loggedAt.compareTo(left.loggedAt));
    } catch (error) {
      if (!silent) {
        _setRequestError(
          error,
          'Couldn\'t load error reports right now. Please try again.',
        );
      }
    } finally {
      if (!silent) {
        loadingErrors = false;
      }
      onChanged();
    }
  }

  Future<void> loadBackups() async {
    final client = api();
    if (client == null) {
      return;
    }
    loadingBackups = true;
    onChanged();
    try {
      backups = await client.fetchBackups();
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t load backups right now. Please try again.',
      );
    } finally {
      loadingBackups = false;
      onChanged();
    }
  }

  Future<void> loadAppBackups() async {
    final client = api();
    if (client == null) {
      return;
    }
    loadingAppBackups = true;
    onChanged();
    try {
      appBackups = await client.fetchAppBackups();
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t load app backups right now. Please try again.',
      );
    } finally {
      loadingAppBackups = false;
      onChanged();
    }
  }

  Future<void> loadSystemInfo({bool silent = false}) async {
    final client = api();
    if (client == null) {
      return;
    }
    if (!silent) {
      loadingSystemInfo = true;
      onChanged();
    }
    try {
      systemInfo = await client.fetchSystemInfo();
    } catch (error) {
      if (!silent || systemInfo == null) {
        _setRequestError(
          error,
          'Couldn\'t load system information right now. Please try again.',
        );
      }
    } finally {
      if (!silent) {
        loadingSystemInfo = false;
      }
      onChanged();
    }
  }

  Future<void> loadHealth({bool silent = false}) async {
    final client = api();
    if (client == null) {
      return;
    }
    if (!silent) {
      loadingHealth = true;
      onChanged();
    }
    try {
      backendHealth = await client.fetchHealth();
    } catch (error) {
      backendHealth = BackendHealth(
        status: 'offline',
        backend: BackendHealthStatus(ok: false, label: 'Offline', detail: null),
        comfy: BackendHealthStatus(ok: false, label: 'Offline', detail: null),
        ollama: BackendHealthStatus(ok: false, label: 'Offline', detail: null),
        queue: const <String, dynamic>{},
      );
      if (!silent || backendHealth == null) {
        _setRequestError(
          error,
          'Couldn\'t load server health right now. Please try again.',
        );
      }
    } finally {
      if (!silent) {
        loadingHealth = false;
      }
      onChanged();
    }
  }

  Future<void> createBackup() async {
    final client = api();
    if (client == null) {
      return;
    }
    creatingBackup = true;
    setMessage(null);
    onChanged();
    try {
      final backup = await client.createBackup();
      backups = [backup, ...backups.where((item) => item.name != backup.name)];
      backups.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      setMessage('Backup created.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t create a backup right now. Please try again.',
      );
    } finally {
      creatingBackup = false;
      onChanged();
    }
  }

  Future<void> deleteBackup(String backupName) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.deleteBackup(backupName);
      backups = backups.where((item) => item.name != backupName).toList();
      setMessage('Backup deleted.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t delete the backup right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> deleteAppBackup(String backupName) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.deleteAppBackup(backupName);
      appBackups = appBackups.where((item) => item.name != backupName).toList();
      setMessage('App backup deleted.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t delete the app backup right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> createAppBackup() async {
    final client = api();
    if (client == null) {
      return;
    }

    creatingAppBackup = true;
    setMessage(null);
    onChanged();
    try {
      final prefs = await SharedPreferences.getInstance();
      final backup = await client.createAppBackup(
        buildAppDataBackupPayload(prefs),
      );
      appBackups = [
        backup,
        ...appBackups.where((item) => item.name != backup.name),
      ];
      appBackups.sort(
        (left, right) => right.createdAt.compareTo(left.createdAt),
      );
      setMessage('App backup created.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t create an app backup right now. Please try again.',
      );
    } finally {
      creatingAppBackup = false;
      onChanged();
    }
  }

  Future<void> applyBackup(String backupName, {bool merge = false}) async {
    final client = api();
    if (client == null) {
      return;
    }

    applyingBackup = true;
    setMessage(null);
    onChanged();
    try {
      await client.applyBackup(backupName, merge: merge);
      await clearGenerationSources();
      setLatestJob(null);
      setLatestImage(null);
      resetLaunchJobRestore();

      await refreshAssets();
      await loadGalleryFirstPage();
      await loadJobs();
      await loadLatestResult(silent: true);
      await loadBackups();
      setMessage(merge ? 'Server backup merged.' : 'Server backup applied.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t apply the server backup right now. Please try again.',
      );
    } finally {
      applyingBackup = false;
      onChanged();
    }
  }

  Future<void> applyAppBackup(String backupName) async {
    final client = api();
    if (client == null) {
      return;
    }

    applyingAppBackup = true;
    setMessage(null);
    onChanged();
    try {
      final payload = await client.fetchAppBackup(backupName);
      await restoreAppDataBackupPayload(payload);
      await loadSettings();
      setLatestJob(null);
      setLatestImage(null);
      backendHealth = null;
      await clearGenerationSources();
      resetLaunchJobRestore();
      setMessage('App backup applied.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t apply the app backup right now. Please try again.',
      );
    } finally {
      applyingAppBackup = false;
      onChanged();
    }
  }

  Future<void> sendWakeOnLan({
    required String macAddress,
    required String broadcastAddress,
    required String port,
    required String baseUrl,
  }) async {
    setMessage(
      await wakeOnLan.send(
        macAddress: macAddress,
        broadcastAddress: broadcastAddress,
        port: port,
        baseUrl: baseUrl,
      ),
    );
    onChanged();
  }

  Future<void> clearErrors() async {
    if (clearingErrors) {
      return;
    }
    clearingErrors = true;
    onChanged();
    try {
      final localDeleted = await crashReports.clearReports();
      final client = api();
      final serverDeleted = client == null ? 0 : await client.clearErrors();
      final deleted = localDeleted + serverDeleted;
      errors = <AppErrorRecord>[];
      setMessage(
        deleted == 1 ? '1 report cleared.' : '$deleted reports cleared.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t clear the error reports right now. Please try again.',
      );
    } finally {
      clearingErrors = false;
      onChanged();
    }
  }

  Future<void> forceUnloadAllModels() async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.forceUnloadAllModels();
      setMessage(
        'Requested unload of ComfyUI, Ollama, and app-managed models.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t unload the loaded models right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> deleteModel(String modelId) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.deleteModel(modelId);
      await refreshAssets();
      setMessage('Model deleted.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t delete the model right now. Please try again.',
      );
      onChanged();
    }
  }

  Future<void> deleteLora(String loraId) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.deleteLora(loraId);
      await refreshAssets();
      setMessage('LoRA deleted.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t delete the LoRA right now. Please try again.',
      );
      onChanged();
    }
  }

  Future<void> shutdownHost() async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.requestShutdown();
      setMessage('Shutdown command sent to the server host.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t send the shutdown command right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> restartServer() async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.requestServerRestart();
      setMessage('Backend restart requested. The connection may drop briefly.');
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t restart the backend right now. Please try again.',
      );
    }
    onChanged();
  }

  void _setRequestError(Object error, String generalMessage) {
    setMessage(requestErrorMessage(error, generalMessage: generalMessage));
  }
}
