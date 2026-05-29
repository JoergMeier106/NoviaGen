import 'package:flutter/material.dart';

import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/models/backups.dart';
import 'package:flutter_app/models/chat_models.dart';
import 'package:flutter_app/models/chat_sessions.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/models/system.dart';
import 'package:flutter_app/app/app_change_bus.dart';
import 'package:flutter_app/app/controllers/asset_refresh_controller.dart';
import 'package:flutter_app/app/controllers/backend_refresh_controller.dart';
import 'package:flutter_app/app/controllers/configuration_controller.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_chat_runtime_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/scaling_preferences_store.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/chat/state/chat_session_store.dart';
import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/domain/video_diffusion_model_selection.dart';
import 'package:flutter_app/features/generate/domain/video_workflow_lora_selection.dart';
import 'package:flutter_app/features/generate/domain/generation_settings.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/features/jobs/controllers/job_operations_controller.dart';
import 'package:flutter_app/features/settings/logs/log_store.dart';
import 'package:flutter_app/features/gallery/controllers/media_actions_controller.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/features/settings/system/system_operations_controller.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/settings/system/wake_on_lan_settings.dart';

abstract class SettingsViewModel implements Listenable {
  String get baseUrl;
  set baseUrl(String value);
  String? get message;
  ThemeMode get themeMode;
  set themeMode(ThemeMode value);
  int? get contextWindow;
  set contextWindow(int? value);
  bool get thinkingEnabled;
  set thinkingEnabled(bool value);
  int get slideshowIntervalSeconds;
  set slideshowIntervalSeconds(int value);
  bool get deleteSourceAfterScaling;
  set deleteSourceAfterScaling(bool value);
  WakeOnLanSettings get wakeOnLan;
  BackendHealth? get backendHealth;
  BackendSystemInfo? get systemInfo;
  bool get loadingSystemInfo;
  bool get loadingHealth;
  bool get loadingAssets;
  bool get loadingJobs;
  bool get importingGalleryMedia;
  List<ModelAsset> get models;
  List<ModelAsset> get modelsByRating;
  List<LoraAsset> get loras;
  List<VideoModelAsset> get videoModels;
  List<VideoDiffusionModelAsset> get diffusionModels;
  List<VideoPresetOption> get videoPresets;
  List<JobStatus> get jobs;
  int get interJobDelaySeconds;
  List<AppErrorRecord> get errors;
  bool get loadingErrors;
  bool get clearingErrors;
  List<BackupRecord> get backups;
  List<BackupRecord> get appBackups;
  bool get loadingBackups;
  bool get loadingAppBackups;
  bool get creatingBackup;
  bool get creatingAppBackup;
  bool get applyingBackup;
  bool get applyingAppBackup;
  bool get clearingFinishedJobs;
  bool get cancellingAllJobs;
  bool get updatingShutdownWhenJobsComplete;
  bool get shutdownWhenJobsComplete;
  List<PromptPreset> get presets;
  List<SavedPrompt> get savedPromptsTextToImage;
  String? get selectedImagePresetId;
  String? get selectedVideoPresetId;
  int get numInferenceSteps;
  double get guidanceScale;
  int get imageToImageNumInferenceSteps;
  double get imageToImageGuidanceScale;
  ImageOrientationSetting get imageOrientation;
  String get promptGeneratorBasePrompt;
  String get imageToImagePromptGeneratorBasePrompt;
  String get textToVideoPromptGeneratorBasePrompt;
  String get imageToVideoPromptGeneratorBasePrompt;
  bool get textToImageAutoMetadataEnabled;
  bool get imageToImageAutoMetadataEnabled;
  String? get selectedTextToImageAutoMetadataModelName;
  String? get selectedImageToImageAutoMetadataModelName;
  String? get preferredAutoPromptModelName;
  String? get preferredImageToVideoAutoPromptModelName;
  List<OllamaModelInfo> get autoPromptModels;
  String? get selectedAutoPromptModelName;
  String? get selectedImageToImageAutoPromptModelName;
  String? get selectedTextToVideoAutoPromptModelName;
  String? get selectedImageToVideoAutoPromptModelName;
  String? get selectedTextToVideoHighDiffusionModel;
  String? get selectedTextToVideoLowDiffusionModel;
  String? get selectedImageToVideoHighDiffusionModel;
  String? get selectedImageToVideoLowDiffusionModel;
  List<VideoDiffusionModelSelectionOption>
  get textToVideoDiffusionModelSelections;
  String? get selectedTextToVideoDiffusionModelSelectionValue;
  List<VideoDiffusionModelSelectionOption>
  get imageToVideoDiffusionModelSelections;
  String? get selectedImageToVideoDiffusionModelSelectionValue;
  List<VideoWorkflowLoraAsset> get textToVideoWorkflowLoras;
  List<VideoWorkflowLoraAsset> get imageToVideoWorkflowLoras;
  Map<String, double> get textToVideoWorkflowLoraStrengths;
  Map<String, double> get imageToVideoWorkflowLoraStrengths;
  List<VideoWorkflowLoraSelectionOption> get textToVideoWorkflowLoraSelections;
  List<VideoWorkflowLoraSelectionOption> get imageToVideoWorkflowLoraSelections;
  Map<String, double> get textToVideoWorkflowLoraSelectionStrengths;
  Map<String, double> get imageToVideoWorkflowLoraSelectionStrengths;
  String get selectedSource;
  String get severityFilter;
  int get rowLimit;
  ChatSessionRecord? get selectedSession;

