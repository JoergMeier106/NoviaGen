import 'dart:async';

import 'package:noviagen/models/chat_attachments.dart';
import 'package:noviagen/models/chat_messages.dart';
import 'package:noviagen/models/chat_sessions.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/chat/state/chat_attachment_store.dart';
import 'package:noviagen/features/chat/state/chat_session_store.dart';

class ChatJobMessageController {
  ChatJobMessageController({
    required this.chat,
    required this.context,
    required this.gallery,
    required this.isActiveJob,
    required this.setDraft,
    required this.setMessage,
    required this.loadErrors,
    required this.selectedModelName,
    required this.requestScrollToMessage,
  });

  final ChatSessionStore chat;
  final ChatAttachmentStore context;
  final Iterable<ImageRecord> Function() gallery;
  final bool Function(String jobId) isActiveJob;
  final void Function(String value) setDraft;
  final void Function(String? value) setMessage;
  final Future<void> Function({bool silent}) loadErrors;
  final String Function() selectedModelName;
  final void Function(String messageId) requestScrollToMessage;

  final Map<String, String> _userTempMessageIdsByJobId = <String, String>{};
  final Map<String, String> _assistantTempMessageIdsByJobId =
      <String, String>{};
  final Map<String, List<ChatAttachmentRecord>> _attachmentsByJobId =
      <String, List<ChatAttachmentRecord>>{};
  final Map<String, String> _draftsByJobId = <String, String>{};

  String? userTempMessageId(String jobId) => _userTempMessageIdsByJobId[jobId];

  String? assistantTempMessageId(String jobId) {
    return _assistantTempMessageIdsByJobId[jobId];
  }

  List<ChatAttachmentRecord>? trackedAttachments(String jobId) {
    return _attachmentsByJobId[jobId];
  }

  String trackedDraft(JobStatus job) {
    return _draftsByJobId[job.jobId] ?? '${job.payload['content'] ?? ''}';
  }

  void trackSubmittedJob({
    required JobStatus job,
    required String userTempMessageId,
    required String assistantTempMessageId,
    required List<ChatAttachmentRecord> attachments,
    required String draft,
  }) {
    _userTempMessageIdsByJobId[job.jobId] = userTempMessageId;
    _assistantTempMessageIdsByJobId[job.jobId] = assistantTempMessageId;
    _attachmentsByJobId[job.jobId] = List<ChatAttachmentRecord>.from(
      attachments,
    );
    _draftsByJobId[job.jobId] = draft;
  }

  void ensureTempMessages(
    JobStatus job, {
    List<ChatAttachmentRecord>? attachments,
  }) {
    if (job.type != 'chat_message') {
      return;
    }
    final sessionId = '${job.payload['session_id'] ?? ''}'.trim();
    if (sessionId.isEmpty || chat.selectedSessionId != sessionId) {
      return;
    }

    final userTempId =
        _userTempMessageIdsByJobId[job.jobId] ??
        'chat-user-temp-job-${job.jobId}';
    final assistantTempId =
        _assistantTempMessageIdsByJobId[job.jobId] ??
        'chat-assistant-temp-job-${job.jobId}';
    _userTempMessageIdsByJobId[job.jobId] = userTempId;
    _assistantTempMessageIdsByJobId[job.jobId] = assistantTempId;

    final content = trackedDraft(job);
    final modelName = '${job.payload['model_name'] ?? selectedModelName()}';
    final effectiveAttachments =
        _attachmentsByJobId[job.jobId] ??
        _chatAttachmentsFromJob(job, fallback: attachments);
    _attachmentsByJobId[job.jobId] = List<ChatAttachmentRecord>.from(
      effectiveAttachments,
    );

    final createdAt = DateTime.now().toUtc().toIso8601String();
    if (!chat.activeMessages.any((item) => item.id == userTempId)) {
      chat.activeMessages = <ChatMessageRecord>[
        ...chat.activeMessages,
        ChatMessageRecord(
          id: userTempId,
          sessionId: sessionId,
          role: 'user',
          content: content,
          createdAt: createdAt,
          summarizedIntoMemory: false,
          attachments: effectiveAttachments,
          modelName: modelName,
        ),
      ];
    }
    if (!chat.activeMessages.any((item) => item.id == assistantTempId)) {
      chat.activeMessages = <ChatMessageRecord>[
        ...chat.activeMessages,
        ChatMessageRecord(
          id: assistantTempId,
          sessionId: sessionId,
          role: 'assistant',
          content: '',
          createdAt: createdAt,
          summarizedIntoMemory: false,
          modelName: modelName,
        ),
      ];
      requestScrollToMessage(assistantTempId);
    }
  }

