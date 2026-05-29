import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/models/generation.dart';
import 'package:flutter_app/app/persistence/settings_codecs.dart';


class RandomImageGenerationSelection {
  const RandomImageGenerationSelection({
    required this.modelId,
    required this.loras,
  });

  final String modelId;
  final List<SelectedLora> loras;
}

class ImageModelSelectionStore {
  ImageModelSelectionStore({required this.setMessage, required this.onChanged});

  static const selectedModelKey = 'selected_model_id';
  static const selectedLorasKey = 'selected_loras';

  final void Function(String? value) setMessage;
  final void Function() onChanged;
  final math.Random _random = math.Random();

  List<ModelAsset> models = <ModelAsset>[];
  List<LoraAsset> loras = <LoraAsset>[];
  String? selectedModelId;
  final Map<String, double> selectedLoraStrengths = <String, double>{};

  List<ModelAsset> get modelsByRating {
    final sorted = List<ModelAsset>.from(models);
    sorted.sort((left, right) {
      final ratingCompare = right.rating.compareTo(left.rating);
      if (ratingCompare != 0) {
        return ratingCompare;
      }
      return left.label.toLowerCase().compareTo(right.label.toLowerCase());
    });
    return sorted;
  }

  List<SelectedLora> get selectedLoras {
    return selectedLoraStrengths.entries
        .map((entry) => SelectedLora(loraId: entry.key, strength: entry.value))
        .toList();
  }

  void loadPreferences(SharedPreferences prefs) {
    selectedModelId = prefs.getString(selectedModelKey);
    selectedLoraStrengths
      ..clear()
      ..addAll(decodeSelectedLoras(prefs.getString(selectedLorasKey)));
  }

  void applyAssets({
    required List<ModelAsset> models,
    required List<LoraAsset> loras,
  }) {
    this.models = models;
    this.loras = _sortLorasByRating(loras);
    if (selectedModelId == null ||
        !this.models.any((item) => item.id == selectedModelId)) {
      selectedModelId = modelsByRating.isNotEmpty
          ? modelsByRating.first.id
          : null;
    }
    final validLoraIds = this.loras.map((item) => item.id).toSet();
    selectedLoraStrengths.removeWhere(
      (loraId, _) => !validLoraIds.contains(loraId),
    );
  }

  void setSelectedModel(String? modelId) {
    selectedModelId = modelId;
    _persistAndNotify();
  }

  void toggleLora(LoraAsset lora, bool enabled) {
    if (enabled) {
      selectedLoraStrengths[lora.id] =
          selectedLoraStrengths[lora.id] ?? lora.defaultStrength;
    } else {
      selectedLoraStrengths.remove(lora.id);
    }
    _persistAndNotify();
  }

  void setLoraStrength(String loraId, double strength) {
    selectedLoraStrengths[loraId] = strength;
    _persistAndNotify();
  }

  void clearSelectedLoras() {
    if (selectedLoraStrengths.isEmpty) {
      return;
    }
    selectedLoraStrengths.clear();
    _persistAndNotify();
  }

  void randomizeImageModelAndLoras() {
    if (models.isEmpty) {
      setMessage('No image models are available yet.');
      onChanged();
      return;
    }
    final randomModel = models[_random.nextInt(models.length)];
    selectedModelId = randomModel.id;
    selectedLoraStrengths.clear();
    if (loras.isNotEmpty) {
      final randomizedLoras = List<LoraAsset>.from(loras)..shuffle(_random);
      final selectionCount =
          1 + _random.nextInt(math.min(3, randomizedLoras.length));
      for (final lora in randomizedLoras.take(selectionCount)) {
        selectedLoraStrengths[lora.id] = lora.defaultStrength;
      }
      setMessage(
        'Randomized ${randomModel.label} with $selectionCount LoRA'
        '${selectionCount == 1 ? '' : 's'}.',
      );
    } else {
      setMessage('Randomized ${randomModel.label}.');
    }
    _persistAndNotify();
  }

  RandomImageGenerationSelection? createRandomGenerationSelection() {
    if (models.isEmpty) {
      setMessage('No image models are available yet.');
      onChanged();
      return null;
    }

    final model = models[_random.nextInt(models.length)];
    final selectedLoras = <SelectedLora>[];
    if (loras.isNotEmpty) {
      final randomizedLoras = List<LoraAsset>.from(loras)..shuffle(_random);
      final selectionCount =
          1 + _random.nextInt(math.min(3, randomizedLoras.length));
      for (final lora in randomizedLoras.take(selectionCount)) {
        selectedLoras.add(
          SelectedLora(loraId: lora.id, strength: lora.defaultStrength),
        );
      }
    }

    return RandomImageGenerationSelection(
      modelId: model.id,
      loras: selectedLoras,
    );
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (selectedModelId == null || selectedModelId!.isEmpty) {
      await prefs.remove(selectedModelKey);
    } else {
      await prefs.setString(selectedModelKey, selectedModelId!);
    }
    await prefs.setString(selectedLorasKey, jsonEncode(selectedLoraStrengths));
  }

  void _persistAndNotify() {
    unawaited(savePreferences());
    onChanged();
  }

  static List<LoraAsset> _sortLorasByRating(Iterable<LoraAsset> items) {
    final sorted = List<LoraAsset>.from(items);
    sorted.sort((left, right) {
      final ratingCompare = right.rating.compareTo(left.rating);
      if (ratingCompare != 0) {
        return ratingCompare;
      }
      return left.label.toLowerCase().compareTo(right.label.toLowerCase());
    });
    return sorted;
  }
}