  void notifyStateChanged();
  Future<void> refreshAssets();
  Future<void> refreshBackendData({bool silent = true});
  Future<bool> saveSettings(SaveSettingsRequest request);
  Future<void> loadLatestResult({bool silent = false});
  Future<void> loadAutoPromptModels({bool silent = false});
  OllamaModelInfo? selectedChatModelInfo(ChatSessionRecord? session);
  Future<void> setPreferredAutoPromptModelName(String? modelName);
  Future<void> setPreferredImageToImageAutoPromptModelName(String? modelName);
  Future<void> setPreferredTextToVideoAutoPromptModelName(String? modelName);
  Future<void> setPreferredImageToVideoAutoPromptModelName(String? modelName);
  Future<void> setPromptGeneratorBasePrompt(String value);
  Future<void> setImageToImagePromptGeneratorBasePrompt(String value);
  Future<void> setTextToVideoPromptGeneratorBasePrompt(String value);
  Future<void> setImageToVideoPromptGeneratorBasePrompt(String value);
  Future<void> setTextToImageAutoMetadataEnabled(bool value);
  Future<void> setImageToImageAutoMetadataEnabled(bool value);
  Future<void> setTextToImageAutoMetadataModelName(String? modelName);
  Future<void> setImageToImageAutoMetadataModelName(String? modelName);
  Future<void> setTextToImageGenerationDefaults({
    required int steps,
    required double guidance,
  });
  Future<void> setImageToImageGenerationDefaults({
    required int steps,
    required double guidance,
  });
  void setTextToVideoHighDiffusionModel(String? value);
  void setTextToVideoLowDiffusionModel(String? value);
  void setImageToVideoHighDiffusionModel(String? value);
  void setImageToVideoLowDiffusionModel(String? value);
  void setTextToVideoDiffusionModelSelection(String? value);
  void setImageToVideoDiffusionModelSelection(String? value);
  void setTextToVideoWorkflowLoraStrength(String loraId, double strength);
  void setImageToVideoWorkflowLoraStrength(String loraId, double strength);
  Future<void> createPresetAndPersist({
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  });
  Future<void> updatePresetAndPersist({
    required String id,
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  });
  Future<void> deletePresetAndPersist(String id);
  Future<void> createSavedPromptAndPersist(
    SavedPromptCollection collection, {
    required String idPrefix,
    required String name,
    required String prompt,
  });
  Future<void> updateSavedPromptAndPersist({
    required SavedPromptCollection collection,
    required String id,
    required String name,
    required String prompt,
  });
  Future<void> deleteSavedPromptAndPersist(
    SavedPromptCollection collection,
    String id,
  );
  List<SavedPrompt> savedPrompts(SavedPromptCollection collection);
  Future<void> loadHealth({bool silent = false});
  Future<void> loadSystemInfo({bool silent = false});
  Future<void> loadErrors({bool silent = false});
  Future<void> clearErrors();
  Future<void> loadBackups();
  Future<void> loadAppBackups();
  Future<void> createBackup();
  Future<void> createAppBackup();
  Future<void> deleteBackup(String backupName);
  Future<void> deleteAppBackup(String backupName);
  Future<void> applyBackup(String backupName, {bool merge = false});
  Future<void> applyAppBackup(String backupName);
  Future<void> forceUnloadAllModels();
  Future<void> deleteModel(String modelId);
  Future<void> deleteLora(String loraId);
  Future<void> shutdownHost();
  Future<void> restartServer();
  Future<void> sendWakeOnLan({
    required String macAddress,
    required String broadcastAddress,
    required String port,
    required String baseUrl,
  });
  Future<void> loadJobs();
  Future<void> cancelJob(String jobId);
  Future<void> cancelAllJobs();
  Future<void> clearFinishedJobs();
  Future<void> setShutdownWhenJobsComplete(bool value);
  Future<void> syncInterJobDelaySetting({bool silent = false});
  Future<bool> saveInterJobDelaySeconds(int value);
  bool isLoading(String source);
  BackendLogSnapshot? snapshotForSource(String source);
  Future<void> load({
    required String source,
    required int limit,
    bool silent = false,
  });
  Future<void> savePreferences({
    String? selectedSource,
    String? severityFilter,
    int? rowLimit,
    bool? followLatest,
  });
}

