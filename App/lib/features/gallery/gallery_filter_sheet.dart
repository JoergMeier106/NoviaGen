import 'package:flutter/material.dart';

import 'package:noviagen/features/gallery/state/gallery_browser_store.dart';
import 'package:noviagen/features/gallery/gallery_view_model.dart';
import 'package:noviagen/features/gallery/gallery_filter_summary.dart';
import 'package:noviagen/features/gallery/gallery_filter_widgets.dart';


Future<void> showGalleryFilterSheet(
  BuildContext context,
  GalleryViewModel browser,
) async {
  var selectedModel = browser.modelFilter ?? 'All models';
  var selectedMediaType = browser.mediaTypeFilter;
  var includeTags = List<String>.from(browser.includeTags);
  var excludeTags = List<String>.from(browser.excludeTags);
  var minRating = browser.minRating;
  var showDeleted = browser.showDeleted;
  var showPlaceholders = browser.showPlaceholders;
  final availableTags = browser.availableTags;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter media',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              _MediaTypeDropdown(
                value: selectedMediaType,
                onChanged: (value) {
                  setModalState(() {
                    selectedMediaType = value;
                  });
                  browser.setMediaTypeFilter(value);
                },
              ),
              const SizedBox(height: 16),
              _ModelDropdown(
                value: selectedModel,
                models: browser.modelFilters,
                onChanged: (value) {
                  setModalState(() {
                    selectedModel = value;
                  });
                  browser.setModelFilter(value);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showDeleted,
                title: const Text('Show deleted media'),
                onChanged: (value) {
                  setModalState(() {
                    showDeleted = value;
                  });
                  browser.setShowDeleted(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showPlaceholders,
                title: const Text('Show placeholders'),
                onChanged: (value) {
                  setModalState(() {
                    showPlaceholders = value;
                  });
                  browser.setShowPlaceholders(value);
                },
              ),
              const SizedBox(height: 16),
              _TagFilters(
                availableTags: availableTags,
                includeTags: includeTags,
                excludeTags: excludeTags,
                onChanged: (nextIncluded, nextExcluded) {
                  setModalState(() {
                    includeTags = nextIncluded;
                    excludeTags = nextExcluded;
                  });
                  browser.setIncludeTags(includeTags);
                  browser.setExcludeTags(excludeTags);
                },
              ),
              const SizedBox(height: 16),
              Text('Minimum rating: $minRating'),
              Slider(
                value: minRating.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                label: '$minRating',
                onChanged: (value) {
                  final updatedValue = value.round();
                  setModalState(() {
                    minRating = updatedValue;
                  });
                  browser.setMinRating(updatedValue);
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setModalState(() {
                      selectedModel = 'All models';
                      selectedMediaType = GalleryMediaTypeFilter.all;
                      includeTags = <String>[];
                      excludeTags = <String>[];
                      minRating = 0;
                      showDeleted = false;
                      showPlaceholders = true;
                    });
                    _resetGalleryFilters(browser);
                  },
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _resetGalleryFilters(GalleryViewModel browser) {
  browser.setMediaTypeFilter(GalleryMediaTypeFilter.all);
  browser.setModelFilter('All models');
  browser.setIncludeTags(const <String>[]);
  browser.setExcludeTags(const <String>[]);
  browser.setMinRating(0);
  browser.setShowDeleted(false);
  browser.setShowPlaceholders(true);
}

class _MediaTypeDropdown extends StatelessWidget {
  const _MediaTypeDropdown({required this.value, required this.onChanged});

  final GalleryMediaTypeFilter value;
  final ValueChanged<GalleryMediaTypeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<GalleryMediaTypeFilter>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Media type',
        border: OutlineInputBorder(),
      ),
      items: GalleryMediaTypeFilter.values
          .map(
            (item) => DropdownMenuItem<GalleryMediaTypeFilter>(
              value: item,
              child: Text(galleryMediaTypeFilterLabel(item)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.value,
    required this.models,
    required this.onChanged,
  });

  final String value;
  final List<String> models;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Model',
        border: OutlineInputBorder(),
      ),
      items: models
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _TagFilters extends StatelessWidget {
  const _TagFilters({
    required this.availableTags,
    required this.includeTags,
    required this.excludeTags,
    required this.onChanged,
  });

  final List<String> availableTags;
  final List<String> includeTags;
  final List<String> excludeTags;
  final void Function(List<String> includeTags, List<String> excludeTags)
  onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TagFilterSection(
          title: 'Include tags',
          emptyLabel: 'No tags available yet.',
          allTags: availableTags,
          selectedTags: includeTags,
          onToggle: _toggleIncludedTag,
        ),
        const SizedBox(height: 16),
        TagFilterSection(
          title: 'Exclude tags',
          emptyLabel: 'No tags available yet.',
          allTags: availableTags,
          selectedTags: excludeTags,
          onToggle: _toggleExcludedTag,
        ),
      ],
    );
  }

  void _toggleIncludedTag(String tag) {
    final nextIncluded = List<String>.from(includeTags);
    final nextExcluded = List<String>.from(excludeTags);
    if (nextIncluded.contains(tag)) {
      nextIncluded.remove(tag);
    } else {
      nextIncluded.add(tag);
      nextExcluded.remove(tag);
    }
    onChanged(nextIncluded, nextExcluded);
  }

  void _toggleExcludedTag(String tag) {
    final nextIncluded = List<String>.from(includeTags);
    final nextExcluded = List<String>.from(excludeTags);
    if (nextExcluded.contains(tag)) {
      nextExcluded.remove(tag);
    } else {
      nextExcluded.add(tag);
      nextIncluded.remove(tag);
    }
    onChanged(nextIncluded, nextExcluded);
  }
}
