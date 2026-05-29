import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/state/gallery_state.dart';
import 'package:flutter_app/state/image_model_selection_state.dart';
import 'package:flutter_app/state/media_actions_state.dart';
import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/models/gallery.dart';
import 'package:flutter_app/models/generation.dart';
import 'package:flutter_app/models/media.dart';

const _galleryPageSize = 30;

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required this.assetResponse,
    this.firstGalleryPage,
    this.secondGalleryPage,
    this.galleryFilters,
    this.updatedImage,
  }) : super('http://example.test');

  final AssetResponse assetResponse;
  final GalleryPageResponse? firstGalleryPage;
  final GalleryPageResponse? secondGalleryPage;
  final GalleryFiltersResponse? galleryFilters;
  final ImageRecord? updatedImage;
  final List<Map<String, Object?>> galleryRequests = <Map<String, Object?>>[];

  @override
  Future<AssetResponse> fetchAssets() async => assetResponse;

  @override
  Future<GalleryPageResponse> fetchGalleryImagesPage({
    int page = 1,
    int pageSize = 20,
    String search = '',
    String mediaType = 'all',
    String? modelId,
    List<String> includeTags = const <String>[],
    List<String> excludeTags = const <String>[],
    int minRating = 0,
    String sort = 'newest',
    bool includeDeleted = false,
    bool includePlaceholders = true,
  }) async {
    galleryRequests.add(<String, Object?>{
      'page': page,
      'pageSize': pageSize,
      'search': search,
      'mediaType': mediaType,
      'modelId': modelId,
      'includeTags': includeTags,
      'excludeTags': excludeTags,
      'minRating': minRating,
      'sort': sort,
      'includeDeleted': includeDeleted,
      'includePlaceholders': includePlaceholders,
    });
    if (page == 1 && firstGalleryPage != null) {
      return firstGalleryPage!;
    }
    if (page == 2 && secondGalleryPage != null) {
      return secondGalleryPage!;
    }
    return GalleryPageResponse(
      items: const <ImageRecord>[],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    );
  }

  @override
  Future<GalleryFiltersResponse> fetchGalleryFilters({
    bool includeDeleted = false,
  }) async {
    return galleryFilters ??
        GalleryFiltersResponse(
          models: const <String>[],
          tags: const <String>[],
        );
  }

  @override
  Future<ImageRecord> setImageRating(String imageId, int rating) async {
    return updatedImage!;
  }

  @override
  Future<ImageRecord> setImageTags(String imageId, List<String> tags) async {
    return updatedImage!;
  }
}

AssetResponse _assetResponseWithLoras(List<LoraAsset> loras) {
  return AssetResponse(
    models: const <ModelAsset>[],
    loras: loras,
    videoModels: const <VideoModelAsset>[],
    videoDiffusionModels: const <VideoDiffusionModelAsset>[],
    videoPresets: const <VideoPresetOption>[],
  );
}

