import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/shared/media_preview.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';
import 'package:flutter_app/features/gallery/fullscreen_media_page.dart';
import 'package:flutter_app/features/gallery/media_detail_actions.dart';
import 'package:flutter_app/features/gallery/media_detail_info_card.dart';
import 'package:flutter_app/features/gallery/media_tag_editor.dart';
import 'package:flutter_app/features/gallery/gallery_picker_sheets.dart';

import 'package:provider/provider.dart';
import 'package:flutter_app/features/gallery/gallery_view_model.dart';

class MediaDetailPage extends StatelessWidget {
  const MediaDetailPage({
    super.key,
    required this.images,
    required this.initialIndex,
    this.useLiveGallery = false,
  });

  final List<ImageRecord> images;
  final int initialIndex;
  final bool useLiveGallery;

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryViewModel>(
      builder: (context, viewModel, _) => _MediaDetailPageBody(
        viewModel: viewModel,
        images: images,
        initialIndex: initialIndex,
        useLiveGallery: useLiveGallery,
      ),
    );
  }
}

class ImageDetailPage extends MediaDetailPage {
  const ImageDetailPage({
    super.key,
    required super.images,
    required super.initialIndex,
    super.useLiveGallery,
  });
}

class _MediaDetailPageBody extends StatefulWidget {
  const _MediaDetailPageBody({
    required this.viewModel,
    required this.images,
    required this.initialIndex,
    required this.useLiveGallery,
  });

  final GalleryViewModel viewModel;
  final List<ImageRecord> images;
  final int initialIndex;
  final bool useLiveGallery;

  @override
  State<_MediaDetailPageBody> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<_MediaDetailPageBody> {
  static const int _galleryPagePrefetchThreshold = 6;

  late final PageController _pageController;
  late final List<String> _pageImageIds;
  late int _currentIndex;
  final Map<String, ImageRecord?> _sourceImageCache = <String, ImageRecord?>{};
  final Set<String> _loadingSourceImageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _pageImageIds = [for (final image in widget.images) image.id];
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadMoreGalleryItems(_currentIndex);
      unawaited(_ensureSourceLoadedForCurrentImage());
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _ensureSourceLoadedForCurrentImage() async {
    await _ensureSourceLoadedFor(_currentImage());
  }

  List<ImageRecord> get _pageImages {
    if (!widget.useLiveGallery) {
      return widget.images;
    }
    _appendNewLiveGalleryIds();
    if (_pageImageIds.isEmpty) {
      return widget.images;
    }
    return [
      for (final id in _pageImageIds)
        if (_knownImageForId(id) != null) _knownImageForId(id)!,
    ];
  }

  void _appendNewLiveGalleryIds() {
    final knownIds = _pageImageIds.toSet();
    for (final image in widget.viewModel.gallery) {
      if (knownIds.add(image.id)) {
        _pageImageIds.add(image.id);
      }
    }
  }

  int _safeIndexFor(List<ImageRecord> images, int index) {
    if (images.isEmpty) {
      return 0;
    }
    return index.clamp(0, images.length - 1).toInt();
  }

  void _maybeLoadMoreGalleryItems(int index) {
    if (!widget.useLiveGallery || !widget.viewModel.hasMore) {
      return;
    }
    final images = _pageImages;
    if (images.isEmpty ||
        index < images.length - _galleryPagePrefetchThreshold) {
      return;
    }
    unawaited(widget.viewModel.loadGalleryNextPage());
  }

  Future<void> _ensureSourceLoadedFor(ImageRecord image) async {
    final sourceImageId = image.sourceImageId?.trim() ?? '';
    if (sourceImageId.isEmpty || !image.sourceImageExists) {
      return;
    }
    final known = widget.viewModel.findKnownMediaById(sourceImageId);
    if (known != null) {
      if (_sourceImageCache[sourceImageId]?.id != known.id && mounted) {
        setState(() {
          _sourceImageCache[sourceImageId] = known;
        });
      } else {
        _sourceImageCache[sourceImageId] = known;
      }
      return;
    }
    if (_loadingSourceImageIds.contains(sourceImageId) ||
        _sourceImageCache.containsKey(sourceImageId)) {
      return;
    }
    if (mounted) {
      setState(() {
        _loadingSourceImageIds.add(sourceImageId);
      });
    } else {
      _loadingSourceImageIds.add(sourceImageId);
    }
    final fetched = await widget.viewModel.fetchImageById(sourceImageId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingSourceImageIds.remove(sourceImageId);
      _sourceImageCache[sourceImageId] = fetched;
    });
  }

