class PromptPreset {
  PromptPreset({
    required this.id,
    required this.name,
    required this.positivePrompt,
    required this.negativePrompt,
  });

  final String id;
  final String name;
  final String positivePrompt;
  final String negativePrompt;

  PromptPreset copyWith({
    String? id,
    String? name,
    String? positivePrompt,
    String? negativePrompt,
  }) {
    return PromptPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      positivePrompt: positivePrompt ?? this.positivePrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
    );
  }

  factory PromptPreset.fromJson(Map<String, dynamic> json) {
    return PromptPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      positivePrompt: json['positive_prompt'] as String? ?? '',
      negativePrompt: json['negative_prompt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'positive_prompt': positivePrompt,
      'negative_prompt': negativePrompt,
    };
  }
}

abstract class NamedPromptEntry {
  String get id;
  String get name;
  String get prompt;
}

class ChatSystemPrompt implements NamedPromptEntry {
  ChatSystemPrompt({
    required this.id,
    required this.name,
    required this.prompt,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final String prompt;

  ChatSystemPrompt copyWith({String? id, String? name, String? prompt}) {
    return ChatSystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
    );
  }

  factory ChatSystemPrompt.fromJson(Map<String, dynamic> json) {
    return ChatSystemPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      prompt: json['prompt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'prompt': prompt};
  }
}

class SavedPrompt implements NamedPromptEntry {
  SavedPrompt({required this.id, required this.name, required this.prompt});

  @override
  final String id;
  @override
  final String name;
  @override
  final String prompt;

  SavedPrompt copyWith({String? id, String? name, String? prompt}) {
    return SavedPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
    );
  }

  factory SavedPrompt.fromJson(Map<String, dynamic> json) {
    return SavedPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      prompt: json['prompt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'prompt': prompt};
  }
}
