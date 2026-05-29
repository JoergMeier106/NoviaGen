import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:noviagen/models/assets.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/shared/app_formatters.dart';
import 'package:noviagen/shared/cached_media_image.dart';
import 'package:noviagen/features/generate/generation_form_widgets.dart';
import 'package:noviagen/features/generate/generation_settings_fields.dart';
import 'package:noviagen/features/generate/generation_source_picker.dart';
import 'package:noviagen/features/generate/video_settings_controls.dart';

import 'package:noviagen/features/generate/generation_view_model.dart';

class VideoGeneratePanel extends StatefulWidget {
  const VideoGeneratePanel({
    super.key,
    required this.viewModel,
    required this.promptController,
  });

  final GenerationViewModel viewModel;
  final TextEditingController promptController;

  @override
  State<VideoGeneratePanel> createState() => _VideoGeneratePanelState();
}

class _VideoGeneratePanelState extends State<VideoGeneratePanel> {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _fpsController;
  late final TextEditingController _numFramesController;
  late final Listenable _changes;

  @override
  void initState() {
    super.initState();
    final videoSettings = widget.viewModel;
    _widthController = TextEditingController(text: videoSettings.widthDraft);
    _heightController = TextEditingController(text: videoSettings.heightDraft);
    _fpsController = TextEditingController(text: videoSettings.fpsDraft);
    _numFramesController = TextEditingController(
      text: videoSettings.numFramesDraft,
    );
    _changes = widget.viewModel;
    _changes.addListener(_syncControllersFromState);
  }

  @override
  void dispose() {
    _changes.removeListener(_syncControllersFromState);
    _widthController.dispose();
    _heightController.dispose();
    _fpsController.dispose();
    _numFramesController.dispose();
    super.dispose();
  }

