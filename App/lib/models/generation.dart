class SelectedLora {
  SelectedLora({required this.loraId, required this.strength});

  final String loraId;
  final double strength;

  SelectedLora copyWith({String? loraId, double? strength}) {
    return SelectedLora(
      loraId: loraId ?? this.loraId,
      strength: strength ?? this.strength,
    );
  }

  factory SelectedLora.fromJson(Map<String, dynamic> json) {
    return SelectedLora(
      loraId: json['lora_id'] as String,
      strength: (json['strength'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'lora_id': loraId, 'strength': strength};
  }
}

class VideoWorkflowLoraStrength {
  VideoWorkflowLoraStrength({required this.loraId, required this.strength});

  final String loraId;
  final double strength;

  Map<String, dynamic> toJson() {
    return {'lora_id': loraId, 'strength': strength};
  }
}
