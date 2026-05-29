import 'package:flutter/material.dart';

import 'package:noviagen/features/generate/domain/generation_settings.dart';
import 'package:noviagen/app/persistence/generation_draft_persistence.dart';
import 'package:noviagen/app/persistence/settings_persistence.dart';
import 'package:noviagen/app/persistence/settings_persistence_scope.dart';


class ConfigurationDependencies {
  const ConfigurationDependencies({
    required this.persistence,
    required this.resetPolling,
    required this.syncMediaRefreshTimer,
    required this.clearBackendBoundState,
    required this.notifyChanged,
  });

  final SettingsPersistenceScope persistence;
  final void Function() resetPolling;
  final void Function() syncMediaRefreshTimer;
  final void Function() clearBackendBoundState;
  final void Function() notifyChanged;
}

class SaveSettingsRequest {
  const SaveSettingsRequest({
    required this.baseUrl,
    required this.themeMode,
    required this.numInferenceSteps,
    required this.guidanceScale,
    required this.imageOrientation,
    required this.promptGeneratorBasePrompt,
    required this.imageToVideoPromptGeneratorBasePrompt,
    required this.gallerySlideshowIntervalSeconds,
    required this.interJobDelaySeconds,
    required this.deleteSourceAfterScaling,
    required this.chatContextWindow,
    required this.chatThinkingEnabled,
    required this.autoPromptModelName,
    required this.imageToVideoAutoPromptModelName,
    required this.wakeOnLanMacAddress,
    required this.wakeOnLanBroadcastAddress,
    required this.wakeOnLanPort,
  });

  final String baseUrl;
  final ThemeMode themeMode;
  final int numInferenceSteps;
  final double guidanceScale;
  final ImageOrientationSetting imageOrientation;
  final String promptGeneratorBasePrompt;
  final String imageToVideoPromptGeneratorBasePrompt;
  final int gallerySlideshowIntervalSeconds;
  final int interJobDelaySeconds;
  final bool deleteSourceAfterScaling;
  final int? chatContextWindow;
  final bool chatThinkingEnabled;
  final String? autoPromptModelName;
  final String? imageToVideoAutoPromptModelName;
  final String wakeOnLanMacAddress;
  final String wakeOnLanBroadcastAddress;
  final String wakeOnLanPort;
}

class ConfigurationController {
  ConfigurationController(this.dependencies);

  final ConfigurationDependencies dependencies;
  final SettingsPersistence _persistence = SettingsPersistence();
  final GenerationDraftPersistence _draftPersistence =
      const GenerationDraftPersistence();

  Future<void> loadSettings() async {
    await _persistence.load(dependencies.persistence);
    dependencies.syncMediaRefreshTimer();
    dependencies.notifyChanged();
  }

  Future<bool> saveSettings(SaveSettingsRequest request) async {
    final didChangeBaseUrl = await _persistence.save(
      dependencies.persistence,
      SaveAppSettingsInput(
        baseUrl: request.baseUrl,
        themeMode: request.themeMode,
        numInferenceSteps: request.numInferenceSteps,
        guidanceScale: request.guidanceScale,
        imageOrientation: request.imageOrientation,
        promptGeneratorBasePrompt: request.promptGeneratorBasePrompt,
        imageToVideoPromptGeneratorBasePrompt:
            request.imageToVideoPromptGeneratorBasePrompt,
        gallerySlideshowIntervalSeconds:
            request.gallerySlideshowIntervalSeconds,
        interJobDelaySeconds: request.interJobDelaySeconds,
        deleteSourceAfterScaling: request.deleteSourceAfterScaling,
        chatContextWindow: request.chatContextWindow,
        chatThinkingEnabled: request.chatThinkingEnabled,
        autoPromptModelName: request.autoPromptModelName,
        imageToVideoAutoPromptModelName:
            request.imageToVideoAutoPromptModelName,
        wakeOnLanMacAddress: request.wakeOnLanMacAddress,
        wakeOnLanBroadcastAddress: request.wakeOnLanBroadcastAddress,
        wakeOnLanPort: request.wakeOnLanPort,
      ),
    );
    if (didChangeBaseUrl) {
      dependencies.clearBackendBoundState();
    }
    dependencies.syncMediaRefreshTimer();
    dependencies.notifyChanged();
    return didChangeBaseUrl;
  }

  Future<void> persistGenerateDraft() {
    return _draftPersistence.persistGenerateDraft(dependencies.persistence);
  }

  Future<void> persistGenerationSource({required bool forVideo}) {
    return _draftPersistence.persistGenerationSource(
      dependencies.persistence,
      forVideo: forVideo,
    );
  }

  Future<void> persistVideoDraft() {
    return _draftPersistence.persistVideoDraft(dependencies.persistence);
  }

  Future<void> persistSelectedVideoPreset() {
    return _draftPersistence.persistSelectedVideoPreset(
      dependencies.persistence,
    );
  }
}
