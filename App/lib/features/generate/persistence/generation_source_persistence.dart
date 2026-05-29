import 'dart:convert';
import 'dart:io';

import 'package:noviagen/features/generate/domain/generation_settings.dart';
import 'package:noviagen/features/generate/services/image_orientation_detector.dart';
import 'package:noviagen/models/media.dart';

class RestoredGenerationSource {
  const RestoredGenerationSource({
    required this.storedSource,
    required this.localSource,
    required this.sourceOrientation,
  });

  final ImageRecord? storedSource;
  final LocalImageSource? localSource;
  final ImageOrientationSetting? sourceOrientation;

  bool get hasSource => storedSource != null || localSource != null;
}

Map<String, dynamic>? encodeGenerationSource({
  required ImageRecord? storedSource,
  required LocalImageSource? localSource,
}) {
  if (storedSource != null) {
    return {
      'kind': 'stored',
      'image': imageRecordToGenerationSourceJson(storedSource),
    };
  }
  if (localSource != null) {
    return {
      'kind': 'local',
      'path': localSource.path,
      'name': localSource.name,
    };
  }
  return null;
}

Future<RestoredGenerationSource> decodePersistedGenerationSource(
  String? rawValue, {
  required bool forVideo,
}) async {
  ImageRecord? storedSource;
  LocalImageSource? localSource;
  ImageOrientationSetting? sourceOrientation;
  final raw = rawValue?.trim() ?? '';
  if (raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final payload = Map<String, dynamic>.from(decoded);
        final kind = payload['kind'] as String? ?? '';
        if (kind == 'stored') {
          final imageJson = payload['image'];
          if (imageJson is Map) {
            storedSource = ImageRecord.fromJson(
              Map<String, dynamic>.from(imageJson),
            );
            if (forVideo) {
              sourceOrientation = imageOrientationFromDimensions(
                storedSource.width,
                storedSource.height,
              );
            }
          }
        } else if (kind == 'local') {
          final path = (payload['path'] as String? ?? '').trim();
          final name = (payload['name'] as String? ?? '').trim();
          if (path.isNotEmpty && name.isNotEmpty && File(path).existsSync()) {
            localSource = LocalImageSource(path: path, name: name);
            if (forVideo) {
              sourceOrientation = await detectLocalImageOrientation(path);
            }
          }
        }
      }
    } catch (_) {}
  }

  return RestoredGenerationSource(
    storedSource: storedSource,
    localSource: localSource,
    sourceOrientation: sourceOrientation,
  );
}

Map<String, dynamic> imageRecordToGenerationSourceJson(ImageRecord image) {
  return {
    'id': image.id,
    'status': image.status,
    'media_type': image.mediaType,
    'mime_type': image.mimeType,
    'width': image.width,
    'height': image.height,
    'prompt': image.prompt,
    'default_positive_prompt': image.defaultPositivePrompt,
    'default_negative_prompt': image.defaultNegativePrompt,
    'final_positive_prompt': image.finalPositivePrompt,
    'model_id': image.modelId,
    'loras': image.loras.map((item) => item.toJson()).toList(),
    'tags': image.tags,
    'caption': image.caption,
    'num_inference_steps': image.numInferenceSteps,
    'guidance_scale': image.guidanceScale,
    'image_orientation': image.imageOrientation,
    'file_url': image.fileUrl,
    'preview_url': image.previewUrl,
    'thumbnail_url': image.thumbnailUrl,
    'created_at': image.createdAt,
    'rating': image.rating,
    'stored_at': image.storedAt,
    'deleted_at': image.deletedAt,
    'source_image_id': image.sourceImageId,
    'source_image_exists': image.sourceImageExists,
    'scale_factor': image.scaleFactor,
    'is_upscaled': image.isUpscaled,
    'poster_url': image.posterUrl,
    'duration_seconds': image.durationSeconds,
    'generation_duration_seconds': image.generationDurationSeconds,
    'fps': image.fps,
    'num_frames': image.numFrames,
  };
}
