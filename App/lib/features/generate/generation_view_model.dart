import 'package:flutter/foundation.dart';

import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/models/gallery.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/app/controllers/asset_refresh_controller.dart';
import 'package:flutter_app/features/generate/controllers/generation_source_controller.dart';
import 'package:flutter_app/features/generate/controllers/image_generation_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_generation_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_lucky_generation_controller.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/generation_draft_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';
import 'package:flutter_app/features/generate/controllers/auto_prompt_controller.dart';
import 'package:flutter_app/features/chat/state/chat_attachment_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/domain/generation_settings.dart';
import 'package:flutter_app/features/generate/state/generation_source_store.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/features/jobs/controllers/job_operations_controller.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';

abstract class GenerationViewModel implements Listenable {
  String get baseUrl;
  String? get message;
  String get imagePrompt;
  String get videoPrompt;
  GenerateMode get mode;
  ImageRecord? get latestImage;
  List<ModelAsset> get models;
  List<ModelAsset> get modelsByRating;
  String? get selectedModelId;
  List<LoraAsset> get loras;
  Map<String, double> get selectedLoraStrengths;
  List<PromptPreset> get presets;
  String? get selectedImagePresetId;
  String? get selectedVideoPresetId;
  ImageOrientationSetting get imageOrientation;
  double get imageToImageStrength;
  bool get hasImageSource;
  bool get hasVideoSource;
  ImageRecord? get imageSource;
  LocalImageSource? get imageLocalSource;
  ImageRecord? get videoSource;
  LocalImageSource? get videoLocalSource;
  bool get generatingPrompt;
  List<VideoPresetOption> get videoPresets;
  VideoPresetOption? get selectedPreset;
  List<VideoModelAsset> get videoModels;
  String? get validationMessage;
  Map<String, int>? get currentSettings;
  String? get resolutionAdjustmentLabel;
  double? get currentDurationSeconds;
  String get widthDraft;
  String get heightDraft;
  String get fpsDraft;
  String get numFramesDraft;

  Future<void> syncInterJobDelaySetting({bool silent = false});
  Future<void> restoreActiveJobOnLaunch();
  Future<void> refreshAssets();
  void setGenerateMode(GenerateMode value);
  Future<String?> generatePromptText({
    required bool forVideo,
    required String currentPrompt,
  });
  Future<ImageRecord?> generate(String prompt);
  Future<ImageRecord?> generateFeelingLucky();
  Future<ImageRecord?> submit(String prompt);
  Future<ImageRecord?> generateLuckyVideo();
  void setPromptDraft(String value);
  void setVideoPromptDraft(String value);
  void setSelectedModel(String? modelId);
  void randomizeImageModelAndLoras();
  void setImageOrientation(ImageOrientationSetting value);
  void toggleLora(LoraAsset lora, bool enabled);
  void setLoraStrength(String loraId, double strength);
  void clearSelectedLoras();
  void setImageToImageStrength(double value);
  Future<void> setSelectedImagePresetIdAndPersist(String? presetId);
  Future<void> setSelectedVideoPresetIdAndPersist(String? presetId);
  Future<void> attachLocalGenerationSource({
    required String path,
    required String name,
    required bool forVideo,
  });
  Future<void> attachStoredGenerationSource(ImageRecord image, {required bool forVideo});
  void clearImageGenerationSource();
  void clearVideoGenerationSource();
  void setVideoPreset(String value);
  void setWidthDraft(String value);
  void setHeightDraft(String value);
  void setFpsDraft(String value);
  void setNumFramesDraft(String value);
  void increaseResolution();
  void decreaseResolution();
  Future<GalleryPageResponse> fetchAttachableGalleryImagesPage({
    required String search,
    required int page,
    required int pageSize,
  });
  Future<String?> deleteStoredImage(String imageId);
}

