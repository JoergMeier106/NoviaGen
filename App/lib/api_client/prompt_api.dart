import 'dart:async';
import 'package:dio/dio.dart';
import '../models/jobs.dart';
import 'transport.dart';

mixin PromptApi on ApiClientTransport {
  Future<String> generatePrompt({
    required String prompt,
    String? modelName,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/prompt/generate',
      data: {
        'prompt': prompt,
        if (modelName != null && modelName.trim().isNotEmpty)
          'model_name': modelName.trim(),
      },
    );
    return response.data!['prompt'] as String;
  }

  Future<String> generateImageToVideoPrompt({
    required String prompt,
    String? imageId,
    String? imagePath,
    String? imageName,
    String? modelName,
  }) async {
    final hasUploadedImage =
        imagePath != null &&
        imagePath.isNotEmpty &&
        imageName != null &&
        imageName.isNotEmpty;
    final response = await dio.post<Map<String, dynamic>>(
      '/api/prompt/generate-i2v',
      data: hasUploadedImage
          ? FormData.fromMap({
              'prompt': prompt,
              if (modelName != null && modelName.trim().isNotEmpty)
                'model_name': modelName.trim(),
              'image': await MultipartFile.fromFile(
                imagePath,
                filename: imageName,
              ),
            })
          : {
              'prompt': prompt,
              if (modelName != null && modelName.trim().isNotEmpty)
                'model_name': modelName.trim(),
              if (imageId != null && imageId.isNotEmpty) 'image_id': imageId,
            },
    );
    return response.data!['prompt'] as String;
  }

  Future<JobStatus> createGeneratePromptJob({
    required String prompt,
    String? modelName,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate-prompt',
      data: {
        'prompt': prompt,
        if (modelName != null && modelName.trim().isNotEmpty)
          'model_name': modelName.trim(),
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createGenerateImageToVideoPromptJob({
    required String prompt,
    String? imageId,
    String? imagePath,
    String? imageName,
    String? modelName,
  }) async {
    final hasUploadedImage =
        imagePath != null &&
        imagePath.isNotEmpty &&
        imageName != null &&
        imageName.isNotEmpty;
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate-i2v-prompt',
      data: hasUploadedImage
          ? FormData.fromMap({
              'prompt': prompt,
              if (modelName != null && modelName.trim().isNotEmpty)
                'model_name': modelName.trim(),
              'image': await MultipartFile.fromFile(
                imagePath,
                filename: imageName,
              ),
            })
          : {
              'prompt': prompt,
              if (modelName != null && modelName.trim().isNotEmpty)
                'model_name': modelName.trim(),
              if (imageId != null && imageId.isNotEmpty) 'image_id': imageId,
            },
    );
    return JobStatus.fromJson(response.data!);
  }
}
