import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';


class MediaVideoPlaybackController extends ChangeNotifier {
  _MediaVideoPlayerState? _state;
  Completer<void>? _initializationCompleter = Completer<void>();

  bool get isAttached => _state != null;
  bool get isInitialized => _state?._isControllerInitialized ?? false;
  bool get isPlaying => _state?._controllerValue?.isPlaying ?? false;
  Duration get position => _state?._controllerValue?.position ?? Duration.zero;
  Duration get duration => _state?._controllerValue?.duration ?? Duration.zero;

  Future<bool> waitUntilInitialized({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (isInitialized) {
      return true;
    }
    final completer = _initializationCompleter ??= Completer<void>();
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      return isInitialized;
    }
    return isInitialized;
  }

  Future<void> play() async {
    await _state?._playFromController();
  }

  Future<void> pause() async {
    await _state?._pauseFromController();
  }

  Future<void> seekTo(Duration position) async {
    await _state?._seekFromController(position);
  }

  void _attach(_MediaVideoPlayerState state) {
    _state = state;
    _initializationCompleter ??= Completer<void>();
    if (state._isControllerInitialized &&
        !(_initializationCompleter?.isCompleted ?? true)) {
      _initializationCompleter!.complete();
    }
    notifyListeners();
  }

  void _detach(_MediaVideoPlayerState state) {
    if (!identical(_state, state)) {
      return;
    }
    _state = null;
    _initializationCompleter = Completer<void>();
    notifyListeners();
  }

  void _handleControllerLoadingStart() {
    _initializationCompleter = Completer<void>();
    notifyListeners();
  }

  void _handleControllerInitialized() {
    _initializationCompleter ??= Completer<void>();
    if (!(_initializationCompleter?.isCompleted ?? true)) {
      _initializationCompleter!.complete();
    }
    notifyListeners();
  }

  void _handleControllerStateChanged() {
    notifyListeners();
  }
}

class MediaVideoPlayer extends StatefulWidget {
  const MediaVideoPlayer({
    super.key,
    required this.url,
    this.poster,
    this.autoplay = false,
    this.fit = BoxFit.contain,
    this.showControls = true,
    this.onSurfaceTap,
    this.onDoubleTapDown,
    this.onDoubleTap,
    this.transformationController,
    this.interactiveGesturesEnabled = true,
    this.minScale = 1,
    this.maxScale = 1,
    this.onInteractionEnd,
    this.initiallyMuted = false,
    this.playbackController,
  });

  final String url;
  final Widget? poster;
  final bool autoplay;
  final BoxFit fit;
  final bool showControls;
  final VoidCallback? onSurfaceTap;
  final GestureTapDownCallback? onDoubleTapDown;
  final VoidCallback? onDoubleTap;
  final TransformationController? transformationController;
  final bool interactiveGesturesEnabled;
  final double minScale;
  final double maxScale;
  final GestureScaleEndCallback? onInteractionEnd;
  final bool initiallyMuted;
  final MediaVideoPlaybackController? playbackController;

  @override
  State<MediaVideoPlayer> createState() => _MediaVideoPlayerState();
}

