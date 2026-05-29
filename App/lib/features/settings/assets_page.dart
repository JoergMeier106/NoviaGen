import 'package:flutter/material.dart';

import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';

import 'package:flutter_app/features/settings/settings_view_model.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loaded && widget.viewModel.baseUrl.isNotEmpty) {
        _loaded = true;
        widget.viewModel.refreshAssets();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortedModels = widget.viewModel.modelsByRating;
    final sortedLoras = List<LoraAsset>.from(widget.viewModel.loras)
          ..sort((left, right) {
            final ratingCompare = right.rating.compareTo(left.rating);
            if (ratingCompare != 0) {
              return ratingCompare;
            }
            return left.label.toLowerCase().compareTo(
              right.label.toLowerCase(),
            );
          });
    return Scaffold(
          appBar: AppBar(
            title: const Text('Assets'),
            actions: [
              IconButton(
                onPressed: widget.viewModel.loadingAssets
                    ? null
                    : widget.viewModel.refreshAssets,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh assets',
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: widget.viewModel.refreshAssets,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.viewModel.loadingAssets &&
                    sortedModels.isEmpty &&
                    sortedLoras.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  InfoCard(
                    title: 'Models',
                    child: sortedModels.isEmpty
                        ? const Text('No models available.')
                        : Column(
                            children: sortedModels
                                .map(
                                  (model) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _AssetListTile(
                                      title: model.label,
                                      rating: model.rating,
                                      ratingCount: model.ratingCount,
                                      onDelete: () =>
                                          _confirmDeleteModel(context, model),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  InfoCard(
                    title: 'LoRAs',
                    child: sortedLoras.isEmpty
                        ? const Text('No LoRAs available.')
                        : Column(
                            children: sortedLoras
                                .map(
                                  (lora) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _AssetListTile(
                                      title: lora.label,
                                      subtitle:
                                          'Default strength ${lora.defaultStrength.toStringAsFixed(2)}',
                                      rating: lora.rating,
                                      ratingCount: lora.ratingCount,
                                      onDelete: () =>
                                          _confirmDeleteLora(context, lora),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ],
            ),
          ),
    );
  }

  Future<void> _confirmDeleteModel(
    BuildContext context,
    ModelAsset model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete model'),
        content: Text('Delete ${model.label}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    await widget.viewModel.deleteModel(model.id);
    final message = widget.viewModel.message;
    if (context.mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmDeleteLora(BuildContext context, LoraAsset lora) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete LoRA'),
        content: Text('Delete ${lora.label}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    await widget.viewModel.deleteLora(lora.id);
    final message = widget.viewModel.message;
    if (context.mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _AssetListTile extends StatelessWidget {
  const _AssetListTile({
    required this.title,
    required this.rating,
    required this.ratingCount,
    required this.onDelete,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final double rating;
  final int ratingCount;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            _AssetRatingSummary(rating: rating, ratingCount: ratingCount),
          ],
        ),
      ),
    );
  }
}

class _AssetRatingSummary extends StatelessWidget {
  const _AssetRatingSummary({required this.rating, required this.ratingCount});

  final double rating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRating = ratingCount > 0 && rating > 0;
    final activeColor = theme.colorScheme.secondary;
    final inactiveColor = theme.colorScheme.outlineVariant;

    return Row(
      children: [
        for (var index = 0; index < 5; index++)
          Padding(
            padding: EdgeInsets.only(right: index == 4 ? 0 : 2),
            child: Icon(
              hasRating && rating >= index + 1
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              size: 18,
              color: hasRating ? activeColor : inactiveColor,
            ),
          ),
        if (hasRating) ...[
          const SizedBox(width: 8),
          Text('$ratingCount', style: theme.textTheme.titleSmall),
        ],
      ],
    );
  }
}
