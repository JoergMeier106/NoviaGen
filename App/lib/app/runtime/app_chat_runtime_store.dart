import 'package:dio/dio.dart';

import 'package:noviagen/models/chat_tools.dart';

class AppChatRuntimeStore {
  String draft = '';
  int? contextWindow;
  bool thinkingEnabled = true;
  final Map<String, Set<String>> _enabledToolIdsBySessionId =
      <String, Set<String>>{};
  List<ChatToolInfo> tools = <ChatToolInfo>[];
  bool loadingTools = false;
  String? toolsError;
  bool sendingMessage = false;
  CancelToken? activeCancelToken;
  String? activeJobId;

  List<String> enabledToolIdsFor(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return const <String>[];
    }
    return (_enabledToolIdsBySessionId[normalizedSessionId] ?? <String>{})
        .toList(growable: false);
  }

  bool isToolEnabledFor(String? sessionId, String toolId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return false;
    }
    return _enabledToolIdsBySessionId[normalizedSessionId]?.contains(toolId) ??
        false;
  }

  void setToolEnabledFor(String? sessionId, String toolId, bool value) {
    final normalizedSessionId = sessionId?.trim();
    final normalizedToolId = toolId.trim();
    if (normalizedSessionId == null ||
        normalizedSessionId.isEmpty ||
        normalizedToolId.isEmpty) {
      return;
    }
    final next = <String>{...?_enabledToolIdsBySessionId[normalizedSessionId]};
    if (value) {
      next.add(normalizedToolId);
    } else {
      next.remove(normalizedToolId);
    }
    if (next.isEmpty) {
      _enabledToolIdsBySessionId.remove(normalizedSessionId);
    } else {
      _enabledToolIdsBySessionId[normalizedSessionId] = next;
    }
  }
}