class AppSettingsViewModel implements SettingsViewModel {
  AppSettingsViewModel({
    required this.changes,
    required this.connection,
    required this.activity,
    required this.chatRuntime,
    required this.jobRuntime,
    required this.scalingPreferences,
    required this.assetRefresh,
    required this.backendRefresh,
    required this.configuration,
    required this.chatModelCatalog,
    required this.chatSessions,
    required this.galleryBrowser,
    required this.defaults,
    required this.imageModels,
    required this.jobOperations,
    required this.logs,
    required this.mediaActions,
    required this.promptLibrary,
    required this.systemOperations,
    required this.videoAssets,
  });

  final AppChangeBus changes;
  final AppConnectionStore connection;
  final AppActivityStore activity;
  final AppChatRuntimeStore chatRuntime;
  final JobRuntimeStore jobRuntime;
  final ScalingPreferencesStore scalingPreferences;
  final AssetRefreshController assetRefresh;
  final BackendRefreshController backendRefresh;
  final ConfigurationController configuration;
  final ChatModelCatalogStore chatModelCatalog;
  final ChatSessionStore chatSessions;
  final GalleryBrowserStore galleryBrowser;
  final GenerationDefaultsStore defaults;
  final ImageModelSelectionStore imageModels;
  final JobOperationsController jobOperations;
  final LogStore logs;
  final MediaActionsController mediaActions;
  final PromptLibraryStore promptLibrary;
  final SystemOperationsController systemOperations;
  final VideoAssetSelectionStore videoAssets;

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      changes.removeListener(listener);

  @override
  void notifyStateChanged() => changes.notifyStateChanged();

  @override
  String get baseUrl => connection.baseUrl;

  @override
  set baseUrl(String value) => connection.baseUrl = value;

  @override
  String? get message => connection.message;

  @override
  ThemeMode get themeMode => connection.themeMode;

