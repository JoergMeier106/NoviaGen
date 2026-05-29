import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noviagen/app/persistence/settings_codecs.dart';
import 'package:noviagen/features/generate/domain/generation_settings.dart';

class GenerationDefaultsStore {
  GenerationDefaultsStore({required this.onChanged});

  static const numInferenceStepsKey = 'num_inference_steps';
  static const guidanceScaleKey = 'guidance_scale';
  static const imageToImageNumInferenceStepsKey =
      'image_to_image_num_inference_steps';
  static const imageToImageGuidanceScaleKey = 'image_to_image_guidance_scale';
  static const imageOrientationKey = 'image_orientation';
  static const promptGeneratorBasePromptKey = 'prompt_generator_base_prompt';
  static const imageToImagePromptGeneratorBasePromptKey =
      'image_to_image_prompt_generator_base_prompt';
  static const textToVideoPromptGeneratorBasePromptKey =
      'text_to_video_prompt_generator_base_prompt';
  static const imageToVideoPromptGeneratorBasePromptKey =
      'image_to_video_prompt_generator_base_prompt';
  static const imageToImageStrengthKey = 'image_to_image_strength';
  static const textToImageAutoMetadataEnabledKey =
      'text_to_image_auto_metadata_enabled';
  static const imageToImageAutoMetadataEnabledKey =
      'image_to_image_auto_metadata_enabled';
  static const textToImageAutoMetadataModelKey =
      'text_to_image_auto_metadata_model_name';
  static const imageToImageAutoMetadataModelKey =
      'image_to_image_auto_metadata_model_name';

  final VoidCallback onChanged;

  int numInferenceSteps = 40;
  double guidanceScale = 5.0;
  int imageToImageNumInferenceSteps = 40;
  double imageToImageGuidanceScale = 5.0;
  ImageOrientationSetting imageOrientation = ImageOrientationSetting.landscape;
  String promptGeneratorBasePrompt = '';
  String imageToImagePromptGeneratorBasePrompt = '';
  String textToVideoPromptGeneratorBasePrompt = '';
  String imageToVideoPromptGeneratorBasePrompt = '';
  double imageToImageStrength = 0.35;
  bool textToImageAutoMetadataEnabled = true;
  bool imageToImageAutoMetadataEnabled = true;
  String? textToImageAutoMetadataModelName;
  String? imageToImageAutoMetadataModelName;

  void loadPreferences(SharedPreferences prefs) {
    numInferenceSteps = prefs.getInt(numInferenceStepsKey) ?? 40;
    guidanceScale = prefs.getDouble(guidanceScaleKey) ?? 5.0;
    imageToImageNumInferenceSteps =
        prefs.getInt(imageToImageNumInferenceStepsKey) ?? numInferenceSteps;
    imageToImageGuidanceScale =
        prefs.getDouble(imageToImageGuidanceScaleKey) ?? guidanceScale;
    imageOrientation = imageOrientationFromString(
      prefs.getString(imageOrientationKey),
    );
    promptGeneratorBasePrompt =
        prefs.getString(promptGeneratorBasePromptKey) ?? '';
    imageToImagePromptGeneratorBasePrompt =
        prefs.getString(imageToImagePromptGeneratorBasePromptKey) ??
        promptGeneratorBasePrompt;
    textToVideoPromptGeneratorBasePrompt =
        prefs.getString(textToVideoPromptGeneratorBasePromptKey) ??
        promptGeneratorBasePrompt;
    imageToVideoPromptGeneratorBasePrompt =
        prefs.getString(imageToVideoPromptGeneratorBasePromptKey) ?? '';
    imageToImageStrength = prefs.getDouble(imageToImageStrengthKey) ?? 0.35;
    textToImageAutoMetadataEnabled =
        prefs.getBool(textToImageAutoMetadataEnabledKey) ?? true;
    imageToImageAutoMetadataEnabled =
        prefs.getBool(imageToImageAutoMetadataEnabledKey) ?? true;
    textToImageAutoMetadataModelName = prefs.getString(
      textToImageAutoMetadataModelKey,
    );
    imageToImageAutoMetadataModelName = prefs.getString(
      imageToImageAutoMetadataModelKey,
    );
  }

