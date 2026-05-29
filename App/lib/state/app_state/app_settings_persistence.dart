import 'package:shared_preferences/shared_preferences.dart';

import '../app_state_codecs.dart';
import '../job_operations_state.dart';
import '../log_state.dart';
import 'app_settings_keys.dart';
import 'app_settings_persistence_scope.dart';


class AppSettingsPersistence {
  Future<void> load(AppSettingsPersistenceScope dependencies) async {
    final prefs = await SharedPreferences.getInstance();
    dependencies.connection.baseUrl =
        prefs.getString(AppSettingsKeys.baseUrl) ?? '';
    await _loadPromptLibrary(dependencies, prefs);
    dependencies.connection.themeMode = themeModeFromString(
      prefs.getString(AppSettingsKeys.themeMode),
    );
    dependencies.generationDefaults().loadPreferences(prefs);
    dependencies.generationDrafts.imagePrompt =
        prefs.getString(AppSettingsKeys.promptDraft) ?? '';
    dependencies.generationDrafts.videoPrompt =
        prefs.getString(AppSettingsKeys.videoPromptDraft) ?? '';
    dependencies.chat().loadPreferences(prefs);
    dependencies.chatRuntime.contextWindow =
        prefs.containsKey(AppSettingsKeys.chatContextWindow)
        ? prefs.getInt(AppSettingsKeys.chatContextWindow)
        : null;
    dependencies.chatRuntime.thinkingEnabled =
        prefs.getBool(AppSettingsKeys.chatThinkingEnabled) ?? true;
    dependencies.chatModelCatalog().loadPreferences(prefs);
    dependencies.imageModels().loadPreferences(prefs);
    dependencies.videoAssets().loadPreferences(prefs);
    _loadVideoDrafts(dependencies, prefs);
    await _restoreGenerationSources(dependencies, prefs);
    dependencies.galleryBrowser().loadPreferences(prefs);
    dependencies.jobRuntime.interJobDelaySeconds =
        prefs.getInt(JobOperationsState.interJobDelaySecondsKey) ?? 0;
    dependencies.scalingPreferences.deleteSourceAfterScaling =
        prefs.getBool(AppSettingsKeys.deleteSourceAfterScaling) ?? false;
    dependencies.logs().loadPreferences(prefs);
    dependencies.system().loadWakeOnLanPreferences(prefs);
  }

  Future<bool> save(
    AppSettingsPersistenceScope dependencies,
    SaveAppSettingsInput input,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmedBaseUrl = input.baseUrl.trim();
    final didChangeBaseUrl = dependencies.connection.baseUrl != trimmedBaseUrl;

    dependencies.connection.baseUrl = trimmedBaseUrl;
    dependencies.connection.themeMode = input.themeMode;
    await dependencies.generationDefaults().saveMainSettings(
      numInferenceSteps: input.numInferenceSteps,
      guidanceScale: input.guidanceScale,
      imageOrientation: input.imageOrientation,
      promptGeneratorBasePrompt: input.promptGeneratorBasePrompt,
      imageToVideoPromptGeneratorBasePrompt:
          input.imageToVideoPromptGeneratorBasePrompt,
    );
    dependencies.galleryBrowser().slideshowIntervalSeconds =
        input.gallerySlideshowIntervalSeconds;
    dependencies.jobRuntime.interJobDelaySeconds = input.interJobDelaySeconds;
    dependencies.scalingPreferences.deleteSourceAfterScaling =
        input.deleteSourceAfterScaling;
    dependencies.chatRuntime.contextWindow = input.chatContextWindow;
    dependencies.chatRuntime.thinkingEnabled = input.chatThinkingEnabled;
    dependencies.chatModelCatalog().preferredAutoPromptModelName = input
        .autoPromptModelName
        ?.trim();
    dependencies.chatModelCatalog().preferredImageToVideoAutoPromptModelName =
        input.imageToVideoAutoPromptModelName?.trim();
    dependencies.system().wakeOnLan.macAddress = input.wakeOnLanMacAddress
        .trim();
    dependencies.system().wakeOnLan.broadcastAddress = input
        .wakeOnLanBroadcastAddress
        .trim();
    dependencies.system().wakeOnLan.port = input.wakeOnLanPort.trim();

    await _saveCoreSettings(dependencies, prefs);
    await _saveChatSettings(dependencies, prefs);
    await dependencies.chatModelCatalog().savePreferences();
    await dependencies.system().saveWakeOnLanPreferences();
    return didChangeBaseUrl;
  }

