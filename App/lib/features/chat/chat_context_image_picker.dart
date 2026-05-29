import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/chat/chat_time_formatters.dart';
import 'package:flutter_app/features/chat/chat_view_model.dart';

class ChatContextImagePicker extends StatefulWidget {
  const ChatContextImagePicker({
    super.key,
    required this.viewModel,
  });

  final ChatViewModel viewModel;

  @override
  State<ChatContextImagePicker> createState() => ChatContextImagePickerState();
}

class ChatContextImagePickerState extends State<ChatContextImagePicker> {
  static const int _pageSize = 60;

  late final TextEditingController _searchController;
  final List<ImageRecord> _images = <ImageRecord>[];
  final Set<String> _selectedImageIds = <String>{};
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
          Text(
            'Attach image context',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await widget.viewModel.pickImages(ImageSource.camera);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await widget.viewModel.pickImages(ImageSource.gallery);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Phone gallery'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedImageIds.isEmpty
                      ? 'Select one or more stored gallery images'
                      : '${_selectedImageIds.length} stored image(s) selected',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _selectedImageIds.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          _images
                              .where(
                                (item) => _selectedImageIds.contains(item.id),
                              )
                              .toList(),
                        );
                      },
                child: const Text('Attach selected'),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            Text(
              'Couldn\'t load gallery images.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
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
          final selected = _selectedImageIds.contains(image.id);
          return InkWell(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedImageIds.remove(image.id);
                } else {
                  _selectedImageIds.add(image.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(18),
            child: Card(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
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
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
                          compactChatTimeLabel(image.createdAt),
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
        _selectedImageIds.clear();
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
}