  ImageRecord? _sourceImageFor(ImageRecord image) {
    final sourceImageId = image.sourceImageId?.trim() ?? '';
    if (sourceImageId.isEmpty || !image.sourceImageExists) {
      return null;
    }
    return widget.viewModel.findKnownMediaById(sourceImageId) ??
        _sourceImageCache[sourceImageId];
  }

  bool _isLoadingSourceFor(ImageRecord image) {
    final sourceImageId = image.sourceImageId?.trim() ?? '';
    if (sourceImageId.isEmpty || !image.sourceImageExists) {
      return false;
    }
    return _loadingSourceImageIds.contains(sourceImageId);
  }

  String _sourceRelationshipLabel(ImageRecord image, ImageRecord? sourceImage) {
    if (image.isUpscaled) {
      return image.isVideo
          ? 'Scaled from source video'
          : 'Scaled from source image';
    }
    if (image.isVideo) {
      return 'Generated from source image';
    }
    if (image.isGif) {
      return 'Converted from source video';
    }
    if (sourceImage?.isVideo == true) {
      return 'Derived from source video';
    }
    return 'Derived from source image';
  }

  Future<void> _openSourceDetails(ImageRecord sourceImage) async {
    final galleryImages = <ImageRecord>[...widget.viewModel.gallery];
    final sourceIndex = galleryImages.indexWhere(
      (item) => item.id == sourceImage.id,
    );
    final images = sourceIndex >= 0
        ? galleryImages
        : <ImageRecord>[sourceImage];
    final initialIndex = sourceIndex >= 0 ? sourceIndex : 0;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MediaDetailPage(
          images: images,
          initialIndex: initialIndex,
          useLiveGallery: sourceIndex >= 0,
        ),
      ),
    );
  }

  Future<void> _deleteCurrentImage(ImageRecord currentImage) async {
    final deletedMessage = await widget.viewModel.deleteStoredImage(
      currentImage.id,
    );
    if (!mounted) {
      return;
    }
    if (deletedMessage != null) {
      final remainingImages = widget.viewModel.showDeleted
          ? <ImageRecord>[...widget.viewModel.gallery]
          : [
              for (final item in _pageImages)
                if (item.id != currentImage.id) _imageForId(item.id),
            ];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(deletedMessage)));
      if (remainingImages.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      final deletedIndex = remainingImages.indexWhere(
        (item) => item.id == currentImage.id,
      );
      final nextIndex = deletedIndex >= 0
          ? deletedIndex
          : _currentIndex >= remainingImages.length
          ? remainingImages.length - 1
          : _currentIndex;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => MediaDetailPage(
            images: remainingImages,
            initialIndex: nextIndex,
            useLiveGallery: widget.useLiveGallery,
          ),
        ),
      );
      return;
    }
    _showStateMessage();
  }

  Future<void> _restoreCurrentImage(ImageRecord currentImage) async {
    final restoredMessage = await widget.viewModel.restoreDeletedImage(
      currentImage.id,
    );
    if (!mounted) {
      return;
    }
    if (restoredMessage != null) {
      final remainingImages = widget.viewModel.showDeleted
          ? <ImageRecord>[...widget.viewModel.gallery]
          : [
              for (final item in _pageImages)
                if (item.id != currentImage.id) _imageForId(item.id),
            ];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(restoredMessage)));
      if (widget.viewModel.showDeleted) {
        if (remainingImages.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        final nextIndex = _currentIndex >= remainingImages.length
            ? remainingImages.length - 1
            : _currentIndex;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => MediaDetailPage(
              images: remainingImages,
              initialIndex: nextIndex,
              useLiveGallery: widget.useLiveGallery,
            ),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
      return;
    }
    _showStateMessage();
  }

  Future<void> _openFullscreen(List<ImageRecord> pageImages) async {
    final selectedImageId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => FullscreenMediaPage(
          images: [for (final item in pageImages) _imageForId(item.id)],
          initialIndex: _currentIndex,
          useLiveGallery: widget.useLiveGallery,
        ),
      ),
    );
    if (!mounted || selectedImageId == null) {
      return;
    }
    _jumpToImage(selectedImageId);
  }

  void _jumpToImage(String imageId) {
    final selectedIndex = _pageImages.indexWhere((item) => item.id == imageId);
    if (selectedIndex < 0 || selectedIndex == _currentIndex) {
      return;
    }
    _pageController.jumpToPage(selectedIndex);
    setState(() {
      _currentIndex = selectedIndex;
    });
    unawaited(_ensureSourceLoadedForCurrentImage());
  }

  Future<void> _downloadImage(ImageRecord image) async {
    final savedPath = await widget.viewModel.downloadStoredImage(image);
    if (!mounted) {
      return;
    }
    if (savedPath != null) {
      _showSnackBar('${image.mediaTypeLabel} downloaded to $savedPath');
      return;
    }
    _showStateMessage();
  }

  Future<void> _regenerateImage(ImageRecord image) async {
    final regeneratedImage = image.isVideo
        ? await widget.viewModel.regenerateVideo(image)
        : await widget.viewModel.regenerateImage(image);
    if (!mounted) {
      return;
    }
    if (regeneratedImage != null) {
      _showSnackBar(
        image.isVideo
            ? 'Video regeneration added to the queue.'
            : 'Image regeneration added to the queue.',
      );
      return;
    }
    _showStateMessage();
  }

  Future<void> _scaleImage(ImageRecord image) async {
    final scaleFactor = await showGalleryScaleFactorPicker(context, [image]);
    if (!mounted || scaleFactor == null) {
      return;
    }
    final upscaledImage = await widget.viewModel.upscaleImage(
      image,
      scaleFactor,
    );
    if (!mounted) {
      return;
    }
    if (upscaledImage != null) {
      _showSnackBar('Scaling job added to the queue.');
      return;
    }
    _showStateMessage();
  }

  Future<void> _generateAudioVideo(ImageRecord image) async {
    final generatedImage = await widget.viewModel.generateAudioVideo(image);
    if (!mounted) {
      return;
    }
    if (generatedImage != null) {
      _showSnackBar('Audio video generation added to the queue.');
      return;
    }
    _showStateMessage();
  }

  Future<void> _convertVideoToGif(ImageRecord image) async {
    final convertedImage = await widget.viewModel.convertVideoToGif(image);
    if (!mounted) {
      return;
    }
    if (convertedImage != null) {
      _showSnackBar('GIF conversion added to the queue.');
      return;
    }
    _showStateMessage();
  }

  Future<void> _cancelJob(JobStatus job) async {
    await widget.viewModel.cancelJob(job.jobId);
    if (!mounted) {
      return;
    }
    _showStateMessage();
  }

  void _useAsImageSource(ImageRecord image) {
    widget.viewModel.attachStoredImageForGeneration(image);
    Navigator.of(context).pop();
  }

  void _createVideoFromImage(ImageRecord image) {
    widget.viewModel.attachStoredImageForVideoGeneration(image);
    Navigator.of(context).pop();
  }

  Future<void> _createPromptAndVideo(ImageRecord image) async {
    final queuedImage = await widget.viewModel.createPromptAndAnimateImage(
      image,
    );
    if (!mounted) {
      return;
    }
    if (queuedImage != null) {
      _showSnackBar('Prompt + video generation workflow added to the queue.');
      return;
    }
    _showStateMessage();
  }

  void _showStateMessage() {
    final message = widget.viewModel.message;
    if (message != null) {
      _showSnackBar(message);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pageImages = _pageImages;
    final currentIndex = _safeIndexFor(pageImages, _currentIndex);
    final currentImage = _currentImage();
    final currentJob = currentImage.isPending
        ? widget.viewModel.jobForImage(currentImage.id)
        : null;
    final sourceImageId = currentImage.sourceImageId?.trim() ?? '';
    final sourceImage = _sourceImageFor(currentImage);
    final loadingSource = _isLoadingSourceFor(currentImage);
    return Scaffold(
      appBar: AppBar(title: Text('${currentIndex + 1} / ${pageImages.length}')),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: pageImages.length,
              onPageChanged: (value) {
                setState(() {
                  _currentIndex = value;
                });
                _maybeLoadMoreGalleryItems(value);
                unawaited(_ensureSourceLoadedForCurrentImage());
              },
              itemBuilder: (context, index) {
                final image = _imageForIndex(index);
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: image.width / image.height,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: mediaPrimaryPreview(
                              image,
                              fit: BoxFit.contain,
                            ),
                          ),
                          if (image.canPreviewFile)
                            Positioned(
                              right: 12,
                              top: 12,
                              child: MediaFullscreenButton(
                                onPressed: () => _openFullscreen(pageImages),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                MediaDetailActionBar(
                  image: currentImage,
                  currentJob: currentJob,
                  onDownload: currentImage.canDownload
                      ? () => _downloadImage(currentImage)
                      : null,
                  onRegenerate: () => _regenerateImage(currentImage),
                  onScale: () => _scaleImage(currentImage),
                  onGenerateAudioVideo: () => _generateAudioVideo(currentImage),
                  onConvertToGif: () => _convertVideoToGif(currentImage),
                  onCancelJob: currentJob == null
                      ? null
                      : () => _cancelJob(currentJob),
                  onUseAsImageSource: () => _useAsImageSource(currentImage),
                  onCreateVideo: () => _createVideoFromImage(currentImage),
                  onCreatePromptAndVideo:
                      currentImage.isStillImage && currentImage.isReady
                      ? () => _createPromptAndVideo(currentImage)
                      : null,
                  onRestore: () => _restoreCurrentImage(currentImage),
                  onDelete: currentImage.isPending
                      ? null
                      : () => _deleteCurrentImage(currentImage),
                ),
                const SizedBox(height: 12),
                RatingBar(
                  rating: currentImage.rating,
                  onChanged: (value) =>
                      widget.viewModel.setImageRating(currentImage.id, value),
                ),
                const SizedBox(height: 16),
                MediaTagEditor(
                  image: currentImage,
                  suggestedTags: widget.viewModel.suggestedTags,
                  onChanged: (tags) =>
                      widget.viewModel.setImageTags(currentImage.id, tags),
                  onDeleteTag: widget.viewModel.deleteTag,
                  onGenerateTags: currentImage.isStillImage
                      ? () =>
                            widget.viewModel.generateImageTags(currentImage.id)
                      : null,
                ),
                const SizedBox(height: 16),
                MediaDetailInfoCard(
                  image: currentImage,
                  sourceImageId: sourceImageId,
                  sourceImage: sourceImage,
                  loadingSource: loadingSource,
                  sourceRelationshipLabel: _sourceRelationshipLabel(
                    currentImage,
                    sourceImage,
                  ),
                  onOpenSource: sourceImage == null
                      ? () {}
                      : () => _openSourceDetails(sourceImage),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ImageRecord _currentImage() => _imageForIndex(_currentIndex);

  ImageRecord _imageForIndex(int index) {
    final images = _pageImages;
    final baseImage = images[_safeIndexFor(images, index)];
    return _knownImageForId(baseImage.id) ?? baseImage;
  }

  ImageRecord? _knownImageForId(String id) {
    for (final item in widget.viewModel.gallery) {
      if (item.id == id) {
        return item;
      }
    }
    final fallback = widget.images.where((item) => item.id == id);
    if (fallback.isNotEmpty) {
      return fallback.first;
    }
    return null;
  }

  ImageRecord _imageForId(String id) {
    return _knownImageForId(id) ?? _pageImages.first;
  }
}
