import 'package:noviagen/models/assets.dart';
const int videoResolutionStep = 32;
const int videoMinWidth = 32;
const int videoMaxWidth = 1920;
const int videoMinHeight = 32;
const int videoMaxHeight = 1080;
const int videoMinFps = 1;
const int videoMaxFps = 60;
const int videoMinNumFrames = 8;

class VideoSettingsDraft {
  String widthDraft = '';
  String heightDraft = '';
  String fpsDraft = '';
  String numFramesDraft = '';

  int? get widthValue => int.tryParse(widthDraft.trim());
  int? get heightValue => int.tryParse(heightDraft.trim());
  int? get fpsValue => int.tryParse(fpsDraft.trim());
  int? get numFramesValue => int.tryParse(numFramesDraft.trim());

  String? validationMessage(VideoPresetOption? preset) {
    return validateVideoSettings(
      preset: preset,
      width: widthValue,
      height: heightValue,
      fps: fpsValue,
      numFrames: numFramesValue,
    );
  }

  String? get resolutionAdjustmentLabel {
    final rawWidth = widthValue;
    final rawHeight = heightValue;
    if (rawWidth == null || rawHeight == null) {
      return null;
    }
    final adjustedWidth = normalizeVideoWidth(rawWidth);
    final adjustedHeight = normalizeVideoHeight(rawHeight);
    if (adjustedWidth == rawWidth && adjustedHeight == rawHeight) {
      return null;
    }
    return 'Rendered as $adjustedWidth×$adjustedHeight so the backend accepts it.';
  }

  void applyPreset(VideoPresetOption preset) {
    final presetSettings = videoPresetSettings(preset);
    widthDraft = '${presetSettings['width']}';
    heightDraft = '${presetSettings['height']}';
    fpsDraft = '${presetSettings['fps']}';
    numFramesDraft = '${presetSettings['num_frames']}';
  }

  void applyNormalizedResolution({required int width, required int height}) {
    widthDraft = '${normalizeVideoWidth(width)}';
    heightDraft = '${normalizeVideoHeight(height)}';
  }

  Map<String, int>? normalizedSettings() {
    final width = widthValue;
    final height = heightValue;
    final fps = fpsValue;
    final numFrames = numFramesValue;
    if (width == null || height == null || fps == null || numFrames == null) {
      return null;
    }
    return <String, int>{
      'width': normalizeVideoWidth(width),
      'height': normalizeVideoHeight(height),
      'fps': fps,
      'num_frames': numFrames,
    };
  }
}

String? validateVideoSettings({
  required VideoPresetOption? preset,
  required int? width,
  required int? height,
  required int? fps,
  required int? numFrames,
}) {
  if (preset == null) {
    return 'No video preset is available from the server.';
  }
  if (width == null) {
    return 'Enter a whole number for width.';
  }
  if (width < videoMinWidth || width > videoMaxWidth) {
    return 'Width must be between $videoMinWidth and $videoMaxWidth.';
  }
  if (height == null) {
    return 'Enter a whole number for height.';
  }
  if (height < videoMinHeight || height > videoMaxHeight) {
    return 'Height must be between $videoMinHeight and $videoMaxHeight.';
  }
  if (fps == null) {
    return 'Enter a whole number for FPS.';
  }
  if (fps < videoMinFps || fps > videoMaxFps) {
    return 'FPS must be between $videoMinFps and $videoMaxFps.';
  }
  if (numFrames == null) {
    return 'Enter a whole number for frames.';
  }
  if (numFrames < videoMinNumFrames) {
    return 'Frames must be at least $videoMinNumFrames.';
  }
  return null;
}

Map<String, int> videoPresetSettings(VideoPresetOption preset) {
  return <String, int>{
    'width': preset.maxWidth,
    'height': preset.maxHeight,
    'fps': preset.fps,
    'num_frames': preset.numFrames,
  };
}

int normalizeVideoWidth(int value) {
  return normalizeVideoDimension(value, min: videoMinWidth, max: videoMaxWidth);
}

int normalizeVideoHeight(int value) {
  return normalizeVideoDimension(
    value,
    min: videoMinHeight,
    max: videoMaxHeight,
  );
}

int normalizeVideoDimension(int value, {required int min, required int max}) {
  final clamped = value.clamp(min, max).toInt();
  final rounded = (clamped / videoResolutionStep).round() * videoResolutionStep;
  return rounded.clamp(min, max).toInt();
}
