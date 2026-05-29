import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/features/gallery/controllers/gallery_selection_actions_controller.dart';
import 'package:flutter_app/features/gallery/domain/gallery_selection_capabilities.dart';
import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/gallery/state/gallery_selection_state.dart';
import 'package:flutter_app/features/gallery/gallery_filter_sheet.dart';
import 'package:flutter_app/features/gallery/gallery_filter_summary.dart';
import 'package:flutter_app/features/gallery/gallery_picker_sheets.dart';
import 'package:flutter_app/features/gallery/gallery_selection_action_bar.dart';
import 'package:flutter_app/features/gallery/gallery_view_model.dart';
import 'package:flutter_app/features/gallery/gallery_widgets.dart';
import 'package:flutter_app/features/gallery/media_detail_page.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';

import 'package:provider/provider.dart';

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryViewModel>(
      builder: (context, viewModel, _) =>
          _GalleryPageBody(viewModel: viewModel),
    );
  }
}

class _GalleryPageBody extends StatefulWidget {
  const _GalleryPageBody({required this.viewModel});

  final GalleryViewModel viewModel;

  @override
  State<_GalleryPageBody> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPageBody> {
  bool _loaded = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, bool> _expandedGroups = <String, bool>{};
  final GallerySelectionState _selection = GallerySelectionState();
  Timer? _searchDebounce;
  bool _showScrollToTop = false;

  GallerySelectionActionsController get _selectionActions {
    return GallerySelectionActionsController(
      viewModel: widget.viewModel,
      showMessage: _showSnackBar,
      showStateMessage: _showStateMessage,
      clearSelection: _clearSelection,
      isMounted: () => mounted,
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.viewModel.searchQuery;
    _scrollController.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loaded && widget.viewModel.baseUrl.isNotEmpty) {
        _loaded = true;
        widget.viewModel.loadGalleryFirstPage();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScrollChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gallery = widget.viewModel;
    final browser = widget.viewModel;
    final visibleGallery = gallery.gallery.toList(growable: false);
    final groupedSections = browser.groupItems(visibleGallery);
    final rows = _buildGalleryRows(groupedSections);
    final selectedImages = _selection.selectedImagesFrom(visibleGallery);
    final selectionCapabilities = GallerySelectionCapabilities.fromImages(
      selectedImages,
      jobForImage: widget.viewModel.jobForImage,
    );

    if (browser.loadingFirstPage && gallery.gallery.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (gallery.gallery.isEmpty &&
        !browser.loadingFirstPage &&
        browser.currentPage == 0 &&
        !hasActiveGalleryFilters(browser)) {
      return Center(
        child: FilledButton.tonal(
          onPressed: widget.viewModel.loadGalleryFirstPage,
          child: const Text('Load stored media'),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.viewModel.loadGalleryFirstPage,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: _scheduleSearchQueryUpdate,
                        decoration: InputDecoration(
                          hintText: 'Search stored media',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: browser.searchQuery.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    browser.setSearchQuery('');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GalleryToolbar(
                        sortLabel: gallerySortLabel(browser.sortOption),
                        filterLabel: galleryFilterLabel(browser),
                        groupLabel: galleryGroupLabel(browser.groupOption),
                        selectionLabel: _selection.selectionMode
                            ? 'Done'
                            : 'Select',
                        selectionIcon: _selection.selectionMode
                            ? Icons.close
                            : Icons.checklist,
                        onSortTap: () =>
                            showGallerySortPicker(context, browser),
                        onFilterTap: () =>
                            showGalleryFilterSheet(context, browser),
                        onGroupTap: () =>
                            showGalleryGroupPicker(context, browser),
                        onSelectTap: _toggleSelectionMode,
                        onClearTap: hasActiveGalleryFilters(browser)
                            ? () {
                                _searchController.clear();
                                browser.resetPreferences();
                              }
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        browser.totalCount > 0
                            ? 'Loaded ${visibleGallery.length} of ${browser.totalCount} item(s)'
                            : '${visibleGallery.length} item(s)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (hasActiveGalleryFilters(browser)) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: activeGalleryFilterChips(
                            browser: browser,
                            onClearSearch: _clearSearchQuery,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_selection.selectionMode)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: GallerySelectionActionBarHeader(
                    selectedCount: selectedImages.length,
                    capabilities: selectionCapabilities,
                    onClearSelection: _clearSelection,
                    onDownload: selectionCapabilities.canDownload
                        ? _downloadSelected
                        : null,
                    onRegenerate: selectionCapabilities.canRegenerate
                        ? _regenerateSelected
                        : null,
                    onScale: selectionCapabilities.canScale
                        ? _scaleSelected
                        : null,
                    onGenerateAudioVideo:
                        selectionCapabilities.canGenerateAudioVideo
                        ? _generateAudioVideoForSelected
                        : null,
                    onConvertToGif: selectionCapabilities.canConvertVideoToGif
                        ? _convertSelectedVideosToGif
                        : null,
                    onUseAsImageSource:
                        selectionCapabilities.canUseAsImageSource
                        ? _useSelectedAsImageSource
                        : null,
                    onCreateVideo: selectionCapabilities.canCreateVideo
                        ? _createVideoFromSelected
                        : null,
                    onCreatePromptAndVideo:
                        selectionCapabilities.canCreatePromptAndVideo
                        ? _createPromptAndVideoFromSelected
                        : null,
                    onRestore: selectionCapabilities.canRestore
                        ? _restoreSelected
                        : null,
                    onDelete: selectionCapabilities.canDelete
                        ? _deleteSelected
                        : null,
                    onCancelJobs: selectionCapabilities.canCancelJobs
                        ? _cancelSelectedJobs
                        : null,
                  ),
                ),
              if (visibleGallery.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverToBoxAdapter(
                    child: InfoCard(
                      title: 'Gallery',
                      child: Text('No media matches the current filters.'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        if (browser.loadingNextPage) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (browser.hasMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: Text('Loading more media...')),
                          );
                        }
                        return const SizedBox(height: 16);
                      }

                      final row = rows[index];
                      if (row.isHeader) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              title: Text(row.title!),
                              subtitle: Text('${row.count} item(s)'),
                              trailing: Icon(
                                row.expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                              onTap: () {
                                setState(() {
                                  _expandedGroups[row.title!] = !row.expanded;
                                });
                              },
                            ),
                          ),
                        );
                      }

                      final image = row.image!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GalleryImageTile(
                          key: ValueKey(image.id),
                          image: image,
                          selectionMode: _selection.selectionMode,
                          selected: _selection.isSelected(image.id),
                          onSelectionChanged: (_) =>
                              _toggleImageSelection(image.id),
                          onLongPress: () => _startSelectionWith(image.id),
                          onTap: () => _openDetails(visibleGallery, image),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: AnimatedScale(
            scale: _showScrollToTop ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: FloatingActionButton.small(
              heroTag: 'gallery-scroll-top',
              onPressed: _showScrollToTop ? _scrollToTop : null,
              child: const Icon(Icons.vertical_align_top),
            ),
          ),
        ),
      ],
    );
  }

  void _openDetails(List<ImageRecord> visibleGallery, ImageRecord image) {
    final initialIndex = visibleGallery.indexWhere(
      (item) => item.id == image.id,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MediaDetailPage(
          images: visibleGallery,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          useLiveGallery: true,
        ),
      ),
    );
  }

  void _handleScrollChanged() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 320;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter < 600) {
      unawaited(widget.viewModel.loadGalleryNextPage());
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleSearchQueryUpdate(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      widget.viewModel.setSearchQuery(value);
    });
  }

  void _clearSearchQuery() {
    _searchController.clear();
    widget.viewModel.setSearchQuery('');
  }

  void _toggleSelectionMode() {
    setState(_selection.toggleSelectionMode);
  }

  void _startSelectionWith(String imageId) {
    setState(() {
      _selection.startSelectionWith(imageId);
    });
  }

  void _toggleImageSelection(String imageId) {
    setState(() {
      _selection.toggleImageSelection(imageId);
    });
  }

  void _clearSelection() {
    setState(_selection.clearSelection);
  }

  List<ImageRecord> _selectedImages() {
    return _selection.selectedImagesFrom(widget.viewModel.gallery);
  }

  Future<void> _downloadSelected() {
    return _selectionActions.download(_selectedImages());
  }

  Future<void> _regenerateSelected() {
    return _selectionActions.regenerate(_selectedImages());
  }

  Future<void> _scaleSelected() async {
    final scaleFactor = await showGalleryScaleFactorPicker(
      context,
      _selectedImages(),
    );
    if (!mounted || scaleFactor == null) {
      return;
    }
    await _selectionActions.scale(_selectedImages(), scaleFactor);
  }

  Future<void> _generateAudioVideoForSelected() {
    return _selectionActions.generateAudioVideo(_selectedImages());
  }

  Future<void> _convertSelectedVideosToGif() {
    return _selectionActions.convertVideosToGif(_selectedImages());
  }

  void _useSelectedAsImageSource() {
    _selectionActions.useAsImageSource(_selectedImages());
  }

  void _createVideoFromSelected() {
    _selectionActions.createVideoFromImage(_selectedImages());
  }

  Future<void> _createPromptAndVideoFromSelected() {
    return _selectionActions.createPromptAndVideo(_selectedImages());
  }

  Future<void> _restoreSelected() {
    return _selectionActions.restore(_selectedImages());
  }

  Future<void> _deleteSelected() {
    return _selectionActions.delete(_selectedImages());
  }

  Future<void> _cancelSelectedJobs() {
    return _selectionActions.cancelJobs(_selectedImages());
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

  List<GalleryListRow> _buildGalleryRows(List<GalleryGroupSection> sections) {
    final rows = <GalleryListRow>[];
    for (final section in sections) {
      if (section.title.isEmpty) {
        rows.addAll(section.items.map((image) => GalleryListRow.image(image)));
        continue;
      }
      final expanded = _expandedGroups[section.title] ?? false;
      rows.add(
        GalleryListRow.header(
          title: section.title,
          count: section.items.length,
          expanded: expanded,
        ),
      );
      if (expanded) {
        rows.addAll(section.items.map((image) => GalleryListRow.image(image)));
      }
    }
    return rows;
  }
}
