import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/features/generate/domain/video_diffusion_model_selection.dart';
import 'package:flutter_app/features/generate/domain/video_workflow_lora_selection.dart';
import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/models/generation.dart';
import 'package:flutter_app/app/persistence/settings_codecs.dart';

class VideoAssetSelectionStore {
  VideoAssetSelectionStore({required this.onChanged});

  static const selectedPresetKey = 'selected_video_preset_id';
  static const selectedHighDiffusionModelKey =
      'selected_video_high_diffusion_model_name';
  static const selectedLowDiffusionModelKey =
      'selected_video_low_diffusion_model_name';
  static const selectedImageToVideoHighDiffusionModelKey =
      'selected_i2v_high_diffusion_model_name';
  static const selectedImageToVideoLowDiffusionModelKey =
      'selected_i2v_low_diffusion_model_name';
  static const textToVideoWorkflowLoraStrengthsKey =
      't2v_workflow_lora_strengths';
  static const imageToVideoWorkflowLoraStrengthsKey =
      'i2v_workflow_lora_strengths';

  final void Function() onChanged;

  List<VideoModelAsset> videoModels = <VideoModelAsset>[];
  List<VideoDiffusionModelAsset> diffusionModels = <VideoDiffusionModelAsset>[];
  List<VideoPresetOption> presets = <VideoPresetOption>[];
  String? selectedPresetId;
  String? selectedTextToVideoHighDiffusionModelName;
  String? selectedTextToVideoLowDiffusionModelName;
  String? selectedImageToVideoHighDiffusionModelName;
  String? selectedImageToVideoLowDiffusionModelName;
  Map<String, double> textToVideoWorkflowLoraStrengths = <String, double>{};
  Map<String, double> imageToVideoWorkflowLoraStrengths = <String, double>{};

  VideoPresetOption? get selectedPreset {
    final presetId = selectedPresetId;
    if (presetId != null) {
      for (final preset in presets) {
        if (preset.id == presetId) {
          return preset;
        }
      }
    }
    for (final preset in presets) {
      if (preset.isDefault) {
        return preset;
      }
    }
    return presets.isEmpty ? null : presets.first;
  }

  String? get selectedTextToVideoHighDiffusionModel {
    return _validDiffusionModelName(selectedTextToVideoHighDiffusionModelName);
  }

  String? get selectedTextToVideoLowDiffusionModel {
    return _validDiffusionModelName(selectedTextToVideoLowDiffusionModelName);
  }

  String? get selectedImageToVideoHighDiffusionModel {
    return _validDiffusionModelName(selectedImageToVideoHighDiffusionModelName);
  }

  String? get selectedImageToVideoLowDiffusionModel {
    return _validDiffusionModelName(selectedImageToVideoLowDiffusionModelName);
  }

  List<VideoDiffusionModelSelectionOption>
  get textToVideoDiffusionModelSelections {
    return buildVideoDiffusionModelSelectionOptions(
      diffusionModels.map((item) => item.name),
    );
  }

  String? get selectedTextToVideoDiffusionModelSelectionValue {
    return resolveVideoDiffusionModelSelectionOption(
      textToVideoDiffusionModelSelections,
      highModelName: selectedTextToVideoHighDiffusionModelName,
      lowModelName: selectedTextToVideoLowDiffusionModelName,
    )?.value;
  }

  List<VideoDiffusionModelSelectionOption>
  get imageToVideoDiffusionModelSelections {
    return buildVideoDiffusionModelSelectionOptions(
      diffusionModels.map((item) => item.name),
    );
  }

  String? get selectedImageToVideoDiffusionModelSelectionValue {
    return resolveVideoDiffusionModelSelectionOption(
      imageToVideoDiffusionModelSelections,
      highModelName: selectedImageToVideoHighDiffusionModelName,
      lowModelName: selectedImageToVideoLowDiffusionModelName,
    )?.value;
  }

  VideoModelAsset? get textToVideoModel {
    return _videoModelById('comfy-text-to-video');
  }

