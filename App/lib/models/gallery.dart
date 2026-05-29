import 'media.dart';

class GalleryPageResponse {
  GalleryPageResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasMore,
  });

  final List<ImageRecord> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  factory GalleryPageResponse.fromJson(Map<String, dynamic> json) {
    return GalleryPageResponse(
      items: ((json['items'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(ImageRecord.fromJson)
          .toList()),
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 20,
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class GalleryFiltersResponse {
  GalleryFiltersResponse({required this.models, required this.tags});

  final List<String> models;
  final List<String> tags;

  factory GalleryFiltersResponse.fromJson(Map<String, dynamic> json) {
    return GalleryFiltersResponse(
      models: (json['models'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item as String)
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item as String)
          .toList(),
    );
  }
}

class GalleryImportFailure {
  GalleryImportFailure({required this.filename, required this.error});

  final String filename;
  final String error;

  factory GalleryImportFailure.fromJson(Map<String, dynamic> json) {
    return GalleryImportFailure(
      filename: json['filename'] as String? ?? 'image',
      error: json['error'] as String? ?? 'Import failed.',
    );
  }
}

class GalleryImportResponse {
  GalleryImportResponse({
    required this.items,
    required this.failures,
    required this.importedCount,
  });

  final List<ImageRecord> items;
  final List<GalleryImportFailure> failures;
  final int importedCount;

  factory GalleryImportResponse.fromJson(Map<String, dynamic> json) {
    return GalleryImportResponse(
      items: ((json['items'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(ImageRecord.fromJson)
          .toList()),
      failures: ((json['failures'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(GalleryImportFailure.fromJson)
          .toList()),
      importedCount: (json['imported_count'] as num?)?.toInt() ?? 0,
    );
  }
}
