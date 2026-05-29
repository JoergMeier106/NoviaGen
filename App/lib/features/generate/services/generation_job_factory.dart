import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/models/generation.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';

class GenerationJobFactory {
  GenerationJobFactory({
    required this.defaults,
    required this.videoAssets,
    required this.chatModelCatalog,
  });

  final GenerationDefaultsStore defaults;
  final VideoAssetSelectionStore videoAssets;
  final ChatModelCatalogStore chatModelCatalog;

  Map<String, dynamic> imageGenerationPayload({
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String modelId,
    required List<SelectedLora> loras,
    ImageRecord? sourceImage,
    String? uploadRef,
  }) {
    final useImageToImageDefaults = sourceImage != null || uploadRef != null;
    final steps = useImageToImageDefaults
        ? defaults.imageToImageNumInferenceSteps
        : defaults.numInferenceSteps;
    final guidance = useImageToImageDefaults
        ? defaults.imageToImageGuidanceScale
        : defaults.guidanceScale;
    final autoMetadataEnabled = useImageToImageDefaults
        ? defaults.imageToImageAutoMetadataEnabled
        : defaults.textToImageAutoMetadataEnabled;
    final autoMetadataModelName = useImageToImageDefaults
        ? _selectedAutoMetadataModelName(
            defaults.imageToImageAutoMetadataModelName,
          )
        : _selectedAutoMetadataModelName(
            defaults.textToImageAutoMetadataModelName,
          );
    return {
      'prompt': prompt,
      'default_positive_prompt': defaultPositivePrompt,
      'default_negative_prompt': defaultNegativePrompt,
      'model_id': modelId,
      'loras': loras.map((item) => item.toJson()).toList(),
      'num_inference_steps': steps,
      'guidance_scale': guidance,
      'image_orientation': defaults.imageOrientation.name,
      if (sourceImage != null) 'image_id': sourceImage.id,
      if (uploadRef != null && uploadRef.isNotEmpty) 'upload_ref': uploadRef,
      if (sourceImage != null || uploadRef != null)
        'strength': defaults.imageToImageStrength,
      'auto_metadata_enabled': autoMetadataEnabled,
      if (autoMetadataEnabled && autoMetadataModelName != null)
        'auto_metadata_model_name': autoMetadataModelName,
    };
  }

  Map<String, dynamic> videoGenerationPayload({
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String presetId,
    required Map<String, int> settings,
    bool imageToVideo = false,
    ImageRecord? storedSource,
    String? uploadRef,
  }) {
    final useImageToVideoDefaults =
        imageToVideo || storedSource != null || uploadRef != null;
    final highDiffusionModelName = useImageToVideoDefaults
        ? videoAssets.selectedImageToVideoHighDiffusionModel
        : videoAssets.selectedTextToVideoHighDiffusionModel;
    final lowDiffusionModelName = useImageToVideoDefaults
        ? videoAssets.selectedImageToVideoLowDiffusionModel
        : videoAssets.selectedTextToVideoLowDiffusionModel;
    final workflowLoras = videoAssets.workflowLoraStrengths(
      imageToVideo: useImageToVideoDefaults,
    );
    return {
      'prompt': prompt,
      'default_positive_prompt': defaultPositivePrompt,
      'default_negative_prompt': defaultNegativePrompt,
      'preset': presetId,
      if (settings['width'] != null) 'width': settings['width'],
      if (settings['height'] != null) 'height': settings['height'],
      if (settings['fps'] != null) 'fps': settings['fps'],
      if (settings['num_frames'] != null) 'num_frames': settings['num_frames'],
      if (highDiffusionModelName?.trim().isNotEmpty ?? false)
        'high_diffusion_model_name': highDiffusionModelName!.trim(),
      if (lowDiffusionModelName?.trim().isNotEmpty ?? false)
        'low_diffusion_model_name': lowDiffusionModelName!.trim(),
      if (workflowLoras.isNotEmpty)
        'workflow_loras': workflowLoras.map((item) => item.toJson()).toList(),
      if (storedSource != null) 'image_id': storedSource.id,
      if (uploadRef != null && uploadRef.isNotEmpty) 'upload_ref': uploadRef,
    };
  }