ImageRecord _imageRecord({
  required String id,
  String prompt = 'prompt',
  String finalPositivePrompt = 'prompt',
  String modelId = 'demo-model',
  List<String> tags = const <String>[],
  int rating = 0,
}) {
  return ImageRecord(
    id: id,
    status: 'stored',
    mediaType: 'image',
    mimeType: 'image/png',
    width: 640,
    height: 480,
    prompt: prompt,
    defaultPositivePrompt: 'default pos',
    defaultNegativePrompt: 'default neg',
    finalPositivePrompt: finalPositivePrompt,
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
    createdAt: '2026-01-01T00:00:00+00:00',
    rating: rating,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'image model selection sorts LoRAs by rating descending and label ascending',
    () async {
      final imageModels = ImageModelSelectionState(
        setMessage: (_) {},
        onChanged: () {},
      );
      final assets = _assetResponseWithLoras(<LoraAsset>[
        LoraAsset(
          id: 'zebra',
          label: 'Zebra',
          defaultStrength: 0.85,
          rating: 5,
        ),
        LoraAsset(
          id: 'alpha',
          label: 'Alpha',
          defaultStrength: 0.85,
          rating: 2,
        ),
        LoraAsset(
          id: 'aurora',
          label: 'Aurora',
          defaultStrength: 0.85,
          rating: 5,
        ),
      ]);

      imageModels.applyAssets(models: assets.models, loras: assets.loras);

      expect(imageModels.loras.map((item) => item.id).toList(), <String>[
        'aurora',
        'zebra',
        'alpha',
      ]);
    },
  );

  test('loadGalleryFirstPage stores first page and filter metadata', () async {
    final harness = _MediaActionsHarness(
      api: _FakeApiClient(
        assetResponse: _assetResponseWithLoras(const <LoraAsset>[]),
        firstGalleryPage: GalleryPageResponse(
          items: <ImageRecord>[_imageRecord(id: 'img-1')],
          page: 1,
          pageSize: _galleryPageSize,
          total: 2,
          hasMore: true,
        ),
        galleryFilters: GalleryFiltersResponse(
          models: const <String>['demo-model'],
          tags: const <String>['favorites', 'portrait'],
        ),
      ),
    );

    await harness.media.loadGalleryFirstPage();

    expect(harness.gallery.map((item) => item.id).toList(), <String>['img-1']);
    expect(harness.browser.currentPage, 1);
    expect(harness.browser.totalCount, 2);
    expect(harness.browser.hasMore, isTrue);
    expect(harness.browser.modelFilters, <String>['All models', 'demo-model']);
    expect(harness.browser.availableTags, <String>['favorites', 'portrait']);
  });

  test('loadGalleryNextPage appends paged items', () async {
    final api = _FakeApiClient(
      assetResponse: _assetResponseWithLoras(const <LoraAsset>[]),
      firstGalleryPage: GalleryPageResponse(
        items: <ImageRecord>[_imageRecord(id: 'img-1')],
        page: 1,
        pageSize: _galleryPageSize,
        total: 2,
        hasMore: true,
      ),
      secondGalleryPage: GalleryPageResponse(
        items: <ImageRecord>[_imageRecord(id: 'img-2')],
        page: 2,
        pageSize: _galleryPageSize,
        total: 2,
        hasMore: false,
      ),
      galleryFilters: GalleryFiltersResponse(
        models: const <String>['demo-model'],
        tags: const <String>[],
      ),
    );
    final harness = _MediaActionsHarness(api: api);

    await harness.media.loadGalleryFirstPage();
    await harness.media.loadGalleryNextPage();

    expect(harness.gallery.map((item) => item.id).toList(), <String>[
      'img-1',
      'img-2',
    ]);
    expect(harness.browser.currentPage, 2);
    expect(harness.browser.hasMore, isFalse);
  });

  test(
    'loadGalleryNextPage deduplicates overlapping paged items by id',
    () async {
      final api = _FakeApiClient(
        assetResponse: _assetResponseWithLoras(const <LoraAsset>[]),
        firstGalleryPage: GalleryPageResponse(
          items: <ImageRecord>[
            _imageRecord(id: 'img-1', prompt: 'first version'),
            _imageRecord(id: 'img-2'),
          ],
          page: 1,
          pageSize: _galleryPageSize,
          total: 3,
          hasMore: true,
        ),
        secondGalleryPage: GalleryPageResponse(
          items: <ImageRecord>[
            _imageRecord(id: 'img-2', prompt: 'updated version'),
            _imageRecord(id: 'img-3'),
          ],
          page: 2,
          pageSize: _galleryPageSize,
          total: 3,
          hasMore: false,
        ),
        galleryFilters: GalleryFiltersResponse(
          models: const <String>['demo-model'],
          tags: const <String>[],
        ),
      );
      final harness = _MediaActionsHarness(api: api);

      await harness.media.loadGalleryFirstPage();
      await harness.media.loadGalleryNextPage();

      expect(harness.gallery.map((item) => item.id).toList(), <String>[
        'img-1',
        'img-2',
        'img-3',
      ]);
      expect(
        harness.gallery.firstWhere((item) => item.id == 'img-2').prompt,
        'updated version',
      );
    },
  );

  test(
    'galleryBrowser.setSearchQuery reloads the first page with current search',
    () async {
      final api = _FakeApiClient(
        assetResponse: _assetResponseWithLoras(const <LoraAsset>[]),
        firstGalleryPage: GalleryPageResponse(
          items: <ImageRecord>[_imageRecord(id: 'img-1', prompt: 'night fox')],
          page: 1,
          pageSize: _galleryPageSize,
          total: 1,
          hasMore: false,
        ),
        galleryFilters: GalleryFiltersResponse(
          models: const <String>['demo-model'],
          tags: const <String>[],
        ),
      );
      final harness = _MediaActionsHarness(api: api);

      harness.browser.setSearchQuery('night');
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.galleryRequests, isNotEmpty);
      expect(api.galleryRequests.last['search'], 'night');
      expect(harness.gallery.map((item) => item.id).toList(), <String>[
        'img-1',
      ]);
    },
  );

  test('setImageRating updates the loaded gallery item in place', () async {
    final updated = _imageRecord(id: 'img-1', rating: 4);
    final harness = _MediaActionsHarness(
      api: _FakeApiClient(
        assetResponse: _assetResponseWithLoras(const <LoraAsset>[]),
        updatedImage: updated,
      ),
    );
    harness.gallery = <ImageRecord>[_imageRecord(id: 'img-1', rating: 1)];

    await harness.media.setImageRating('img-1', 4);

    expect(harness.gallery.first.rating, 4);
  });

  test('setImageTags updates the loaded gallery item in place', () async {
    final updated = _imageRecord(id: 'img-1', tags: const <String>['portrait']);
    final harness = _MediaActionsHarness(
      api: _FakeApiClient(
        assetResponse: _assetResponseWithLoras(const <LoraAsset>[]),
        updatedImage: updated,
      ),
    );
    harness.gallery = <ImageRecord>[_imageRecord(id: 'img-1')];

    await harness.media.setImageTags('img-1', const <String>['portrait']);

    expect(harness.gallery.first.tags, <String>['portrait']);
    expect(harness.browser.availableTags, contains('portrait'));
  });
}

