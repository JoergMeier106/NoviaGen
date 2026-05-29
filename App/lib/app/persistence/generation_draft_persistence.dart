import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:noviagen/app/persistence/settings_keys.dart';
import 'package:noviagen/app/persistence/settings_persistence_scope.dart';


class GenerationDraftPersistence {
  const GenerationDraftPersistence();

  Future<void> persistGenerateDraft(
    SettingsPersistenceScope dependencies,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      SettingsKeys.promptDraft,
      dependencies.generationDrafts.imagePrompt,
    );
    await dependencies.imageModels().savePreferences();
  }

  Future<void> persistGenerationSource(
    SettingsPersistenceScope dependencies, {
    required bool forVideo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = forVideo
        ? SettingsKeys.videoGenerationSource
        : SettingsKeys.imageGenerationSource;
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
    SettingsPersistenceScope dependencies,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      SettingsKeys.videoPromptDraft,
      dependencies.generationDrafts.videoPrompt,
    );
    await prefs.setString(
      SettingsKeys.videoCustomWidth,
      dependencies.videoSettings().widthDraft,
    );
    await prefs.setString(
      SettingsKeys.videoCustomHeight,
      dependencies.videoSettings().heightDraft,
    );
    await prefs.setString(
      SettingsKeys.videoCustomFps,
      dependencies.videoSettings().fpsDraft,
    );
    await prefs.setString(
      SettingsKeys.videoCustomNumFrames,
      dependencies.videoSettings().numFramesDraft,
    );
  }

  Future<void> persistSelectedVideoPreset(
    SettingsPersistenceScope dependencies,
  ) async {
    await dependencies.videoAssets().saveSelectedPreset();
    await persistVideoDraft(dependencies);
  }
}