  @override
  set themeMode(ThemeMode value) => connection.themeMode = value;

  @override
  int? get contextWindow => chatRuntime.contextWindow;

  @override
  set contextWindow(int? value) => chatRuntime.contextWindow = value;

  @override
  bool get thinkingEnabled => chatRuntime.thinkingEnabled;

  @override
  set thinkingEnabled(bool value) => chatRuntime.thinkingEnabled = value;

  @override
  int get slideshowIntervalSeconds => galleryBrowser.slideshowIntervalSeconds;

  @override
  set slideshowIntervalSeconds(int value) =>
      galleryBrowser.slideshowIntervalSeconds = value;

  @override
  bool get deleteSourceAfterScaling =>
      scalingPreferences.deleteSourceAfterScaling;

  @override
  set deleteSourceAfterScaling(bool value) =>
      scalingPreferences.deleteSourceAfterScaling = value;

  @override
  WakeOnLanSettings get wakeOnLan => systemOperations.wakeOnLan;

  @override
  BackendHealth? get backendHealth => systemOperations.backendHealth;

  @override
  BackendSystemInfo? get systemInfo => systemOperations.systemInfo;

  @override
  bool get loadingSystemInfo => systemOperations.loadingSystemInfo;

  @override
  bool get loadingHealth => systemOperations.loadingHealth;

  @override
  bool get loadingAssets => activity.loadingAssets;

  @override
  bool get loadingJobs => activity.loadingJobs;

  @override
  bool get importingGalleryMedia => activity.importingGalleryMedia;

  @override
  List<ModelAsset> get models => imageModels.models;

  @override
  List<ModelAsset> get modelsByRating => imageModels.modelsByRating;

  @override
  List<LoraAsset> get loras => imageModels.loras;

  @override
  List<VideoModelAsset> get videoModels => videoAssets.videoModels;

  @override
  List<VideoDiffusionModelAsset> get diffusionModels =>
      videoAssets.diffusionModels;

  @override
  List<VideoPresetOption> get videoPresets => videoAssets.presets;

  @override
  List<JobStatus> get jobs => jobRuntime.jobs;

  @override
  int get interJobDelaySeconds => jobRuntime.interJobDelaySeconds;

  @override
  List<AppErrorRecord> get errors => systemOperations.errors;

  @override
  bool get loadingErrors => systemOperations.loadingErrors;

  @override
  bool get clearingErrors => systemOperations.clearingErrors;

  @override
  List<BackupRecord> get backups => systemOperations.backups;

  @override
  List<BackupRecord> get appBackups => systemOperations.appBackups;

  @override
  bool get loadingBackups => systemOperations.loadingBackups;

  @override
  bool get loadingAppBackups => systemOperations.loadingAppBackups;

  @override
  bool get creatingBackup => systemOperations.creatingBackup;

  @override
  bool get creatingAppBackup => systemOperations.creatingAppBackup;

  @override
  bool get applyingBackup => systemOperations.applyingBackup;

  @override
  bool get applyingAppBackup => systemOperations.applyingAppBackup;

  @override
  bool get clearingFinishedJobs => jobOperations.clearingFinishedJobs;

  @override
  bool get cancellingAllJobs => jobOperations.cancellingAllJobs;

  @override
  bool get updatingShutdownWhenJobsComplete =>
      jobOperations.updatingShutdownWhenJobsComplete;

  @override
  bool get shutdownWhenJobsComplete => jobOperations.shutdownWhenJobsComplete;

  @override
  List<PromptPreset> get presets => promptLibrary.presets;

  @override
  List<SavedPrompt> get savedPromptsTextToImage =>
      promptLibrary.textToImageAutoPromptBasePrompts;

  @override
  String? get selectedImagePresetId => promptLibrary.selectedImagePresetId;

  @override
  String? get selectedVideoPresetId => promptLibrary.selectedVideoPresetId;

