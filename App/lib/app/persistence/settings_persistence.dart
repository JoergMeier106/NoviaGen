import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/app/persistence/settings_codecs.dart';
import 'package:flutter_app/features/jobs/persistence/inter_job_delay_persistence.dart';
import 'package:flutter_app/features/settings/logs/log_store.dart';
import 'package:flutter_app/app/persistence/settings_keys.dart';
import 'package:flutter_app/app/persistence/settings_persistence_scope.dart';


class SettingsPersistence {
  Future<void> load(SettingsPersistenceScope dependencies) async {
    final prefs = await SharedPreferences.getInstance();
    dependencies.connection.baseUrl =
        prefs.getString(SettingsKeys.baseUrl) ?? '';
    await _loadPromptLibrary(dependencies, prefs);
    dependencies.connection.themeMode = themeModeFromString(
      prefs.getString(SettingsKeys.themeMode),
    );
    dependencies.generationDefaults().loadPreferences(prefs);
    dependencies.generationDrafts.imagePrompt =
        prefs.getString(SettingsKeys.promptDraft) ?? '';
    dependencies.generationDrafts.videoPrompt =
        prefs.getString(SettingsKeys.videoPromptDraft) ?? '';
    dependencies.chat().loadPreferences(prefs);
    dependencies.chatRuntime.contextWindow =
        prefs.containsKey(SettingsKeys.chatContextWindow)
        ? prefs.getInt(SettingsKeys.chatContextWindow)
        : null;
    dependencies.chatRuntime.thinkingEnabled =
        prefs.getBool(SettingsKeys.chatThinkingEnabled) ?? true;
    dependencies.chatModelCatalog().loadPreferences(prefs);
    dependencies.imageModels().loadPreferences(prefs);
    dependencies.videoAssets().loadPreferences(prefs);
    _loadVideoDrafts(dependencies, prefs);
    await _restoreGenerationSources(dependencies, prefs);
    dependencies.galleryBrowser().loadPreferences(prefs);
    dependencies.jobRuntime.interJobDelaySeconds =
        readInterJobDelaySeconds(prefs);
    dependencies.scalingPreferences.deleteSourceAfterScaling =
        prefs.getBool(SettingsKeys.deleteSourceAfterScaling) ?? false;
    dependencies.logs().loadPreferences(prefs);
    dependencies.system().loadWakeOnLanPreferences(prefs);
  }

  Future<bool> save(
    SettingsPersistenceScope dependencies,
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
    SettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    final legacyPositivePrompt =
        prefs.getString(SettingsKeys.legacyPositive) ?? '';
    final legacyNegativePrompt =
        prefs.getString(SettingsKeys.legacyNegative) ?? '';
    await dependencies.promptLibrary().loadFromPreferences(
      prefs,
      legacyPositivePrompt: legacyPositivePrompt,
      legacyNegativePrompt: legacyNegativePrompt,
    );
    await prefs.remove(SettingsKeys.legacyPositive);
    await prefs.remove(SettingsKeys.legacyNegative);
  }

  void _loadVideoDrafts(
    SettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) {
    dependencies.videoSettings().loadDrafts(
      width: prefs.getString(SettingsKeys.videoCustomWidth) ?? '',
      height: prefs.getString(SettingsKeys.videoCustomHeight) ?? '',
      fps: prefs.getString(SettingsKeys.videoCustomFps) ?? '',
      numFrames: prefs.getString(SettingsKeys.videoCustomNumFrames) ?? '',
    );
  }

  Future<void> _restoreGenerationSources(
    SettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    final restoredImageSource = await dependencies
        .generationSources()
        .restorePersistedSource(
          prefs.getString(SettingsKeys.imageGenerationSource),
          forVideo: false,
        );
    if (!restoredImageSource) {
      await prefs.remove(SettingsKeys.imageGenerationSource);
    }
    final restoredVideoSource = await dependencies
        .generationSources()
        .restorePersistedSource(
          prefs.getString(SettingsKeys.videoGenerationSource),
          forVideo: true,
        );
    if (!restoredVideoSource) {
      await prefs.remove(SettingsKeys.videoGenerationSource);
    }
  }

  Future<void> _saveCoreSettings(
    SettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    await prefs.setString(
      SettingsKeys.baseUrl,
      dependencies.connection.baseUrl,
    );
    await prefs.setString(
      SettingsKeys.themeMode,
      dependencies.connection.themeMode.name,
    );
    await dependencies.galleryBrowser().savePreferences();
    await prefs.setInt(
      interJobDelaySecondsPreferenceKey,
      dependencies.jobRuntime.interJobDelaySeconds,
    );
    await prefs.setBool(
      SettingsKeys.deleteSourceAfterScaling,
      dependencies.scalingPreferences.deleteSourceAfterScaling,
    );
    await prefs.setString(
      LogStore.selectedSourceKey,
      dependencies.logs().selectedSource,
    );
    await prefs.setString(
      LogStore.severityFilterKey,
      dependencies.logs().severityFilter,
    );
    await prefs.setInt(LogStore.rowLimitKey, dependencies.logs().rowLimit);
    await prefs.setBool(
      LogStore.followLatestKey,
      dependencies.logs().followLatest,
    );
  }

  Future<void> _saveChatSettings(
    SettingsPersistenceScope dependencies,
    SharedPreferences prefs,
  ) async {
    final contextWindow = dependencies.chatRuntime.contextWindow;
    if (contextWindow == null) {
      await prefs.remove(SettingsKeys.chatContextWindow);
    } else {
      await prefs.setInt(SettingsKeys.chatContextWindow, contextWindow);
    }
    await prefs.setBool(
      SettingsKeys.chatThinkingEnabled,
      dependencies.chatRuntime.thinkingEnabled,
    );
  }
}
