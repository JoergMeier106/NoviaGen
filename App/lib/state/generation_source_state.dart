import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/media.dart';
import 'generation_settings.dart';
import 'image_orientation_detector.dart';
import 'request_errors.dart';

class GenerationSourceState {
  GenerationSourceState({
    required this.setMessage,
    required this.setGenerateMode,
    required this.syncVideoDraftOrientation,
    required this.persistSource,
    required this.setRequestError,
    required this.onChanged,
  });

  final void Function(String? value) setMessage;
  final void Function(GenerateMode value) setGenerateMode;
  final VoidCallback syncVideoDraftOrientation;
  final Future<void> Function({required bool forVideo}) persistSource;
  final RequestErrorHandler setRequestError;
  final VoidCallback onChanged;
  final ImagePicker _imagePicker = ImagePicker();

  ImageRecord? imageSource;
  LocalImageSource? imageLocalSource;
  ImageRecord? videoSource;
  LocalImageSource? videoLocalSource;
  ImageOrientationSetting? videoSourceOrientation;

  bool get hasImageSource => imageSource != null || imageLocalSource != null;
  bool get hasVideoSource => videoSource != null || videoLocalSource != null;

  bool attachStoredImageForImageGeneration(ImageRecord image) {
    if (image.isVideo) {
      setMessage('Only still images can be used as source.');
      onChanged();
      return false;
    }
    imageSource = image;
    imageLocalSource = null;
    setMessage('Image attached as source.');
    unawaited(persistSource(forVideo: false));
    onChanged();
    return true;
  }

  bool attachStoredImageForVideoGeneration(ImageRecord image) {
    if (image.isVideo) {
      setMessage('Only still images can be used as source.');
      onChanged();
      return false;
    }
    videoSource = image;
    videoLocalSource = null;
    videoSourceOrientation = imageOrientationFromDimensions(
      image.width,
      image.height,
    );
    setMessage('Image attached as video source.');
    unawaited(persistSource(forVideo: true));
    onChanged();
    return true;
  }

  Future<void> attachLocalImage({
    required LocalImageSource source,
    required bool forVideo,
  }) async {
    if (forVideo) {
      videoLocalSource = source;
      videoSource = null;
      videoSourceOrientation = await detectLocalImageOrientation(source.path);
      setMessage('Local image attached as video source.');
      unawaited(persistSource(forVideo: true));
    } else {
      imageLocalSource = source;
      imageSource = null;
      setMessage('Local image attached as source.');
      unawaited(persistSource(forVideo: false));
    }
    onChanged();
  }

  Future<void> attachLocalGenerationSource({
    required String path,
    required String name,
    required bool forVideo,
  }) async {
    await attachLocalImage(
      source: LocalImageSource(path: path, name: name),
      forVideo: forVideo,
    );
    if (forVideo) {
      syncVideoDraftOrientation();
      setGenerateMode(GenerateMode.video);
    } else {
      setGenerateMode(GenerateMode.image);
    }
    onChanged();
  }

  Future<void> pickGenerationSource({
    required ImageSource source,
    required bool forVideo,
  }) async {
    try {
      final file = await _imagePicker.pickImage(source: source);
      if (file == null) {
        return;
      }
      await attachLocalGenerationSource(
        path: file.path,
        name: file.name,
        forVideo: forVideo,
      );
      setMessage(_pickedSourceMessage(source: source, forVideo: forVideo));
    } catch (error) {
      setRequestError(
        error,
        generalMessage: 'Couldn\'t load the selected image. Please try again.',
      );
    }
    onChanged();
  }

  void clearImageSource() {
    imageSource = null;
    imageLocalSource = null;
    unawaited(persistSource(forVideo: false));
    onChanged();
  }

  void clearVideoSource() {
    videoSource = null;
    videoLocalSource = null;
    videoSourceOrientation = null;
    unawaited(persistSource(forVideo: true));
    onChanged();
  }

  void setStoredVideoSource(ImageRecord image) {
    videoSource = image;
    videoLocalSource = null;
    videoSourceOrientation = imageOrientationFromDimensions(
      image.width,
      image.height,
    );
    unawaited(persistSource(forVideo: true));
  }

  Future<void> clearAll() async {
    imageSource = null;
    imageLocalSource = null;
    videoSource = null;
    videoLocalSource = null;
    videoSourceOrientation = null;
    await persistSource(forVideo: false);
    await persistSource(forVideo: true);
    onChanged();
  }

  bool clearStoredSourceById(String imageId) {
    var changed = false;
    if (imageSource?.id == imageId) {
      imageSource = null;
      unawaited(persistSource(forVideo: false));
      changed = true;
    }
    if (videoSource?.id == imageId) {
      videoSource = null;
      videoSourceOrientation = null;
      unawaited(persistSource(forVideo: true));
      changed = true;
    }
    return changed;
  }

  bool replaceStoredSource(ImageRecord image) {
    var changed = false;
    if (imageSource?.id == image.id) {
      imageSource = image;
      unawaited(persistSource(forVideo: false));
      changed = true;
    }
    if (videoSource?.id == image.id) {
      videoSource = image;
      videoSourceOrientation = imageOrientationFromDimensions(
        image.width,
        image.height,
      );
      unawaited(persistSource(forVideo: true));
      changed = true;
    }
    return changed;
  }

  void restore({
    required bool forVideo,
    required ImageRecord? storedSource,
    required LocalImageSource? localSource,
    ImageOrientationSetting? sourceOrientation,
  }) {
    if (forVideo) {
      videoSource = storedSource;
      videoLocalSource = localSource;
      videoSourceOrientation = sourceOrientation;
    } else {
      imageSource = storedSource;
      imageLocalSource = localSource;
    }
  }

  Map<String, dynamic>? encodePersistedSource({required bool forVideo}) {
    final storedSource = forVideo ? videoSource : imageSource;
    final localSource = forVideo ? videoLocalSource : imageLocalSource;
    if (storedSource != null) {
      return {'kind': 'stored', 'image': _imageRecordToJson(storedSource)};
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

  Future<bool> restorePersistedSource(
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
    restore(
      forVideo: forVideo,
      storedSource: storedSource,
      localSource: localSource,
      sourceOrientation: sourceOrientation,
    );
    return storedSource != null || localSource != null;
  }

  String _pickedSourceMessage({
    required ImageSource source,
    required bool forVideo,
  }) {
    if (source == ImageSource.camera) {
      return forVideo
          ? 'Photo attached as video source.'
          : 'Photo attached as source.';
    }
    return forVideo
        ? 'Gallery image attached as video source.'
        : 'Gallery image attached as source.';
  }

  Map<String, dynamic> _imageRecordToJson(ImageRecord image) {
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
}
