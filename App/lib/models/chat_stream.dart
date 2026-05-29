import 'chat_messages.dart';
import 'chat_sessions.dart';

class ChatStreamEvent {
  ChatStreamEvent({
    required this.type,
    this.messageId,
    this.delta,
    this.error,
    this.status,
    this.session,
    this.userMessage,
    this.assistantMessage,
  });

  final String type;
  final String? messageId;
  final String? delta;
  final String? error;
  final int? status;
  final ChatSessionRecord? session;
  final ChatMessageRecord? userMessage;
  final ChatMessageRecord? assistantMessage;

  factory ChatStreamEvent.fromJson(Map<String, dynamic> json) {
    return ChatStreamEvent(
      type: json['type'] as String? ?? '',
      messageId: json['message_id'] as String?,
      delta: json['delta'] as String?,
      error: json['error'] as String?,
      status: (json['status'] as num?)?.toInt(),
      session: json['session'] == null
          ? null
          : ChatSessionRecord.fromJson(json['session'] as Map<String, dynamic>),
      userMessage: json['user_message'] == null
          ? null
          : ChatMessageRecord.fromJson(
              json['user_message'] as Map<String, dynamic>,
            ),
      assistantMessage: json['assistant_message'] == null
          ? null
          : ChatMessageRecord.fromJson(
              json['assistant_message'] as Map<String, dynamic>,
            ),
    );
  }
}
