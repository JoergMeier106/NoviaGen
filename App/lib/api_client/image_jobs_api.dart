import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/generation.dart';
import '../models/jobs.dart';
import '../models/media.dart';
import 'transport.dart';

mixin ImageJobApi on ApiClientTransport {
  Future<JobStatus> createGenerateJob({
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String modelId,
    required List<SelectedLora> loras,
    required int numInferenceSteps,
    required double guidanceScale,
    required String imageOrientation,
    required bool autoMetadataEnabled,
    String? autoMetadataModelName,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate',
      data: {
        'prompt': prompt,
        'default_positive_prompt': defaultPositivePrompt,
        'default_negative_prompt': defaultNegativePrompt,
        'model_id': modelId,
        'loras': loras.map((item) => item.toJson()).toList(),
        'num_inference_steps': numInferenceSteps,
        'guidance_scale': guidanceScale,
        'image_orientation': imageOrientation,
        'auto_metadata_enabled': autoMetadataEnabled,
        if (autoMetadataEnabled &&
            (autoMetadataModelName?.trim().isNotEmpty ?? false))
          'auto_metadata_model_name': autoMetadataModelName!.trim(),
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createGenerateFromStoredImageJob({
    required String imageId,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String modelId,
    required List<SelectedLora> loras,
    required int numInferenceSteps,
    required double guidanceScale,
    required String imageOrientation,
    required bool autoMetadataEnabled,
    String? autoMetadataModelName,
    required double strength,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate-from-image',
      data: {
        'image_id': imageId,
        'prompt': prompt,
        'default_positive_prompt': defaultPositivePrompt,
        'default_negative_prompt': defaultNegativePrompt,
        'model_id': modelId,
        'loras': loras.map((item) => item.toJson()).toList(),
        'num_inference_steps': numInferenceSteps,
        'guidance_scale': guidanceScale,
        'image_orientation': imageOrientation,
        'auto_metadata_enabled': autoMetadataEnabled,
        if (autoMetadataEnabled &&
            (autoMetadataModelName?.trim().isNotEmpty ?? false))
          'auto_metadata_model_name': autoMetadataModelName!.trim(),
        'strength': strength,
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createGenerateFromUploadedImageJob({
    required String imagePath,
    required String imageName,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String modelId,
    required List<SelectedLora> loras,
    required int numInferenceSteps,
    required double guidanceScale,
    required String imageOrientation,
    required bool autoMetadataEnabled,
    String? autoMetadataModelName,
    required double strength,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate-from-image',
      data: FormData.fromMap({
        'image': await MultipartFile.fromFile(imagePath, filename: imageName),
        'prompt': prompt,
        'default_positive_prompt': defaultPositivePrompt,
        'default_negative_prompt': defaultNegativePrompt,
        'model_id': modelId,
        'loras': jsonEncode(loras.map((item) => item.toJson()).toList()),
        'num_inference_steps': numInferenceSteps.toString(),
        'guidance_scale': guidanceScale.toString(),
        'image_orientation': imageOrientation,
        'auto_metadata_enabled': autoMetadataEnabled.toString(),
        if (autoMetadataEnabled &&
            (autoMetadataModelName?.trim().isNotEmpty ?? false))
          'auto_metadata_model_name': autoMetadataModelName!.trim(),
        'strength': strength.toString(),
      }),
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createGenerateJobFromImage({required ImageRecord image}) {
    return createGenerateJob(
      prompt: image.prompt,
      defaultPositivePrompt: image.defaultPositivePrompt,
      defaultNegativePrompt: image.defaultNegativePrompt,
      modelId: image.modelId,
      loras: image.loras,
      numInferenceSteps: image.numInferenceSteps,
      guidanceScale: image.guidanceScale,
      imageOrientation: image.imageOrientation,
      autoMetadataEnabled: false,
    );
  }
}
