import '../app_navigation_state.dart';
import '../log_state.dart';
import '../system_operations_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppSystemStateDependencies {
  const AppSystemStateDependencies({
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

  final AppConnectionState connection;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final Future<void> Function() refreshAssets;
  final Future<void> Function() clearGenerationSources;
  final void Function() resetLaunchJobRestore;
  final Future<void> Function() loadGalleryFirstPage;
  final Future<void> Function() loadJobs;
  final Future<void> Function({bool silent}) loadLatestResult;
  final Future<void> Function() loadSettings;
  final void Function() notifyChanged;
}

class AppSystemStates {
  AppSystemStates(AppSystemStateDependencies dependencies)
    : navigation = AppNavigationState(onChanged: dependencies.notifyChanged),
      system = SystemOperationsState(
        api: () => dependencies.connection.api,
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
      logs = LogState(
        api: () => dependencies.connection.api,
        setMessage: (value) => dependencies.connection.message = value,
        onChanged: dependencies.notifyChanged,
      );

  final AppNavigationState navigation;
  final SystemOperationsState system;
  final LogState logs;
}
