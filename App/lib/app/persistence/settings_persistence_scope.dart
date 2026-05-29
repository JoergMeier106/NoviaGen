import 'package:flutter/material.dart';

import 'package:noviagen/features/chat/state/chat_model_catalog_store.dart';
import 'package:noviagen/features/chat/state/chat_session_store.dart';
import 'package:noviagen/features/gallery/state/gallery_browser_store.dart';
import 'package:noviagen/features/generate/state/generation_defaults_store.dart';
import 'package:noviagen/features/generate/state/generation_source_store.dart';
import 'package:noviagen/features/generate/domain/generation_settings.dart';
import 'package:noviagen/features/generate/state/image_model_selection_store.dart';
import 'package:noviagen/features/settings/logs/log_store.dart';
import 'package:noviagen/features/prompts/state/prompt_library_store.dart';
import 'package:noviagen/features/settings/system/system_operations_controller.dart';
import 'package:noviagen/features/generate/state/video_asset_selection_store.dart';
import 'package:noviagen/features/generate/state/video_generation_settings_store.dart';
import 'package:noviagen/app/runtime/app_chat_runtime_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/generation_draft_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';
import 'package:noviagen/app/runtime/scaling_preferences_store.dart';


class SettingsPersistenceScope {
  const SettingsPersistenceScope({
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

  final AppConnectionStore connection;
  final PromptLibraryStore Function() promptLibrary;
  final GenerationDefaultsStore Function() generationDefaults;
  final GenerationDraftStore generationDrafts;
  final ChatSessionStore Function() chat;
  final AppChatRuntimeStore chatRuntime;
  final ChatModelCatalogStore Function() chatModelCatalog;
  final ImageModelSelectionStore Function() imageModels;
  final VideoAssetSelectionStore Function() videoAssets;
  final VideoGenerationSettingsStore Function() videoSettings;
  final GenerationSourceStore Function() generationSources;
  final GalleryBrowserStore Function() galleryBrowser;
  final JobRuntimeStore jobRuntime;
  final ScalingPreferencesStore scalingPreferences;
  final LogStore Function() logs;
  final SystemOperationsController Function() system;
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
