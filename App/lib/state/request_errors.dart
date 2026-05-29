import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';


typedef RequestErrorHandler =
    void Function(Object error, {required String generalMessage});

String requestErrorMessage(Object error, {required String generalMessage}) {
  if (isTimeoutError(error)) {
    return 'The server is taking longer than expected. If it is warming up a model, give it a moment and try again.';
  }
  if (isConnectionError(error)) {
    return 'The server is not responding right now. Please wait a moment and try again.';
  }
  final backendMessage = backendErrorMessage(error);
  if (backendMessage != null) {
    return backendMessage;
  }
  return generalMessage;
}

String? backendErrorMessage(Object error) {
  if (error is! DioException) {
    return null;
  }
  final data = error.response?.data;
  if (data is Map) {
    final backendError = data['error'];
    if (backendError is String && backendError.trim().isNotEmpty) {
      return backendError.trim();
    }
  }
  return null;
}

bool isTimeoutError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is DioException) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }
  return false;
}

bool isConnectionError(Object error) {
  if (error is DioException) {
    return error.type == DioExceptionType.connectionError ||
        error.error is SocketException;
  }
  return error is SocketException;
}
