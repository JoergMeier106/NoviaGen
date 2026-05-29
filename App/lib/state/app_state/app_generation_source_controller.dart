import 'dart:async';

import 'package:image_picker/image_picker.dart';

import '../../models/media.dart';
import '../app_navigation_state.dart';
import '../app_state_codecs.dart';
import '../generation_defaults_state.dart';
import '../generation_settings.dart';
import '../generation_source_state.dart';
import '../video_asset_selection_state.dart';
import '../video_generation_settings_state.dart';
import 'app_configuration_controller.dart';
import 'runtime/app_generation_draft_state.dart';


class AppGenerationSourceDependencies {
  const AppGenerationSourceDependencies({
    required this.generationDrafts,
    required this.generationDefaults,
    required this.generationSources,
    required this.videoAssets,
    required this.videoSettings,
    required this.configuration,
    required this.navigation,
    required this.notifyChanged,
  });

  final AppGenerationDraftState generationDrafts;
  final GenerationDefaultsState generationDefaults;
  final GenerationSourceState generationSources;
  final VideoAssetSelectionState videoAssets;
  final VideoGenerationSettingsState videoSettings;
  final AppConfigurationController configuration;
  final AppNavigationState navigation;
  final void Function() notifyChanged;
}

class AppGenerationSourceController {
  AppGenerationSourceController(this.dependencies);

  final AppGenerationSourceDependencies dependencies;

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