  @override
  int get numInferenceSteps => defaults.numInferenceSteps;

  @override
  double get guidanceScale => defaults.guidanceScale;

  @override
  int get imageToImageNumInferenceSteps =>
      defaults.imageToImageNumInferenceSteps;

  @override
  double get imageToImageGuidanceScale => defaults.imageToImageGuidanceScale;

  @override
  ImageOrientationSetting get imageOrientation => defaults.imageOrientation;

  @override
  String get promptGeneratorBasePrompt => defaults.promptGeneratorBasePrompt;

  @override
  String get imageToImagePromptGeneratorBasePrompt =>
      defaults.imageToImagePromptGeneratorBasePrompt;

  @override
  String get textToVideoPromptGeneratorBasePrompt =>
      defaults.textToVideoPromptGeneratorBasePrompt;

  @override
  String get imageToVideoPromptGeneratorBasePrompt =>
      defaults.imageToVideoPromptGeneratorBasePrompt;

  @override
  bool get textToImageAutoMetadataEnabled =>
      defaults.textToImageAutoMetadataEnabled;

  @override
  bool get imageToImageAutoMetadataEnabled =>
      defaults.imageToImageAutoMetadataEnabled;

  @override
  String? get selectedTextToImageAutoMetadataModelName =>
      _selectedAutoMetadataModelName(defaults.textToImageAutoMetadataModelName);

  @override
  String? get selectedImageToImageAutoMetadataModelName =>
      _selectedAutoMetadataModelName(
        defaults.imageToImageAutoMetadataModelName,
      );

  @override
  String? get preferredAutoPromptModelName =>
      chatModelCatalog.preferredAutoPromptModelName;

  @override
  String? get preferredImageToVideoAutoPromptModelName =>
      chatModelCatalog.preferredImageToVideoAutoPromptModelName;

  @override
  List<OllamaModelInfo> get autoPromptModels =>
      chatModelCatalog.autoPromptModels;

  @override
  String? get selectedAutoPromptModelName =>
      chatModelCatalog.selectedAutoPromptModelName;

  @override
  String? get selectedImageToImageAutoPromptModelName =>
      chatModelCatalog.selectedImageToImageAutoPromptModelName;

  @override
  String? get selectedTextToVideoAutoPromptModelName =>
      chatModelCatalog.selectedTextToVideoAutoPromptModelName;

  @override
  String? get selectedImageToVideoAutoPromptModelName =>
      chatModelCatalog.selectedImageToVideoAutoPromptModelName;

  String? _selectedAutoMetadataModelName(String? preferredModelName) {
    final preferred = preferredModelName?.trim() ?? '';
    if (preferred.isNotEmpty &&
        chatModelCatalog.autoPromptModels.any(
          (item) => item.name == preferred,
        )) {
      return preferred;
    }
    if (chatModelCatalog.autoPromptModels.isNotEmpty) {
      return chatModelCatalog.autoPromptModels.first.name;
    }
    return null;
  }

  @override
  String? get selectedTextToVideoHighDiffusionModel =>
      videoAssets.selectedTextToVideoHighDiffusionModel;

  @override
  String? get selectedTextToVideoLowDiffusionModel =>
      videoAssets.selectedTextToVideoLowDiffusionModel;

  @override
  String? get selectedImageToVideoHighDiffusionModel =>
      videoAssets.selectedImageToVideoHighDiffusionModel;

  @override
  String? get selectedImageToVideoLowDiffusionModel =>
      videoAssets.selectedImageToVideoLowDiffusionModel;

  @override
  List<VideoDiffusionModelSelectionOption>
  get textToVideoDiffusionModelSelections =>
      videoAssets.textToVideoDiffusionModelSelections;

  @override
  String? get selectedTextToVideoDiffusionModelSelectionValue =>
      videoAssets.selectedTextToVideoDiffusionModelSelectionValue;

