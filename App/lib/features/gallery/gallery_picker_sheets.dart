import 'package:flutter/material.dart';

import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/gallery/state/gallery_browser_store.dart';
import 'package:noviagen/features/gallery/gallery_view_model.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';


Future<void> showGallerySortPicker(
  BuildContext context,
  GalleryViewModel browser,
) async {
  final selected = await showModalBottomSheet<GallerySortOption>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortTile(context, browser, 'Newest first', GallerySortOption.newest),
          _sortTile(context, browser, 'Oldest first', GallerySortOption.oldest),
          _sortTile(
            context,
            browser,
            'Highest rating',
            GallerySortOption.ratingHigh,
          ),
          _sortTile(
            context,
            browser,
            'Lowest rating',
            GallerySortOption.ratingLow,
          ),
          _sortTile(
            context,
            browser,
            'Largest resolution',
            GallerySortOption.resolutionHigh,
          ),
          _sortTile(
            context,
            browser,
            'Longest playback duration',
            GallerySortOption.durationHigh,
          ),
          _sortTile(
            context,
            browser,
            'Shortest playback duration',
            GallerySortOption.durationLow,
          ),
          _sortTile(
            context,
            browser,
            'Longest generation time',
            GallerySortOption.generationDurationHigh,
          ),
          _sortTile(
            context,
            browser,
            'Shortest generation time',
            GallerySortOption.generationDurationLow,
          ),
        ],
      ),
    ),
  );
  if (selected != null) {
    browser.setSortOption(selected);
  }
}

Future<void> showGalleryGroupPicker(
  BuildContext context,
  GalleryViewModel browser,
) async {
  final selected = await showModalBottomSheet<GalleryGroupOption>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _groupTile(context, browser, 'No grouping', GalleryGroupOption.none),
          _groupTile(
            context,
            browser,
            'Group by model',
            GalleryGroupOption.model,
          ),
          _groupTile(
            context,
            browser,
            'Group by rating',
            GalleryGroupOption.rating,
          ),
          _groupTile(
            context,
            browser,
            'Group by media type',
            GalleryGroupOption.mediaType,
          ),
        ],
      ),
    ),
  );
  if (selected != null) {
    browser.setGroupOption(selected);
  }
}

Widget _sortTile(
  BuildContext context,
  GalleryViewModel browser,
  String title,
  GallerySortOption option,
) {
  return PickerTile(
    title: title,
    selected: browser.sortOption == option,
    onTap: () => Navigator.of(context).pop(option),
  );
}

Widget _groupTile(
  BuildContext context,
  GalleryViewModel browser,
  String title,
  GalleryGroupOption option,
) {
  return PickerTile(
    title: title,
    selected: browser.groupOption == option,
    onTap: () => Navigator.of(context).pop(option),
  );
}


Future<double?> showGalleryScaleFactorPicker(
  BuildContext context,
  List<ImageRecord> images,
) {
  const minScale = 1.1;
  const maxScale = 10.0;
  const initialScale = 2.0;
  var scaleFactor = initialScale;

  return showModalBottomSheet<double>(
    context: context,
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scale media',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Text('Scale factor: ${_formatScaleFactor(scaleFactor)}x'),
              Slider(
                value: scaleFactor,
                min: minScale,
                max: maxScale,
                divisions: 89,
                label: '${_formatScaleFactor(scaleFactor)}x',
                onChanged: (value) {
                  setModalState(() {
                    scaleFactor = value;
                  });
                },
              ),
              Text(_targetResolutionLabel(images, scaleFactor)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(scaleFactor),
                    child: const Text('Scale'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

String _targetResolutionLabel(List<ImageRecord> images, double scaleFactor) {
  if (images.isEmpty) {
    return 'Target resolution unavailable.';
  }
  final first = images.first;
  final targetWidth = (first.width * scaleFactor).round();
  final targetHeight = (first.height * scaleFactor).round();
  final allSameSize = images.every(
    (image) => image.width == first.width && image.height == first.height,
  );
  final targetResolution = '$targetWidth x $targetHeight';
  if (images.length == 1 || allSameSize) {
    return 'Target resolution: $targetResolution';
  }
  return 'Target resolution varies by source size. First selected: $targetResolution';
}

String _formatScaleFactor(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.001) {
    return rounded.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}
