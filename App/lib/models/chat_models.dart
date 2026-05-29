enum OllamaThinkingMode { unsupported, toggle, levelOnly }

class OllamaModelInfo {
  OllamaModelInfo({
    required this.name,
    required this.model,
    required this.details,
    required this.isLoaded,
    required this.capabilities,
    required this.thinkingMode,
    this.modifiedAt,
    this.size,
    this.digest,
    this.contextLength,
    this.modelContextLength,
    this.sizeVram,
    this.expiresAt,
  });

  final String name;
  final String model;
  final Map<String, dynamic> details;
  final bool isLoaded;
  final List<String> capabilities;
  final OllamaThinkingMode thinkingMode;
  final String? modifiedAt;
  final int? size;
  final String? digest;
  final int? contextLength;
  final int? modelContextLength;
  final int? sizeVram;
  final String? expiresAt;

  bool get supportsThinkingToggle => thinkingMode == OllamaThinkingMode.toggle;
  bool get usesThinkingLevels => thinkingMode == OllamaThinkingMode.levelOnly;
  bool get supportsVision =>
      capabilities.any((item) => item.toLowerCase() == 'vision');
  bool get supportsTools =>
      capabilities.any((item) => item.toLowerCase() == 'tools');
  bool get supportsAudio =>
      capabilities.any((item) => item.toLowerCase() == 'audio');
  bool get supportsThinking =>
      capabilities.any((item) => item.toLowerCase() == 'thinking');

  factory OllamaModelInfo.fromJson(Map<String, dynamic> json) {
    return OllamaModelInfo(
      name: json['name'] as String? ?? '',
      model: json['model'] as String? ?? '',
      details: Map<String, dynamic>.from(
        json['details'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      isLoaded: json['is_loaded'] as bool? ?? false,
      capabilities: ((json['capabilities'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .toList()),
      thinkingMode: switch (json['thinking_mode'] as String? ?? 'unsupported') {
        'toggle' => OllamaThinkingMode.toggle,
        'level_only' => OllamaThinkingMode.levelOnly,
        _ => OllamaThinkingMode.unsupported,
      },
      modifiedAt: json['modified_at'] as String?,
      size: (json['size'] as num?)?.toInt(),
      digest: json['digest'] as String?,
      contextLength: (json['context_length'] as num?)?.toInt(),
      modelContextLength: (json['model_context_length'] as num?)?.toInt(),
      sizeVram: (json['size_vram'] as num?)?.toInt(),
      expiresAt: json['expires_at'] as String?,
    );
  }
}
