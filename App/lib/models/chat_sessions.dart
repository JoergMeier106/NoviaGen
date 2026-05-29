class ChatSessionRecord {
  ChatSessionRecord({
    required this.id,
    required this.title,
    required this.modelName,
    required this.systemMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    this.lastMessagePreview,
    this.lastMessageRole,
    this.lastMessageAt,
  });

  final String id;
  final String title;
  final String modelName;
  final String systemMessage;
  final String createdAt;
  final String updatedAt;
  final int messageCount;
  final String? lastMessagePreview;
  final String? lastMessageRole;
  final String? lastMessageAt;

  factory ChatSessionRecord.fromJson(Map<String, dynamic> json) {
    return ChatSessionRecord(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'New chat',
      modelName: json['model_name'] as String? ?? '',
      systemMessage: json['system_message'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageRole: json['last_message_role'] as String?,
      lastMessageAt: json['last_message_at'] as String?,
    );
  }
}

class ChatSessionSummary {
  ChatSessionSummary({
    required this.sessionId,
    required this.summaryText,
    required this.updatedAt,
    this.coveredThroughMessageId,
  });

  final String sessionId;
  final String summaryText;
  final String updatedAt;
  final String? coveredThroughMessageId;

  factory ChatSessionSummary.fromJson(Map<String, dynamic> json) {
    return ChatSessionSummary(
      sessionId: json['session_id'] as String? ?? '',
      summaryText: json['summary_text'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      coveredThroughMessageId: json['covered_through_message_id'] as String?,
    );
  }
}
