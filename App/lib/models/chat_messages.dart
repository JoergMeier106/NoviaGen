import 'chat_attachments.dart';
import 'chat_sessions.dart';
import 'media.dart';

class ChatMessageRecord {
  ChatMessageRecord({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.summarizedIntoMemory,
    this.attachments = const <ChatAttachmentRecord>[],
    this.toolTraces = const <ChatToolTraceRecord>[],
    this.thinking,
    this.contextImageId,
    this.contextImage,
    this.contextImageUrl,
    this.contextLocalImagePath,
    this.modelName,
    this.totalDurationNs,
    this.loadDurationNs,
    this.promptEvalCount,
    this.promptEvalDurationNs,
    this.evalCount,
    this.evalDurationNs,
  });

  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String createdAt;
  final bool summarizedIntoMemory;
  final List<ChatAttachmentRecord> attachments;
  final List<ChatToolTraceRecord> toolTraces;
  final String? thinking;
  final String? contextImageId;
  final ImageRecord? contextImage;
  final String? contextImageUrl;
  final String? contextLocalImagePath;
  final String? modelName;
  final int? totalDurationNs;
  final int? loadDurationNs;
  final int? promptEvalCount;
  final int? promptEvalDurationNs;
  final int? evalCount;
  final int? evalDurationNs;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  List<ChatAttachmentRecord> get effectiveAttachments {
    if (attachments.isNotEmpty) {
      return attachments;
    }
    if (contextImage != null ||
        contextImageUrl != null ||
        contextLocalImagePath != null) {
      return <ChatAttachmentRecord>[
        ChatAttachmentRecord(
          contextImageId: contextImageId,
          contextImage: contextImage,
          contextImageUrl: contextImageUrl,
          localPath: contextLocalImagePath,
        ),
      ];
    }
    return const <ChatAttachmentRecord>[];
  }

  ChatMessageRecord copyWith({
    String? id,
    String? content,
    String? thinking,
    List<ChatToolTraceRecord>? toolTraces,
    List<ChatAttachmentRecord>? attachments,
    ImageRecord? contextImage,
    String? contextImageUrl,
    String? contextLocalImagePath,
  }) {
    return ChatMessageRecord(
      id: id ?? this.id,
      sessionId: sessionId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      summarizedIntoMemory: summarizedIntoMemory,
      attachments: attachments ?? this.attachments,
      toolTraces: toolTraces ?? this.toolTraces,
      thinking: thinking ?? this.thinking,
      contextImageId: contextImageId,
      contextImage: contextImage ?? this.contextImage,
      contextImageUrl: contextImageUrl ?? this.contextImageUrl,
      contextLocalImagePath:
          contextLocalImagePath ?? this.contextLocalImagePath,
      modelName: modelName,
      totalDurationNs: totalDurationNs,
      loadDurationNs: loadDurationNs,
      promptEvalCount: promptEvalCount,
      promptEvalDurationNs: promptEvalDurationNs,
      evalCount: evalCount,
      evalDurationNs: evalDurationNs,
    );
  }

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) {
    return ChatMessageRecord(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      summarizedIntoMemory: json['summarized_into_memory'] as bool? ?? false,
      attachments: ((json['attachments'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(ChatAttachmentRecord.fromJson)
          .toList()),
      toolTraces: ((json['tool_traces'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(ChatToolTraceRecord.fromJson)
          .toList()),
      thinking: json['thinking'] as String?,
      contextImageId: json['context_image_id'] as String?,
      contextImage: json['context_image'] == null
          ? null
          : ImageRecord.fromJson(json['context_image'] as Map<String, dynamic>),
      contextImageUrl: json['context_image_url'] as String?,
      contextLocalImagePath: json['context_local_image_path'] as String?,
      modelName: json['model_name'] as String?,
      totalDurationNs: (json['total_duration_ns'] as num?)?.toInt(),
      loadDurationNs: (json['load_duration_ns'] as num?)?.toInt(),
      promptEvalCount: (json['prompt_eval_count'] as num?)?.toInt(),
      promptEvalDurationNs: (json['prompt_eval_duration_ns'] as num?)?.toInt(),
      evalCount: (json['eval_count'] as num?)?.toInt(),
      evalDurationNs: (json['eval_duration_ns'] as num?)?.toInt(),
    );
  }
}

class ChatToolTraceRecord {
  ChatToolTraceRecord({required this.content, this.toolId, this.toolName});

  final String content;
  final String? toolId;
  final String? toolName;

  String get label {
    final name = toolName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final id = toolId?.trim();
    return id == null || id.isEmpty ? 'Tool' : id;
  }

  factory ChatToolTraceRecord.fromJson(Map<String, dynamic> json) {
    return ChatToolTraceRecord(
      content: json['content'] as String? ?? '',
      toolId: json['tool_id'] as String?,
      toolName: json['tool_name'] as String?,
    );
  }
}

class ChatMessagesResponse {
  ChatMessagesResponse({
    required this.session,
    required this.items,
    this.summary,
  });

  final ChatSessionRecord session;
  final List<ChatMessageRecord> items;
  final ChatSessionSummary? summary;

  factory ChatMessagesResponse.fromJson(Map<String, dynamic> json) {
    return ChatMessagesResponse(
      session: ChatSessionRecord.fromJson(
        json['session'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      items: ((json['items'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(ChatMessageRecord.fromJson)
          .toList()),
      summary: json['summary'] == null
          ? null
          : ChatSessionSummary.fromJson(
              json['summary'] as Map<String, dynamic>,
            ),
    );
  }
}
