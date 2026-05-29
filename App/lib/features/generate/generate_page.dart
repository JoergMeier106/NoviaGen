import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/features/generate/domain/generation_settings.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/shared/cached_media_image.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';
import 'package:flutter_app/features/generate/generation_form_widgets.dart';
import 'package:flutter_app/features/generate/generation_settings_fields.dart';
import 'package:flutter_app/features/generate/generation_source_picker.dart';
import 'package:flutter_app/features/generate/latest_media_card.dart';
import 'package:flutter_app/features/generate/lora_selection_page.dart';
import 'package:flutter_app/features/generate/video_generate_panel.dart';

import 'package:provider/provider.dart';
import 'package:flutter_app/features/generate/generation_view_model.dart';

class GeneratePage extends StatelessWidget {
  const GeneratePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GenerationViewModel>(
      builder: (context, viewModel, _) =>
          _GeneratePageBody(viewModel: viewModel),
    );
  }
}

class _GeneratePageBody extends StatefulWidget {
  const _GeneratePageBody({required this.viewModel});

  final GenerationViewModel viewModel;

  @override
  State<_GeneratePageBody> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<_GeneratePageBody> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _videoPromptController = TextEditingController();
  bool _requestedAssets = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptController.text = widget.viewModel.imagePrompt;
      _videoPromptController.text = widget.viewModel.videoPrompt;
      if (widget.viewModel.baseUrl.isEmpty) {
        return;
      }
      unawaited(widget.viewModel.syncInterJobDelaySetting(silent: true));
      unawaited(widget.viewModel.restoreActiveJobOnLaunch());
      if (!_requestedAssets && widget.viewModel.models.isEmpty) {
        _requestedAssets = true;
        unawaited(widget.viewModel.refreshAssets());
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _videoPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.viewModel.mode;
    final latestImage = widget.viewModel.latestImage;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<GenerateMode>(
          segments: const [
            ButtonSegment<GenerateMode>(
              value: GenerateMode.image,
              icon: Icon(Icons.image_outlined),
              label: Text('Image'),
            ),
            ButtonSegment<GenerateMode>(
              value: GenerateMode.video,
              icon: Icon(Icons.movie_creation_outlined),
              label: Text('Video'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              widget.viewModel.setGenerateMode(
            selection.first,
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: mode == GenerateMode.image
              ? 'Generate Image'
              : 'Generate Video',
          child: mode == GenerateMode.image
              ? _ImageGeneratePanel(viewModel: widget.viewModel, promptController: _promptController)
              : VideoGeneratePanel(viewModel: widget.viewModel, promptController: _videoPromptController),
        ),
        const SizedBox(height: 16),
        if (latestImage != null)
          LatestMediaCard(
            key: ValueKey('latest-media-${latestImage.id}'),
            viewModel: widget.viewModel,
            image: latestImage,
          ),
      ],
    );
  }
}

class _ImageGeneratePanel extends StatelessWidget {
  const _ImageGeneratePanel({
    required this.viewModel,
    required this.promptController,
  });

  final GenerationViewModel viewModel;
  final TextEditingController promptController;

  @override
  Widget build(BuildContext context) {
    Future<void> generatePrompt() async {
      final generatedPrompt = await viewModel.generatePromptText(
        forVideo: false,
        currentPrompt: promptController.text,
      );
      if (generatedPrompt == null) {
        return;
      }
      promptController.value = TextEditingValue(
        text: generatedPrompt,
        selection: TextSelection.collapsed(offset: generatedPrompt.length),
      );
    }

    final models = viewModel.modelsByRating;
    final selectedModelId = viewModel.selectedModelId;
    final presets = viewModel.presets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () =>
                unawaited(viewModel.generateFeelingLucky()),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Feeling Lucky'),
          ),
        ),
        const SizedBox(height: 12),
        _ImageSourceCard(viewModel: viewModel),
        const SizedBox(height: 12),
        PromptGenerateField(
          controller: promptController,
          onChanged: viewModel.setPromptDraft,
          hintText: 'Describe the image you want to generate.',
          generatingPrompt: viewModel.generatingPrompt,
          disableGenerate: false,
          onGenerate: generatePrompt,
          additionalActions: [
            IconButton.outlined(
              onPressed: models.isEmpty
                  ? null
                  : viewModel.randomizeImageModelAndLoras,
              tooltip: 'Random model + LoRAs',
              icon: const Icon(Icons.shuffle),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PromptPresetDropdown(
          label: 'Prompt preset',
          selectedPresetId: viewModel.selectedImagePresetId,
          presets: presets,
          onChanged: viewModel.setSelectedImagePresetIdAndPersist,
          helperText: presets.isEmpty
              ? 'No prompt presets yet. Add them in Settings > Prompt presets.'
              : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: models.any((item) => item.id == selectedModelId)
              ? selectedModelId
              : null,
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
          items: models
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.label),
                ),
              )
              .toList(),
          onChanged: viewModel.setSelectedModel,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ImageOrientationSetting>(
          initialValue: viewModel.imageOrientation,
          decoration: const InputDecoration(
            labelText: 'Image orientation',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: ImageOrientationSetting.landscape,
              child: Text('Landscape'),
            ),
            DropdownMenuItem(
              value: ImageOrientationSetting.portrait,
              child: Text('Portrait'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              viewModel.setImageOrientation(value);
            }
          },
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(Icons.tune),
            title: const Text('LoRAs'),
            subtitle: Text(_selectedLoraSummary(context)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => LoraSelectionPage(viewModel: viewModel),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => unawaited(
            viewModel.generate(promptController.text),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            viewModel.hasImageSource
                ? 'Generate image from source'
                : 'Generate image',
          ),
        ),
      ],
    );
  }

  String _selectedLoraSummary(BuildContext context) {
    if (viewModel.loras.isEmpty) {
      return 'No LoRAs loaded yet.';
    }
    final selectedCount = viewModel.selectedLoraStrengths.length;
    if (selectedCount == 0) {
      return '${viewModel.loras.length} available';
    }
    return '$selectedCount selected';
  }
}

class _ImageSourceCard extends StatelessWidget {
  const _ImageSourceCard({required this.viewModel});

  final GenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final storedSource = viewModel.imageSource;
    final localSource = viewModel.imageLocalSource;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (storedSource != null || localSource != null)
              _SelectedImageSourcePreview(
                storedSource: storedSource,
                localSource: localSource,
                onClear: viewModel
                    .clearImageGenerationSource,
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openGenerationSourcePicker(
                  context,
                  viewModel: viewModel,
                  forVideo: false,
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Select source image (Optional)'),
              ),
            ),
            if (viewModel.hasImageSource) ...[
              const SizedBox(height: 12),
              Text(
                'Edit strength ${viewModel.imageToImageStrength.toStringAsFixed(2)}',
              ),
              Slider(
                value: viewModel.imageToImageStrength,
                min: 0.1,
                max: 0.9,
                divisions: 16,
                label: viewModel.imageToImageStrength
                    .toStringAsFixed(2),
                onChanged:
                    viewModel.setImageToImageStrength,
              ),
              Text(
                'Lower values keep the source image closer. '
                'Higher values follow your prompt more strongly. '
                'As a rule of thumb: 0.25-0.40 for subtle edits, '
                '0.50-0.70 for clear changes, 0.75+ for major redraws.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectedImageSourcePreview extends StatelessWidget {
  const _SelectedImageSourcePreview({
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
