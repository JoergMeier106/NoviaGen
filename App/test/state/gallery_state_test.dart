import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/generation.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/state/gallery_state.dart';

ImageRecord _media({
  required String id,
  required String createdAt,
  int rating = 0,
  String mediaType = 'image',
  List<String> tags = const <String>[],
  String modelId = 'demo-model',
  double? durationSeconds,
  double? generationDurationSeconds,
  bool isDeleted = false,
}) {
  return ImageRecord(
    id: id,
    status: isDeleted ? 'deleted' : 'stored',
    mediaType: mediaType,
    mimeType: mediaType == 'video' ? 'video/mp4' : 'image/png',
    width: 640,
    height: 480,
    prompt: 'A bright portrait',
    defaultPositivePrompt: 'default pos',
    defaultNegativePrompt: 'default neg',
    finalPositivePrompt: 'A bright portrait with detail',
    modelId: modelId,
    loras: <SelectedLora>[],
    tags: tags,
    caption: '',
    numInferenceSteps: 40,
    guidanceScale: 5.0,
    imageOrientation: 'landscape',
    fileUrl: 'http://example.test/files/$id',
    previewUrl: 'http://example.test/preview/$id',
    thumbnailUrl: 'http://example.test/thumb/$id',
    createdAt: createdAt,
    rating: rating,
    durationSeconds: durationSeconds,
    generationDurationSeconds: generationDurationSeconds,
  );
}

void main() {
  test('compareGalleryItems sorts newest first by default', () {
    final older = _media(id: 'older', createdAt: '2026-01-01T00:00:00Z');
    final newer = _media(id: 'newer', createdAt: '2026-01-02T00:00:00Z');

    final items = <ImageRecord>[older, newer]
      ..sort(
        (left, right) =>
            compareGalleryItems(left, right, GallerySortOption.newest),
      );

    expect(items.map((item) => item.id), <String>['newer', 'older']);
  });

  test(
    'matchesGalleryQuery applies model tags rating and deletion filters',
    () {
      final item = _media(
        id: 'match',
        createdAt: '2026-01-01T00:00:00Z',
        rating: 4,
        tags: const <String>['portrait', 'favorite'],
        modelId: 'demo-model',
      );

      expect(
        matchesGalleryQuery(
          item,
          const GalleryQuery(
            search: 'bright',
            model: 'demo-model',
            includeTags: <String>['portrait'],
            excludeTags: <String>['landscape'],
            minRating: 3,
            mediaType: GalleryMediaTypeFilter.images,
            showDeleted: false,
            showPlaceholders: true,
          ),
        ),
        isTrue,
      );
    },
  );

  test('groupGalleryItems groups by media type label', () {
    final sections = groupGalleryItems(<ImageRecord>[
      _media(id: 'image', createdAt: '2026-01-01T00:00:00Z'),
      _media(
        id: 'video',
        createdAt: '2026-01-02T00:00:00Z',
        mediaType: 'video',
      ),
    ], GalleryGroupOption.mediaType);

    expect(
      sections.map((section) => section.title),
      containsAll(['Images', 'Videos']),
    );
  });
}