class _MediaActionsHarness {
  _MediaActionsHarness({required this.api}) {
    browser = GalleryBrowserState(
      reloadFirstPage: () => media.loadGalleryFirstPage(),
      sortLoadedItems: () => gallery.sort(browser.compareItems),
      onChanged: () {},
    );
    media = MediaActionsState(
      api: () => api,
      galleryBrowser: browser,
      gallery: () => gallery,
      setGallery: (value) => gallery = value,
      latestImage: () => latestImage,
      setLatestImage: (value) => latestImage = value,
      setSuggestedTags: (value) => suggestedTags = value,
      setImportingGalleryMedia: (value) => importingGalleryMedia = value,
      findKnownMedia: _findKnownMedia,
      removeGalleryItem: _removeGalleryItem,
      replaceGalleryItem: _replaceGalleryItem,
      loadJobs: () async {},
      syncMediaRefreshTimer: () {},
      setMessage: (value) => message = value,
      setRequestError: (error, {required generalMessage}) {},
      onChanged: () {},
      galleryPageSize: _galleryPageSize,
    );
  }

  final ApiClient api;
  late final GalleryBrowserState browser;
  late final MediaActionsState media;
  List<ImageRecord> gallery = <ImageRecord>[];
  ImageRecord? latestImage;
  List<String> suggestedTags = <String>[];
  bool importingGalleryMedia = false;
  String? message;

  ImageRecord? _findKnownMedia(String imageId) {
    if (latestImage?.id == imageId) {
      return latestImage;
    }
    for (final item in gallery) {
      if (item.id == imageId) {
        return item;
      }
    }
    return null;
  }

  void _removeGalleryItem(String imageId) {
    final beforeCount = gallery.length;
    gallery = gallery.where((item) => item.id != imageId).toList();
    browser.decrementTotalCount(beforeCount - gallery.length);
  }

  void _replaceGalleryItem(ImageRecord image) {
    final index = gallery.indexWhere((item) => item.id == image.id);
    final matchesQuery = browser.matches(image);
    if (index >= 0 && !matchesQuery) {
      gallery.removeAt(index);
      browser.decrementTotalCount(1);
      return;
    }
    if (!matchesQuery) {
      return;
    }
    if (index >= 0) {
      gallery[index] = image;
    } else {
      gallery.insert(0, image);
      browser.incrementTotalCount();
    }
    gallery.sort(browser.compareItems);
  }
}