class _MediaVideoPlayerState extends State<MediaVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _muted = false;
  String? _error;
  int _initGeneration = 0;

  VideoPlayerValue? get _controllerValue => _controller?.value;
  bool get _isControllerInitialized =>
      _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    _muted = widget.initiallyMuted;
    widget.playbackController?._attach(this);
    unawaited(_init());
  }

  @override
  void didUpdateWidget(covariant MediaVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackController != widget.playbackController) {
      oldWidget.playbackController?._detach(this);
      widget.playbackController?._attach(this);
    }
    if (oldWidget.url != widget.url) {
      unawaited(_init());
    }
  }

  @override
  void dispose() {
    widget.playbackController?._detach(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;
    final activeController = initialized ? controller : null;
    if (_error != null) {
      return _VideoFrame(
        child: Center(
          child: Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _VideoFrame(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onSurfaceTap,
              onDoubleTapDown: widget.onDoubleTapDown,
              onDoubleTap: widget.onDoubleTap,
              child: _buildSurface(activeController),
            ),
          ),
          if (_loading)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            ),
          if (activeController != null && widget.showControls)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: false,
                child: Stack(
                  children: [
                    Align(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _togglePlayPause,
                          iconSize: 32,
                          padding: const EdgeInsets.all(16),
                          color: Colors.white,
                          icon: Icon(
                            activeController.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          tooltip: activeController.value.isPlaying
                              ? 'Pause'
                              : 'Play',
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  min: 0,
                                  max: activeController
                                      .value
                                      .duration
                                      .inMilliseconds
                                      .clamp(1, 1 << 31)
                                      .toDouble(),
                                  value: activeController
                                      .value
                                      .position
                                      .inMilliseconds
                                      .clamp(
                                        0,
                                        activeController
                                            .value
                                            .duration
                                            .inMilliseconds,
                                      )
                                      .toDouble(),
                                  onChanged: (value) {
                                    activeController.seekTo(
                                      Duration(milliseconds: value.round()),
                                    );
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: _toggleMute,
                                icon: Icon(
                                  _muted ? Icons.volume_off : Icons.volume_up,
                                  color: Colors.white,
                                ),
                                tooltip: _muted ? 'Unmute' : 'Mute',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSurface(VideoPlayerController? activeController) {
    final surface = SizedBox.expand(
      child: activeController != null
          ? FittedBox(
              fit: widget.fit,
              child: SizedBox(
                width: activeController.value.size.width,
                height: activeController.value.size.height,
                child: VideoPlayer(activeController),
              ),
            )
          : widget.poster ?? const ColoredBox(color: Colors.black12),
    );
    if (widget.transformationController == null || widget.maxScale <= 1) {
      return surface;
    }
    return InteractiveViewer(
      transformationController: widget.transformationController,
      panEnabled: widget.interactiveGesturesEnabled,
      scaleEnabled: widget.interactiveGesturesEnabled,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      onInteractionEnd: widget.onInteractionEnd,
      child: surface,
    );
  }

  Future<void> _init() async {
    final initGeneration = ++_initGeneration;
    final oldController = _controller;
    oldController?.removeListener(_handleVideoControllerChanged);
    widget.playbackController?._handleControllerLoadingStart();
    setState(() {
      _controller = null;
      _loading = true;
      _error = null;
    });
    unawaited(oldController?.dispose());
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted || initGeneration != _initGeneration) {
        await controller.dispose();
        return;
      }
      controller.addListener(_handleVideoControllerChanged);
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (widget.autoplay) {
        await controller.play();
      }
      if (!mounted || initGeneration != _initGeneration) {
        controller.removeListener(_handleVideoControllerChanged);
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      widget.playbackController?._handleControllerInitialized();
      widget.playbackController?._handleControllerStateChanged();
    } catch (error) {
      await controller.dispose();
      if (!mounted || initGeneration != _initGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Failed to load video.';
      });
      widget.playbackController?._handleControllerStateChanged();
    }
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    widget.playbackController?._handleControllerStateChanged();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final nextMuted = !_muted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) {
      setState(() {
        _muted = nextMuted;
      });
    }
    widget.playbackController?._handleControllerStateChanged();
  }

  Future<void> _playFromController() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.play();
    widget.playbackController?._handleControllerStateChanged();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pauseFromController() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.pause();
    widget.playbackController?._handleControllerStateChanged();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _seekFromController(Duration position) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final duration = controller.value.duration;
    final clampedPosition = duration <= Duration.zero
        ? Duration.zero
        : Duration(
            milliseconds: position.inMilliseconds.clamp(
              0,
              duration.inMilliseconds,
            ),
          );
    await controller.seekTo(clampedPosition);
    widget.playbackController?._handleControllerStateChanged();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleVideoControllerChanged() {
    widget.playbackController?._handleControllerStateChanged();
    if (mounted) {
      setState(() {});
    }
  }
}

class _VideoFrame extends StatelessWidget {
  const _VideoFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(color: Colors.black, child: child),
    );
  }
}
