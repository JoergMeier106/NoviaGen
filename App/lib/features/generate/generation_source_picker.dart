import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/generate/generation_view_model.dart';
import 'package:flutter_app/shared/request_errors.dart';

Future<void> openGenerationSourcePicker(
  BuildContext context, {
  required GenerationViewModel viewModel,
  required bool forVideo,
}) async {
  final selected = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _GenerationSourcePickerSheet(
        viewModel: viewModel,
        forVideo: forVideo,
      ),
    ),
  );
  if (selected is ImageRecord) {
    await viewModel.attachStoredGenerationSource(selected, forVideo: forVideo);
  } else if (selected is LocalImageSource) {
    await viewModel.attachLocalGenerationSource(
      path: selected.path,
      name: selected.name,
      forVideo: forVideo,
    );
  }
}

class _GenerationSourcePickerSheet extends StatefulWidget {
  const _GenerationSourcePickerSheet({
    required this.viewModel,
    required this.forVideo,
  });

  final GenerationViewModel viewModel;
  final bool forVideo;

  @override
  State<_GenerationSourcePickerSheet> createState() =>
      _GenerationSourcePickerSheetState();
}

class _GenerationSourcePickerSheetState
    extends State<_GenerationSourcePickerSheet> {
  static const int _pageSize = 60;

  final LocalImagePicker _localImagePicker = const LocalImagePicker();
  late final TextEditingController _searchController;
  final List<ImageRecord> _images = <ImageRecord>[];
  bool _loadingInitial = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    unawaited(_loadImages(reset: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.forVideo
        ? 'Select video source image'
        : 'Select source image';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _pickLocalSource(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _pickLocalSource(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Phone gallery'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Or use a stored gallery image',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search prompt text',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
            onSubmitted: (_) => _reload(),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildGalleryGrid(context)),
        ],
      ),
    );
  }

  Widget _buildGalleryGrid(BuildContext context) {
    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Couldn\'t load gallery images.'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_images.isEmpty) {
      return const Center(child: Text('No attachable gallery images found.'));
    }
    final itemCount = _images.length + (_hasMore || _loadingMore ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 320) {
          unawaited(_loadImages());
        }
        return false;
      },
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= _images.length) {
            if (_loadError != null) {
              return Card(
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => unawaited(_loadImages()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              );
            }
            return const Card(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final image = _images[index];
          return InkWell(
            onTap: () => Navigator.of(context).pop(image),
            borderRadius: BorderRadius.circular(18),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Image.network(
                      image.previewUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          image.prompt.isEmpty
                              ? image.mediaTypeLabel
                              : image.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          image.createdAt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadImages({bool reset = false}) async {
    if (_loadingInitial || _loadingMore) {
      return;
    }
    final pageToLoad = reset ? 1 : _nextPage;
    if (!reset && !_hasMore) {
      return;
    }
    setState(() {
      if (reset) {
        _loadingInitial = true;
        _images.clear();
        _hasMore = true;
        _nextPage = 1;
      } else {
        _loadingMore = true;
      }
      _loadError = null;
    });
    try {
      final response = await widget.viewModel.fetchAttachableGalleryImagesPage(
        search: _searchController.text.trim(),
        page: pageToLoad,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      final existingIds = _images.map((item) => item.id).toSet();
      final nextItems = response.items
          .where((item) => !existingIds.contains(item.id))
          .toList();
      setState(() {
        _images.addAll(nextItems);
        _hasMore = response.hasMore;
        _nextPage = response.page + 1;
        _loadingInitial = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loadingInitial = false;
        _loadingMore = false;
      });
    }
  }

  void _reload() {
    unawaited(_loadImages(reset: true));
  }

  Future<void> _pickLocalSource(ImageSource source) async {
    try {
      final localSource = await _localImagePicker.pick(source);
      if (!mounted || localSource == null) {
        return;
      }
      Navigator.of(context).pop(localSource);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _localImagePickerErrorMessage(error);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

String _localImagePickerErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'no_valid_image_uri') {
    return 'Android couldn\'t access the selected image. Try picking it again or choose a different image.';
  }
  return requestErrorMessage(
    error,
    generalMessage: 'Couldn\'t load the selected image. Please try again.',
  );
}

class LocalImagePicker {
  const LocalImagePicker();

  Future<LocalImageSource?> pick(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null) {
      return null;
    }
    return LocalImageSource(path: picked.path, name: picked.name);
  }
}
