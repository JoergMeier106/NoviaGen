import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/chat_messages.dart';
import '../models/chat_models.dart';
import '../models/chat_sessions.dart';
import '../models/chat_stream.dart';
import '../models/chat_tools.dart';
import '../models/jobs.dart';
import '../models/media.dart';
import 'transport.dart';

mixin ChatApi on ApiClientTransport {
  Future<JobStatus> createChatMessageJob({
    required String sessionId,
    required String content,
    required String modelName,
    List<String> contextImageIds = const <String>[],
    List<LocalImageSource> localContextImages = const <LocalImageSource>[],
    int? contextWindow,
    bool? think,
    List<String> enabledToolIds = const <String>[],
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/jobs/chat-message',
      data: localContextImages.isNotEmpty
          ? FormData.fromMap({
              'session_id': sessionId,
              'content': content,
              'model_name': modelName,
              if (contextImageIds.isNotEmpty)
                'context_image_ids': contextImageIds,
              if (contextWindow != null)
                'context_window': contextWindow.toString(),
              if (think != null) 'think': think.toString(),
              if (enabledToolIds.isNotEmpty)
                'enabled_tool_ids': jsonEncode(enabledToolIds),
              'images': [
                for (final image in localContextImages)
                  await MultipartFile.fromFile(
                    image.path,
                    filename: image.name,
                  ),
              ],
            })
          : {
              'session_id': sessionId,
              'content': content,
              'model_name': modelName,
              if (contextImageIds.isNotEmpty)
                'context_image_ids': contextImageIds,
              ...?contextWindow == null
                  ? null
                  : {'context_window': contextWindow},
              ...?think == null ? null : {'think': think},
              if (enabledToolIds.isNotEmpty) 'enabled_tool_ids': enabledToolIds,
            },
    );
    return JobStatus.fromJson(response.data!);
  }

  Future<List<OllamaModelInfo>> fetchChatModels() async {
    final response = await dio.get<Map<String, dynamic>>('/api/chat/models');
    final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .cast<Map<String, dynamic>>()
        .map(OllamaModelInfo.fromJson)
        .toList();
  }

  Future<List<ChatToolInfo>> fetchChatTools() async {
    final response = await dio.get<Map<String, dynamic>>('/api/chat/tools');
    final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .cast<Map<String, dynamic>>()
        .map(ChatToolInfo.fromJson)
        .where((item) => item.id.trim().isNotEmpty)
        .toList();
  }

  Future<List<ChatSessionRecord>> fetchChatSessions() async {
    final response = await dio.get<Map<String, dynamic>>('/api/chat/sessions');
    final items = response.data!['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .cast<Map<String, dynamic>>()
        .map(ChatSessionRecord.fromJson)
        .toList();
  }

  Future<ChatSessionRecord> createChatSession({
    required String modelName,
    String? title,
    String? systemMessage,
  }) async {
    final data = {
      'model_name': modelName,
      ...?title == null || title.trim().isEmpty
          ? null
          : {'title': title.trim()},
      ...?systemMessage == null ? null : {'system_message': systemMessage},
    };
    final response = await dio.post<Map<String, dynamic>>(
      '/api/chat/sessions',
      data: data,
    );
    return ChatSessionRecord.fromJson(response.data!);
  }

  Future<ChatSessionRecord> updateChatSession({
    required String sessionId,
    String? title,
    String? modelName,
    String? systemMessage,
  }) async {
    final data = {
      ...?title == null ? null : {'title': title},
      ...?modelName == null ? null : {'model_name': modelName},
      ...?systemMessage == null ? null : {'system_message': systemMessage},
    };
    final response = await dio.patch<Map<String, dynamic>>(
      '/api/chat/sessions/$sessionId',
      data: data,
    );
    return ChatSessionRecord.fromJson(response.data!);
  }

  Future<void> deleteChatSession(String sessionId) async {
    await dio.delete<void>('/api/chat/sessions/$sessionId');
  }

  Future<ChatMessagesResponse> fetchChatMessages(String sessionId) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/chat/sessions/$sessionId/messages',
    );
    return ChatMessagesResponse.fromJson(response.data!);
  }

  Stream<ChatStreamEvent> streamChatMessage({
    required String sessionId,
    required String content,
    required String modelName,
    List<String> contextImageIds = const <String>[],
    List<LocalImageSource> localContextImages = const <LocalImageSource>[],
    int? contextWindow,
    bool? think,
    List<String> enabledToolIds = const <String>[],
    CancelToken? cancelToken,
  }) async* {
    final data = localContextImages.isNotEmpty
        ? FormData.fromMap({
            'content': content,
            'model_name': modelName,
            if (contextImageIds.isNotEmpty)
              'context_image_ids': contextImageIds,
            if (contextWindow != null)
              'context_window': contextWindow.toString(),
            if (think != null) 'think': think.toString(),
            if (enabledToolIds.isNotEmpty)
              'enabled_tool_ids': jsonEncode(enabledToolIds),
            'images': [
              for (final image in localContextImages)
                await MultipartFile.fromFile(image.path, filename: image.name),
            ],
          })
        : {
            'content': content,
            'model_name': modelName,
            if (contextImageIds.isNotEmpty)
              'context_image_ids': contextImageIds,
            ...?contextWindow == null
                ? null
                : {'context_window': contextWindow},
            ...?think == null ? null : {'think': think},
            if (enabledToolIds.isNotEmpty) 'enabled_tool_ids': enabledToolIds,
          };
    final response = await dio.post<ResponseBody>(
      '/api/chat/sessions/$sessionId/stream',
      data: data,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.stream),
    );
    final body = response.data;
    if (body == null) {
      throw StateError('Chat stream did not return a response body.');
    }
    final lines = utf8.decoder
        .bind(body.stream)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      yield ChatStreamEvent.fromJson(decoded);
    }
  }
}
