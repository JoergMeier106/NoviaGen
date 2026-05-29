import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_keys.dart';
import 'app_settings_persistence_scope.dart';


class AppGenerationDraftPersistence {
  const AppGenerationDraftPersistence();

  Future<void> persistGenerateDraft(
    AppSettingsPersistenceScope dependencies,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppSettingsKeys.promptDraft,
      dependencies.generationDrafts.imagePrompt,
    );
    await dependencies.imageModels().savePreferences();
  }

  Future<void> persistGenerationSource(
    AppSettingsPersistenceScope dependencies, {
    required bool forVideo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = forVideo
        ? AppSettingsKeys.videoGenerationSource
        : AppSettingsKeys.imageGenerationSource;
    final payload = dependencies.generationSources().encodePersistedSource(
      forVideo: forVideo,
    );
    if (payload == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(payload));
  }

  Future<void> persistVideoDraft(
    AppSettingsPersistenceScope dependencies,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppSettingsKeys.videoPromptDraft,
      dependencies.generationDrafts.videoPrompt,
    );
    await prefs.setString(
      AppSettingsKeys.videoCustomWidth,
      dependencies.videoSettings().widthDraft,
    );
    await prefs.setString(
      AppSettingsKeys.videoCustomHeight,
      dependencies.videoSettings().heightDraft,
    );
    await prefs.setString(
      AppSettingsKeys.videoCustomFps,
      dependencies.videoSettings().fpsDraft,
    );
    await prefs.setString(
      AppSettingsKeys.videoCustomNumFrames,
      dependencies.videoSettings().numFramesDraft,
    );
  }

  Future<void> persistSelectedVideoPreset(
    AppSettingsPersistenceScope dependencies,
  ) async {
    await dependencies.videoAssets().saveSelectedPreset();
    await persistVideoDraft(dependencies);
  }
}
