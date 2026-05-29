import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/features/generate/domain/video_diffusion_model_selection.dart';
import 'package:flutter_app/features/generate/domain/video_workflow_lora_selection.dart';
import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/features/settings/auto_prompt_base_prompts_page.dart';
import 'package:flutter_app/features/settings/generation_defaults_widgets.dart';
import 'package:flutter_app/features/settings/settings_validation.dart';
import 'package:flutter_app/features/settings/settings_widgets.dart';

import 'package:flutter_app/features/settings/settings_view_model.dart';

enum _GenerationDefaultsKind {
  textToImage,
  imageToImage,
  textToVideo,
  imageToVideo,
}

class TextToImageDefaultsPage extends StatelessWidget {
  const TextToImageDefaultsPage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return _GenerationDefaultsPage(
      viewModel: viewModel,
      kind: _GenerationDefaultsKind.textToImage,
    );
  }
}

class ImageToImageDefaultsPage extends StatelessWidget {
  const ImageToImageDefaultsPage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return _GenerationDefaultsPage(
      viewModel: viewModel,
      kind: _GenerationDefaultsKind.imageToImage,
    );
  }
}

class TextToVideoDefaultsPage extends StatelessWidget {
  const TextToVideoDefaultsPage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return _GenerationDefaultsPage(
      viewModel: viewModel,
      kind: _GenerationDefaultsKind.textToVideo,
    );
  }
}

class ImageToVideoDefaultsPage extends StatelessWidget {
  const ImageToVideoDefaultsPage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return _GenerationDefaultsPage(
      viewModel: viewModel,
      kind: _GenerationDefaultsKind.imageToVideo,
    );
  }
}

class _GenerationDefaultsPage extends StatefulWidget {
  const _GenerationDefaultsPage({required this.viewModel, required this.kind});

  final SettingsViewModel viewModel;
  final _GenerationDefaultsKind kind;

  @override
  State<_GenerationDefaultsPage> createState() =>
      _GenerationDefaultsPageState();
}

class _GenerationDefaultsPageState extends State<_GenerationDefaultsPage> {
  late final TextEditingController _stepsController;
  late final TextEditingController _guidanceController;
  Timer? _saveDebounce;
  String? _stepsErrorText;
  String? _guidanceErrorText;

  @override
  void initState() {
    super.initState();
    _stepsController = TextEditingController(text: _steps.toString());
    _guidanceController = TextEditingController(
      text: _guidance.toStringAsFixed(1),
    );
    _stepsController.addListener(_scheduleAutosave);
    _guidanceController.addListener(_scheduleAutosave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.viewModel.baseUrl.isNotEmpty) {
        unawaited(widget.viewModel.loadAutoPromptModels(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _stepsController.dispose();
    _guidanceController.dispose();
    super.dispose();
  }

  bool get _usesImageSettings =>
      widget.kind == _GenerationDefaultsKind.textToImage ||
      widget.kind == _GenerationDefaultsKind.imageToImage;

  bool get _usesVideoSettings =>
      widget.kind == _GenerationDefaultsKind.textToVideo ||
      widget.kind == _GenerationDefaultsKind.imageToVideo;

  int get _steps {
    return switch (widget.kind) {
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.imageToImageNumInferenceSteps,
      _ => widget.viewModel.numInferenceSteps,
    };
  }

  double get _guidance {
    return switch (widget.kind) {
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.imageToImageGuidanceScale,
      _ => widget.viewModel.guidanceScale,
    };
  }

  String get _basePrompt {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.promptGeneratorBasePrompt,
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.imageToImagePromptGeneratorBasePrompt,
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.textToVideoPromptGeneratorBasePrompt,
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.imageToVideoPromptGeneratorBasePrompt,
    };
  }

  String get _selectedAutoPromptModelName {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.selectedAutoPromptModelName ?? '',
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.selectedImageToImageAutoPromptModelName ?? '',
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.selectedTextToVideoAutoPromptModelName ?? '',
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.selectedImageToVideoAutoPromptModelName ?? '',
    };
  }

  bool get _autoMetadataEnabled {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.textToImageAutoMetadataEnabled,
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.imageToImageAutoMetadataEnabled,
      _ => false,
    };
  }

