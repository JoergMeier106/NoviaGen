import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:noviagen/models/prompts.dart';
import 'package:noviagen/features/generate/domain/generation_settings.dart';


List<PromptPreset> decodePromptPresets(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return <PromptPreset>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <PromptPreset>[];
    }
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => PromptPreset.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  } catch (_) {
    return <PromptPreset>[];
  }
}

List<ChatSystemPrompt> decodeChatSystemPrompts(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return <ChatSystemPrompt>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <ChatSystemPrompt>[];
    }
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => ChatSystemPrompt.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  } catch (_) {
    return <ChatSystemPrompt>[];
  }
}

List<SavedPrompt> decodeSavedPrompts(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return <SavedPrompt>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <SavedPrompt>[];
    }
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => SavedPrompt.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  } catch (_) {
    return <SavedPrompt>[];
  }
}

String newPromptPresetId() {
  return 'prompt_preset_${DateTime.now().microsecondsSinceEpoch}';
}

String newChatSystemPromptId() {
  return 'chat_system_prompt_${DateTime.now().microsecondsSinceEpoch}';
}

String newSavedPromptId(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}

ThemeMode themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

ImageOrientationSetting imageOrientationFromString(String? value) {
  switch (value) {
    case 'portrait':
      return ImageOrientationSetting.portrait;
    default:
      return ImageOrientationSetting.landscape;
  }
}

String logSourceFromString(String? value) {
  return value == 'comfy' ? 'comfy' : 'server';
}

String logSeverityFilterFromString(String? value) {
  switch (value) {
    case 'info':
    case 'warn':
    case 'error':
      return value!;
    default:
      return 'all';
  }
}

int logRowLimitFromInt(int? value) {
  switch (value) {
    case 200:
    case 500:
    case 1000:
    case 2000:
      return value!;
    default:
      return 500;
  }
}

Map<String, double> decodeSelectedLoras(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return <String, double>{};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <String, double>{};
    }
    return decoded.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );
  } catch (_) {
    return <String, double>{};
  }
}
