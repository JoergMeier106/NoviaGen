import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/models/chat_attachments.dart';
import 'package:flutter_app/models/chat_messages.dart';
import 'package:flutter_app/models/chat_models.dart';
import 'package:flutter_app/models/chat_sessions.dart';
import 'package:flutter_app/models/chat_tools.dart';
import 'package:flutter_app/models/gallery.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/features/chat/controllers/chat_message_controller.dart';
import 'package:flutter_app/app/runtime/app_chat_runtime_store.dart';
import 'package:flutter_app/features/chat/state/chat_attachment_store.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/chat/state/chat_session_store.dart';
import 'package:flutter_app/features/jobs/controllers/job_operations_controller.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/features/settings/system/system_operations_controller.dart';

abstract class ChatViewModel implements Listenable {
  String get draft;
  bool get sendingMessage;
  List<ChatToolInfo> get tools;
  bool get loadingTools;
  String? get toolsError;
  List<ChatAttachmentRecord> get attachments;
  List<ChatMessageRecord> get activeMessages;
  bool get loadingMessages;
  bool get loadingSessions;
  List<ChatSessionRecord> get sessions;
  ChatSessionRecord? get selectedSession;
  String? get selectedSessionId;
  List<OllamaModelInfo> get items;
  int get scrollToChatMessageRequestCount;
  String? get scrollToChatMessageId;
  List<ChatSystemPrompt> get chatSystemPrompts;

  Future<void> ensureReady();
  Future<void> loadJobs();
  Future<void> loadHealth({bool silent = false});
  Future<void> createSession();
  Future<void> selectSession(String sessionId);
  Future<void> updateSelectedModel(String modelName);
  Future<void> renameSession({
    required String sessionId,
    required String title,
  });
  Future<void> deleteSession(String sessionId);
  Future<void> updateSystemMessage({
    required String sessionId,
    required String systemMessage,
  });
  void setDraft(String value);
  Future<void> loadTools();
  bool isToolEnabled(String toolId);
  void setToolEnabled(String toolId, bool value);
  Future<void> sendMessage();
  Future<void> abortMessage();
  void addImages(List<ImageRecord> images);
  void remove(String stableKey);
  Future<void> pickImages(ImageSource source);
  Future<GalleryPageResponse> fetchAttachableGalleryImagesPage({
    required String search,
    required int page,
    required int pageSize,
  });
  Future<void> createChatSystemPromptAndPersist({
    required String name,
    required String prompt,
  });
  Future<void> updateChatSystemPromptAndPersist({
    required String id,
    required String name,
    required String prompt,
  });
  Future<void> deleteChatSystemPromptAndPersist(String id);
}

class AppChatViewModel implements ChatViewModel {
  AppChatViewModel({
    required this.changes,
    required this.navigation,
    required this.runtime,
    required this.contextState,
    required this.modelCatalog,
    required this.sessionsState,
    required this.jobOperations,
    required this.systemOperations,
    required this.messageController,
    required this.promptLibrary,
  });

  final Listenable changes;
  final AppNavigationController navigation;
  final AppChatRuntimeStore runtime;
  final ChatAttachmentStore contextState;
  final ChatModelCatalogStore modelCatalog;
  final ChatSessionStore sessionsState;
  final JobOperationsController jobOperations;
  final SystemOperationsController systemOperations;
  final ChatMessageController messageController;
  final PromptLibraryStore promptLibrary;

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      changes.removeListener(listener);

  @override
  String get draft => runtime.draft;

  @override
  bool get sendingMessage => runtime.sendingMessage;

  @override
  List<ChatToolInfo> get tools => runtime.tools;

  @override
  bool get loadingTools => runtime.loadingTools;

  @override
  String? get toolsError => runtime.toolsError;

  @override
  List<ChatAttachmentRecord> get attachments => contextState.attachments;

  @override
  List<ChatMessageRecord> get activeMessages => sessionsState.activeMessages;

  @override
  bool get loadingMessages => sessionsState.loadingMessages;

  @override
  bool get loadingSessions => sessionsState.loadingSessions;

  @override
  List<ChatSessionRecord> get sessions => sessionsState.sessions;

  @override
  ChatSessionRecord? get selectedSession => sessionsState.selectedSession;

  @override
  String? get selectedSessionId => sessionsState.selectedSessionId;

  @override
  List<OllamaModelInfo> get items => modelCatalog.items;

  @override
  int get scrollToChatMessageRequestCount =>
      navigation.scrollToChatMessageRequestCount;

  @override
  String? get scrollToChatMessageId => navigation.scrollToChatMessageId;

  @override
  List<ChatSystemPrompt> get chatSystemPrompts =>
      promptLibrary.chatSystemPrompts;

  @override
  Future<void> ensureReady() => sessionsState.ensureReady();

  @override
  Future<void> loadJobs() => jobOperations.loadJobs();

  @override
  Future<void> loadHealth({bool silent = false}) =>
      systemOperations.loadHealth(silent: silent);

  @override
  Future<void> createSession() => sessionsState.createSession();

  @override
  Future<void> selectSession(String sessionId) =>
      sessionsState.selectSession(sessionId);

  @override
  Future<void> updateSelectedModel(String modelName) =>
      sessionsState.updateSelectedModel(modelName);

  @override
  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) => sessionsState.renameSession(sessionId: sessionId, title: title);

  @override
  Future<void> deleteSession(String sessionId) =>
      sessionsState.deleteSession(sessionId);

  @override
  Future<void> updateSystemMessage({
    required String sessionId,
    required String systemMessage,
  }) => sessionsState.updateSystemMessage(
    sessionId: sessionId,
    systemMessage: systemMessage,
  );

  @override
  void setDraft(String value) => messageController.setDraft(value);

  @override
  Future<void> loadTools() => messageController.loadTools();

  @override
  bool isToolEnabled(String toolId) =>
      runtime.isToolEnabledFor(sessionsState.selectedSession?.id, toolId);

  @override
  void setToolEnabled(String toolId, bool value) =>
      messageController.setToolEnabled(toolId, value);

  @override
  Future<void> sendMessage() => messageController.sendMessage();

  @override
  Future<void> abortMessage() => messageController.abortMessage();

  @override
  void addImages(List<ImageRecord> images) => contextState.addImages(images);

  @override
  void remove(String stableKey) => contextState.remove(stableKey);

  @override
  Future<void> pickImages(ImageSource source) =>
      contextState.pickImages(source);

  @override
  Future<GalleryPageResponse> fetchAttachableGalleryImagesPage({
    required String search,
    required int page,
    required int pageSize,
  }) => contextState.fetchAttachableGalleryImagesPage(
    search: search,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<void> createChatSystemPromptAndPersist({
    required String name,
    required String prompt,
  }) => promptLibrary.createChatSystemPromptAndPersist(
    name: name,
    prompt: prompt,
  );

  @override
  Future<void> updateChatSystemPromptAndPersist({
    required String id,
    required String name,
    required String prompt,
  }) => promptLibrary.updateChatSystemPromptAndPersist(
    id: id,
    name: name,
    prompt: prompt,
  );

  @override
  Future<void> deleteChatSystemPromptAndPersist(String id) =>
      promptLibrary.deleteChatSystemPromptAndPersist(id);
}
