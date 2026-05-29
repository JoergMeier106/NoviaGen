import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models/chat_messages.dart';
import '../models/chat_sessions.dart';
import 'chat_context_state.dart';
import 'chat_model_catalog_state.dart';
import 'request_errors.dart';

class ChatSessionState {
  ChatSessionState({
    required this.api,
    required this.modelCatalog,
    required this.context,
    required this.loadModels,
    required this.selectedModelName,
    required this.setMessage,
    required this.setRequestError,
    required this.onChanged,
  });

  static const selectedSessionKey = 'selected_chat_session_id';

  final ApiClient? Function() api;
  final ChatModelCatalogState modelCatalog;
  final ChatContextState context;
  final Future<void> Function() loadModels;
  final String Function() selectedModelName;
  final void Function(String? value) setMessage;
  final RequestErrorHandler setRequestError;
  final void Function() onChanged;

  bool loadingSessions = false;
  bool loadingMessages = false;
  List<ChatSessionRecord> sessions = <ChatSessionRecord>[];
  List<ChatMessageRecord> activeMessages = <ChatMessageRecord>[];
  ChatSessionSummary? activeSummary;
  String? selectedSessionId;

  bool get loading => loadingSessions || loadingMessages;

  ChatSessionRecord? get selectedSession {
    final sessionId = selectedSessionId;
    if (sessionId == null) {
      return null;
    }
    for (final session in sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  void loadPreferences(SharedPreferences prefs) {
    selectedSessionId = prefs.getString(selectedSessionKey);
  }

  void clearAll() {
    sessions = <ChatSessionRecord>[];
    activeMessages = <ChatMessageRecord>[];
    activeSummary = null;
    selectedSessionId = null;
    context.clear(notify: false);
  }

  Future<void> loadSessions({bool createIfMissing = true}) async {
    final client = api();
    if (client == null || loadingSessions) {
      return;
    }

    loadingSessions = true;
    onChanged();
    try {
      sessions = await client.fetchChatSessions();
      if (sessions.isEmpty && createIfMissing) {
        await _createInitialSessionIfPossible(client);
      }
      normalizeSelectedSession();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t load chat sessions right now. Please try again.',
      );
    } finally {
      loadingSessions = false;
      onChanged();
    }
  }

  Future<void> loadMessages(String sessionId) async {
    final client = api();
    if (client == null || loadingMessages) {
      return;
    }

    loadingMessages = true;
    onChanged();
    try {
      final response = await client.fetchChatMessages(sessionId);
      upsertSession(response.session);
      activeMessages = response.items;
      activeSummary = response.summary;
      selectedSessionId = response.session.id;
      await persistSelectedSessionId();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t load chat messages right now. Please try again.',
      );
    } finally {
      loadingMessages = false;
      onChanged();
    }
  }

  Future<void> ensureReady() async {
    final client = api();
    if (client == null) {
      setMessage('Set a backend URL first.');
      onChanged();
      return;
    }
    if (modelCatalog.items.isEmpty) {
      await loadModels();
    }
    await loadSessions();
    final session = selectedSession;
    if (session != null &&
        (activeMessages.isEmpty ||
            activeMessages.first.sessionId != session.id)) {
      await loadMessages(session.id);
    }
  }

  Future<void> selectSession(String sessionId) async {
    if (selectedSessionId == sessionId &&
        activeMessages.isNotEmpty &&
        activeMessages.first.sessionId == sessionId) {
      return;
    }
    selectedSessionId = sessionId;
    await persistSelectedSessionId();
    onChanged();
    await loadMessages(sessionId);
  }

