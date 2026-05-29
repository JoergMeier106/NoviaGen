import 'dart:async';
import '../models/jobs.dart';
import 'transport.dart';

mixin MediaJobApi on ApiClientTransport {
  Future<JobStatus> createUpscaleJob({
    required String imageId,
    required double scaleFactor,
    required int numInferenceSteps,
    required double guidanceScale,
    bool deleteSourceAfterFinish = false,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/upscale',
      data: {
        'image_id': imageId,
        'scale_factor': scaleFactor,
        'num_inference_steps': numInferenceSteps,
        'guidance_scale': guidanceScale,
        'delete_source_after_finish': deleteSourceAfterFinish,
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createUpscaleVideoJob({
    required String imageId,
    required double scaleFactor,
    bool deleteSourceAfterFinish = false,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/upscale-video',
      data: {
        'image_id': imageId,
        'scale_factor': scaleFactor,
        'delete_source_after_finish': deleteSourceAfterFinish,
      },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createConvertVideoToGifJob({
    required String imageId,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/convert-video-gif',
      data: {'image_id': imageId},
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<JobStatus> createGenerateAudioVideoJob({
    required String imageId,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/generate-audio-video',
      data: {'image_id': imageId},
    );
    return JobStatus.fromJson(response.data!);
  }
}