class AppGenerationViewModel implements GenerationViewModel {
  AppGenerationViewModel({
    required this.changes,
    required this.connection,
    required this.drafts,
    required this.mediaRuntime,
    required this.jobOperations,
    required this.assetRefresh,
    required this.sourceController,
    required this.imageController,
    required this.videoController,
    required this.videoLuckyController,
    required this.autoPrompts,
    required this.chatContext,
    required this.defaults,
    required this.sources,
    required this.imageModels,
    required this.promptLibrary,
    required this.videoAssets,
    required this.videoSettings,
    required this.deleteStoredImageById,
  });

  final Listenable changes;
  final AppConnectionStore connection;
  final GenerationDraftStore drafts;
  final MediaRuntimeStore mediaRuntime;
  final JobOperationsController jobOperations;
  final AssetRefreshController assetRefresh;
  final GenerationSourceController sourceController;
  final ImageGenerationController imageController;
  final VideoGenerationController videoController;
  final VideoLuckyGenerationController videoLuckyController;
  final AutoPromptController autoPrompts;
  final ChatAttachmentStore chatContext;
  final GenerationDefaultsStore defaults;
  final GenerationSourceStore sources;
  final ImageModelSelectionStore imageModels;
  final PromptLibraryStore promptLibrary;
  final VideoAssetSelectionStore videoAssets;
  final VideoGenerationSettingsStore videoSettings;
  final Future<String?> Function(String imageId) deleteStoredImageById;

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => changes.removeListener(listener);

  @override
  String get baseUrl => connection.baseUrl;

  @override
  String? get message => connection.message;

  @override
  String get imagePrompt => drafts.imagePrompt;

  @override
  String get videoPrompt => drafts.videoPrompt;

  @override
  GenerateMode get mode => drafts.mode;

  @override
  ImageRecord? get latestImage => mediaRuntime.latestImage;

  @override
  List<ModelAsset> get models => imageModels.models;

  @override
  List<ModelAsset> get modelsByRating => imageModels.modelsByRating;

  @override
  String? get selectedModelId => imageModels.selectedModelId;

  @override
  List<LoraAsset> get loras => imageModels.loras;

  @override
  Map<String, double> get selectedLoraStrengths =>
      imageModels.selectedLoraStrengths;

  @override
  List<PromptPreset> get presets => promptLibrary.presets;

  @override
  String? get selectedImagePresetId => promptLibrary.selectedImagePresetId;

  @override
  String? get selectedVideoPresetId => promptLibrary.selectedVideoPresetId;

  @override
  ImageOrientationSetting get imageOrientation => defaults.imageOrientation;

  @override
  double get imageToImageStrength => defaults.imageToImageStrength;

  @override
  bool get hasImageSource => sources.hasImageSource;

  @override
  bool get hasVideoSource => sources.hasVideoSource;

  @override
  ImageRecord? get imageSource => sources.imageSource;

  @override
  LocalImageSource? get imageLocalSource => sources.imageLocalSource;

  @override
  ImageRecord? get videoSource => sources.videoSource;

  @override
  LocalImageSource? get videoLocalSource => sources.videoLocalSource;

  @override
  bool get generatingPrompt => autoPrompts.generatingPrompt;

  @override
  List<VideoPresetOption> get videoPresets => videoAssets.presets;

  @override
  VideoPresetOption? get selectedPreset => videoAssets.selectedPreset;

  @override
  List<VideoModelAsset> get videoModels => videoAssets.videoModels;

  @override
  String? get validationMessage => videoSettings.validationMessage;

  @override
  Map<String, int>? get currentSettings => videoSettings.currentSettings;

  @override
  String? get resolutionAdjustmentLabel =>
      videoSettings.resolutionAdjustmentLabel;

  @override
  double? get currentDurationSeconds => videoSettings.currentDurationSeconds;

  @override
  String get widthDraft => videoSettings.widthDraft;

  @override
  String get heightDraft => videoSettings.heightDraft;

  @override
  String get fpsDraft => videoSettings.fpsDraft;

  @override
  String get numFramesDraft => videoSettings.numFramesDraft;

