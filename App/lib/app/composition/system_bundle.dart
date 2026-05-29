import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/app/runtime/app_crash_report_store.dart';
import 'package:flutter_app/features/settings/logs/log_store.dart';
import 'package:flutter_app/features/settings/system/system_operations_controller.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';

class SystemBundleDependencies {
  const SystemBundleDependencies({
    required this.connection,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.refreshAssets,
    required this.clearGenerationSources,
    required this.resetLaunchJobRestore,
    required this.loadGalleryFirstPage,
    required this.loadJobs,
    required this.loadLatestResult,
    required this.loadSettings,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final Future<void> Function() refreshAssets;
  final Future<void> Function() clearGenerationSources;
  final void Function() resetLaunchJobRestore;
  final Future<void> Function() loadGalleryFirstPage;
  final Future<void> Function() loadJobs;
  final Future<void> Function({bool silent}) loadLatestResult;
  final Future<void> Function() loadSettings;
  final void Function() notifyChanged;
}

class SystemBundle {
  SystemBundle(SystemBundleDependencies dependencies)
    : navigation = AppNavigationController(
        onChanged: dependencies.notifyChanged,
      ),
      system = SystemOperationsController(
        api: () => dependencies.connection.api,
        crashReports: AppCrashReportStore.instance,
        setMessage: (value) => dependencies.connection.message = value,
        onChanged: dependencies.notifyChanged,
        refreshAssets: dependencies.refreshAssets,
        clearGenerationSources: dependencies.clearGenerationSources,
        setLatestJob: (value) => dependencies.jobRuntime.latestJob = value,
        setLatestImage: (value) =>
            dependencies.mediaRuntime.latestImage = value,
        resetLaunchJobRestore: dependencies.resetLaunchJobRestore,
        loadGalleryFirstPage: dependencies.loadGalleryFirstPage,
        loadJobs: dependencies.loadJobs,
        loadLatestResult: dependencies.loadLatestResult,
        loadSettings: dependencies.loadSettings,
      ),
      logs = LogStore(
        api: () => dependencies.connection.api,
        setMessage: (value) => dependencies.connection.message = value,
        onChanged: dependencies.notifyChanged,
      );

  final AppNavigationController navigation;
  final SystemOperationsController system;
  final LogStore logs;
}