  String get _selectedAutoMetadataModelName {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.selectedTextToImageAutoMetadataModelName ?? '',
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.selectedImageToImageAutoMetadataModelName ?? '',
      _ => '',
    };
  }

  String get _title {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage => 'Text to image',
      _GenerationDefaultsKind.imageToImage => 'Image to image',
      _GenerationDefaultsKind.textToVideo => 'Text to video',
      _GenerationDefaultsKind.imageToVideo => 'Image to video',
    };
  }

  String get _shortName {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage => 't2i',
      _GenerationDefaultsKind.imageToImage => 'i2i',
      _GenerationDefaultsKind.textToVideo => 't2v',
      _GenerationDefaultsKind.imageToVideo => 'i2v',
    };
  }

  List<VideoDiffusionModelSelectionOption> get _videoDiffusionModelSelections {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.textToVideoDiffusionModelSelections,
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.imageToVideoDiffusionModelSelections,
      _ => const <VideoDiffusionModelSelectionOption>[],
    };
  }

  String? get _selectedVideoDiffusionModelSelectionValue {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.selectedTextToVideoDiffusionModelSelectionValue,
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.selectedImageToVideoDiffusionModelSelectionValue,
      _ => null,
    };
  }

  List<VideoWorkflowLoraSelectionOption> get _workflowLoraSelections {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.textToVideoWorkflowLoraSelections,
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.imageToVideoWorkflowLoraSelections,
      _ => const <VideoWorkflowLoraSelectionOption>[],
    };
  }

  Map<String, double> get _workflowLoraSelectionStrengths {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.textToVideoWorkflowLoraSelectionStrengths,
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.imageToVideoWorkflowLoraSelectionStrengths,
      _ => const <String, double>{},
    };
  }

  SavedPromptCollection get _savedPromptCollection {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage => SavedPromptCollection.textToImage,
      _GenerationDefaultsKind.imageToImage =>
        SavedPromptCollection.imageToImage,
      _GenerationDefaultsKind.textToVideo => SavedPromptCollection.textToVideo,
      _GenerationDefaultsKind.imageToVideo =>
        SavedPromptCollection.imageToVideo,
    };
  }

  String get _savedPromptIdPrefix {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage => 'auto_prompt_base',
      _GenerationDefaultsKind.imageToImage => 'i2i_auto_prompt_base',
      _GenerationDefaultsKind.textToVideo => 't2v_auto_prompt_base',
      _GenerationDefaultsKind.imageToVideo => 'i2v_auto_prompt_base',
    };
  }

  void _setVideoDiffusionModelSelection(String? value) {
    switch (widget.kind) {
      case _GenerationDefaultsKind.textToVideo:
        widget.viewModel.setTextToVideoDiffusionModelSelection(value);
      case _GenerationDefaultsKind.imageToVideo:
        widget.viewModel.setImageToVideoDiffusionModelSelection(value);
      default:
        break;
    }
  }

  void _setWorkflowLoraStrength(String loraId, double strength) {
    switch (widget.kind) {
      case _GenerationDefaultsKind.textToVideo:
        widget.viewModel.setTextToVideoWorkflowLoraStrength(loraId, strength);
      case _GenerationDefaultsKind.imageToVideo:
        widget.viewModel.setImageToVideoWorkflowLoraStrength(loraId, strength);
      default:
        break;
    }
  }

  Future<void> _setBasePrompt(String value) {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.setPromptGeneratorBasePrompt(value),
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.setImageToImagePromptGeneratorBasePrompt(value),
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.setTextToVideoPromptGeneratorBasePrompt(value),
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.setImageToVideoPromptGeneratorBasePrompt(value),
    };
  }

  List<SavedPrompt> _savedAutoPromptBasePrompts() {
    return widget.viewModel.savedPrompts(_savedPromptCollection);
  }

  Future<void> _createSavedAutoPromptBasePrompt({
    required String name,
    required String prompt,
  }) {
    return widget.viewModel.createSavedPromptAndPersist(
      _savedPromptCollection,
      idPrefix: _savedPromptIdPrefix,
      name: name,
      prompt: prompt,
    );
  }

  Future<void> _updateSavedAutoPromptBasePrompt({
    required String id,
    required String name,
    required String prompt,
  }) {
    return widget.viewModel.updateSavedPromptAndPersist(
      collection: _savedPromptCollection,
      id: id,
      name: name,
      prompt: prompt,
    );
  }

  Future<void> _deleteSavedAutoPromptBasePrompt(String id) {
    return widget.viewModel.deleteSavedPromptAndPersist(
      _savedPromptCollection,
      id,
    );
  }

  Future<void> _setAutoPromptModel(String value) {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.setPreferredAutoPromptModelName(value),
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.setPreferredImageToImageAutoPromptModelName(value),
      _GenerationDefaultsKind.textToVideo =>
        widget.viewModel.setPreferredTextToVideoAutoPromptModelName(value),
      _GenerationDefaultsKind.imageToVideo =>
        widget.viewModel.setPreferredImageToVideoAutoPromptModelName(value),
    };
  }

  Future<void> _setAutoMetadataEnabled(bool value) {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.setTextToImageAutoMetadataEnabled(value),
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.setImageToImageAutoMetadataEnabled(value),
      _ => Future<void>.value(),
    };
  }

  Future<void> _setAutoMetadataModel(String value) {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.setTextToImageAutoMetadataModelName(value),
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.setImageToImageAutoMetadataModelName(value),
      _ => Future<void>.value(),
    };
  }

  Future<void> _saveImageDefaults({
    required int steps,
    required double guidance,
  }) {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToImage =>
        widget.viewModel.setTextToImageGenerationDefaults(
          steps: steps,
          guidance: guidance,
        ),
      _GenerationDefaultsKind.imageToImage =>
        widget.viewModel.setImageToImageGenerationDefaults(
          steps: steps,
          guidance: guidance,
        ),
      _ => Future<void>.value(),
    };
  }

  void _scheduleAutosave() {
    final validation = validateGenerationDefaultsInput(
      steps: _stepsController.text,
      guidance: _guidanceController.text,
    );
    final changedValidation =
        validation.stepsError != _stepsErrorText ||
        validation.guidanceError != _guidanceErrorText;
    if (changedValidation && mounted) {
      setState(() {
        _stepsErrorText = validation.stepsError;
        _guidanceErrorText = validation.guidanceError;
      });
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!_usesImageSettings || validation.hasAutosaveBlockingError) {
        return;
      }
      final steps = int.tryParse(_stepsController.text.trim());
      final guidance = double.tryParse(_guidanceController.text.trim());
      if (steps == null || guidance == null) {
        return;
      }
      await _saveImageDefaults(steps: steps, guidance: guidance);
    });
  }

  Future<void> _openAutoPromptLibrary() async {
    _saveDebounce?.cancel();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AutoPromptBasePromptsPage(
          changes: widget.viewModel,
          pageTitle: '$_shortName auto-prompt prompts',
          currentPromptTitle: 'Current $_shortName auto-prompt base prompt',
          currentPrompt: () => _basePrompt,
          currentPromptHintText:
              'Add the standing instructions used for $_shortName auto-prompting.',
          currentPromptDescription:
              'This base prompt is prepended when the app auto-generates $_shortName prompts.',
          savedPromptsTitle: 'Saved prompts',
          savedPromptsDescription:
              'Store reusable $_shortName auto-prompt instructions here, then apply one whenever you want.',
          emptyCurrentPromptText:
              'No $_shortName auto-prompt base prompt is active yet.',
          currentPromptEditorTitle: '$_title auto-prompt base prompt',
          createButtonLabel: 'Create saved prompt',
          savedPrompts: _savedAutoPromptBasePrompts,
          updateCurrentPrompt: _setBasePrompt,
          createPrompt: _createSavedAutoPromptBasePrompt,
          updatePrompt: _updateSavedAutoPromptBasePrompt,
          deletePrompt: _deleteSavedAutoPromptBasePrompt,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  List<Widget> _videoDiffusionModelControls() {
    return switch (widget.kind) {
      _GenerationDefaultsKind.textToVideo => <Widget>[
        VideoDiffusionModelSelectionDropdown(
          label: 'Video diffusion model',
          selectedValue: _selectedVideoDiffusionModelSelectionValue,
          options: _videoDiffusionModelSelections,
          onChanged: _setVideoDiffusionModelSelection,
        ),
      ],
      _GenerationDefaultsKind.imageToVideo => <Widget>[
        VideoDiffusionModelSelectionDropdown(
          label: 'Video diffusion model',
          selectedValue: _selectedVideoDiffusionModelSelectionValue,
          options: _videoDiffusionModelSelections,
          onChanged: _setVideoDiffusionModelSelection,
        ),
      ],
      _ => const <Widget>[],
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InfoCard(
            title: 'Defaults',
            child: Column(
              children: [
                SettingsEntryTile(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Saved auto-prompt base prompts',
                  subtitle: 'Manage reusable base prompts for $_shortName.',
                  onTap: _openAutoPromptLibrary,
                ),
                const SizedBox(height: 12),
                if (_usesImageSettings) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable auto caption and tags'),
                    value: _autoMetadataEnabled,
                    onChanged: (value) {
                      unawaited(_setAutoMetadataEnabled(value));
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  AutoPromptModelDropdown(
                    label: 'Auto metadata LLM',
                    selectedModelName: _selectedAutoMetadataModelName,
                    models: widget.viewModel.autoPromptModels,
                    onChanged: (value) =>
                        unawaited(_setAutoMetadataModel(value)),
                  ),
                  const SizedBox(height: 12),
                ],
                AutoPromptModelDropdown(
                  label: 'Auto-prompt LLM',
                  selectedModelName: _selectedAutoPromptModelName,
                  models: widget.viewModel.autoPromptModels,
                  onChanged: (value) => unawaited(_setAutoPromptModel(value)),
                ),               
                const SizedBox(height: 12), 
                if (_usesImageSettings) ...[
                  TextField(
                    controller: _stepsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Number of inference steps',
                      errorText: _stepsErrorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _guidanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Guidance scale',
                      errorText: _guidanceErrorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_usesVideoSettings) ...[
                  ..._videoDiffusionModelControls(),
                  const SizedBox(height: 12),
                  WorkflowLoraStrengthSection(
                    loras: _workflowLoraSelections,
                    strengths: _workflowLoraSelectionStrengths,
                    onStrengthChanged: _setWorkflowLoraStrength,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