  @override
  Future<void> syncInterJobDelaySetting({bool silent = false}) =>
      jobOperations.syncInterJobDelaySetting(silent: silent);

  @override
  Future<void> restoreActiveJobOnLaunch() =>
      jobOperations.restoreActiveJobOnLaunch();

  @override
  Future<void> refreshAssets() => assetRefresh.refreshAssets();

  @override
  void setGenerateMode(GenerateMode value) =>
      sourceController.setGenerateMode(value);

  @override
  Future<String?> generatePromptText({
    required bool forVideo,
    required String currentPrompt,
  }) => autoPrompts.generatePromptText(
    forVideo: forVideo,
    currentPrompt: currentPrompt,
  );

  @override
  Future<ImageRecord?> generate(String prompt) => imageController.generate(prompt);

  @override
  Future<ImageRecord?> generateFeelingLucky() =>
      imageController.generateFeelingLucky();

  @override
  Future<ImageRecord?> submit(String prompt) => videoController.submit(prompt);

  @override
  Future<ImageRecord?> generateLuckyVideo() => videoLuckyController.generate();

  @override
  void setPromptDraft(String value) => sourceController.setPromptDraft(value);

  @override
  void setVideoPromptDraft(String value) =>
      sourceController.setVideoPromptDraft(value);

  @override
  void setSelectedModel(String? modelId) => imageModels.setSelectedModel(modelId);

  @override
  void randomizeImageModelAndLoras() =>
      imageModels.randomizeImageModelAndLoras();

  @override
  void setImageOrientation(ImageOrientationSetting value) =>
      defaults.setImageOrientation(value);

  @override
  void toggleLora(LoraAsset lora, bool enabled) =>
      imageModels.toggleLora(lora, enabled);

  @override
  void setLoraStrength(String loraId, double strength) =>
      imageModels.setLoraStrength(loraId, strength);

  @override
  void clearSelectedLoras() => imageModels.clearSelectedLoras();

  @override
  void setImageToImageStrength(double value) =>
      sourceController.setImageToImageStrength(value);

  @override
  Future<void> setSelectedImagePresetIdAndPersist(String? presetId) =>
      promptLibrary.setSelectedImagePresetIdAndPersist(presetId);

  @override
  Future<void> setSelectedVideoPresetIdAndPersist(String? presetId) =>
      promptLibrary.setSelectedVideoPresetIdAndPersist(presetId);

  @override
  Future<void> attachLocalGenerationSource({
    required String path,
    required String name,
    required bool forVideo,
  }) => sourceController.attachLocalGenerationSource(
    path: path,
    name: name,
    forVideo: forVideo,
  );

  @override
  Future<void> attachStoredGenerationSource(
    ImageRecord image, {
    required bool forVideo,
  }) => sourceController.attachStoredGenerationSource(
    image,
    forVideo: forVideo,
  );

  @override
  void clearImageGenerationSource() =>
      sourceController.clearImageGenerationSource();

  @override
  void clearVideoGenerationSource() =>
      sourceController.clearVideoGenerationSource();

  @override
  void setVideoPreset(String value) => sourceController.setVideoPreset(value);

  @override
  void setWidthDraft(String value) => videoSettings.setWidthDraft(value);

  @override
  void setHeightDraft(String value) => videoSettings.setHeightDraft(value);

  @override
  void setFpsDraft(String value) => videoSettings.setFpsDraft(value);

  @override
  void setNumFramesDraft(String value) => videoSettings.setNumFramesDraft(value);

  @override
  void increaseResolution() => videoSettings.increaseResolution();

  @override
  void decreaseResolution() => videoSettings.decreaseResolution();

  @override
  Future<GalleryPageResponse> fetchAttachableGalleryImagesPage({
    required String search,
    required int page,
    required int pageSize,
  }) => chatContext.fetchAttachableGalleryImagesPage(
    search: search,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<String?> deleteStoredImage(String imageId) =>
      deleteStoredImageById(imageId);
}
