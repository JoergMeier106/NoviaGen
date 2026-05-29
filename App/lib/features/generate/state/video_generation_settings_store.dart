import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:noviagen/models/assets.dart';
import 'package:noviagen/features/generate/domain/generation_settings.dart';
import 'package:noviagen/features/generate/domain/video_settings_draft.dart';


class VideoGenerationSettingsStore {
  VideoGenerationSettingsStore({
    required this.selectedPreset,
    required this.sourceOrientation,
    required this.setMessage,
    required this.persistDraft,
    required this.onChanged,
  });

  final VideoPresetOption? Function() selectedPreset;
  final ImageOrientationSetting? Function() sourceOrientation;
  final void Function(String? value) setMessage;
  final Future<void> Function() persistDraft;
  final VoidCallback onChanged;

  final VideoSettingsDraft _draft = VideoSettingsDraft();

  String get widthDraft => _draft.widthDraft;
  String get heightDraft => _draft.heightDraft;
  String get fpsDraft => _draft.fpsDraft;
  String get numFramesDraft => _draft.numFramesDraft;

  int? get widthValue => _draft.widthValue;
  int? get heightValue => _draft.heightValue;
  int? get fpsValue => _draft.fpsValue;
  int? get numFramesValue => _draft.numFramesValue;

  ImageOrientationSetting get effectiveOrientation {
    final width = widthValue;
    final height = heightValue;
    if (width != null && height != null && width != height) {
      return width > height
          ? ImageOrientationSetting.landscape
          : ImageOrientationSetting.portrait;
    }
    return ImageOrientationSetting.landscape;
  }

  String? get validationMessage {
    return _draft.validationMessage(selectedPreset());
  }

  Map<String, int>? get currentSettings {
    if (validationMessage != null) {
      return null;
    }
    final settings = _draft.normalizedSettings();
    if (settings == null) {
      return null;
    }
    return _applySourceOrientation(settings);
  }

  String? get resolutionAdjustmentLabel {
    if (validationMessage != null) {
      return null;
    }
    return _draft.resolutionAdjustmentLabel;
  }

  double? get currentDurationSeconds {
    final settings = currentSettings;
    if (settings == null) {
      return null;
    }
    final fps = settings['fps']!;
    final numFrames = settings['num_frames']!;
    if (fps <= 0) {
      return null;
    }
    return numFrames / fps;
  }

  void loadDrafts({
    required String width,
    required String height,
    required String fps,
    required String numFrames,
  }) {
    _draft.widthDraft = width;
    _draft.heightDraft = height;
    _draft.fpsDraft = fps;
    _draft.numFramesDraft = numFrames;
  }

  void setWidthDraft(String value) =>
      _setDraft(() => _draft.widthDraft = value);

  void setHeightDraft(String value) =>
      _setDraft(() => _draft.heightDraft = value);

  void setFpsDraft(String value) => _setDraft(() => _draft.fpsDraft = value);

  void setNumFramesDraft(String value) {
    _setDraft(() => _draft.numFramesDraft = value);
  }

  void scaleResolutionBy(double factor) {
    final baseSettings = currentSettings ?? _presetDraftSettings();
    if (baseSettings == null) {
      setMessage(validationMessage ?? 'Enter valid video settings first.');
      onChanged();
      return;
    }
    _applyScaledResolution(
      width: math
          .max(videoMinWidth, (baseSettings['width']! * factor).round())
          .toInt(),
      height: math
          .max(videoMinHeight, (baseSettings['height']! * factor).round())
          .toInt(),
    );
  }

  void increaseResolution() {
    _stepResolution(increase: true);
  }

  void decreaseResolution() {
    _stepResolution(increase: false);
  }

  void ensureInitialized({bool force = false}) {
    final preset = selectedPreset();
    if (preset == null) {
      return;
    }
    if (!force &&
        _draft.widthDraft.isNotEmpty &&
        _draft.heightDraft.isNotEmpty &&
        _draft.fpsDraft.isNotEmpty &&
        _draft.numFramesDraft.isNotEmpty) {
      return;
    }
    _draft.applyPreset(preset);
  }

  void syncDraftOrientationToSource() {
    final orientation = sourceOrientation();
    if (orientation == null) {
      return;
    }
    final width = widthValue;
    final height = heightValue;
    if (width == null || height == null || width == height) {
      return;
    }
    final sourceIsPortrait = orientation == ImageOrientationSetting.portrait;
    final draftsArePortrait = height > width;
    if (sourceIsPortrait == draftsArePortrait) {
      return;
    }
    _draft.widthDraft = '$height';
    _draft.heightDraft = '$width';
    unawaited(persistDraft());
  }

  void _setDraft(VoidCallback updateDraft) {
    updateDraft();
    unawaited(persistDraft());
    onChanged();
  }

  void _stepResolution({required bool increase}) {
    final baseSettings = currentSettings ?? _presetDraftSettings();
    if (baseSettings == null) {
      setMessage(validationMessage ?? 'Enter valid video settings first.');
      onChanged();
      return;
    }

    final currentWidth = normalizeVideoWidth(baseSettings['width']!);
    final currentHeight = normalizeVideoHeight(baseSettings['height']!);
    final primaryIsWidth = currentWidth >= currentHeight;
    final currentPrimary = primaryIsWidth ? currentWidth : currentHeight;
    final minPrimary = primaryIsWidth ? videoMinWidth : videoMinHeight;
    final maxPrimary = primaryIsWidth ? videoMaxWidth : videoMaxHeight;
    final nextPrimary =
        (currentPrimary +
                (increase ? videoResolutionStep : -videoResolutionStep))
            .clamp(minPrimary, maxPrimary)
            .toInt();

    if (nextPrimary == currentPrimary) {
      setMessage(
        increase
            ? 'Resolution is already at the highest supported size.'
            : 'Resolution is already at the lowest supported size.',
      );
      onChanged();
      return;
    }

    final factor = nextPrimary / currentPrimary;
    _applyScaledResolution(
      width: math.max(videoMinWidth, (currentWidth * factor).round()).toInt(),
      height: math
          .max(videoMinHeight, (currentHeight * factor).round())
          .toInt(),
    );
  }

  void _applyScaledResolution({required int width, required int height}) {
    _draft.applyNormalizedResolution(width: width, height: height);
    unawaited(persistDraft());
    onChanged();
  }

  Map<String, int>? _presetDraftSettings() {
    final preset = selectedPreset();
    return preset == null ? null : videoPresetSettings(preset);
  }

  Map<String, int> _applySourceOrientation(Map<String, int> settings) {
    final orientation = sourceOrientation();
    if (orientation == null) {
      return settings;
    }
    final width = settings['width'];
    final height = settings['height'];
    if (width == null || height == null || width == height) {
      return settings;
    }
    final sourceIsPortrait = orientation == ImageOrientationSetting.portrait;
    final settingsArePortrait = height > width;
    if (sourceIsPortrait == settingsArePortrait) {
      return settings;
    }
    return <String, int>{...settings, 'width': height, 'height': width};
  }
}
