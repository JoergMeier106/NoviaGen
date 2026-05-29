import 'dart:async';

import 'package:flutter/material.dart';

import 'package:noviagen/media_video_player.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/gallery/fullscreen_system_ui.dart';
import 'package:noviagen/features/gallery/fullscreen_media_widgets.dart';

import 'package:provider/provider.dart';
import 'package:noviagen/features/gallery/gallery_view_model.dart';

class FullscreenMediaPage extends StatelessWidget {
  const FullscreenMediaPage({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.useLiveGallery = false,
  });

  final List<ImageRecord> images;
  final int initialIndex;
  final bool useLiveGallery;

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryViewModel>(
      builder: (context, viewModel, _) => _FullscreenMediaPageBody(
        viewModel: viewModel,
        images: images,
        initialIndex: initialIndex,
        useLiveGallery: useLiveGallery,
      ),
    );
  }
}

class FullscreenImagePage extends FullscreenMediaPage {
  const FullscreenImagePage({
    super.key,
    required super.images,
    super.initialIndex,
    super.useLiveGallery,
  });
}

class _FullscreenMediaPageBody extends StatefulWidget {
  const _FullscreenMediaPageBody({
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
  State<_FullscreenMediaPageBody> createState() => _FullscreenMediaPageState();
}

class _FullscreenMediaPageState extends State<_FullscreenMediaPageBody>
    with WidgetsBindingObserver {
  static const int _galleryPagePrefetchThreshold = 6;

  late final PageController _pageController;
  late final List<String> _pageImageIds;
  late int _currentIndex;
  final Map<int, TransformationController> _transformationControllers =
      <int, TransformationController>{};
  final Map<String, MediaVideoPlaybackController> _videoPlaybackControllers =
      <String, MediaVideoPlaybackController>{};
  final MediaVideoPlaybackController _sourcePreviewVideoPlaybackController =
      MediaVideoPlaybackController();
  final Map<String, ImageRecord?> _sourceImageCache = <String, ImageRecord?>{};
  final Set<String> _loadingSourceImageIds = <String>{};
  final FullscreenSystemUi _systemUi = FullscreenSystemUi();
  Timer? _slideshowTimer;
  Timer? _metricsDebounce;
  int _pageCorrectionToken = 0;
  bool _pageSwipeEnabled = true;
  bool _interfaceVisible = true;
  bool _slideshowRunning = false;
  bool _showingSourcePreview = false;
  bool _sourcePreviewDisplayReady = false;
  Duration? _sourcePreviewEntryPosition;
  bool? _sourcePreviewEntryWasPlaying;
  TapDownDetails? _doubleTapDetails;
  int? _pendingPageIndex;
  int _sourcePreviewToggleToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageImageIds = [for (final image in widget.images) image.id];
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadMoreGalleryItems(_currentIndex);
      _enterFullscreenForCurrentImage();
      unawaited(_ensureSourceLoadedForCurrentImage());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slideshowTimer?.cancel();
    _metricsDebounce?.cancel();
    for (final controller in _transformationControllers.values) {
      controller.dispose();
    }
    for (final controller in _videoPlaybackControllers.values) {
      controller.dispose();
    }
    _sourcePreviewVideoPlaybackController.dispose();
    _pageController.dispose();
    _systemUi.restore();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _metricsDebounce?.cancel();
    _metricsDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      final targetIndex = _pendingPageIndex ?? _currentIndex;
      unawaited(_enterFullscreenForIndex(targetIndex));
      _schedulePageCorrection(targetIndex);
      _updatePageSwipeState();
      _restartSlideshowTimer();
    });
  }

  Future<void> _enterFullscreenForCurrentImage() async {
    return _enterFullscreenForIndex(_pendingPageIndex ?? _currentIndex);
  }

  Future<void> _enterFullscreenForIndex(int index) async {
    await _systemUi.enterForMedia(
      _imageForIndex(index),
      pageIndex: index,
      schedulePageCorrection: _schedulePageCorrection,
    );
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

  ImageRecord? _sourcePreviewImageForCurrent() {
    final sourceImage = _sourceImageFor(_currentImage());
    if (sourceImage == null || !sourceImage.canPreviewFile) {
      return null;
    }
    return sourceImage;
  }

  MediaVideoPlaybackController _videoPlaybackControllerForImage(
    ImageRecord image,
  ) {
    return _videoPlaybackControllers.putIfAbsent(
      image.id,
      () => MediaVideoPlaybackController(),
    );
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _setSourcePreviewVisible(bool value) async {
    final currentImage = _currentImage();
    final sourcePreviewImage = _sourcePreviewImageForCurrent();
    if (value && sourcePreviewImage == null) {
      return;
    }
    final toggleToken = ++_sourcePreviewToggleToken;
    final canSynchronizePlayback =
        currentImage.isVideo && sourcePreviewImage?.isVideo == true;
    if (!canSynchronizePlayback) {
      if (_showingSourcePreview == value &&
          (!value || _sourcePreviewDisplayReady)) {
        return;
      }
      if (mounted) {
        setState(() {
          _sourcePreviewDisplayReady = value;
          _showingSourcePreview = value;
        });
      } else {
        _sourcePreviewDisplayReady = value;
        _showingSourcePreview = value;
      }
      return;
    }

    if (value) {
      _stopSlideshow();
    }

    final currentPlaybackController = _videoPlaybackControllerForImage(
      currentImage,
    );

    if (value) {
      final currentPosition = currentPlaybackController.position;
      final wasPlaying = currentPlaybackController.isPlaying;
      _sourcePreviewEntryPosition = currentPosition;
      _sourcePreviewEntryWasPlaying = wasPlaying;
      if (mounted) {
        setState(() {
          _sourcePreviewDisplayReady = false;
        });
      } else {
        _sourcePreviewDisplayReady = false;
      }
      await currentPlaybackController.pause();
      final sourceReady = await _sourcePreviewVideoPlaybackController
          .waitUntilInitialized();
      if (toggleToken != _sourcePreviewToggleToken) {
        return;
      }
      if (!sourceReady) {
        if (wasPlaying) {
          await currentPlaybackController.play();
        } else {
          await currentPlaybackController.pause();
        }
        return;
      }
      await _sourcePreviewVideoPlaybackController.pause();
      await _sourcePreviewVideoPlaybackController.seekTo(currentPosition);
      await _waitForNextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (toggleToken != _sourcePreviewToggleToken) {
        return;
      }
      if (mounted) {
        setState(() {
          _sourcePreviewDisplayReady = true;
          _showingSourcePreview = true;
        });
      } else {
        _sourcePreviewDisplayReady = true;
        _showingSourcePreview = true;
      }
      if (wasPlaying) {
        await _sourcePreviewVideoPlaybackController.play();
      } else {
        await _sourcePreviewVideoPlaybackController.pause();
      }
      return;
    }

    final sourceReady = await _sourcePreviewVideoPlaybackController
        .waitUntilInitialized(timeout: Duration.zero);
    final resumePosition = sourceReady
        ? _sourcePreviewVideoPlaybackController.position
        : (_sourcePreviewEntryPosition ?? currentPlaybackController.position);
    final resumePlaying = sourceReady
        ? _sourcePreviewVideoPlaybackController.isPlaying
        : (_sourcePreviewEntryWasPlaying ??
              currentPlaybackController.isPlaying);
    await _sourcePreviewVideoPlaybackController.pause();
    final currentReady = await currentPlaybackController.waitUntilInitialized();
    if (toggleToken != _sourcePreviewToggleToken) {
      return;
    }
    if (currentReady) {
      await currentPlaybackController.seekTo(resumePosition);
      await _waitForNextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (resumePlaying) {
        await currentPlaybackController.play();
      } else {
        await currentPlaybackController.pause();
      }
    }
    if (mounted) {
      setState(() {
        _sourcePreviewDisplayReady = false;
        _showingSourcePreview = false;
      });
    } else {
      _sourcePreviewDisplayReady = false;
      _showingSourcePreview = false;
    }
    _sourcePreviewEntryPosition = null;
    _sourcePreviewEntryWasPlaying = null;
  }

  Widget _buildFullscreenMediaItem(
    ImageRecord image,
    int index, {
    bool showControls = true,
    bool initiallyMuted = false,
    bool autoplay = true,
    bool enableZoom = true,
    bool interactiveZoom = true,
    TransformationController? transformationControllerOverride,
    MediaVideoPlaybackController? playbackController,
  }) {
    final transformationController =
        transformationControllerOverride ??
        (enableZoom ? _controllerForIndex(index) : null);
    return FullscreenMediaFrame(
      image: image,
      showControls: showControls,
      initiallyMuted: initiallyMuted,
      autoplay: autoplay,
      interactiveZoom: interactiveZoom,
      transformationController: transformationController,
      playbackController: playbackController,
      onToggleInterface: _toggleInterfaceVisibility,
      onDoubleTapDown: (details) {
        _doubleTapDetails = details;
      },
      onDoubleTap: () => _toggleDoubleTapZoom(index),
      onInteractionEnd: interactiveZoom ? (_) => _updatePageSwipeState() : null,
    );
  }

  void _toggleInterfaceVisibility() {
    setState(() {
      _interfaceVisible = !_interfaceVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageImages = _pageImages;
    final currentImage = _currentImage();
    final sourcePreviewImage = _sourcePreviewImageForCurrent();
    final showSourcePreviewButton = sourcePreviewImage != null;
    return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              return;
            }
            Navigator.of(context).pop(currentImage.id);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final viewportSize = constraints.biggest;
                final viewPadding = MediaQuery.of(context).viewPadding;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _pageSwipeEnabled
                            ? const PageScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        itemCount: pageImages.length,
                        onPageChanged: _handlePageChanged,
                        itemBuilder: (context, index) =>
                            _buildFullscreenPage(index),
                      ),
                    ),
                    if (_interfaceVisible)
                      FullscreenTopOverlay(
                        topPadding: viewPadding.top,
                        counterLabel: _counterLabel(pageImages),
                        showCounter: pageImages.length > 1,
                        showSourcePreview: _showingSourcePreview,
                        canStartSlideshow: pageImages.length > 1,
                        slideshowRunning: _slideshowRunning,
                        onToggleSlideshow: _toggleSlideshow,
                        onClose: () => _closeFullscreen(currentImage),
                      ),
                    if (_interfaceVisible && showSourcePreviewButton)
                      FullscreenSourcePreviewOverlay(
                        currentImage: currentImage,
                        viewportSize: viewportSize,
                        viewPadding: viewPadding,
                        interfaceVisible: _interfaceVisible,
                        showingSourcePreview: _showingSourcePreview,
                        onPressedStateChanged: _setSourcePreviewVisible,
                      ),
                  ],
                );
              },
            ),
          ),
    );
  }

  void _handlePageChanged(int value) {
    final visibleIndex = _visiblePageIndex();
    final pendingPageIndex = _pendingPageIndex;
    if (pendingPageIndex != null && value != pendingPageIndex) {
      return;
    }
    if (visibleIndex != null && visibleIndex != value) {
      return;
    }
    setState(() {
      _currentIndex = value;
      _showingSourcePreview = false;
      _sourcePreviewEntryPosition = null;
      _sourcePreviewEntryWasPlaying = null;
      if (pendingPageIndex == value) {
        _pendingPageIndex = null;
      }
    });
    _maybeLoadMoreGalleryItems(value);
    _sourcePreviewToggleToken++;
    unawaited(_sourcePreviewVideoPlaybackController.pause());
    _updatePageSwipeState();
    _restartSlideshowTimer();
    unawaited(_enterFullscreenForCurrentImage());
    unawaited(_ensureSourceLoadedForCurrentImage());
  }

  Widget _buildFullscreenPage(int index) {
    final image = _imageForIndex(index);
    final isCurrentPage = index == _currentIndex;
    final sourceOverlayImage = isCurrentPage
        ? _sourcePreviewImageForCurrent()
        : null;
    final showSourceOverlay =
        _showingSourcePreview && _sourcePreviewDisplayReady && isCurrentPage;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildFullscreenMediaItem(
          image,
          index,
          showControls: _interfaceVisible,
          playbackController: image.isVideo
              ? _videoPlaybackControllerForImage(image)
              : null,
        ),
        if (sourceOverlayImage != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showSourceOverlay,
              child: Visibility(
                visible: showSourceOverlay,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: _buildSourcePreviewOverlay(sourceOverlayImage, index),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSourcePreviewOverlay(ImageRecord sourceOverlayImage, int index) {
    return _buildFullscreenMediaItem(
      sourceOverlayImage,
      index,
      showControls: false,
      initiallyMuted: true,
      autoplay: false,
      enableZoom: true,
      interactiveZoom: false,
      transformationControllerOverride: _controllerForIndex(index),
      playbackController: sourceOverlayImage.isVideo
          ? _sourcePreviewVideoPlaybackController
          : null,
    );
  }

  String _counterLabel(List<ImageRecord> pageImages) {
    final visibleIndex = _safeIndexFor(pageImages, _currentIndex) + 1;
    return '$visibleIndex / ${pageImages.length}';
  }

  void _closeFullscreen(ImageRecord currentImage) {
    Navigator.of(context).pop(currentImage.id);
  }

  TransformationController _controllerForIndex(int index) {
    return _transformationControllers.putIfAbsent(index, () {
      final controller = TransformationController();
      controller.addListener(() {
        if (index == _currentIndex) {
          _updatePageSwipeState();
        }
      });
      return controller;
    });
  }

  void _updatePageSwipeState() {
    final currentController = _transformationControllers[_currentIndex];
    final scale = currentController?.value.getMaxScaleOnAxis() ?? 1.0;
    final shouldEnableSwipe = scale <= 1.01;
    if (_pageSwipeEnabled != shouldEnableSwipe && mounted) {
      setState(() {
        _pageSwipeEnabled = shouldEnableSwipe;
      });
    }
  }

  ImageRecord _currentImage() {
    final images = _pageImages;
    final currentId = images[_safeIndexFor(images, _currentIndex)].id;
    return _knownImageForId(currentId) ??
        images[_safeIndexFor(images, _currentIndex)];
  }

  ImageRecord _imageForIndex(int index) {
    final images = _pageImages;
    final imageId = images[_safeIndexFor(images, index)].id;
    return _knownImageForId(imageId) ?? images[_safeIndexFor(images, index)];
  }

  ImageRecord? _knownImageForId(String imageId) {
    for (final image in widget.viewModel.gallery) {
      if (image.id == imageId) {
        return image;
      }
    }
    final fallback = widget.images.where((image) => image.id == imageId);
    if (fallback.isNotEmpty) {
      return fallback.first;
    }
    return null;
  }

  void _toggleDoubleTapZoom(int index) {
    final controller = _controllerForIndex(index);
    final currentScale = controller.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      controller.value = Matrix4.identity();
      _updatePageSwipeState();
      return;
    }

    final tapPosition = _doubleTapDetails?.localPosition;
    const targetScale = 2.5;
    if (tapPosition == null) {
      controller.value = Matrix4.identity()
        ..scaleByDouble(targetScale, targetScale, 1, 1);
      _updatePageSwipeState();
      return;
    }

    controller.value = Matrix4.identity()
      ..translateByDouble(
        -tapPosition.dx * (targetScale - 1),
        -tapPosition.dy * (targetScale - 1),
        0,
        1,
      )
      ..scaleByDouble(targetScale, targetScale, 1, 1);
    _updatePageSwipeState();
  }

  void _toggleSlideshow() {
    if (_slideshowRunning) {
      _stopSlideshow();
      return;
    }
    if (_pageImages.length <= 1) {
      return;
    }
    setState(() {
      _slideshowRunning = true;
      _interfaceVisible = true;
    });
    _restartSlideshowTimer();
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    if (!_slideshowRunning) {
      return;
    }
    setState(() {
      _slideshowRunning = false;
    });
  }

  void _restartSlideshowTimer() {
    _slideshowTimer?.cancel();
    if (!_slideshowRunning || _pageImages.length <= 1) {
      return;
    }
    final seconds = widget.viewModel.slideshowIntervalSeconds.clamp(
      1,
      60,
    );
    _slideshowTimer = Timer(Duration(seconds: seconds.toInt()), () {
      if (!mounted || !_slideshowRunning) {
        return;
      }
      unawaited(_advanceToNextSlide());
    });
  }

  Future<void> _advanceToNextSlide() async {
    final images = _pageImages;
    if (!_pageController.hasClients || images.length <= 1) {
      _stopSlideshow();
      return;
    }
    final baseIndex = _visiblePageIndex() ?? _pendingPageIndex ?? _currentIndex;
    if (_currentIndex != baseIndex && mounted) {
      setState(() {
        _currentIndex = baseIndex;
      });
    }
    final nextIndex = (baseIndex + 1) % images.length;
    _pendingPageIndex = nextIndex;
    _maybeLoadMoreGalleryItems(nextIndex);
    _resetZoomForIndex(baseIndex);
    _resetZoomForIndex(nextIndex);
    await _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    if (!mounted) {
      return;
    }
    if (_pendingPageIndex == nextIndex) {
      setState(() {
        _currentIndex = nextIndex;
        _pendingPageIndex = null;
      });
      unawaited(_enterFullscreenForCurrentImage());
    }
  }

  void _schedulePageCorrection(int targetIndex) {
    final token = ++_pageCorrectionToken;
    void scheduleAttempt(Duration delay) {
      unawaited(
        Future<void>.delayed(delay, () {
          if (!mounted || token != _pageCorrectionToken) {
            return;
          }
          _correctPagePosition(targetIndex);
        }),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _pageCorrectionToken) {
        return;
      }
      _correctPagePosition(targetIndex);
    });
    scheduleAttempt(const Duration(milliseconds: 80));
    scheduleAttempt(const Duration(milliseconds: 180));
    scheduleAttempt(const Duration(milliseconds: 320));
  }

  void _correctPagePosition(int targetIndex) {
    if (!_pageController.hasClients) {
      return;
    }
    final currentPage = _pageController.page;
    if (currentPage == null) {
      return;
    }
    if ((currentPage - targetIndex).abs() <= 0.01) {
      return;
    }
    _pageController.jumpToPage(targetIndex);
  }

  int? _visiblePageIndex() {
    if (!_pageController.hasClients) {
      return null;
    }
    final page = _pageController.page;
    if (page == null) {
      return null;
    }
    final rounded = page.round();
    if (rounded < 0 || rounded >= _pageImages.length) {
      return null;
    }
    if ((page - rounded).abs() > 0.51) {
      return null;
    }
    return rounded;
  }

  void _resetZoomForIndex(int index) {
    final controller = _transformationControllers[index];
    if (controller == null) {
      return;
    }
    if (controller.value.getMaxScaleOnAxis() > 1.01) {
      controller.value = Matrix4.identity();
    }
  }
}
