import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/app/persistence/settings_codecs.dart';
import 'package:flutter_app/features/prompts/domain/saved_prompt_collection.dart';
import 'package:flutter_app/models/prompts.dart';
export 'package:flutter_app/features/prompts/domain/saved_prompt_collection.dart';

class PromptLibraryStore {
  PromptLibraryStore({this.onChanged});

  static const promptPresetsKey = 'prompt_presets';
  static const chatSystemPromptsKey = 'chat_system_prompts';
  static const savedTextToImageAutoPromptBasePromptsKey =
      'saved_auto_prompt_base_prompts';
  static const savedImageToImageAutoPromptBasePromptsKey =
      'saved_i2i_auto_prompt_base_prompts';
  static const savedTextToVideoAutoPromptBasePromptsKey =
      'saved_t2v_auto_prompt_base_prompts';
  static const savedImageToVideoAutoPromptBasePromptsKey =
      'saved_i2v_auto_prompt_base_prompts';
  static const selectedImagePromptPresetKey = 'selected_image_prompt_preset_id';
  static const selectedVideoPromptPresetKey = 'selected_video_prompt_preset_id';

  final void Function()? onChanged;

  List<PromptPreset> presets = <PromptPreset>[];
  List<ChatSystemPrompt> chatSystemPrompts = <ChatSystemPrompt>[];
  List<SavedPrompt> textToImageAutoPromptBasePrompts = <SavedPrompt>[];
  List<SavedPrompt> imageToImageAutoPromptBasePrompts = <SavedPrompt>[];
  List<SavedPrompt> textToVideoAutoPromptBasePrompts = <SavedPrompt>[];
  List<SavedPrompt> imageToVideoAutoPromptBasePrompts = <SavedPrompt>[];

  String? selectedImagePresetId;
  String? selectedVideoPresetId;

  PromptPreset? get selectedImagePreset => presetById(selectedImagePresetId);

  PromptPreset? get selectedVideoPreset => presetById(selectedVideoPresetId);

  Future<void> loadFromPreferences(
    SharedPreferences prefs, {
    required String? legacyPositivePrompt,
    required String? legacyNegativePrompt,
  }) async {
    presets = decodePromptPresets(prefs.getString(promptPresetsKey));
    chatSystemPrompts = decodeChatSystemPrompts(
      prefs.getString(chatSystemPromptsKey),
    );
    textToImageAutoPromptBasePrompts = decodeSavedPrompts(
      prefs.getString(savedTextToImageAutoPromptBasePromptsKey),
    );
    imageToImageAutoPromptBasePrompts =
        prefs.containsKey(savedImageToImageAutoPromptBasePromptsKey)
        ? decodeSavedPrompts(
            prefs.getString(savedImageToImageAutoPromptBasePromptsKey),
          )
        : List<SavedPrompt>.of(textToImageAutoPromptBasePrompts);
    textToVideoAutoPromptBasePrompts =
        prefs.containsKey(savedTextToVideoAutoPromptBasePromptsKey)
        ? decodeSavedPrompts(
            prefs.getString(savedTextToVideoAutoPromptBasePromptsKey),
          )
        : List<SavedPrompt>.of(textToImageAutoPromptBasePrompts);
    imageToVideoAutoPromptBasePrompts = decodeSavedPrompts(
      prefs.getString(savedImageToVideoAutoPromptBasePromptsKey),
    );

    if (presets.isEmpty && (legacyPositivePrompt?.trim().isNotEmpty ?? false)) {
      final importedPreset = PromptPreset(
        id: newPromptPresetId(),
        name: 'Imported defaults',
        positivePrompt: legacyPositivePrompt!.trim(),
        negativePrompt: legacyNegativePrompt?.trim() ?? '',
      );
      presets = <PromptPreset>[importedPreset];
      selectedImagePresetId = importedPreset.id;
      selectedVideoPresetId = importedPreset.id;
      await persistPresetSettings(prefs: prefs);
      return;
    }

    setSelectedImagePresetId(prefs.getString(selectedImagePromptPresetKey));
    setSelectedVideoPresetId(prefs.getString(selectedVideoPromptPresetKey));
    ensureValidPresetSelections();
  }

  Future<void> createPresetAndPersist({
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  }) async {
    createPreset(
      id: newPromptPresetId(),
      name: name,
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
    );
    await persistPresetSettings();
    onChanged?.call();
  }

  Future<void> updatePresetAndPersist({
    required String id,
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  }) async {
    updatePreset(
      id: id,
      name: name,
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
    );
    await persistPresetSettings();
    onChanged?.call();
  }

