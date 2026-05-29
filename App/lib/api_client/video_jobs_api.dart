import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/generation.dart';
import '../models/jobs.dart';
import 'transport.dart';

mixin VideoJobApi on ApiClientTransport {
  Future<JobStatus> createGenerateVideoJob({
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String preset,
    int? customWidth,
    int? customHeight,
    int? customFps,
    int? customNumFrames,
    String? highDiffusionModelName,
    String? lowDiffusionModelName,
    List<VideoWorkflowLoraStrength> workflowLoras =
        const <VideoWorkflowLoraStrength>[],
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate-video',
      data: {
        'prompt': prompt,
        'default_positive_prompt': defaultPositivePrompt,
        'default_negative_prompt': defaultNegativePrompt,
        'preset': preset,
        ...?customWidth == null ? null : {'width': customWidth},
        ...?customHeight == null ? null : {'height': customHeight},
        ...?customFps == null ? null : {'fps': customFps},
        ...?customNumFrames == null ? null : {'num_frames': customNumFrames},
        if (highDiffusionModelName?.trim().isNotEmpty ?? false)
          'high_diffusion_model_name': highDiffusionModelName!.trim(),
        if (lowDiffusionModelName?.trim().isNotEmpty ?? false)
          'low_diffusion_model_name': lowDiffusionModelName!.trim(),
        if (workflowLoras.isNotEmpty)
          'workflow_loras': workflowLoras.map((item) => item.toJson()).toList(),
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createAnimateImageJob({
    required String imageId,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String preset,
    int? customWidth,
    int? customHeight,
    int? customFps,
    int? customNumFrames,
    String? highDiffusionModelName,
    String? lowDiffusionModelName,
    List<VideoWorkflowLoraStrength> workflowLoras =
        const <VideoWorkflowLoraStrength>[],
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/animate-image',
      data: {
        'image_id': imageId,
        'prompt': prompt,
        'default_positive_prompt': defaultPositivePrompt,
        'default_negative_prompt': defaultNegativePrompt,
        'preset': preset,
        ...?customWidth == null ? null : {'width': customWidth},
        ...?customHeight == null ? null : {'height': customHeight},
        ...?customFps == null ? null : {'fps': customFps},
        ...?customNumFrames == null ? null : {'num_frames': customNumFrames},
        if (highDiffusionModelName?.trim().isNotEmpty ?? false)
          'high_diffusion_model_name': highDiffusionModelName!.trim(),
        if (lowDiffusionModelName?.trim().isNotEmpty ?? false)
          'low_diffusion_model_name': lowDiffusionModelName!.trim(),
        if (workflowLoras.isNotEmpty)
          'workflow_loras': workflowLoras.map((item) => item.toJson()).toList(),
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createAnimateUploadedImageJob({
    required String imagePath,
    required String imageName,
    required String prompt,
    required String defaultPositivePrompt,
    required String defaultNegativePrompt,
    required String preset,
    int? customWidth,
    int? customHeight,
    int? customFps,
    int? customNumFrames,
    String? highDiffusionModelName,
    String? lowDiffusionModelName,
    List<VideoWorkflowLoraStrength> workflowLoras =
        const <VideoWorkflowLoraStrength>[],
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/animate-image',
      data: FormData.fromMap({
        'image': await MultipartFile.fromFile(imagePath, filename: imageName),
        'prompt': prompt,
        'default_positive_prompt': defaultPositivePrompt,
        'default_negative_prompt': defaultNegativePrompt,
        'preset': preset,
        if (customWidth != null) 'width': customWidth.toString(),
        if (customHeight != null) 'height': customHeight.toString(),
        if (customFps != null) 'fps': customFps.toString(),
        if (customNumFrames != null) 'num_frames': customNumFrames.toString(),
        if (highDiffusionModelName?.trim().isNotEmpty ?? false)
          'high_diffusion_model_name': highDiffusionModelName!.trim(),
        if (lowDiffusionModelName?.trim().isNotEmpty ?? false)
          'low_diffusion_model_name': lowDiffusionModelName!.trim(),
        if (workflowLoras.isNotEmpty)
          'workflow_loras': jsonEncode(
            workflowLoras.map((item) => item.toJson()).toList(),
          ),
      }),
    );
    return JobStatus.fromJson(response.data!);
  }
}