  @override
  List<VideoDiffusionModelSelectionOption>
  get imageToVideoDiffusionModelSelections =>
      videoAssets.imageToVideoDiffusionModelSelections;

  @override
  String? get selectedImageToVideoDiffusionModelSelectionValue =>
      videoAssets.selectedImageToVideoDiffusionModelSelectionValue;

  @override
  List<VideoWorkflowLoraAsset> get textToVideoWorkflowLoras =>
      videoAssets.textToVideoWorkflowLoras;

  @override
  List<VideoWorkflowLoraAsset> get imageToVideoWorkflowLoras =>
      videoAssets.imageToVideoWorkflowLoras;

  @override
  Map<String, double> get textToVideoWorkflowLoraStrengths =>
      videoAssets.textToVideoWorkflowLoraStrengths;

  @override
  Map<String, double> get imageToVideoWorkflowLoraStrengths =>
      videoAssets.imageToVideoWorkflowLoraStrengths;

  @override
  List<VideoWorkflowLoraSelectionOption>
  get textToVideoWorkflowLoraSelections =>
      videoAssets.textToVideoWorkflowLoraSelections;

  @override
  List<VideoWorkflowLoraSelectionOption>
  get imageToVideoWorkflowLoraSelections =>
      videoAssets.imageToVideoWorkflowLoraSelections;

  @override
  Map<String, double> get textToVideoWorkflowLoraSelectionStrengths =>
      videoAssets.textToVideoWorkflowLoraSelectionStrengths;

  @override
  Map<String, double> get imageToVideoWorkflowLoraSelectionStrengths =>
      videoAssets.imageToVideoWorkflowLoraSelectionStrengths;

  @override
  String get selectedSource => logs.selectedSource;

  @override
  String get severityFilter => logs.severityFilter;

  @override
  int get rowLimit => logs.rowLimit;

  @override
  ChatSessionRecord? get selectedSession => chatSessions.selectedSession;

  @override
  Future<void> refreshAssets() => assetRefresh.refreshAssets();

  @override
  Future<void> refreshBackendData({bool silent = true}) =>
      backendRefresh.refreshBackendData(silent: silent);

  @override
  Future<bool> saveSettings(SaveSettingsRequest request) =>
      configuration.saveSettings(request);

  @override
  Future<void> loadLatestResult({bool silent = false}) =>
      mediaActions.loadLatestResult(silent: silent);

  @override
  Future<void> loadAutoPromptModels({bool silent = false}) =>
      chatModelCatalog.loadAutoPromptModels(silent: silent);

  @override
  OllamaModelInfo? selectedChatModelInfo(ChatSessionRecord? session) =>
      chatModelCatalog.selectedChatModelInfo(session);

  @override
  Future<void> setPreferredAutoPromptModelName(String? modelName) {
    final normalized = modelName?.trim() ?? '';
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return chatModelCatalog.setPreferredAutoPromptModelName(normalized);
  }

  @override
  Future<void> setPreferredImageToImageAutoPromptModelName(String? modelName) {
    final normalized = modelName?.trim() ?? '';
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return chatModelCatalog.setPreferredImageToImageAutoPromptModelName(
      normalized,
    );
  }

  @override
  Future<void> setPreferredTextToVideoAutoPromptModelName(String? modelName) {
    final normalized = modelName?.trim() ?? '';
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return chatModelCatalog.setPreferredTextToVideoAutoPromptModelName(
      normalized,
    );
  }

  @override
  Future<void> setPreferredImageToVideoAutoPromptModelName(String? modelName) {
    final normalized = modelName?.trim() ?? '';
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return chatModelCatalog.setPreferredImageToVideoAutoPromptModelName(
      normalized,
    );
  }

  @override
  Future<void> setPromptGeneratorBasePrompt(String value) =>
      defaults.setPromptGeneratorBasePrompt(value);

