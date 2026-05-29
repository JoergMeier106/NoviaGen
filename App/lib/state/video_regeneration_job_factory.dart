import 'package:dio/dio.dart';

import '../api_client.dart';
import '../models/jobs.dart';
import '../models/media.dart';
import 'video_asset_selection_state.dart';


class VideoRegenerationJobFactory {
  VideoRegenerationJobFactory({
    required this.videoAssets,
    required this.findKnownMedia,
  });

  final VideoAssetSelectionState videoAssets;
  final ImageRecord? Function(String imageId) findKnownMedia;

  Future<JobStatus> create({
    required ApiClient client,
    required ImageRecord image,
  }) async {
    final presetId = _regenerationPresetId;
    final sourceImage = _findRegenerationSourceImage(image);
    if (sourceImage != null) {
      return _createImageToVideoJob(
        client: client,
        sourceImageId: sourceImage.id,
        image: image,
        presetId: presetId,
      );
    }

    final sourceImageId = image.sourceImageId;
    if (sourceImageId != null) {
      final animateJob = await _tryCreateImageToVideoJob(
        client: client,
        sourceImageId: sourceImageId,
        image: image,
        presetId: presetId,
      );
      if (animateJob != null) {
        return animateJob;
      }
    }

    return client.createGenerateVideoJob(
      prompt: image.prompt,
      defaultPositivePrompt: image.defaultPositivePrompt,
      defaultNegativePrompt: image.defaultNegativePrompt,
      preset: presetId,
      customWidth: image.width,
      customHeight: image.height,
      customFps: image.fps,
      customNumFrames: image.numFrames,
    );
  }

  String get _regenerationPresetId {
    return videoAssets.selectedPreset?.id ??
        (videoAssets.presets.isNotEmpty
            ? videoAssets.presets.first.id
            : 'standard');
  }

  ImageRecord? _findRegenerationSourceImage(ImageRecord image) {
    final visited = <String>{};
    String? currentId = image.sourceImageId;
    while (currentId != null &&
        currentId.isNotEmpty &&
        visited.add(currentId)) {
      final current = findKnownMedia(currentId);
      if (current == null) {
        return null;
      }
      if (current.isStillImage) {
        return current;
      }
      currentId = current.sourceImageId;
    }
    return null;
  }

  Future<JobStatus?> _tryCreateImageToVideoJob({
    required ApiClient client,
    required String sourceImageId,
    required ImageRecord image,
    required String presetId,
  }) async {
    try {
      return await _createImageToVideoJob(
        client: client,
        sourceImageId: sourceImageId,
        image: image,
        presetId: presetId,
      );
    } on DioException catch (error) {
      if (!_canFallbackToTextToVideo(error)) {
        rethrow;
      }
      return null;
    }
  }

  Future<JobStatus> _createImageToVideoJob({
    required ApiClient client,
    required String sourceImageId,
    required ImageRecord image,
    required String presetId,
  }) {
    return client.createAnimateImageJob(
      imageId: sourceImageId,
      prompt: image.prompt,
      defaultPositivePrompt: image.defaultPositivePrompt,
      defaultNegativePrompt: image.defaultNegativePrompt,
      preset: presetId,
      customWidth: image.width,
      customHeight: image.height,
      customFps: image.fps,
      customNumFrames: image.numFrames,
    );
  }

  bool _canFallbackToTextToVideo(DioException error) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;
    final errorText = responseData is Map<String, dynamic>
        ? '${responseData['error'] ?? ''}'
        : '';
    return statusCode == 400 ||
        statusCode == 404 ||
        errorText.contains('Only images can be animated') ||
        errorText.contains('Only images or GIFs can be animated') ||
        errorText.contains('Only stored images can be animated') ||
        errorText.contains('Only stored images or GIFs can be animated') ||
        errorText.contains('Unknown image_id');
  }
}
