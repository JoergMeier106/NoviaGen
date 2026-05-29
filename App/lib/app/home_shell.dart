import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:noviagen/features/chat/chat_page.dart';
import 'package:noviagen/features/gallery/gallery_page.dart';
import 'package:noviagen/features/gallery/media_detail_page.dart';
import 'package:noviagen/features/generate/generate_page.dart';
import 'package:noviagen/features/settings/settings_pages.dart';
import 'package:noviagen/features/settings/settings_view_model.dart';
import 'package:noviagen/job_text.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/app/system_ui.dart';
import 'package:noviagen/app/app_shell_view_model.dart';

import 'package:provider/provider.dart';


enum _GalleryImportAction { takePhoto, phoneGallery }

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.viewModel,
  });

  final AppShellViewModel viewModel;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final Listenable _changes;

  int _index = 0;
  DateTime? _lastBackPressedAt;
  int _lastOpenGeneratePageRequestCount = 0;
  int _lastOpenGalleryDetailRequestCount = 0;
  int _lastQueuedJobToastRequestCount = 0;
  String? _lastFeedbackMessage;
  Timer? _runtimeTicker;
  bool _jobStatusExpanded = false;
  String? _lastRunningJobId;
  String? _openingGalleryDetailMediaId;

  @override
  void initState() {
    super.initState();
    _changes = widget.viewModel;
    _lastOpenGeneratePageRequestCount =
        widget.viewModel.openGeneratePageRequestCount;
    _lastOpenGalleryDetailRequestCount = 0;
    _lastQueuedJobToastRequestCount =
        widget.viewModel.queuedJobToastRequestCount;
    _lastFeedbackMessage = widget.viewModel.message?.trim();
    _lastRunningJobId = widget.viewModel.activeRunningJob?.jobId;
    _changes.addListener(_handleStateChanged);
    _syncRuntimeTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreStandardSystemUi();
      _handleNavigationRequests();
    });
  }

  @override
  void dispose() {
    _runtimeTicker?.cancel();
    _changes.removeListener(_handleStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final activeJob = widget.viewModel.activeRunningJob;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final shouldExit = await _handleBackPress(context);
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titleForIndex(_index)),
          actions: [
            if (_index == 1)
              PopupMenuButton<_GalleryImportAction>(
                enabled: !widget.viewModel.importingGalleryMedia,
                tooltip: 'Import media',
                onSelected: (value) =>
                    unawaited(_handleGalleryImportAction(value)),
                itemBuilder: (context) => const [
                  PopupMenuItem<_GalleryImportAction>(
                    value: _GalleryImportAction.takePhoto,
                    child: ListTile(
                      leading: Icon(Icons.photo_camera_outlined),
                      title: Text('Take photo'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_GalleryImportAction>(
                    value: _GalleryImportAction.phoneGallery,
                    child: ListTile(
                      leading: Icon(Icons.photo_library_outlined),
                      title: Text('Phone gallery'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                icon: widget.viewModel.importingGalleryMedia
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
              ),
            if (_index == 3)
              IconButton(
                onPressed: widget.viewModel.loadingAssets
                    ? null
                    : () => unawaited(
                        context.read<SettingsViewModel>().refreshBackendData(),
                      ),
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload backend data',
              ),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: [
            const GeneratePage(),
            const GalleryPage(),
            const ChatPage(),
            SettingsPage(isActive: _index == 3),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: activeJob == null
                  ? const SizedBox.shrink()
                  : _PersistentJobStatusPanel(
                      key: ValueKey(activeJob.jobId),
                      job: activeJob,
                      isExpanded: _jobStatusExpanded,
                      onToggle: _toggleJobStatusExpanded,
                    ),
            ),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome),
                  label: 'Generate',
                ),
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark),
                  label: 'Gallery',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGalleryImportAction(_GalleryImportAction action) async {
    switch (action) {
      case _GalleryImportAction.takePhoto:
        await widget.viewModel.importGalleryImages(ImageSource.camera);
        return;
      case _GalleryImportAction.phoneGallery:
        await widget.viewModel.importGalleryImages(ImageSource.gallery);
        return;
    }
  }

  Future<bool> _handleBackPress(BuildContext context) async {
    if (_index != 0) {
      setState(() {
        _index = 0;
      });
      return false;
    }

    final now = DateTime.now();
    final recentPress =
        _lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) < const Duration(seconds: 2);
    if (recentPress) {
      return true;
    }

    _lastBackPressedAt = now;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to close NoviaGen.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    return false;
  }

  void _handleStateChanged() {
    if (!mounted) {
      return;
    }
    _syncRuntimeTicker();

    final activeJobId = widget.viewModel.activeRunningJob?.jobId;
    if (activeJobId != _lastRunningJobId) {
      _lastRunningJobId = activeJobId;
      if (activeJobId != null) {
        _jobStatusExpanded = false;
      }
    }

    final queuedToastRequestCount =
        widget.viewModel.queuedJobToastRequestCount;
    if (queuedToastRequestCount != _lastQueuedJobToastRequestCount) {
      _lastQueuedJobToastRequestCount = queuedToastRequestCount;
      final toastMessage = widget.viewModel.queuedJobToastMessage?.trim();
      if (toastMessage != null && toastMessage.isNotEmpty) {
        final messenger = ScaffoldMessenger.of(context);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(toastMessage),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }

    final feedbackMessage = widget.viewModel.message?.trim();
    if (feedbackMessage != null &&
        feedbackMessage.isNotEmpty &&
        feedbackMessage != _lastFeedbackMessage) {
      _lastFeedbackMessage = feedbackMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedbackMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (feedbackMessage == null || feedbackMessage.isEmpty) {
      _lastFeedbackMessage = null;
    }

    _handleNavigationRequests();
  }

  void _handleNavigationRequests() {
    final navigation = widget.viewModel;
    final galleryDetailRequestCount = navigation.openGalleryDetailRequestCount;
    if (galleryDetailRequestCount != _lastOpenGalleryDetailRequestCount) {
      _lastOpenGalleryDetailRequestCount = galleryDetailRequestCount;
      final mediaId = navigation.openGalleryDetailMediaId?.trim();
      if (mediaId != null && mediaId.isNotEmpty) {
        unawaited(_openGalleryDetailForNotification(mediaId));
      }
    }

    final requestCount = navigation.openGeneratePageRequestCount;
    if (requestCount == _lastOpenGeneratePageRequestCount || _index == 0) {
      _lastOpenGeneratePageRequestCount = requestCount;
      return;
    }
    _lastOpenGeneratePageRequestCount = requestCount;
    setState(() {
      _index = 0;
    });
  }

  Future<void> _openGalleryDetailForNotification(String mediaId) async {
    if (_openingGalleryDetailMediaId == mediaId) {
      return;
    }
    _openingGalleryDetailMediaId = mediaId;
    try {
      if (!mounted) {
        return;
      }
      if (_index != 1) {
        setState(() {
          _index = 1;
        });
      }
      final image = await widget.viewModel.fetchImageById(
        mediaId,
        refresh: true,
      );
      if (!mounted) {
        return;
      }
      if (image == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The completed media is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final galleryImages = <ImageRecord>[...widget.viewModel.gallery];
      final initialIndex = galleryImages.indexWhere(
        (item) => item.id == image.id,
      );
      final images = initialIndex >= 0 ? galleryImages : <ImageRecord>[image];
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => MediaDetailPage(
            images: images,
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
            useLiveGallery: initialIndex >= 0,
          ),
        ),
      );
    } finally {
      if (_openingGalleryDetailMediaId == mediaId) {
        _openingGalleryDetailMediaId = null;
      }
    }
  }

  void _syncRuntimeTicker() {
    final activeJob = widget.viewModel.activeRunningJob;
    final shouldTick = activeJob != null && jobElapsedText(activeJob) != null;
    if (!shouldTick) {
      _runtimeTicker?.cancel();
      _runtimeTicker = null;
      return;
    }
    if (_runtimeTicker != null) {
      return;
    }
    _runtimeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _toggleJobStatusExpanded() {
    setState(() {
      _jobStatusExpanded = !_jobStatusExpanded;
    });
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Generate';
      case 1:
        return 'Gallery';
      case 2:
        return 'Chat';
      default:
        return 'Settings';
    }
  }

  Future<void> _restoreStandardSystemUi() async {
    await restoreStandardSystemUi();
  }
}

class _PersistentJobStatusPanel extends StatelessWidget {
  const _PersistentJobStatusPanel({
    super.key,
    required this.job,
    required this.isExpanded,
    required this.onToggle,
  });

  final JobStatus job;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = job.progress.clamp(0.0, 1.0);
    final progressPercent = '${(progressValue * 100).round()}%';
    final elapsed = jobElapsedDuration(job);
    final compactElapsed = elapsed == null
        ? null
        : formatJobElapsedDuration(elapsed);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onToggle,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          jobTitleText(job),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isExpanded ? '' : progressPercent,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!isExpanded && compactElapsed != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          compactElapsed,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jobStatusText(job),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (compactElapsed != null)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 14,
                                        color: theme
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Running for $compactElapsed',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progressValue,
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              progressPercent,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
