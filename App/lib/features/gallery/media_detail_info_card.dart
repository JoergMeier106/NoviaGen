import 'package:flutter/material.dart';

import 'package:flutter_app/job_text.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/shared/app_formatters.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';

class MediaDetailInfoCard extends StatelessWidget {
  const MediaDetailInfoCard({
    super.key,
    required this.image,
    required this.sourceImageId,
    required this.sourceImage,
    required this.loadingSource,
    required this.sourceRelationshipLabel,
    required this.onOpenSource,
  });

  final ImageRecord image;
  final String sourceImageId;
  final ImageRecord? sourceImage;
  final bool loadingSource;
  final String sourceRelationshipLabel;
  final VoidCallback onOpenSource;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: InfoCard(
        title: 'Details',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailSection(
              icon: Icons.info_outline,
              title: 'Overview',
              child: _DetailFactGrid(facts: _overviewFacts()),
            ),
            const SizedBox(height: 16),
            _DetailSection(
              icon: Icons.tune,
              title: 'Generation',
              child: _DetailFactGrid(facts: _generationFacts()),
            ),
            if (image.caption.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _DetailTextSection(
                icon: Icons.notes,
                title: 'Caption',
                text: image.caption.trim(),
              ),
            ],
            if (sourceImageId.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSourceDetails(context),
            ],
            if (_hasPromptDetails) ...[
              const SizedBox(height: 16),
              _buildPromptDetails(context),
            ],
            if (image.isImage) ...[
              const SizedBox(height: 16),
              _buildLoraDetails(context),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasPromptDetails =>
      image.prompt.trim().isNotEmpty ||
      image.finalPositivePrompt.trim().isNotEmpty ||
      image.defaultNegativePrompt.trim().isNotEmpty;

  List<_DetailFact> _overviewFacts() {
    return [
      _DetailFact('Type', image.mediaTypeLabel),
      _DetailFact('Model', image.modelId),
      _DetailFact('Size', '${image.width} x ${image.height}'),
      _DetailFact('Orientation', sentenceCase(image.imageOrientation)),
      _DetailFact('Rating', '${image.rating}/5'),
      if (image.tags.isNotEmpty) _DetailFact('Tags', image.tags.join(', ')),
      if (image.scaleFactor != null)
        _DetailFact('Scale factor', '${image.scaleFactor}x'),
      if (image.isVideo && image.durationSeconds != null)
        _DetailFact('Duration', formatDurationLabel(image.durationSeconds)),
      if (image.generationDurationSeconds != null)
        _DetailFact(
          'Generation time',
          formatGenerationDurationLabel(image.generationDurationSeconds),
        ),
    ];
  }

  List<_DetailFact> _generationFacts() {
    return [
      _DetailFact('Inference steps', '${image.numInferenceSteps}'),
      _DetailFact('Guidance scale', image.guidanceScale.toStringAsFixed(1)),
      if (image.isVideo && image.fps != null)
        _DetailFact('FPS', '${image.fps}'),
      if (image.isVideo && image.numFrames != null)
        _DetailFact('Frames', '${image.numFrames}'),
    ];
  }

  Widget _buildSourceDetails(BuildContext context) {
    final source = sourceImage;
    return _DetailSection(
      icon: Icons.account_tree_outlined,
      title: sourceRelationshipLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailFactGrid(
            facts: [
              _DetailFact('Source ID', sourceImageId),
              if (source != null) ...[
                _DetailFact('Type', source.mediaTypeLabel),
                _DetailFact('Size', '${source.width} x ${source.height}'),
              ],
            ],
          ),
          if (source != null)
            ..._buildAvailableSourceDetails(source)
          else if (loadingSource)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Loading source media details...'),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Source media is no longer available.'),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildAvailableSourceDetails(ImageRecord source) {
    return [
      if (source.prompt.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        _DetailTextBlock(label: 'Source prompt', text: source.prompt.trim()),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: onOpenSource,
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open source details'),
      ),
    ];
  }

  Widget _buildPromptDetails(BuildContext context) {
    return _DetailSection(
      icon: Icons.subject,
      title: 'Prompts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.prompt.trim().isNotEmpty)
            _DetailTextBlock(label: 'Prompt', text: image.prompt.trim()),
          if (image.prompt.trim().isNotEmpty &&
              image.finalPositivePrompt.trim().isNotEmpty)
            const SizedBox(height: 12),
          if (image.finalPositivePrompt.trim().isNotEmpty)
            _DetailTextBlock(
              label: 'Final positive prompt',
              text: image.finalPositivePrompt.trim(),
            ),
          if ((image.prompt.trim().isNotEmpty ||
                  image.finalPositivePrompt.trim().isNotEmpty) &&
              image.defaultNegativePrompt.trim().isNotEmpty)
            const SizedBox(height: 12),
          if (image.defaultNegativePrompt.trim().isNotEmpty)
            _DetailTextBlock(
              label: 'Negative prompt',
              text: image.defaultNegativePrompt.trim(),
            ),
        ],
      ),
    );
  }

  Widget _buildLoraDetails(BuildContext context) {
    return _DetailSection(
      icon: Icons.layers_outlined,
      title: 'LoRAs',
      child: image.loras.isEmpty
          ? const Text('None')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in image.loras)
                  _LoraChip(
                    label: item.loraId,
                    strength: item.strength.toStringAsFixed(2),
                  ),
              ],
            ),
    );
  }
}

class _DetailFact {
  const _DetailFact(this.label, this.value);

  final String label;
  final String value;
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _DetailFactGrid extends StatelessWidget {
  const _DetailFactGrid({required this.facts});

  final List<_DetailFact> facts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= 360;
        final gap = twoColumn ? 10.0 : 8.0;
        final tileWidth = twoColumn
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final fact in facts)
              SizedBox(
                width: tileWidth,
                child: _DetailFactTile(fact: fact),
              ),
          ],
        );
      },
    );
  }
}

class _DetailFactTile extends StatelessWidget {
  const _DetailFactTile({required this.fact});

  final _DetailFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fact.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fact.value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTextSection extends StatelessWidget {
  const _DetailTextSection({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _DetailSection(
      icon: icon,
      title: title,
      child: _DetailTextBlock(label: title, text: text, showLabel: false),
    );
  }
}

class _DetailTextBlock extends StatelessWidget {
  const _DetailTextBlock({
    required this.label,
    required this.text,
    this.showLabel = true,
  });

  final String label;
  final String text;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabel) ...[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _LoraChip extends StatelessWidget {
  const _LoraChip({required this.label, required this.strength});

  final String label;
  final String strength;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.layers_outlined, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          '$label ($strength)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
