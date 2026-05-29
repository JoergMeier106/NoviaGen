import 'package:dio/dio.dart';


class AppChatRuntimeState {
  String draft = '';
  int? contextWindow;
  bool thinkingEnabled = true;
  bool sendingMessage = false;
  CancelToken? activeCancelToken;
  String? activeJobId;
}
