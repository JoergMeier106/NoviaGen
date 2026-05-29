class ModelAsset {
  ModelAsset({
    required this.id,
    required this.label,
    required this.rating,
    this.ratingCount = 0,
  });

  final String id;
  final String label;
  final double rating;
  final int ratingCount;

  factory ModelAsset.fromJson(Map<String, dynamic> json) {
    return ModelAsset(
      id: json['id'] as String,
      label: json['label'] as String,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class LoraAsset {
  LoraAsset({
    required this.id,
    required this.label,
    required this.defaultStrength,
    required this.rating,
    this.ratingCount = 0,
  });

  final String id;
  final String label;
  final double defaultStrength;
  final double rating;
  final int ratingCount;

  factory LoraAsset.fromJson(Map<String, dynamic> json) {
    return LoraAsset(
      id: json['id'] as String,
      label: json['label'] as String,
      defaultStrength: (json['default_strength'] as num).toDouble(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class VideoModelAsset {
  VideoModelAsset({
    required this.id,
    required this.label,
    this.workflowLoras = const <VideoWorkflowLoraAsset>[],
  });

  final String id;
  final String label;
  final List<VideoWorkflowLoraAsset> workflowLoras;

  factory VideoModelAsset.fromJson(Map<String, dynamic> json) {
    return VideoModelAsset(
      id: json['id'] as String,
      label: json['label'] as String,
      workflowLoras: ((json['workflow_loras'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(VideoWorkflowLoraAsset.fromJson)
          .toList()),
    );
  }
}

class VideoWorkflowLoraAsset {
  VideoWorkflowLoraAsset({
    required this.id,
    required this.name,
    required this.label,
    required this.defaultStrength,
    required this.enabled,
    this.nodeTitle = '',
  });

  final String id;
  final String name;
  final String label;
  final double defaultStrength;
  final bool enabled;
  final String nodeTitle;

  factory VideoWorkflowLoraAsset.fromJson(Map<String, dynamic> json) {
    return VideoWorkflowLoraAsset(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['label'] as String? ?? '',
      label: json['label'] as String? ?? json['name'] as String? ?? '',
      defaultStrength: (json['default_strength'] as num?)?.toDouble() ?? 1.0,
      enabled: json['enabled'] as bool? ?? true,
      nodeTitle: json['node_title'] as String? ?? '',
    );
  }
}

class VideoDiffusionModelAsset {
  VideoDiffusionModelAsset({required this.name});

  final String name;

  String get label => name;

  factory VideoDiffusionModelAsset.fromJson(dynamic json) {
    if (json is String) {
      return VideoDiffusionModelAsset(name: json);
    }
    final map = json as Map<String, dynamic>;
    return VideoDiffusionModelAsset(
      name: (map['name'] ?? map['filename'] ?? map['model_name']) as String,
    );
  }
}

class VideoPresetOption {
  VideoPresetOption({
    required this.id,
    required this.label,
    required this.maxWidth,
    required this.maxHeight,
    required this.numFrames,
    required this.fps,
    required this.numInferenceSteps,
    required this.isDefault,
    this.description,
    this.supportsCustomValues = false,
  });

  final String id;
  final String label;
  final int maxWidth;
  final int maxHeight;
  final int numFrames;
  final int fps;
  final int numInferenceSteps;
  final bool isDefault;
  final String? description;
  final bool supportsCustomValues;

  bool get isCustom => id == 'custom';

  factory VideoPresetOption.fromJson(Map<String, dynamic> json) {
    return VideoPresetOption(
      id: json['id'] as String,
      label: json['label'] as String,
      maxWidth: (json['max_width'] as num).toInt(),
      maxHeight: (json['max_height'] as num).toInt(),
      numFrames: (json['num_frames'] as num).toInt(),
      fps: (json['fps'] as num).toInt(),
      numInferenceSteps: (json['num_inference_steps'] as num?)?.toInt() ?? 8,
      isDefault: json['is_default'] as bool? ?? false,
      description: json['description'] as String?,
      supportsCustomValues: json['supports_custom_values'] as bool? ?? false,
    );
  }
}

class AssetResponse {
  AssetResponse({
    required this.models,
    required this.loras,
    required this.videoModels,
    required this.videoDiffusionModels,
    required this.videoPresets,
  });

  final List<ModelAsset> models;
  final List<LoraAsset> loras;
  final List<VideoModelAsset> videoModels;
  final List<VideoDiffusionModelAsset> videoDiffusionModels;
  final List<VideoPresetOption> videoPresets;

  factory AssetResponse.fromJson(Map<String, dynamic> json) {
    return AssetResponse(
      models: ((json['models'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(ModelAsset.fromJson)
          .toList()),
      loras: ((json['loras'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(LoraAsset.fromJson)
          .toList()),
      videoModels: ((json['video_models'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(VideoModelAsset.fromJson)
          .toList()),
      videoDiffusionModels:
          ((json['video_diffusion_models'] as List<dynamic>? ?? <dynamic>[])
              .map(VideoDiffusionModelAsset.fromJson)
              .toList()),
      videoPresets: ((json['video_presets'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(VideoPresetOption.fromJson)
          .toList()),
    );
  }
}