  VideoModelAsset? get imageToVideoModel {
    return _videoModelById('comfy-image-to-video');
  }

  List<VideoWorkflowLoraAsset> get textToVideoWorkflowLoras {
    return textToVideoModel?.workflowLoras ?? const <VideoWorkflowLoraAsset>[];
  }

  List<VideoWorkflowLoraAsset> get imageToVideoWorkflowLoras {
    return imageToVideoModel?.workflowLoras ?? const <VideoWorkflowLoraAsset>[];
  }

  List<VideoWorkflowLoraSelectionOption> get textToVideoWorkflowLoraSelections {
    return buildVideoWorkflowLoraSelectionOptions(textToVideoWorkflowLoras);
  }

  List<VideoWorkflowLoraSelectionOption>
  get imageToVideoWorkflowLoraSelections {
    return buildVideoWorkflowLoraSelectionOptions(imageToVideoWorkflowLoras);
  }

  Map<String, double> get textToVideoWorkflowLoraSelectionStrengths {
    return resolveVideoWorkflowLoraSelectionStrengths(
      loras: textToVideoWorkflowLoras,
      storedStrengths: textToVideoWorkflowLoraStrengths,
    );
  }

  Map<String, double> get imageToVideoWorkflowLoraSelectionStrengths {
    return resolveVideoWorkflowLoraSelectionStrengths(
      loras: imageToVideoWorkflowLoras,
      storedStrengths: imageToVideoWorkflowLoraStrengths,
    );
  }

  List<VideoWorkflowLoraStrength> workflowLoraStrengths({
    required bool imageToVideo,
  }) {
    final workflowLoras = imageToVideo
        ? imageToVideoWorkflowLoras
        : textToVideoWorkflowLoras;
    final selectedStrengths = _normalizedWorkflowLoraStrengthMap(
      imageToVideo: imageToVideo,
    );
    return workflowLoras
        .map(
          (lora) => VideoWorkflowLoraStrength(
            loraId: lora.id,
            strength: selectedStrengths[lora.id] ?? lora.defaultStrength,
          ),
        )
        .toList();
  }

  void loadPreferences(SharedPreferences prefs) {
    selectedPresetId = prefs.getString(selectedPresetKey);
    selectedTextToVideoHighDiffusionModelName = prefs.getString(
      selectedHighDiffusionModelKey,
    );
    selectedTextToVideoLowDiffusionModelName = prefs.getString(
      selectedLowDiffusionModelKey,
    );
    selectedImageToVideoHighDiffusionModelName = prefs.getString(
      selectedImageToVideoHighDiffusionModelKey,
    );
    selectedImageToVideoLowDiffusionModelName = prefs.getString(
      selectedImageToVideoLowDiffusionModelKey,
    );
    textToVideoWorkflowLoraStrengths = decodeSelectedLoras(
      prefs.getString(textToVideoWorkflowLoraStrengthsKey),
    );
    imageToVideoWorkflowLoraStrengths = decodeSelectedLoras(
      prefs.getString(imageToVideoWorkflowLoraStrengthsKey),
    );
  }

  void applyAssets({
    required List<VideoModelAsset> videoModels,
    required List<VideoDiffusionModelAsset> diffusionModels,
    required List<VideoPresetOption> presets,
  }) {
    this.videoModels = videoModels;
    this.diffusionModels = diffusionModels;
    this.presets = presets;
    selectedPresetId = selectedPreset?.id;
    ensureValidDiffusionModelSelections();
    ensureValidWorkflowLoraSelections();
  }

  void setSelectedPresetId(String value) {
    selectedPresetId = value;
    unawaited(saveSelectedPreset());
    onChanged();
  }

  void setTextToVideoHighDiffusionModel(String? value) {
    selectedTextToVideoHighDiffusionModelName = _normalizeOptionalName(value);
    unawaited(saveSelectedDiffusionModels());
    onChanged();
  }

  void setTextToVideoLowDiffusionModel(String? value) {
    selectedTextToVideoLowDiffusionModelName = _normalizeOptionalName(value);
    unawaited(saveSelectedDiffusionModels());
    onChanged();
  }

