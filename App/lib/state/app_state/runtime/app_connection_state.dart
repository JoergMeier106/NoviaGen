import 'package:flutter/material.dart';

import '../../../api_client.dart';


class AppConnectionState {
  String baseUrl = '';
  ThemeMode themeMode = ThemeMode.system;
  String? message;
  ApiClient? overrideApiClient;

  ApiClient? get api {
    final injectedClient = overrideApiClient;
    if (injectedClient != null) {
      return injectedClient;
    }
    final trimmedBaseUrl = baseUrl.trim();
    return trimmedBaseUrl.isEmpty ? null : ApiClient(trimmedBaseUrl);
  }
}