  @override
  Future<void> setImageToImagePromptGeneratorBasePrompt(String value) =>
      defaults.setImageToImagePromptGeneratorBasePrompt(value);

  @override
  Future<void> setTextToVideoPromptGeneratorBasePrompt(String value) =>
      defaults.setTextToVideoPromptGeneratorBasePrompt(value);

  @override
  Future<void> setImageToVideoPromptGeneratorBasePrompt(String value) =>
      defaults.setImageToVideoPromptGeneratorBasePrompt(value);

  @override
  Future<void> setTextToImageAutoMetadataEnabled(bool value) =>
      defaults.setTextToImageAutoMetadataEnabled(value);

  @override
  Future<void> setImageToImageAutoMetadataEnabled(bool value) =>
      defaults.setImageToImageAutoMetadataEnabled(value);

  @override
  Future<void> setTextToImageAutoMetadataModelName(String? modelName) =>
      defaults.setTextToImageAutoMetadataModelName(modelName);

  @override
  Future<void> setImageToImageAutoMetadataModelName(String? modelName) =>
      defaults.setImageToImageAutoMetadataModelName(modelName);

  @override
  Future<void> setTextToImageGenerationDefaults({
    required int steps,
    required double guidance,
  }) => defaults.setTextToImageGenerationDefaults(
    steps: steps,
    guidance: guidance,
  );

  @override
  Future<void> setImageToImageGenerationDefaults({
    required int steps,
    required double guidance,
  }) => defaults.setImageToImageGenerationDefaults(
    steps: steps,
    guidance: guidance,
  );

  @override
  void setTextToVideoHighDiffusionModel(String? value) =>
      videoAssets.setTextToVideoHighDiffusionModel(value);

  @override
  void setTextToVideoLowDiffusionModel(String? value) =>
      videoAssets.setTextToVideoLowDiffusionModel(value);

  @override
  void setImageToVideoHighDiffusionModel(String? value) =>
      videoAssets.setImageToVideoHighDiffusionModel(value);

  @override
  void setImageToVideoLowDiffusionModel(String? value) =>
      videoAssets.setImageToVideoLowDiffusionModel(value);

  @override
  void setTextToVideoDiffusionModelSelection(String? value) =>
      videoAssets.setTextToVideoDiffusionModelSelection(value);

  @override
  void setImageToVideoDiffusionModelSelection(String? value) =>
      videoAssets.setImageToVideoDiffusionModelSelection(value);

  @override
  void setTextToVideoWorkflowLoraStrength(String loraId, double strength) =>
      videoAssets.setTextToVideoWorkflowLoraStrength(loraId, strength);

  @override
  void setImageToVideoWorkflowLoraStrength(String loraId, double strength) =>
      videoAssets.setImageToVideoWorkflowLoraStrength(loraId, strength);

  @override
  Future<void> createPresetAndPersist({
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  }) => promptLibrary.createPresetAndPersist(
    name: name,
    positivePrompt: positivePrompt,
    negativePrompt: negativePrompt,
  );

  @override
  Future<void> updatePresetAndPersist({
    required String id,
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  }) => promptLibrary.updatePresetAndPersist(
    id: id,
    name: name,
    positivePrompt: positivePrompt,
    negativePrompt: negativePrompt,
  );

  @override
  Future<void> deletePresetAndPersist(String id) =>
      promptLibrary.deletePresetAndPersist(id);

  @override
  Future<void> createSavedPromptAndPersist(
    SavedPromptCollection collection, {
    required String idPrefix,
    required String name,
    required String prompt,
  }) => promptLibrary.createSavedPromptAndPersist(
    collection,
    idPrefix: idPrefix,
    name: name,
    prompt: prompt,
  );

  @override
  Future<void> updateSavedPromptAndPersist({
    required SavedPromptCollection collection,
    required String id,
    required String name,
    required String prompt,
  }) => promptLibrary.updateSavedPromptAndPersist(
    collection: collection,
    id: id,
    name: name,
    prompt: prompt,
  );

