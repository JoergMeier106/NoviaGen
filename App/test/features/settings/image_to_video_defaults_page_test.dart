import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noviagen/features/generate/domain/video_diffusion_model_selection.dart';
import 'package:noviagen/features/generate/domain/video_workflow_lora_selection.dart';
import 'package:noviagen/features/prompts/domain/saved_prompt_collection.dart';
import 'package:noviagen/features/settings/generation_defaults_pages.dart';
import 'package:noviagen/features/settings/settings_view_model.dart';
import 'package:noviagen/models/assets.dart';
import 'package:noviagen/models/chat_models.dart';
import 'package:noviagen/models/prompts.dart';

void main() {
  testWidgets(
    'Image to video defaults page shows one combined diffusion model field',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageToVideoDefaultsPage(viewModel: _FakeSettingsViewModel()),
        ),
      );

      expect(find.text('Video diffusion model'), findsOneWidget);
      expect(find.text('Video high diffusion model'), findsNothing);
      expect(find.text('Video low diffusion model'), findsNothing);
      expect(find.text('demo-adapter-H/L.safetensors'), findsOneWidget);
    },
  );
}

class _FakeSettingsViewModel extends ChangeNotifier
    implements SettingsViewModel {
  @override
  String get baseUrl => '';

  @override
  List<OllamaModelInfo> get autoPromptModels => const <OllamaModelInfo>[];

  @override
  double get guidanceScale => 1.0;

  @override
  String get imageToVideoPromptGeneratorBasePrompt => '';

  @override
  int get numInferenceSteps => 8;

  @override
  List<VideoDiffusionModelSelectionOption>
  get imageToVideoDiffusionModelSelections =>
      const <VideoDiffusionModelSelectionOption>[
        VideoDiffusionModelSelectionOption(
          value: 'demo-H.safetensors',
          label: 'demo-H/L.safetensors',
          highModelName: 'demo-H.safetensors',
          lowModelName: 'demo-L.safetensors',
        ),
      ];

  @override
  List<VideoWorkflowLoraAsset> get imageToVideoWorkflowLoras =>
      <VideoWorkflowLoraAsset>[
        VideoWorkflowLoraAsset(
          id: 'high',
          name: 'demo-adapter-H.safetensors',
          label: 'demo-adapter-H.safetensors',
          defaultStrength: 1.0,
          enabled: true,
          nodeTitle: 'LoRA High',
        ),
        VideoWorkflowLoraAsset(
          id: 'low',
          name: 'demo-adapter-L.safetensors',
          label: 'demo-adapter-L.safetensors',
          defaultStrength: 1.0,
          enabled: true,
          nodeTitle: 'LoRA Low',
        ),
      ];

  @override
  Map<String, double> get imageToVideoWorkflowLoraStrengths =>
      const <String, double>{};

  @override
  List<VideoWorkflowLoraSelectionOption>
  get imageToVideoWorkflowLoraSelections =>
      const <VideoWorkflowLoraSelectionOption>[
        VideoWorkflowLoraSelectionOption(
          key: 'high',
          label: 'demo-adapter-H/L.safetensors',
          loraIds: <String>['high', 'low'],
          defaultStrength: 1.0,
          subtitle: 'LoRA High • LoRA Low',
          tooltip: 'demo-adapter-H.safetensors\ndemo-adapter-L.safetensors',
        ),
      ];

  @override
  Map<String, double> get imageToVideoWorkflowLoraSelectionStrengths =>
      const <String, double>{'high': 1.0};

  @override
  String? get selectedImageToVideoAutoPromptModelName => null;

  @override
  String? get selectedImageToVideoDiffusionModelSelectionValue =>
      'demo-H.safetensors';

  @override
  String? get selectedImageToVideoHighDiffusionModel => 'demo-H.safetensors';

  @override
  String? get selectedImageToVideoLowDiffusionModel => 'demo-L.safetensors';

  @override
  List<VideoDiffusionModelAsset> get diffusionModels =>
      <VideoDiffusionModelAsset>[
        VideoDiffusionModelAsset(name: 'demo-H.safetensors'),
        VideoDiffusionModelAsset(name: 'demo-L.safetensors'),
      ];

  @override
  Future<void> setPreferredImageToVideoAutoPromptModelName(
    String? modelName,
  ) async {}

  @override
  Future<void> loadAutoPromptModels({bool silent = false}) async {}

  @override
  Future<void> setImageToVideoPromptGeneratorBasePrompt(String value) async {}

  @override
  void setImageToVideoDiffusionModelSelection(String? value) {}

  @override
  void setImageToVideoWorkflowLoraStrength(String loraId, double strength) {}

  @override
  List<SavedPrompt> savedPrompts(SavedPromptCollection collection) =>
      <SavedPrompt>[];

  @override
  Future<void> createSavedPromptAndPersist(
    SavedPromptCollection collection, {
    required String idPrefix,
    required String name,
    required String prompt,
  }) async {}

  @override
  Future<void> updateSavedPromptAndPersist({
    required SavedPromptCollection collection,
    required String id,
    required String name,
    required String prompt,
  }) async {}

  @override
  Future<void> deleteSavedPromptAndPersist(
    SavedPromptCollection collection,
    String id,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
