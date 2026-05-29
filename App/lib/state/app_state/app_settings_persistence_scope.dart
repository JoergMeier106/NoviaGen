import 'package:flutter/material.dart';

import '../chat_model_catalog_state.dart';
import '../chat_session_state.dart';
import '../gallery_state.dart';
import '../generation_defaults_state.dart';
import '../generation_source_state.dart';
import '../generation_settings.dart';
import '../image_model_selection_state.dart';
import '../log_state.dart';
import '../prompt_library_state.dart';
import '../system_operations_state.dart';
import '../video_asset_selection_state.dart';
import '../video_generation_settings_state.dart';
import 'runtime/app_chat_runtime_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_generation_draft_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_scaling_preferences_state.dart';


class AppSettingsPersistenceScope {
  const AppSettingsPersistenceScope({
    required this.connection,
    required this.promptLibrary,
    required this.generationDefaults,
    required this.generationDrafts,
    required this.chat,
    required this.chatRuntime,
    required this.chatModelCatalog,
    required this.imageModels,
    required this.videoAssets,
    required this.videoSettings,
    required this.generationSources,
    required this.galleryBrowser,
    required this.jobRuntime,
    required this.scalingPreferences,
    required this.logs,
    required this.system,
  });

  final AppConnectionState connection;
  final PromptLibraryState Function() promptLibrary;
  final GenerationDefaultsState Function() generationDefaults;
  final AppGenerationDraftState generationDrafts;
  final ChatSessionState Function() chat;
  final AppChatRuntimeState chatRuntime;
  final ChatModelCatalogState Function() chatModelCatalog;
  final ImageModelSelectionState Function() imageModels;
  final VideoAssetSelectionState Function() videoAssets;
  final VideoGenerationSettingsState Function() videoSettings;
  final GenerationSourceState Function() generationSources;
  final GalleryBrowserState Function() galleryBrowser;
  final AppJobRuntimeState jobRuntime;
  final AppScalingPreferencesState scalingPreferences;
  final LogState Function() logs;
  final SystemOperationsState Function() system;
}

class SaveAppSettingsInput {
  const SaveAppSettingsInput({
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