  @override
  Future<void> deleteSavedPromptAndPersist(
    SavedPromptCollection collection,
    String id,
  ) => promptLibrary.deleteSavedPromptAndPersist(collection, id);

  @override
  List<SavedPrompt> savedPrompts(SavedPromptCollection collection) =>
      promptLibrary.savedPrompts(collection);

  @override
  Future<void> loadHealth({bool silent = false}) =>
      systemOperations.loadHealth(silent: silent);

  @override
  Future<void> loadSystemInfo({bool silent = false}) =>
      systemOperations.loadSystemInfo(silent: silent);

  @override
  Future<void> loadErrors({bool silent = false}) =>
      systemOperations.loadErrors(silent: silent);

  @override
  Future<void> clearErrors() => systemOperations.clearErrors();

  @override
  Future<void> loadBackups() => systemOperations.loadBackups();

  @override
  Future<void> loadAppBackups() => systemOperations.loadAppBackups();

  @override
  Future<void> createBackup() => systemOperations.createBackup();

  @override
  Future<void> createAppBackup() => systemOperations.createAppBackup();

  @override
  Future<void> deleteBackup(String backupName) =>
      systemOperations.deleteBackup(backupName);

  @override
  Future<void> deleteAppBackup(String backupName) =>
      systemOperations.deleteAppBackup(backupName);

  @override
  Future<void> applyBackup(String backupName, {bool merge = false}) =>
      systemOperations.applyBackup(backupName, merge: merge);

  @override
  Future<void> applyAppBackup(String backupName) =>
      systemOperations.applyAppBackup(backupName);

  @override
  Future<void> forceUnloadAllModels() =>
      systemOperations.forceUnloadAllModels();

  @override
  Future<void> deleteModel(String modelId) =>
      systemOperations.deleteModel(modelId);

  @override
  Future<void> deleteLora(String loraId) => systemOperations.deleteLora(loraId);

  @override
  Future<void> shutdownHost() => systemOperations.shutdownHost();

  @override
  Future<void> restartServer() => systemOperations.restartServer();

  @override
  Future<void> sendWakeOnLan({
    required String macAddress,
    required String broadcastAddress,
    required String port,
    required String baseUrl,
  }) => systemOperations.sendWakeOnLan(
    macAddress: macAddress,
    broadcastAddress: broadcastAddress,
    port: port,
    baseUrl: baseUrl,
  );

  @override
  Future<void> loadJobs() => jobOperations.loadJobs();

  @override
  Future<void> cancelJob(String jobId) => jobOperations.cancelJob(jobId);

  @override
  Future<void> cancelAllJobs() => jobOperations.cancelAllJobs();

  @override
  Future<void> clearFinishedJobs() => jobOperations.clearFinishedJobs();

  @override
  Future<void> setShutdownWhenJobsComplete(bool value) =>
      jobOperations.setShutdownWhenJobsComplete(value);

  @override
  Future<void> syncInterJobDelaySetting({bool silent = false}) =>
      jobOperations.syncInterJobDelaySetting(silent: silent);

  @override
  Future<bool> saveInterJobDelaySeconds(int value) =>
      jobOperations.saveInterJobDelaySeconds(value);

  @override
  bool isLoading(String source) => logs.isLoading(source);

  @override
  BackendLogSnapshot? snapshotForSource(String source) =>
      logs.snapshotForSource(source);

  @override
  Future<void> load({
    required String source,
    required int limit,
    bool silent = false,
  }) => logs.load(source: source, limit: limit, silent: silent);

  @override
  Future<void> savePreferences({
    String? selectedSource,
    String? severityFilter,
    int? rowLimit,
    bool? followLatest,
  }) => logs.savePreferences(
    selectedSource: selectedSource,
    severityFilter: severityFilter,
    rowLimit: rowLimit,
    followLatest: followLatest,
  );
}
