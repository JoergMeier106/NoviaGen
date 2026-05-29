class BackendRefreshDependencies {
  const BackendRefreshDependencies({
    required this.syncInterJobDelaySetting,
    required this.refreshAssets,
    required this.loadJobs,
    required this.loadLatestResult,
    required this.loadHealth,
    required this.loadAutoPromptModels,
  });

  final Future<void> Function({bool silent}) syncInterJobDelaySetting;
  final Future<void> Function() refreshAssets;
  final Future<void> Function() loadJobs;
  final Future<void> Function({bool silent}) loadLatestResult;
  final Future<void> Function({bool silent}) loadHealth;
  final Future<void> Function({bool silent}) loadAutoPromptModels;
}

class BackendRefreshController {
  BackendRefreshController(this.dependencies);

  final BackendRefreshDependencies dependencies;

  Future<void> refreshBackendData({bool silent = true}) async {
    await dependencies.syncInterJobDelaySetting(silent: silent);
    await dependencies.refreshAssets();
    await dependencies.loadJobs();
    await dependencies.loadLatestResult(silent: silent);
    await dependencies.loadHealth(silent: silent);
    await dependencies.loadAutoPromptModels(silent: silent);
  }
}
