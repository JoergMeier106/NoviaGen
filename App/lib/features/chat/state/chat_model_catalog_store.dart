import 'package:shared_preferences/shared_preferences.dart';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/models/chat_models.dart';
import 'package:noviagen/models/chat_sessions.dart';
class ChatModelCatalogStore {
  ChatModelCatalogStore({
    required this.api,
    required this.setRequestError,
    required this.onChanged,
  });

  static const selectedChatModelKey = 'selected_chat_model_name';
  static const selectedAutoPromptModelKey = 'selected_auto_prompt_model_name';
  static const selectedImageToImageAutoPromptModelKey =
      'selected_i2i_auto_prompt_model_name';
  static const selectedTextToVideoAutoPromptModelKey =
      'selected_t2v_auto_prompt_model_name';
  static const selectedImageToVideoAutoPromptModelKey =
      'selected_i2v_auto_prompt_model_name';

  final ApiClient? Function() api;
  final void Function(Object error, {required String generalMessage})
  setRequestError;
  final void Function() onChanged;

  bool loading = false;
  List<OllamaModelInfo> items = <OllamaModelInfo>[];
  String? preferredChatModelName;
  String? preferredAutoPromptModelName;
  String? preferredImageToImageAutoPromptModelName;
  String? preferredTextToVideoAutoPromptModelName;
  String? preferredImageToVideoAutoPromptModelName;

  List<OllamaModelInfo> get autoPromptModels {
    return items.where((item) => item.supportsVision).toList();
  }

  String selectedChatModelName(ChatSessionRecord? selectedSession) {
    final sessionModel = selectedSession?.modelName.trim();
    if (sessionModel != null && sessionModel.isNotEmpty) {
      return sessionModel;
    }
    final preferredModel = preferredChatModelName?.trim();
    if (preferredModel != null &&
        preferredModel.isNotEmpty &&
        items.any((item) => item.name == preferredModel)) {
      return preferredModel;
    }
    if (items.isNotEmpty) {
      return items.first.name;
    }
    return '';
  }

  OllamaModelInfo? selectedChatModelInfo(ChatSessionRecord? selectedSession) {
    final modelName = selectedChatModelName(selectedSession).trim();
    if (modelName.isEmpty) {
      return null;
    }
    for (final model in items) {
      if (model.name == modelName) {
        return model;
      }
    }
    return null;
  }

  bool effectiveThinkingEnabled({
    required bool chatThinkingEnabled,
    required ChatSessionRecord? selectedSession,
  }) {
    return chatThinkingEnabled &&
        (selectedChatModelInfo(selectedSession)?.supportsThinkingToggle ??
            false);
  }

  String get selectedAutoPromptModelName {
    return _selectedAutoPromptModelNameFor(preferredAutoPromptModelName);
  }

  OllamaModelInfo? get selectedAutoPromptModelInfo {
    final modelName = selectedAutoPromptModelName.trim();
    if (modelName.isEmpty) {
      return null;
    }
    for (final model in autoPromptModels) {
      if (model.name == modelName) {
        return model;
      }
    }
    return null;
  }

  String get selectedImageToImageAutoPromptModelName {
    return _selectedAutoPromptModelNameFor(
      preferredImageToImageAutoPromptModelName,
    );
  }

  String get selectedTextToVideoAutoPromptModelName {
    return _selectedAutoPromptModelNameFor(
      preferredTextToVideoAutoPromptModelName,
    );
  }

  String get selectedImageToVideoAutoPromptModelName {
    return _selectedAutoPromptModelNameFor(
      preferredImageToVideoAutoPromptModelName,
    );
  }

  void loadPreferences(SharedPreferences prefs) {
    preferredChatModelName = prefs.getString(selectedChatModelKey);
    preferredAutoPromptModelName = prefs.getString(selectedAutoPromptModelKey);
    preferredImageToImageAutoPromptModelName = prefs.getString(
      selectedImageToImageAutoPromptModelKey,
    );
    preferredTextToVideoAutoPromptModelName = prefs.getString(
      selectedTextToVideoAutoPromptModelKey,
    );
    preferredImageToVideoAutoPromptModelName = prefs.getString(
      selectedImageToVideoAutoPromptModelKey,
    );
  }

  void clear() {
    items = <OllamaModelInfo>[];
  }