  void setImageToVideoHighDiffusionModel(String? value) {
    selectedImageToVideoHighDiffusionModelName = _normalizeOptionalName(value);
    unawaited(saveSelectedDiffusionModels());
    onChanged();
  }

  void setImageToVideoLowDiffusionModel(String? value) {
    selectedImageToVideoLowDiffusionModelName = _normalizeOptionalName(value);
    unawaited(saveSelectedDiffusionModels());
    onChanged();
  }

  void setTextToVideoDiffusionModelSelection(String? value) {
    final normalizedValue = _normalizeOptionalName(value);
    if (normalizedValue == null) {
      selectedTextToVideoHighDiffusionModelName = null;
      selectedTextToVideoLowDiffusionModelName = null;
    } else {
      final selection = textToVideoDiffusionModelSelections
          .where((item) => item.value == normalizedValue)
          .firstOrNull;
      selectedTextToVideoHighDiffusionModelName = selection?.highModelName;
      selectedTextToVideoLowDiffusionModelName = selection?.lowModelName;
    }
    unawaited(saveSelectedDiffusionModels());
    onChanged();
  }

  void setImageToVideoDiffusionModelSelection(String? value) {
    final normalizedValue = _normalizeOptionalName(value);
    if (normalizedValue == null) {
      selectedImageToVideoHighDiffusionModelName = null;
      selectedImageToVideoLowDiffusionModelName = null;
    } else {
      final selection = imageToVideoDiffusionModelSelections
          .where((item) => item.value == normalizedValue)
          .firstOrNull;
      selectedImageToVideoHighDiffusionModelName = selection?.highModelName;
      selectedImageToVideoLowDiffusionModelName = selection?.lowModelName;
    }
    unawaited(saveSelectedDiffusionModels());
    onChanged();
  }

  void setTextToVideoWorkflowLoraStrength(String loraId, double strength) {
    _setWorkflowLoraStrength(
      imageToVideo: false,
      selectionKey: loraId,
      strength: strength,
    );
  }

  void setImageToVideoWorkflowLoraStrength(String loraId, double strength) {
    _setWorkflowLoraStrength(
      imageToVideo: true,
      selectionKey: loraId,
      strength: strength,
    );
  }

  void _setWorkflowLoraStrength({
    required bool imageToVideo,
    required String selectionKey,
    required double strength,
  }) {
    final storedStrengths = imageToVideo
        ? imageToVideoWorkflowLoraStrengths
        : textToVideoWorkflowLoraStrengths;
    final selections = imageToVideo
        ? imageToVideoWorkflowLoraSelections
        : textToVideoWorkflowLoraSelections;
    final selection = selections
        .where((item) => item.key == selectionKey)
        .firstOrNull;
    if (selection == null) {
      storedStrengths[selectionKey] = strength;
    } else {
      for (final loraId in selection.loraIds) {
        storedStrengths[loraId] = strength;
      }
    }
    unawaited(saveWorkflowLoraStrengths());
    onChanged();
  }

  void ensureValidDiffusionModelSelections() {
    if (diffusionModels.isEmpty) {
      return;
    }
    final validNames = diffusionModels.map((item) => item.name).toSet();
    if (!validNames.contains(selectedTextToVideoHighDiffusionModelName)) {
      selectedTextToVideoHighDiffusionModelName = null;
    }
    if (!validNames.contains(selectedTextToVideoLowDiffusionModelName)) {
      selectedTextToVideoLowDiffusionModelName = null;
    }
    if (!validNames.contains(selectedImageToVideoHighDiffusionModelName)) {
      selectedImageToVideoHighDiffusionModelName = null;
    }
    if (!validNames.contains(selectedImageToVideoLowDiffusionModelName)) {
      selectedImageToVideoLowDiffusionModelName = null;
    }
    final textToVideoSelection = resolveVideoDiffusionModelSelectionOption(
      textToVideoDiffusionModelSelections,
      highModelName: selectedTextToVideoHighDiffusionModelName,
      lowModelName: selectedTextToVideoLowDiffusionModelName,
    );
    if (textToVideoSelection != null) {
      selectedTextToVideoHighDiffusionModelName =
          textToVideoSelection.highModelName;
      selectedTextToVideoLowDiffusionModelName =
          textToVideoSelection.lowModelName;
    }
    final imageToVideoSelection = resolveVideoDiffusionModelSelectionOption(
      imageToVideoDiffusionModelSelections,
      highModelName: selectedImageToVideoHighDiffusionModelName,
      lowModelName: selectedImageToVideoLowDiffusionModelName,
    );
    if (imageToVideoSelection != null) {
      selectedImageToVideoHighDiffusionModelName =
          imageToVideoSelection.highModelName;
      selectedImageToVideoLowDiffusionModelName =
          imageToVideoSelection.lowModelName;
    }
    unawaited(saveSelectedDiffusionModels());
  }