  void _syncControllersFromState() {
    final videoSettings = widget.viewModel;
    if (_widthController.text != videoSettings.widthDraft) {
      _widthController.text = videoSettings.widthDraft;
    }
    if (_heightController.text != videoSettings.heightDraft) {
      _heightController.text = videoSettings.heightDraft;
    }
    if (_fpsController.text != videoSettings.fpsDraft) {
      _fpsController.text = videoSettings.fpsDraft;
    }
    if (_numFramesController.text != videoSettings.numFramesDraft) {
      _numFramesController.text = videoSettings.numFramesDraft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideoModel = widget.viewModel.videoModels.isNotEmpty;
    final selectedPreset = widget.viewModel.selectedPreset;
    final hasSource = widget.viewModel.hasVideoSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFeelingLuckyButton(context, hasVideoModel),
        const SizedBox(height: 12),
        if (!hasVideoModel) _buildMissingModelMessage(),
        _VideoSourceCard(viewModel: widget.viewModel),
        const SizedBox(height: 12),
        _buildPromptField(context, hasSource),
        const SizedBox(height: 12),
        _buildPromptPresetDropdown(context),
        const SizedBox(height: 12),
        _buildVideoPresetDropdown(context),
        if (selectedPreset != null) ...[
          const SizedBox(height: 12),
          _buildResolutionFields(context),
          const SizedBox(height: 12),
          _buildPlaybackFields(context),
          const SizedBox(height: 8),
          _buildSettingsSummary(context, selectedPreset),
        ],
        const SizedBox(height: 12),
        _buildSubmitButton(
          context,
          hasVideoModel: hasVideoModel,
          hasSource: hasSource,
        ),
      ],
    );
  }

  Widget _buildFeelingLuckyButton(BuildContext context, bool hasVideoModel) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: !hasVideoModel
            ? null
            : () => unawaited(widget.viewModel.generateLuckyVideo()),
        icon: const Icon(Icons.casino_outlined),
        label: const Text('Feeling Lucky'),
      ),
    );
  }

  Widget _buildMissingModelMessage() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text('No video model is available on the server.'),
    );
  }

  Widget _buildPromptField(BuildContext context, bool hasSource) {
    return PromptGenerateField(
      controller: widget.promptController,
      onChanged: widget.viewModel.setVideoPromptDraft,
      hintText: hasSource
          ? 'Optional prompt to guide the animation.'
          : 'Describe the video you want to generate.',
      generatingPrompt: widget.viewModel.generatingPrompt,
      disableGenerate: false,
      onGenerate: () => _generatePrompt(context),
    );
  }

  Future<void> _generatePrompt(BuildContext context) async {
    final generatedPrompt = await widget.viewModel.generatePromptText(
      forVideo: true,
      currentPrompt: widget.promptController.text,
    );
    if (generatedPrompt == null) {
      return;
    }
    widget.promptController.value = TextEditingValue(
      text: generatedPrompt,
      selection: TextSelection.collapsed(offset: generatedPrompt.length),
    );
  }

  Widget _buildPromptPresetDropdown(BuildContext context) {
    final presets = widget.viewModel.presets;
    return PromptPresetDropdown(
      label: 'Prompt preset',
      selectedPresetId: widget.viewModel.selectedVideoPresetId,
      presets: presets,
      onChanged: widget.viewModel.setSelectedVideoPresetIdAndPersist,
      helperText: presets.isEmpty
          ? 'No prompt presets yet. Add them in Settings > Prompt presets.'
          : null,
    );
  }

  Widget _buildVideoPresetDropdown(BuildContext context) {
    final selectedPreset = widget.viewModel.selectedPreset;
    final presets = widget.viewModel.videoPresets;
    return DropdownButtonFormField<String>(
      key: ValueKey('video-preset-${selectedPreset?.id}'),
      initialValue: selectedPreset?.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Preset',
        border: OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => presets
          .map((preset) => _VideoPresetLabel(preset: preset))
          .toList(),
      items: presets
          .map(
            (preset) => DropdownMenuItem(
              value: preset.id,
              child: _VideoPresetLabel(preset: preset),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          widget.viewModel.setVideoPreset(value);
        }
      },
    );
  }

  Widget _buildResolutionFields(BuildContext context) {
    final adjustmentLabel = _resolutionAdjustmentLabel(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: VideoSettingField(
                controller: _widthController,
                label: 'Width',
                onChanged: widget.viewModel.setWidthDraft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VideoSettingField(
                controller: _heightController,
                label: 'Height',
                onChanged: widget.viewModel.setHeightDraft,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: VideoResolutionStepper(
                onIncrease: widget.viewModel.increaseResolution,
                onDecrease: widget.viewModel.decreaseResolution,
              ),
            ),
          ],
        ),
        if (adjustmentLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              adjustmentLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaybackFields(BuildContext context) {
    final validationMessage = widget.viewModel.validationMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: VideoSettingField(
                controller: _fpsController,
                label: 'FPS',
                onChanged: widget.viewModel.setFpsDraft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VideoSettingField(
                controller: _numFramesController,
                label: 'Frames',
                onChanged: widget.viewModel.setNumFramesDraft,
              ),
            ),
          ],
        ),
        if (validationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              validationMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsSummary(
    BuildContext context,
    VideoPresetOption selectedPreset,
  ) {
    return Text(
      _settingsSummaryLabel(context, selectedPreset),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  String _settingsSummaryLabel(
    BuildContext context,
    VideoPresetOption selectedPreset,
  ) {
    final currentSettings = widget.viewModel.currentSettings;
    final durationSeconds = widget.viewModel.currentDurationSeconds;
    return '${currentSettings?['width'] ?? selectedPreset.maxWidth}×'
        '${currentSettings?['height'] ?? selectedPreset.maxHeight} • '
        '${currentSettings?['num_frames'] ?? selectedPreset.numFrames} frames • '
        '${currentSettings?['fps'] ?? selectedPreset.fps} FPS'
        '${durationSeconds != null ? ' • Length ${formatDurationLabel(durationSeconds)}' : ''} • '
        '${selectedPreset.numInferenceSteps} steps';
  }

  String? _resolutionAdjustmentLabel(BuildContext context) {
    if (widget.viewModel.validationMessage != null) {
      return null;
    }
    return widget.viewModel.resolutionAdjustmentLabel;
  }

  Widget _buildSubmitButton(
    BuildContext context, {
    required bool hasVideoModel,
    required bool hasSource,
  }) {
    return FilledButton.icon(
      onPressed: !hasVideoModel
          ? null
          : () => unawaited(
                widget.viewModel.submit(
                  widget.promptController.text,
                ),
              ),
      icon: const Icon(Icons.movie_creation_outlined),
      label: Text(hasSource ? 'Create video from source' : 'Generate video'),
    );
  }
}

class _VideoPresetLabel extends StatelessWidget {
  const _VideoPresetLabel({required this.preset});

  final VideoPresetOption preset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        videoPresetDropdownLabel(preset),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _VideoSourceCard extends StatelessWidget {
  const _VideoSourceCard({required this.viewModel});

  final GenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final storedSource = viewModel.videoSource;
    final localSource = viewModel.videoLocalSource;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (storedSource != null || localSource != null)
              _SelectedVideoSourcePreview(
                storedSource: storedSource,
                localSource: localSource,
                onClear: viewModel
                    .clearVideoGenerationSource,
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openGenerationSourcePicker(
                  context,
                  viewModel: viewModel,
                  forVideo: true,
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Select source image (Optional)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedVideoSourcePreview extends StatelessWidget {
  const _SelectedVideoSourcePreview({
    required this.storedSource,
    required this.localSource,
    required this.onClear,
  });

  final ImageRecord? storedSource;
  final LocalImageSource? localSource;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final image = storedSource;
    final local = localSource;
    final preview = image != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedMediaImage(
              imageUrl: image.previewUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (context) => const Center(
                child: Icon(Icons.broken_image_outlined, size: 24),
              ),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(local!.path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image_outlined, size: 24),
              ),
            ),
          );
    final title = image != null ? 'Stored image source' : 'Local image source';
    final subtitle = image != null
        ? (image.prompt.isEmpty ? image.finalPositivePrompt : image.prompt)
        : local!.name;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: preview,
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        onPressed: onClear,
        icon: const Icon(Icons.close),
        tooltip: 'Clear source',
      ),
    );
  }
}
