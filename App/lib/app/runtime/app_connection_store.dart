import 'package:flutter/material.dart';

import 'package:flutter_app/api_client.dart';


class AppConnectionStore {
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
