class ChatToolInfo {
  ChatToolInfo({
    required this.id,
    required this.serverName,
    required this.name,
    required this.description,
  });

  final String id;
  final String serverName;
  final String name;
  final String description;

  String get label {
    final base = name.replaceAll('_', ' ').trim();
    if (serverName.isEmpty) {
      return base.isEmpty ? id : base;
    }
    return base.isEmpty ? id : '$serverName: $base';
  }

  factory ChatToolInfo.fromJson(Map<String, dynamic> json) {
    return ChatToolInfo(
      id: json['id'] as String? ?? '',
      serverName: json['server_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}