  Future<void> deletePresetAndPersist(String id) async {
    deletePreset(id);
    await persistPresetSettings();
    onChanged?.call();
  }

  Future<void> setSelectedImagePresetIdAndPersist(String? presetId) async {
    setSelectedImagePresetId(presetId);
    await persistPresetSettings();
    onChanged?.call();
  }

  Future<void> setSelectedVideoPresetIdAndPersist(String? presetId) async {
    setSelectedVideoPresetId(presetId);
    await persistPresetSettings();
    onChanged?.call();
  }

  Future<void> createChatSystemPromptAndPersist({
    required String name,
    required String prompt,
  }) async {
    addChatSystemPrompt(
      ChatSystemPrompt(
        id: newChatSystemPromptId(),
        name: name.trim(),
        prompt: prompt.trim(),
      ),
    );
    await persistChatSystemPrompts();
    onChanged?.call();
  }

  Future<void> updateChatSystemPromptAndPersist({
    required String id,
    required String name,
    required String prompt,
  }) async {
    updateChatSystemPrompt(id: id, name: name, prompt: prompt);
    await persistChatSystemPrompts();
    onChanged?.call();
  }

  Future<void> deleteChatSystemPromptAndPersist(String id) async {
    deleteChatSystemPrompt(id);
    await persistChatSystemPrompts();
    onChanged?.call();
  }

  Future<void> createSavedPromptAndPersist(
    SavedPromptCollection collection, {
    required String idPrefix,
    required String name,
    required String prompt,
  }) async {
    addSavedPrompt(
      collection,
      SavedPrompt(
        id: newSavedPromptId(idPrefix),
        name: name.trim(),
        prompt: prompt.trim(),
      ),
    );
    await persistSavedPromptCollection(collection);
    onChanged?.call();
  }

  Future<void> updateSavedPromptAndPersist({
    required SavedPromptCollection collection,
    required String id,
    required String name,
    required String prompt,
  }) async {
    updateSavedPrompt(
      collection: collection,
      id: id,
      name: name,
      prompt: prompt,
    );
    await persistSavedPromptCollection(collection);
    onChanged?.call();
  }

  Future<void> deleteSavedPromptAndPersist(
    SavedPromptCollection collection,
    String id,
  ) async {
    deleteSavedPrompt(collection, id);
    await persistSavedPromptCollection(collection);
    onChanged?.call();
  }

  void setSelectedImagePresetId(String? presetId) {
    selectedImagePresetId = normalizePresetId(presetId);
  }

  void setSelectedVideoPresetId(String? presetId) {
    selectedVideoPresetId = normalizePresetId(presetId);
  }

  PromptPreset? presetById(String? presetId) {
    final normalizedId = normalizePresetId(presetId);
    if (normalizedId == null) {
      return null;
    }
    for (final preset in presets) {
      if (preset.id == normalizedId) {
        return preset;
      }
    }
    return null;
  }

  PromptPreset createPreset({
    required String id,
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  }) {
    final preset = PromptPreset(
      id: id,
      name: name.trim(),
      positivePrompt: positivePrompt.trim(),
      negativePrompt: negativePrompt.trim(),
    );
    presets = <PromptPreset>[...presets, preset];
    if (presets.length == 1) {
      selectedImagePresetId = preset.id;
      selectedVideoPresetId = preset.id;
    }
    return preset;
  }

  void updatePreset({
    required String id,
    required String name,
    required String positivePrompt,
    required String negativePrompt,
  }) {
    presets = presets
        .map(
          (preset) => preset.id == id
              ? preset.copyWith(
                  name: name.trim(),
                  positivePrompt: positivePrompt.trim(),
                  negativePrompt: negativePrompt.trim(),
                )
              : preset,
        )
        .toList();
  }

  void deletePreset(String id) {
    presets = presets.where((preset) => preset.id != id).toList();
    if (selectedImagePresetId == id) {
      selectedImagePresetId = null;
    }
    if (selectedVideoPresetId == id) {
      selectedVideoPresetId = null;
    }
  }

  void ensureValidPresetSelections() {
    final validIds = presets.map((preset) => preset.id).toSet();
    if (!validIds.contains(selectedImagePresetId)) {
      selectedImagePresetId = null;
    }
    if (!validIds.contains(selectedVideoPresetId)) {
      selectedVideoPresetId = null;
    }
  }

  void addChatSystemPrompt(ChatSystemPrompt entry) {
    chatSystemPrompts = <ChatSystemPrompt>[...chatSystemPrompts, entry];
  }

