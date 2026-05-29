import 'generation.dart';

class LocalImageSource {
  LocalImageSource({required this.path, required this.name});

  final String path;
  final String name;
}

class ImageRecord {
  ImageRecord({
    required this.id,
    required this.status,
    required this.mediaType,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.prompt,
    required this.defaultPositivePrompt,
    required this.defaultNegativePrompt,
    required this.finalPositivePrompt,
    required this.modelId,
    required this.loras,
    required this.tags,
    required this.caption,
    required this.numInferenceSteps,
    required this.guidanceScale,
    required this.imageOrientation,
    required this.fileUrl,
    required this.previewUrl,
    this.thumbnailUrl,
    required this.createdAt,
    required this.rating,
    this.storedAt,
    this.deletedAt,
    this.sourceImageId,
    this.sourceImageExists = false,
    this.scaleFactor,
    this.isUpscaled = false,
    this.posterUrl,
    this.durationSeconds,
    this.generationDurationSeconds,
    this.fps,
    this.numFrames,
  });

  final String id;
  final String status;
  final String mediaType;
  final String mimeType;
  final int width;
  final int height;
  final String prompt;
  final String defaultPositivePrompt;
  final String defaultNegativePrompt;
  final String finalPositivePrompt;
  final String modelId;
  final List<SelectedLora> loras;
  final List<String> tags;
  final String caption;
  final int numInferenceSteps;
  final double guidanceScale;
  final String imageOrientation;
  final String fileUrl;
  final String previewUrl;
  final String? thumbnailUrl;
  final String createdAt;
  final int rating;
  final String? storedAt;
  final String? deletedAt;
  final String? sourceImageId;
  final bool sourceImageExists;
  final double? scaleFactor;
  final bool isUpscaled;
  final String? posterUrl;
  final double? durationSeconds;
  final double? generationDurationSeconds;
  final int? fps;
  final int? numFrames;

  bool get isPending => status == 'queued' || status == 'running';
  bool get isReady => status == 'stored';
  bool get isDeleted => status == 'deleted';
  bool get isVideo => mediaType == 'video';
  bool get isGif => mediaType == 'gif' || mimeType == 'image/gif';
  bool get isImage => !isVideo && !isGif;
  bool get isStillImage => isImage || isGif;
  bool get canPreviewFile => isReady || isDeleted;
  bool get canDownload => isReady || isDeleted;
  bool get canEditMetadata => isReady;
  bool get canScale => (isReady || isPending) && (isVideo || isImage);
  bool get canRegenerate => isReady && (isVideo || isImage);

  String get mediaTypeLabel => isVideo
      ? 'Video'
      : isGif
      ? 'GIF'
      : 'Image';

  ImageRecord copyWith({
    String? status,
    List<String>? tags,
    String? caption,
    int? rating,
    String? storedAt,
    String? fileUrl,
    bool? sourceImageExists,
    String? previewUrl,
    String? thumbnailUrl,
    String? posterUrl,
  }) {
    return ImageRecord(
      id: id,
      status: status ?? this.status,
      mediaType: mediaType,
      mimeType: mimeType,
      width: width,
      height: height,
      prompt: prompt,
      defaultPositivePrompt: defaultPositivePrompt,
      defaultNegativePrompt: defaultNegativePrompt,
      finalPositivePrompt: finalPositivePrompt,
      modelId: modelId,
      loras: loras,
      tags: tags ?? this.tags,
      caption: caption ?? this.caption,
      numInferenceSteps: numInferenceSteps,
      guidanceScale: guidanceScale,
      imageOrientation: imageOrientation,
      fileUrl: fileUrl ?? this.fileUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt,
      rating: rating ?? this.rating,
      storedAt: storedAt ?? this.storedAt,
      deletedAt: deletedAt,
      sourceImageId: sourceImageId,
      sourceImageExists: sourceImageExists ?? this.sourceImageExists,
      scaleFactor: scaleFactor,
      isUpscaled: isUpscaled,
      posterUrl: posterUrl ?? this.posterUrl,
      durationSeconds: durationSeconds,
      generationDurationSeconds: generationDurationSeconds,
      fps: fps,
      numFrames: numFrames,
    );
  }

  factory ImageRecord.fromJson(Map<String, dynamic> json) {
    return ImageRecord(
      id: json['id'] as String,
      status: json['status'] as String,
      mediaType: json['media_type'] as String? ?? 'image',
      mimeType: json['mime_type'] as String? ?? 'image/png',
      width: json['width'] as int,
      height: json['height'] as int,
      prompt: json['prompt'] as String,
      defaultPositivePrompt: json['default_positive_prompt'] as String,
      defaultNegativePrompt: json['default_negative_prompt'] as String,
      finalPositivePrompt: json['final_positive_prompt'] as String,
      modelId: json['model_id'] as String,
      loras: ((json['loras'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(SelectedLora.fromJson)
          .toList()),
      tags: (json['tags'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item as String)
          .toList(),
      caption: json['caption'] as String? ?? '',
      numInferenceSteps: (json['num_inference_steps'] as num?)?.toInt() ?? 40,
      guidanceScale: (json['guidance_scale'] as num?)?.toDouble() ?? 5.0,
      imageOrientation: json['image_orientation'] as String? ?? 'landscape',
      fileUrl: json['file_url'] as String,
      previewUrl: json['preview_url'] as String? ?? json['file_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdAt: json['created_at'] as String,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      storedAt: json['stored_at'] as String?,
      deletedAt: json['deleted_at'] as String?,
      sourceImageId: json['source_image_id'] as String?,
      sourceImageExists:
          json['source_image_exists'] as bool? ??
          ((json['source_image_id'] as String?)?.trim().isNotEmpty ?? false),
      scaleFactor: (json['scale_factor'] as num?)?.toDouble(),
      isUpscaled: json['is_upscaled'] as bool? ?? false,
      posterUrl: json['poster_url'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      generationDurationSeconds: (json['generation_duration_seconds'] as num?)
          ?.toDouble(),
      fps: (json['fps'] as num?)?.toInt(),
      numFrames: (json['num_frames'] as num?)?.toInt(),
    );
  }
}