  Future<void> _loadPromptLibrary(
    AppSettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    final legacyPositivePrompt =
        prefs.getString(AppSettingsKeys.legacyPositive) ?? '';
    final legacyNegativePrompt =
        prefs.getString(AppSettingsKeys.legacyNegative) ?? '';
    await dependencies.promptLibrary().loadFromPreferences(
      prefs,
      legacyPositivePrompt: legacyPositivePrompt,
      legacyNegativePrompt: legacyNegativePrompt,
    );
    await prefs.remove(AppSettingsKeys.legacyPositive);
    await prefs.remove(AppSettingsKeys.legacyNegative);
  }

  void _loadVideoDrafts(
    AppSettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) {
    dependencies.videoSettings().loadDrafts(
      width: prefs.getString(AppSettingsKeys.videoCustomWidth) ?? '',
      height: prefs.getString(AppSettingsKeys.videoCustomHeight) ?? '',
      fps: prefs.getString(AppSettingsKeys.videoCustomFps) ?? '',
      numFrames: prefs.getString(AppSettingsKeys.videoCustomNumFrames) ?? '',
    );
  }

  Future<void> _restoreGenerationSources(
    AppSettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    final restoredImageSource = await dependencies
        .generationSources()
        .restorePersistedSource(
          prefs.getString(AppSettingsKeys.imageGenerationSource),
          forVideo: false,
        );
    if (!restoredImageSource) {
      await prefs.remove(AppSettingsKeys.imageGenerationSource);
    }
    final restoredVideoSource = await dependencies
        .generationSources()
        .restorePersistedSource(
          prefs.getString(AppSettingsKeys.videoGenerationSource),
          forVideo: true,
        );
    if (!restoredVideoSource) {
      await prefs.remove(AppSettingsKeys.videoGenerationSource);
    }
  }

  Future<void> _saveCoreSettings(
    AppSettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    await prefs.setString(
      AppSettingsKeys.baseUrl,
      dependencies.connection.baseUrl,
    );
    await prefs.setString(
      AppSettingsKeys.themeMode,
      dependencies.connection.themeMode.name,
    );
    await dependencies.galleryBrowser().savePreferences();
    await prefs.setInt(
      JobOperationsState.interJobDelaySecondsKey,
      dependencies.jobRuntime.interJobDelaySeconds,
    );
    await prefs.setBool(
      AppSettingsKeys.deleteSourceAfterScaling,
      dependencies.scalingPreferences.deleteSourceAfterScaling,
    );
    await prefs.setString(
      LogState.selectedSourceKey,
      dependencies.logs().selectedSource,
    );
    await prefs.setString(
      LogState.severityFilterKey,
      dependencies.logs().severityFilter,
    );
    await prefs.setInt(LogState.rowLimitKey, dependencies.logs().rowLimit);
    await prefs.setBool(
      LogState.followLatestKey,
      dependencies.logs().followLatest,
    );
  }

  Future<void> _saveChatSettings(
    AppSettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    final contextWindow = dependencies.chatRuntime.contextWindow;
    if (contextWindow == null) {
      await prefs.remove(AppSettingsKeys.chatContextWindow);
    } else {
      await prefs.setInt(AppSettingsKeys.chatContextWindow, contextWindow);
    }
    await prefs.setBool(
      AppSettingsKeys.chatThinkingEnabled,
      dependencies.chatRuntime.thinkingEnabled,
    );
  }
}
