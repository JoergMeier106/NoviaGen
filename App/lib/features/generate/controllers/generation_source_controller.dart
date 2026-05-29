import 'dart:async';

import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/app/persistence/settings_codecs.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/domain/generation_settings.dart';
import 'package:flutter_app/features/generate/state/generation_source_store.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/app/controllers/configuration_controller.dart';
import 'package:flutter_app/app/runtime/generation_draft_store.dart';


class GenerationSourceDependencies {
  const GenerationSourceDependencies({
    required this.generationDrafts,
    required this.generationDefaults,
    required this.generationSources,
    required this.videoAssets,
    required this.videoSettings,
    required this.configuration,
    required this.navigation,
    required this.notifyChanged,
  });

  final GenerationDraftStore generationDrafts;
  final GenerationDefaultsStore generationDefaults;
  final GenerationSourceStore generationSources;
  final VideoAssetSelectionStore videoAssets;
  final VideoGenerationSettingsStore videoSettings;
  final ConfigurationController configuration;
  final AppNavigationController navigation;
  final void Function() notifyChanged;
}

class GenerationSourceController {
  GenerationSourceController(this.dependencies);

  final GenerationSourceDependencies dependencies;

  void setPromptDraft(String value) {
    dependencies.generationDrafts.imagePrompt = value;
    unawaited(dependencies.configuration.persistGenerateDraft());
    dependencies.notifyChanged();
  }

  Future<void> saveGeneratedImagePromptDraft(String value) async {
    dependencies.generationDrafts.imagePrompt = value;
    await dependencies.configuration.persistGenerateDraft();
  }

  Future<void> saveGeneratedVideoPromptDraft(String value) async {
    dependencies.generationDrafts.videoPrompt = value;
    await dependencies.configuration.persistVideoDraft();
  }

  void setImageToImageStrength(double value) {
    dependencies.generationDefaults.setImageToImageStrength(value);
  }

  void attachStoredImageForGeneration(ImageRecord image) {
    if (!dependencies.generationSources.attachStoredImageForImageGeneration(
      image,
    )) {
      return;
    }
    dependencies.generationDefaults.imageOrientation =
        imageOrientationFromString(image.imageOrientation);
    dependencies.generationDrafts.mode = GenerateMode.image;
    unawaited(dependencies.generationDefaults.persistImageOrientation());
    dependencies.navigation.requestOpenGeneratePage(scrollToTop: true);
    dependencies.notifyChanged();
  }

  Future<void> pickImageGenerationSource(ImageSource source) {
    return dependencies.generationSources.pickGenerationSource(
      source: source,
      forVideo: false,
    );
  }

  void clearImageGenerationSource() {
    dependencies.generationSources.clearImageSource();
  }

  Future<void> attachLocalGenerationSource({
    required String path,
    required String name,
    required bool forVideo,
  }) {
    return dependencies.generationSources.attachLocalGenerationSource(
      path: path,
      name: name,
      forVideo: forVideo,
    );
  }

  Future<void> attachStoredGenerationSource(
    ImageRecord image, {
    required bool forVideo,
  }) async {
    if (forVideo) {
      attachStoredImageForVideoGeneration(image);
      return;
    }
    attachStoredImageForGeneration(image);
  }

  void setVideoPromptDraft(String value) {
    dependencies.generationDrafts.videoPrompt = value;
    unawaited(dependencies.configuration.persistVideoDraft());
    dependencies.notifyChanged();
  }

  void setGenerateMode(GenerateMode value) {
    dependencies.generationDrafts.mode = value;
    dependencies.notifyChanged();
  }

  void setVideoPreset(String value) {
    dependencies.videoAssets.selectedPresetId = value;
    dependencies.videoSettings.ensureInitialized(force: true);
    unawaited(dependencies.configuration.persistSelectedVideoPreset());
    dependencies.notifyChanged();
  }

  void attachStoredImageForVideoGeneration(ImageRecord image) {
    if (!dependencies.generationSources.attachStoredImageForVideoGeneration(
      image,
    )) {
      return;
    }
    dependencies.videoSettings.syncDraftOrientationToSource();
    dependencies.generationDrafts.mode = GenerateMode.video;
    dependencies.navigation.requestOpenGeneratePage(scrollToTop: true);
    dependencies.notifyChanged();
  }

  Future<void> pickVideoGenerationSource(ImageSource source) {
    return dependencies.generationSources.pickGenerationSource(
      source: source,
      forVideo: true,
    );
  }

  void clearVideoGenerationSource() {
    dependencies.generationSources.clearVideoSource();
  }
}