  Future<void> createSession() async {
    final client = api();
    if (client == null) {
      setMessage('Set a backend URL first.');
      onChanged();
      return;
    }
    if (modelCatalog.items.isEmpty) {
      await loadModels();
    }
    final modelName = selectedModelName();
    if (modelName.isEmpty) {
      setMessage('No Ollama models are available yet.');
      onChanged();
      return;
    }
    try {
      final session = await client.createChatSession(modelName: modelName);
      await modelCatalog.setPreferredChatModelName(
        session.modelName,
        notify: false,
      );
      upsertSession(session);
      selectedSessionId = session.id;
      activeMessages = <ChatMessageRecord>[];
      activeSummary = null;
      context.clear(notify: false);
      await persistSelectedSessionId();
      onChanged();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t create a chat session right now. Please try again.',
      );
    }
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      final session = await client.updateChatSession(
        sessionId: sessionId,
        title: title,
      );
      upsertSession(session);
      onChanged();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t rename that chat right now. Please try again.',
      );
    }
  }

  Future<void> updateSystemMessage({
    required String sessionId,
    required String systemMessage,
  }) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      final session = await client.updateChatSession(
        sessionId: sessionId,
        systemMessage: systemMessage,
      );
      upsertSession(session);
      onChanged();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t update the system message right now. Please try again.',
      );
    }
  }

  Future<void> updateSelectedModel(String modelName) async {
    final client = api();
    final session = selectedSession;
    if (client == null || session == null) {
      return;
    }
    try {
      final updated = await client.updateChatSession(
        sessionId: session.id,
        modelName: modelName,
      );
      await modelCatalog.setPreferredChatModelName(
        updated.modelName,
        notify: false,
      );
      upsertSession(updated);
      onChanged();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t switch chat models right now. Please try again.',
      );
    }
  }

  Future<void> deleteSession(String sessionId) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      await client.deleteChatSession(sessionId);
      sessions.removeWhere((item) => item.id == sessionId);
      if (selectedSessionId == sessionId) {
        selectedSessionId = sessions.isEmpty ? null : sessions.first.id;
        activeMessages = <ChatMessageRecord>[];
        activeSummary = null;
        context.clear(notify: false);
        await persistSelectedSessionId();
        final nextSessionId = selectedSessionId;
        if (nextSessionId != null) {
          await loadMessages(nextSessionId);
          return;
        }
      }
      onChanged();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t delete that chat right now. Please try again.',
      );
    }
  }

  void normalizeSelectedSession() {
    if (sessions.isEmpty) {
      selectedSessionId = null;
      activeMessages = <ChatMessageRecord>[];
      activeSummary = null;
      return;
    }
    final currentId = selectedSessionId;
    if (currentId != null && sessions.any((item) => item.id == currentId)) {
      return;
    }
    selectedSessionId = sessions.first.id;
  }

  void upsertSession(ChatSessionRecord session) {
    final index = sessions.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.insert(0, session);
    }
    sessions.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    normalizeSelectedSession();
  }

  void replaceMessage(String targetId, ChatMessageRecord replacement) {
    final index = activeMessages.indexWhere((item) => item.id == targetId);
    if (index >= 0) {
      activeMessages[index] = replacement;
    } else {
      activeMessages.add(replacement);
    }
  }

  void setMessageTemp(
    String messageId, {
    required String content,
    required String thinking,
    List<ChatToolTraceRecord> toolTraces = const <ChatToolTraceRecord>[],
  }) {
    final index = activeMessages.indexWhere((item) => item.id == messageId);
    if (index < 0) {
      return;
    }
    final item = activeMessages[index];
    activeMessages[index] = item.copyWith(
      content: content,
      thinking: thinking,
      toolTraces: toolTraces,
    );
  }

  Future<void> persistSelectedSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = selectedSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      await prefs.remove(selectedSessionKey);
      return;
    }
    await prefs.setString(selectedSessionKey, sessionId);
  }

  Future<void> _createInitialSessionIfPossible(ApiClient client) async {
    if (modelCatalog.items.isEmpty) {
      await loadModels();
    }
    final modelName = selectedModelName();
    if (modelName.isEmpty) {
      return;
    }
    final session = await client.createChatSession(modelName: modelName);
    await modelCatalog.setPreferredChatModelName(
      session.modelName,
      notify: false,
    );
    sessions = <ChatSessionRecord>[session];
    selectedSessionId = session.id;
    await persistSelectedSessionId();
  }
}