  Future<void> loadChatModels() async {
    final client = api();
    if (client == null || loading) {
      return;
    }

    loading = true;
    onChanged();
    try {
      items = await client.fetchChatModels();
      await syncAutoPromptPreferences();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t load chat models right now. Please try again.',
      );
    } finally {
      loading = false;
      onChanged();
    }
  }

  Future<void> loadAutoPromptModels({bool silent = false}) async {
    final client = api();
    if (client == null) {
      return;
    }

    try {
      if (items.isEmpty) {
        items = await client.fetchChatModels();
      }
      await syncAutoPromptPreferences();
      onChanged();
    } catch (error) {
      if (!silent) {
        setRequestError(
          error,
          generalMessage:
              'Couldn\'t load auto-prompt models right now. Please try again.',
        );
      }
    }
  }

  Future<void> savePreferences() async {
    await _persistOptionalString(selectedChatModelKey, preferredChatModelName);
    await _persistOptionalString(
      selectedAutoPromptModelKey,
      preferredAutoPromptModelName,
    );
    await _persistOptionalString(
      selectedImageToImageAutoPromptModelKey,
      preferredImageToImageAutoPromptModelName,
    );
    await _persistOptionalString(
      selectedTextToVideoAutoPromptModelKey,
      preferredTextToVideoAutoPromptModelName,
    );
    await _persistOptionalString(
      selectedImageToVideoAutoPromptModelKey,
      preferredImageToVideoAutoPromptModelName,
    );
  }

  Future<void> setPreferredChatModelName(
    String modelName, {
    bool notify = true,
  }) async {
    final normalized = modelName.trim();
    if (normalized.isEmpty) {
      return;
    }
    preferredChatModelName = normalized;
    await _persistOptionalString(selectedChatModelKey, preferredChatModelName);
    if (notify) {
      onChanged();
    }
  }

  Future<void> setPreferredAutoPromptModelName(String modelName) async {
    final normalized = modelName.trim();
    if (normalized.isEmpty) {
      return;
    }
    preferredAutoPromptModelName = normalized;
    await _persistOptionalString(
      selectedAutoPromptModelKey,
      preferredAutoPromptModelName,
    );
    onChanged();
  }

  Future<void> setPreferredImageToImageAutoPromptModelName(
    String modelName,
  ) async {
    final normalized = modelName.trim();
    if (normalized.isEmpty) {
      return;
    }
    preferredImageToImageAutoPromptModelName = normalized;
    await _persistOptionalString(
      selectedImageToImageAutoPromptModelKey,
      preferredImageToImageAutoPromptModelName,
    );
    onChanged();
  }

  Future<void> setPreferredTextToVideoAutoPromptModelName(
    String modelName,
  ) async {
    final normalized = modelName.trim();
    if (normalized.isEmpty) {
      return;
    }
    preferredTextToVideoAutoPromptModelName = normalized;
    await _persistOptionalString(
      selectedTextToVideoAutoPromptModelKey,
      preferredTextToVideoAutoPromptModelName,
    );
    onChanged();
  }

  Future<void> setPreferredImageToVideoAutoPromptModelName(
    String modelName,
  ) async {
    final normalized = modelName.trim();
    if (normalized.isEmpty) {
      return;
    }
    preferredImageToVideoAutoPromptModelName = normalized;
    await _persistOptionalString(
      selectedImageToVideoAutoPromptModelKey,
      preferredImageToVideoAutoPromptModelName,
    );
    onChanged();
  }

  Future<void> syncAutoPromptPreferences() async {
    final selectedAutoPrompt = preferredAutoPromptModelName?.trim() ?? '';
    if (selectedAutoPrompt.isEmpty ||
        !_hasAutoPromptModel(selectedAutoPrompt)) {
      preferredAutoPromptModelName = autoPromptModels.isEmpty
          ? null
          : autoPromptModels.first.name;
      await _persistOptionalString(
        selectedAutoPromptModelKey,
        preferredAutoPromptModelName,
      );
    }
    await _clearUnavailableAutoPromptModel(
      selectedImageToVideoAutoPromptModelKey,
      () => preferredImageToVideoAutoPromptModelName,
      (value) => preferredImageToVideoAutoPromptModelName = value,
    );
    await _clearUnavailableAutoPromptModel(
      selectedImageToImageAutoPromptModelKey,
      () => preferredImageToImageAutoPromptModelName,
      (value) => preferredImageToImageAutoPromptModelName = value,
    );
    await _clearUnavailableAutoPromptModel(
      selectedTextToVideoAutoPromptModelKey,
      () => preferredTextToVideoAutoPromptModelName,
      (value) => preferredTextToVideoAutoPromptModelName = value,
    );
  }

  String _selectedAutoPromptModelNameFor(String? preferredModelName) {
    final preferredModel = preferredModelName?.trim();
    if (preferredModel != null &&
        preferredModel.isNotEmpty &&
        _hasAutoPromptModel(preferredModel)) {
      return preferredModel;
    }
    if (autoPromptModels.isNotEmpty) {
      return autoPromptModels.first.name;
    }
    return '';
  }

  bool _hasAutoPromptModel(String modelName) {
    return autoPromptModels.any((item) => item.name == modelName);
  }

  Future<void> _clearUnavailableAutoPromptModel(
    String key,
    String? Function() getValue,
    void Function(String? value) setValue,
  ) async {
    final selected = getValue()?.trim() ?? '';
    if (selected.isEmpty || _hasAutoPromptModel(selected)) {
      return;
    }
    setValue(null);
    await _persistOptionalString(key, null);
  }

  Future<void> _persistOptionalString(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, normalized);
  }
}