  Future<JobStatus> queueImageGenerationJob({
    required ApiClient client,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String modelId,
    required List<SelectedLora> loras,
    ImageRecord? sourceImage,
    LocalImageSource? localSource,
  }) {
    final uploadRef = localSource == null ? null : 'source_image';
    final payload = imageGenerationPayload(
      prompt: prompt,
      defaultPositivePrompt: defaultPositivePrompt,
      defaultNegativePrompt: defaultNegativePrompt,
      modelId: modelId,
      loras: loras,
      sourceImage: sourceImage,
      uploadRef: uploadRef,
    );
    if (sourceImage != null) {
      return client.createGenerateFromStoredImageJob(
        imageId: sourceImage.id,
        prompt: payload['prompt'] as String,
        defaultPositivePrompt: payload['default_positive_prompt'] as String,
        defaultNegativePrompt: payload['default_negative_prompt'] as String,
        modelId: payload['model_id'] as String,
        loras: loras,
        numInferenceSteps: payload['num_inference_steps'] as int,
        guidanceScale: payload['guidance_scale'] as double,
        imageOrientation: payload['image_orientation'] as String,
        autoMetadataEnabled: payload['auto_metadata_enabled'] as bool,
        autoMetadataModelName: payload['auto_metadata_model_name'] as String?,
        strength: payload['strength'] as double,
      );
    }
    if (localSource != null) {
      return client.createGenerateFromUploadedImageJob(
        imagePath: localSource.path,
        imageName: localSource.name,
        prompt: payload['prompt'] as String,
        defaultPositivePrompt: payload['default_positive_prompt'] as String,
        defaultNegativePrompt: payload['default_negative_prompt'] as String,
        modelId: payload['model_id'] as String,
        loras: loras,
        numInferenceSteps: payload['num_inference_steps'] as int,
        guidanceScale: payload['guidance_scale'] as double,
        imageOrientation: payload['image_orientation'] as String,
        autoMetadataEnabled: payload['auto_metadata_enabled'] as bool,
        autoMetadataModelName: payload['auto_metadata_model_name'] as String?,
        strength: payload['strength'] as double,
      );
    }
    return client.createGenerateJob(
      prompt: payload['prompt'] as String,
      defaultPositivePrompt: payload['default_positive_prompt'] as String,
      defaultNegativePrompt: payload['default_negative_prompt'] as String,
      modelId: payload['model_id'] as String,
      loras: loras,
      numInferenceSteps: payload['num_inference_steps'] as int,
      guidanceScale: payload['guidance_scale'] as double,
      imageOrientation: payload['image_orientation'] as String,
      autoMetadataEnabled: payload['auto_metadata_enabled'] as bool,
      autoMetadataModelName: payload['auto_metadata_model_name'] as String?,
    );
  }

  Future<JobStatus> queueVideoGenerationJob({
    required ApiClient client,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String presetId,
    required Map<String, int> settings,
    ImageRecord? storedSource,
    LocalImageSource? localSource,
  }) {
    final uploadRef = localSource == null ? null : 'source_image';
    final payload = videoGenerationPayload(
      prompt: prompt,
      defaultPositivePrompt: defaultPositivePrompt,
      defaultNegativePrompt: defaultNegativePrompt,
      presetId: presetId,
      settings: settings,
      storedSource: storedSource,
      uploadRef: uploadRef,
    );
    if (storedSource != null) {
      return client.createAnimateImageJob(
        imageId: storedSource.id,
        prompt: payload['prompt'] as String,
        defaultPositivePrompt: payload['default_positive_prompt'] as String,
        defaultNegativePrompt: payload['default_negative_prompt'] as String,
        preset: payload['preset'] as String,
        customWidth: payload['width'] as int?,
        customHeight: payload['height'] as int?,
        customFps: payload['fps'] as int?,
        customNumFrames: payload['num_frames'] as int?,
        highDiffusionModelName: payload['high_diffusion_model_name'] as String?,
        lowDiffusionModelName: payload['low_diffusion_model_name'] as String?,
        workflowLoras: videoAssets.workflowLoraStrengths(imageToVideo: true),
      );
    }
    if (localSource != null) {
      return client.createAnimateUploadedImageJob(
        imagePath: localSource.path,
        imageName: localSource.name,
        prompt: payload['prompt'] as String,
        defaultPositivePrompt: payload['default_positive_prompt'] as String,
        defaultNegativePrompt: payload['default_negative_prompt'] as String,
        preset: payload['preset'] as String,
        customWidth: payload['width'] as int?,
        customHeight: payload['height'] as int?,
        customFps: payload['fps'] as int?,
        customNumFrames: payload['num_frames'] as int?,
        highDiffusionModelName: payload['high_diffusion_model_name'] as String?,
        lowDiffusionModelName: payload['low_diffusion_model_name'] as String?,
        workflowLoras: videoAssets.workflowLoraStrengths(imageToVideo: true),
      );
    }
    return client.createGenerateVideoJob(
      prompt: payload['prompt'] as String,
      defaultPositivePrompt: payload['default_positive_prompt'] as String,
      defaultNegativePrompt: payload['default_negative_prompt'] as String,
      preset: payload['preset'] as String,
      customWidth: payload['width'] as int?,
      customHeight: payload['height'] as int?,
      customFps: payload['fps'] as int?,
      customNumFrames: payload['num_frames'] as int?,
      highDiffusionModelName: payload['high_diffusion_model_name'] as String?,
      lowDiffusionModelName: payload['low_diffusion_model_name'] as String?,
      workflowLoras: videoAssets.workflowLoraStrengths(imageToVideo: false),
    );
  }

  String? _selectedAutoMetadataModelName(String? preferredModelName) {
    final preferred = preferredModelName?.trim() ?? '';
    if (preferred.isNotEmpty &&
        (chatModelCatalog.autoPromptModels.isEmpty ||
            chatModelCatalog.autoPromptModels.any(
              (item) => item.name == preferred,
            ))) {
      return preferred;
    }
    if (chatModelCatalog.autoPromptModels.isNotEmpty) {
      return chatModelCatalog.autoPromptModels.first.name;
    }
    return null;
  }
}
