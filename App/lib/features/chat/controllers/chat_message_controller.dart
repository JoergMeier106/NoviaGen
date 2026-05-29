import 'package:noviagen/models/chat_attachments.dart';
import 'package:noviagen/models/chat_sessions.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/chat/state/chat_attachment_store.dart';
import 'package:noviagen/features/chat/controllers/chat_job_message_controller.dart';
import 'package:noviagen/features/chat/state/chat_model_catalog_store.dart';
import 'package:noviagen/features/chat/state/chat_session_store.dart';
import 'package:noviagen/shared/request_errors.dart';
import 'package:noviagen/features/chat/services/chat_message_attachments.dart';
import 'package:noviagen/app/runtime/app_activity_store.dart';
import 'package:noviagen/app/runtime/app_chat_runtime_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';

class ChatMessageDependencies {
  const ChatMessageDependencies({
    required this.connection,
    required this.activity,
    required this.chatRuntime,
    required this.jobRuntime,
    required this.context,
    required this.modelCatalog,
    required this.session,
    required this.jobMessages,
    required this.replaceJob,
    required this.pollJob,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final AppChatRuntimeStore chatRuntime;
  final JobRuntimeStore jobRuntime;
  final ChatAttachmentStore context;
  final ChatModelCatalogStore modelCatalog;
  final ChatSessionStore session;
  final ChatJobMessageController jobMessages;
  final void Function(JobStatus job) replaceJob;
  final Future<ImageRecord?> Function(String jobId) pollJob;
  final void Function() notifyChanged;
}

class ChatMessageController {
  ChatMessageController(this.dependencies);

  final ChatMessageDependencies dependencies;

  void setDraft(String value) {
    dependencies.chatRuntime.draft = value;
    dependencies.notifyChanged();
  }

  Future<void> loadTools() async {
    final client = dependencies.connection.api;
    if (client == null || dependencies.chatRuntime.loadingTools) {
      return;
    }
    dependencies.chatRuntime.loadingTools = true;
    dependencies.chatRuntime.toolsError = null;
    dependencies.notifyChanged();
    try {
      dependencies.chatRuntime.tools = await client.fetchChatTools();
    } catch (error) {
      dependencies.chatRuntime.toolsError = requestErrorMessage(
        error,
        generalMessage: "Couldn't load chat tools right now. Please try again.",
      );
    } finally {
      dependencies.chatRuntime.loadingTools = false;
      dependencies.notifyChanged();
    }
  }

  void setToolEnabled(String toolId, bool value) {
    dependencies.chatRuntime.setToolEnabledFor(
      dependencies.session.selectedSession?.id,
      toolId,
      value,
    );
    dependencies.notifyChanged();
  }

  Future<void> abortMessage() async {
    final activeJobId = dependencies.chatRuntime.activeJobId?.trim();
    if (activeJobId != null && activeJobId.isNotEmpty) {
      await _cancelActiveJob(activeJobId);
      return;
    }

    final cancelToken = dependencies.chatRuntime.activeCancelToken;
    if (cancelToken == null || cancelToken.isCancelled) {
      return;
    }
    cancelToken.cancel('Chat request cancelled by user.');
  }

  Future<void> sendMessage() async {
    final client = dependencies.connection.api;
    if (client == null) {
      dependencies.connection.message = 'Set a backend URL first.';
      dependencies.notifyChanged();
      return;
    }
    if (dependencies.chatRuntime.sendingMessage) {
      return;
    }

    final session = await _ensureSession();
    if (session == null) {
      return;
    }

    final content = dependencies.chatRuntime.draft.trim();
    if (content.isEmpty) {
      return;
    }

    final attachments = _capturedAttachments();
    final enabledToolIds = dependencies.chatRuntime.enabledToolIdsFor(
      session.id,
    );
    _beginSend();

    try {
      final job = await client.createChatMessageJob(
        sessionId: session.id,
        content: content,
        modelName: session.modelName,
        contextImageIds: attachments.contextImageIds,
        localContextImages: attachments.localImages,
        contextWindow: dependencies.chatRuntime.contextWindow,
        think: _effectiveThinkingEnabled() ? true : null,
        enabledToolIds: enabledToolIds,
      );
      _trackQueuedJob(job, content, attachments);
      await dependencies.pollJob(job.jobId);
    } catch (error) {
      await _restoreDraftAfterFailure(
        error: error,
        activeJobId: dependencies.chatRuntime.activeJobId,
        session: session,
        content: content,
        attachments: attachments.records,
      );
    } finally {
      _completeSend();
    }
  }

  Future<void> _cancelActiveJob(String jobId) async {
    final client = dependencies.connection.api;
    if (client == null) {
      return;
    }
    try {
      final cancelledJob = await client.cancelJob(jobId);
      dependencies.jobRuntime.latestJob = cancelledJob;
      dependencies.replaceJob(cancelledJob);
      dependencies.notifyChanged();
    } catch (_) {}
  }

  Future<ChatSessionRecord?> _ensureSession() async {
    if (dependencies.modelCatalog.items.isEmpty) {
      await dependencies.modelCatalog.loadChatModels();
    }

    var session = dependencies.session.selectedSession;
    if (session == null) {
      await dependencies.session.createSession();
      session = dependencies.session.selectedSession;
    }
    if (session == null) {
      dependencies.connection.message = 'Create a chat session first.';
      dependencies.notifyChanged();
    }
    return session;
  }

  ChatMessageAttachments _capturedAttachments() {
    return ChatMessageAttachments.fromContext(dependencies.context.attachments);
  }

  void _beginSend() {
    dependencies.chatRuntime.activeCancelToken = null;
    dependencies.chatRuntime.activeJobId = null;
    dependencies.chatRuntime.sendingMessage = true;
    dependencies.connection.message = null;
    dependencies.chatRuntime.draft = '';
    dependencies.context.clear(notify: false);
    dependencies.notifyChanged();
  }

  void _trackQueuedJob(
    JobStatus job,
    String content,
    ChatMessageAttachments attachments,
  ) {
    dependencies.chatRuntime.activeJobId = job.jobId;
    dependencies.jobMessages.trackSubmittedJob(
      job: job,
      userTempMessageId: _temporaryMessageId('user'),
      assistantTempMessageId: _temporaryMessageId('assistant'),
      attachments: attachments.records,
      draft: content,
    );
    dependencies.replaceJob(job);
    dependencies.jobRuntime.latestJob = job;
    dependencies.activity.runningJob = job.canCancel;
    dependencies.jobMessages.ensureTempMessages(
      job,
      attachments: attachments.records,
    );
    dependencies.jobMessages.syncStreamingJob(job);
    dependencies.notifyChanged();
  }

  String _temporaryMessageId(String role) {
    return 'chat-$role-temp-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _restoreDraftAfterFailure({
    required Object error,
    required String? activeJobId,
    required ChatSessionRecord session,
    required String content,
    required List<ChatAttachmentRecord> attachments,
  }) async {
    if (activeJobId != null && activeJobId.isNotEmpty) {
      await dependencies.jobMessages.handleTerminalJob(
        JobStatus(
          jobId: activeJobId,
          type: 'chat_message',
          parentJobId: null,
          chainStepId: null,
          status: 'failed',
          progress: 1,
          statusText: 'Failed',
          cancelRequested: false,
          payload: <String, dynamic>{
            'session_id': session.id,
            'content': content,
            'model_name': session.modelName,
          },
          error: '$error',
        ),
      );
    } else {
      dependencies.chatRuntime.draft = content;
      dependencies.context.replaceAll(attachments, notify: false);
    }
    dependencies.connection.message = requestErrorMessage(
      error,
      generalMessage:
          "Couldn't send the chat connection.message right now. Please try again.",
    );
  }

  void _completeSend() {
    dependencies.chatRuntime.activeJobId = null;
    dependencies.chatRuntime.activeCancelToken = null;
    dependencies.chatRuntime.sendingMessage = false;
    dependencies.notifyChanged();
  }

  bool _effectiveThinkingEnabled() {
    return dependencies.modelCatalog.effectiveThinkingEnabled(
      chatThinkingEnabled: dependencies.chatRuntime.thinkingEnabled,
      selectedSession: dependencies.session.selectedSession,
    );
  }
}
