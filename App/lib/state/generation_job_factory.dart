import '../api_client.dart';
import '../models/generation.dart';
import '../models/jobs.dart';
import '../models/media.dart';
import 'generation_defaults_state.dart';
import 'video_asset_selection_state.dart';

class GenerationJobFactory {
  GenerationJobFactory({required this.defaults, required this.videoAssets});

  final GenerationDefaultsState defaults;
  final VideoAssetSelectionState videoAssets;

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
    final useImageToImageDefaults = sourceImage != null || localSource != null;
    final steps = useImageToImageDefaults
        ? defaults.imageToImageNumInferenceSteps
        : defaults.numInferenceSteps;
    final guidance = useImageToImageDefaults
        ? defaults.imageToImageGuidanceScale
        : defaults.guidanceScale;
    if (sourceImage != null) {
      return client.createGenerateFromStoredImageJob(
        imageId: sourceImage.id,
        prompt: prompt,
        defaultPositivePrompt: defaultPositivePrompt,
        defaultNegativePrompt: defaultNegativePrompt,
        modelId: modelId,
        loras: loras,
        numInferenceSteps: steps,
        guidanceScale: guidance,
        imageOrientation: defaults.imageOrientation.name,
        autoMetadataEnabled: false,
        strength: defaults.imageToImageStrength,
      );
    }
    if (localSource != null) {
      return client.createGenerateFromUploadedImageJob(
        imagePath: localSource.path,
        imageName: localSource.name,
        prompt: prompt,
        defaultPositivePrompt: defaultPositivePrompt,
        defaultNegativePrompt: defaultNegativePrompt,
        modelId: modelId,
        loras: loras,
        numInferenceSteps: steps,
        guidanceScale: guidance,
        imageOrientation: defaults.imageOrientation.name,
        autoMetadataEnabled: false,
        strength: defaults.imageToImageStrength,
      );
    }
    return client.createGenerateJob(
      prompt: prompt,
      defaultPositivePrompt: defaultPositivePrompt,
      defaultNegativePrompt: defaultNegativePrompt,
      modelId: modelId,
      loras: loras,
      numInferenceSteps: steps,
      guidanceScale: guidance,
      imageOrientation: defaults.imageOrientation.name,
      autoMetadataEnabled: false,
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
    final useImageToVideoDefaults = storedSource != null || localSource != null;
    final highDiffusionModelName = useImageToVideoDefaults
        ? videoAssets.selectedImageToVideoHighDiffusionModel
        : videoAssets.selectedTextToVideoHighDiffusionModel;
    final lowDiffusionModelName = useImageToVideoDefaults
        ? videoAssets.selectedImageToVideoLowDiffusionModel
        : videoAssets.selectedTextToVideoLowDiffusionModel;
    final workflowLoras = videoAssets.workflowLoraStrengths(
      imageToVideo: useImageToVideoDefaults,
    );
    if (storedSource != null) {
      return client.createAnimateImageJob(
        imageId: storedSource.id,
        prompt: prompt,
        defaultPositivePrompt: defaultPositivePrompt,
        defaultNegativePrompt: defaultNegativePrompt,
        preset: presetId,
        customWidth: settings['width'],
        customHeight: settings['height'],
        customFps: settings['fps'],
        customNumFrames: settings['num_frames'],
        highDiffusionModelName: highDiffusionModelName,
        lowDiffusionModelName: lowDiffusionModelName,
        workflowLoras: workflowLoras,
      );
    }
    if (localSource != null) {
      return client.createAnimateUploadedImageJob(
        imagePath: localSource.path,
        imageName: localSource.name,
        prompt: prompt,
        defaultPositivePrompt: defaultPositivePrompt,
        defaultNegativePrompt: defaultNegativePrompt,
        preset: presetId,
        customWidth: settings['width'],
        customHeight: settings['height'],
        customFps: settings['fps'],
        customNumFrames: settings['num_frames'],
        highDiffusionModelName: highDiffusionModelName,
        lowDiffusionModelName: lowDiffusionModelName,
        workflowLoras: workflowLoras,
      );
    }
    return client.createGenerateVideoJob(
      prompt: prompt,
      defaultPositivePrompt: defaultPositivePrompt,
      defaultNegativePrompt: defaultNegativePrompt,
      preset: presetId,
      customWidth: settings['width'],
      customHeight: settings['height'],
      customFps: settings['fps'],
      customNumFrames: settings['num_frames'],
      highDiffusionModelName: highDiffusionModelName,
      lowDiffusionModelName: lowDiffusionModelName,
      workflowLoras: workflowLoras,
    );
  }
}