  void ensureValidWorkflowLoraSelections() {
    textToVideoWorkflowLoraStrengths = normalizeVideoWorkflowLoraStrengths(
      loras: textToVideoWorkflowLoras,
      storedStrengths: textToVideoWorkflowLoraStrengths,
    );
    imageToVideoWorkflowLoraStrengths = normalizeVideoWorkflowLoraStrengths(
      loras: imageToVideoWorkflowLoras,
      storedStrengths: imageToVideoWorkflowLoraStrengths,
    );
    unawaited(saveWorkflowLoraStrengths());
  }

  Future<void> saveSelectedPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final presetId = selectedPresetId;
    if (presetId == null || presetId.isEmpty) {
      await prefs.remove(selectedPresetKey);
    } else {
      await prefs.setString(selectedPresetKey, presetId);
    }
  }

  Future<void> saveSelectedDiffusionModels() async {
    final prefs = await SharedPreferences.getInstance();
    await _saveOptionalString(
      prefs,
      selectedHighDiffusionModelKey,
      selectedTextToVideoHighDiffusionModelName,
    );
    await _saveOptionalString(
      prefs,
      selectedLowDiffusionModelKey,
      selectedTextToVideoLowDiffusionModelName,
    );
    await _saveOptionalString(
      prefs,
      selectedImageToVideoHighDiffusionModelKey,
      selectedImageToVideoHighDiffusionModelName,
    );
    await _saveOptionalString(
      prefs,
      selectedImageToVideoLowDiffusionModelKey,
      selectedImageToVideoLowDiffusionModelName,
    );
  }

  Future<void> saveWorkflowLoraStrengths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      textToVideoWorkflowLoraStrengthsKey,
      jsonEncode(textToVideoWorkflowLoraStrengths),
    );
    await prefs.setString(
      imageToVideoWorkflowLoraStrengthsKey,
      jsonEncode(imageToVideoWorkflowLoraStrengths),
    );
  }

  VideoModelAsset? _videoModelById(String id) {
    for (final model in videoModels) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }

  String? _validDiffusionModelName(String? modelName) {
    final normalizedName = modelName?.trim() ?? '';
    if (normalizedName.isEmpty) {
      return null;
    }
    if (diffusionModels.isEmpty ||
        diffusionModels.any((item) => item.name == normalizedName)) {
      return normalizedName;
    }
    return null;
  }

  Map<String, double> _normalizedWorkflowLoraStrengthMap({
    required bool imageToVideo,
  }) {
    return normalizeVideoWorkflowLoraStrengths(
      loras: imageToVideo
          ? imageToVideoWorkflowLoras
          : textToVideoWorkflowLoras,
      storedStrengths: imageToVideo
          ? imageToVideoWorkflowLoraStrengths
          : textToVideoWorkflowLoraStrengths,
    );
  }

  static String? _normalizeOptionalName(String? modelName) {
    final trimmedName = modelName?.trim() ?? '';
    return trimmedName.isEmpty ? null : trimmedName;
  }

  static Future<void> _saveOptionalString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, trimmedValue);
    }
  }
}