  void syncStreamingJob(JobStatus job) {
    if (job.type != 'chat_message') {
      return;
    }
    ensureTempMessages(job);
    final assistantTempId = _assistantTempMessageIdsByJobId[job.jobId];
    if (assistantTempId == null) {
      return;
    }
    final resultData = job.resultData ?? const <String, dynamic>{};
    final content = '${resultData['content'] ?? ''}';
    final thinking = '${resultData['thinking'] ?? ''}';
    final toolTraces =
        ((resultData['tool_traces'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map(
              (item) =>
                  ChatToolTraceRecord.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList());
    chat.setMessageTemp(
      assistantTempId,
      content: content,
      thinking: thinking,
      toolTraces: toolTraces,
    );
  }

  Future<void> handleTerminalJob(JobStatus job) async {
    if (job.type != 'chat_message') {
      return;
    }

    final jobId = job.jobId;
    final sessionId = '${job.payload['session_id'] ?? ''}'.trim();
    final userTempId = userTempMessageId(jobId);
    final assistantTempId = assistantTempMessageId(jobId);
    final attachments = trackedAttachments(jobId);
    final draft = trackedDraft(job);

    if (job.status == 'completed') {
      await _completeJob(
        job,
        sessionId: sessionId,
        userTempId: userTempId,
        assistantTempId: assistantTempId,
      );
      clear(jobId);
      return;
    }

    _removeTemporaryMessages(userTempId, assistantTempId);
    _restoreActiveDraftIfNeeded(job, draft: draft, attachments: attachments);
    clear(jobId);
  }

  void clear(String jobId) {
    _userTempMessageIdsByJobId.remove(jobId);
    _assistantTempMessageIdsByJobId.remove(jobId);
    _attachmentsByJobId.remove(jobId);
    _draftsByJobId.remove(jobId);
  }

  Future<void> _completeJob(
    JobStatus job, {
    required String sessionId,
    required String? userTempId,
    required String? assistantTempId,
  }) async {
    final resultData = job.resultData ?? const <String, dynamic>{};
    _replaceTemporaryMessage(userTempId, resultData['user_message']);
    _replaceTemporaryMessage(assistantTempId, resultData['assistant_message']);
    await _syncCompletedSession(resultData['session']);
    if (_shouldReloadMessages(sessionId, userTempId, assistantTempId)) {
      await chat.loadMessages(sessionId);
    }
  }

  void _replaceTemporaryMessage(String? tempId, Object? messageJson) {
    if (tempId == null || messageJson is! Map) {
      return;
    }
    chat.replaceMessage(
      tempId,
      ChatMessageRecord.fromJson(Map<String, dynamic>.from(messageJson)),
    );
  }

  Future<void> _syncCompletedSession(Object? sessionJson) async {
    if (sessionJson is Map) {
      chat.upsertSession(
        ChatSessionRecord.fromJson(Map<String, dynamic>.from(sessionJson)),
      );
      return;
    }
    await chat.loadSessions(createIfMissing: false);
  }

  bool _shouldReloadMessages(
    String sessionId,
    String? userTempId,
    String? assistantTempId,
  ) {
    return chat.selectedSessionId == sessionId &&
        (userTempId == null || assistantTempId == null);
  }

  void _removeTemporaryMessages(String? userTempId, String? assistantTempId) {
    if (userTempId == null && assistantTempId == null) {
      return;
    }
    chat.activeMessages.removeWhere(
      (item) => item.id == userTempId || item.id == assistantTempId,
    );
  }

  void _restoreActiveDraftIfNeeded(
    JobStatus job, {
    required String draft,
    required List<ChatAttachmentRecord>? attachments,
  }) {
    if (!isActiveJob(job.jobId)) {
      return;
    }

    setDraft(draft.trim());
    if (attachments != null) {
      context.replaceAll(attachments, notify: false);
    }
    if (job.status == 'cancelled') {
      setMessage('Response stopped.');
    } else if (job.status == 'failed') {
      setMessage(_failureMessage(job));
      unawaited(loadErrors(silent: true));
    }
  }

  String _failureMessage(JobStatus job) {
    final jobError = job.error?.trim();
    if (jobError == null || jobError.isEmpty) {
      return 'The chat message could not be completed.';
    }
    return jobError;
  }

  List<ChatAttachmentRecord> _chatAttachmentsFromJob(
    JobStatus job, {
    List<ChatAttachmentRecord>? fallback,
  }) {
    if (fallback != null) {
      return List<ChatAttachmentRecord>.from(fallback);
    }
    final rawIds = job.payload['context_image_ids'];
    final imageIds = rawIds is List
        ? rawIds
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    final attachments = <ChatAttachmentRecord>[];
    for (final imageId in imageIds) {
      ImageRecord? image;
      for (final item in gallery()) {
        if (item.id == imageId) {
          image = item;
          break;
        }
      }
      attachments.add(
        ChatAttachmentRecord(contextImageId: imageId, contextImage: image),
      );
    }
    return attachments;
  }
}