  void updateChatSystemPrompt({
    required String id,
    required String name,
    required String prompt,
  }) {
    chatSystemPrompts = chatSystemPrompts
        .map(
          (entry) => entry.id == id
              ? entry.copyWith(name: name.trim(), prompt: prompt.trim())
              : entry,
        )
        .toList();
  }

  void deleteChatSystemPrompt(String id) {
    chatSystemPrompts = chatSystemPrompts
        .where((entry) => entry.id != id)
        .toList();
  }

  List<SavedPrompt> savedPrompts(SavedPromptCollection collection) {
    return switch (collection) {
      SavedPromptCollection.textToImage => textToImageAutoPromptBasePrompts,
      SavedPromptCollection.imageToImage => imageToImageAutoPromptBasePrompts,
      SavedPromptCollection.textToVideo => textToVideoAutoPromptBasePrompts,
      SavedPromptCollection.imageToVideo => imageToVideoAutoPromptBasePrompts,
    };
  }

  void setSavedPrompts(
    SavedPromptCollection collection,
    List<SavedPrompt> prompts,
  ) {
    switch (collection) {
      case SavedPromptCollection.textToImage:
        textToImageAutoPromptBasePrompts = prompts;
      case SavedPromptCollection.imageToImage:
        imageToImageAutoPromptBasePrompts = prompts;
      case SavedPromptCollection.textToVideo:
        textToVideoAutoPromptBasePrompts = prompts;
      case SavedPromptCollection.imageToVideo:
        imageToVideoAutoPromptBasePrompts = prompts;
    }
  }

  void addSavedPrompt(SavedPromptCollection collection, SavedPrompt prompt) {
    setSavedPrompts(collection, <SavedPrompt>[
      ...savedPrompts(collection),
      prompt,
    ]);
  }

  void updateSavedPrompt({
    required SavedPromptCollection collection,
    required String id,
    required String name,
    required String prompt,
  }) {
    setSavedPrompts(
      collection,
      savedPrompts(collection)
          .map(
            (entry) => entry.id == id
                ? entry.copyWith(name: name.trim(), prompt: prompt.trim())
                : entry,
          )
          .toList(),
    );
  }

  void deleteSavedPrompt(SavedPromptCollection collection, String id) {
    setSavedPrompts(
      collection,
      savedPrompts(collection).where((entry) => entry.id != id).toList(),
    );
  }

  String? normalizePresetId(String? presetId) {
    final trimmedId = presetId?.trim() ?? '';
    return trimmedId.isEmpty ? null : trimmedId;
  }

  Future<void> persistPresetSettings({SharedPreferences? prefs}) async {
    final preferences = prefs ?? await SharedPreferences.getInstance();
    await preferences.setString(
      promptPresetsKey,
      jsonEncode(presets.map((preset) => preset.toJson()).toList()),
    );
    if (selectedImagePresetId == null) {
      await preferences.remove(selectedImagePromptPresetKey);
    } else {
      await preferences.setString(
        selectedImagePromptPresetKey,
        selectedImagePresetId!,
      );
    }
    if (selectedVideoPresetId == null) {
      await preferences.remove(selectedVideoPromptPresetKey);
    } else {
      await preferences.setString(
        selectedVideoPromptPresetKey,
        selectedVideoPresetId!,
      );
    }
  }

  Future<void> persistChatSystemPrompts({SharedPreferences? prefs}) async {
    final preferences = prefs ?? await SharedPreferences.getInstance();
    await preferences.setString(
      chatSystemPromptsKey,
      jsonEncode(chatSystemPrompts.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> persistSavedPromptCollection(
    SavedPromptCollection collection, {
    SharedPreferences? prefs,
  }) async {
    final preferences = prefs ?? await SharedPreferences.getInstance();
    await preferences.setString(
      savedPromptCollectionKey(collection),
      jsonEncode(
        savedPrompts(collection).map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  String savedPromptCollectionKey(SavedPromptCollection collection) {
    return switch (collection) {
      SavedPromptCollection.textToImage =>
        savedTextToImageAutoPromptBasePromptsKey,
      SavedPromptCollection.imageToImage =>
        savedImageToImageAutoPromptBasePromptsKey,
      SavedPromptCollection.textToVideo =>
        savedTextToVideoAutoPromptBasePromptsKey,
      SavedPromptCollection.imageToVideo =>
        savedImageToVideoAutoPromptBasePromptsKey,
    };
  }
}