  Future<void> saveMainSettings({
    required int numInferenceSteps,
    required double guidanceScale,
    required ImageOrientationSetting imageOrientation,
    required String promptGeneratorBasePrompt,
    required String imageToVideoPromptGeneratorBasePrompt,
  }) async {
    this.numInferenceSteps = numInferenceSteps;
    this.guidanceScale = guidanceScale;
    this.imageOrientation = imageOrientation;
    this.promptGeneratorBasePrompt = promptGeneratorBasePrompt.trim();
    this.imageToVideoPromptGeneratorBasePrompt =
        imageToVideoPromptGeneratorBasePrompt.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(numInferenceStepsKey, this.numInferenceSteps);
    await prefs.setDouble(guidanceScaleKey, this.guidanceScale);
    await prefs.setString(imageOrientationKey, this.imageOrientation.name);
    await prefs.setString(
      promptGeneratorBasePromptKey,
      this.promptGeneratorBasePrompt,
    );
    await prefs.setString(
      imageToVideoPromptGeneratorBasePromptKey,
      this.imageToVideoPromptGeneratorBasePrompt,
    );
  }

  Future<void> setPromptGeneratorBasePrompt(String value) async {
    promptGeneratorBasePrompt = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      promptGeneratorBasePromptKey,
      promptGeneratorBasePrompt,
    );
    onChanged();
  }

  Future<void> setTextToImageGenerationDefaults({
    required int steps,
    required double guidance,
  }) async {
    numInferenceSteps = steps;
    guidanceScale = guidance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(numInferenceStepsKey, numInferenceSteps);
    await prefs.setDouble(guidanceScaleKey, guidanceScale);
    onChanged();
  }

  Future<void> setImageToImageGenerationDefaults({
    required int steps,
    required double guidance,
  }) async {
    imageToImageNumInferenceSteps = steps;
    imageToImageGuidanceScale = guidance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      imageToImageNumInferenceStepsKey,
      imageToImageNumInferenceSteps,
    );
    await prefs.setDouble(
      imageToImageGuidanceScaleKey,
      imageToImageGuidanceScale,
    );
    onChanged();
  }

  Future<void> setImageToImagePromptGeneratorBasePrompt(String value) async {
    imageToImagePromptGeneratorBasePrompt = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      imageToImagePromptGeneratorBasePromptKey,
      imageToImagePromptGeneratorBasePrompt,
    );
    onChanged();
  }

  Future<void> setTextToVideoPromptGeneratorBasePrompt(String value) async {
    textToVideoPromptGeneratorBasePrompt = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      textToVideoPromptGeneratorBasePromptKey,
      textToVideoPromptGeneratorBasePrompt,
    );
    onChanged();
  }

  Future<void> setImageToVideoPromptGeneratorBasePrompt(String value) async {
    imageToVideoPromptGeneratorBasePrompt = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      imageToVideoPromptGeneratorBasePromptKey,
      imageToVideoPromptGeneratorBasePrompt,
    );
    onChanged();
  }

  Future<void> setTextToImageAutoMetadataEnabled(bool value) async {
    textToImageAutoMetadataEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(textToImageAutoMetadataEnabledKey, value);
    onChanged();
  }

  Future<void> setImageToImageAutoMetadataEnabled(bool value) async {
    imageToImageAutoMetadataEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(imageToImageAutoMetadataEnabledKey, value);
    onChanged();
  }

  Future<void> setTextToImageAutoMetadataModelName(String? value) async {
    textToImageAutoMetadataModelName = _normalizedOptionalString(value);
    final prefs = await SharedPreferences.getInstance();
    await _persistOptionalString(
      prefs,
      textToImageAutoMetadataModelKey,
      textToImageAutoMetadataModelName,
    );
    onChanged();
  }

  Future<void> setImageToImageAutoMetadataModelName(String? value) async {
    imageToImageAutoMetadataModelName = _normalizedOptionalString(value);
    final prefs = await SharedPreferences.getInstance();
    await _persistOptionalString(
      prefs,
      imageToImageAutoMetadataModelKey,
      imageToImageAutoMetadataModelName,
    );
    onChanged();
  }

  void setImageOrientation(ImageOrientationSetting value) {
    imageOrientation = value;
    unawaited(persistImageOrientation());
    onChanged();
  }

  void setImageToImageStrength(double value) {
    imageToImageStrength = value;
    unawaited(persistImageToImageStrength());
    onChanged();
  }

  Future<void> persistImageOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(imageOrientationKey, imageOrientation.name);
  }

  Future<void> persistImageToImageStrength() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(imageToImageStrengthKey, imageToImageStrength);
  }

  static String? _normalizedOptionalString(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static Future<void> _persistOptionalString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, normalized);
  }
}
