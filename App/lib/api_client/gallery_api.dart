import 'dart:async';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/gallery.dart';
import '../models/media.dart';
import 'transport.dart';

mixin GalleryApi on ApiClientTransport {
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
    final response = await dio.get<Map<String, dynamic>>(
      '/api/images',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (mediaType.trim().isNotEmpty && mediaType != 'all')
          'media_type': mediaType,
        if (modelId != null &&
            modelId.trim().isNotEmpty &&
            modelId != 'All models')
          'model_id': modelId,
        if (includeTags.isNotEmpty) 'include_tags': includeTags.join(','),
        if (excludeTags.isNotEmpty) 'exclude_tags': excludeTags.join(','),
        if (minRating > 0) 'min_rating': minRating,
        if (includeDeleted) 'include_deleted': '1',
        if (!includePlaceholders) 'include_placeholders': 'false',
        'sort': sort,
      },
    );
    return GalleryPageResponse.fromJson(response.data!);
  }

  Future<GalleryFiltersResponse> fetchGalleryFilters({
    bool includeDeleted = false,
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/images/filters',
      queryParameters: {if (includeDeleted) 'include_deleted': '1'},
    );
    return GalleryFiltersResponse.fromJson(response.data!);
  }

  Future<GalleryImportResponse> importGalleryImages(List<XFile> files) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/images/import',
      data: FormData.fromMap({
        'images': [
          for (final file in files)
            await MultipartFile.fromFile(file.path, filename: file.name),
        ],
      }),
    );
    return GalleryImportResponse.fromJson(response.data!);
  }

  Future<ImageRecord> fetchImage(String imageId) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/images/$imageId',
    );
    return ImageRecord.fromJson(response.data!);
  }

  Future<List<String>> fetchTags() async {
    final response = await dio.get<Map<String, dynamic>>('/api/tags');
    final tags = response.data!['tags'] as List<dynamic>? ?? <dynamic>[];
    return tags.map((item) => item as String).toList();
  }

  Future<Map<String, dynamic>> deleteTag(String tag) async {
    final response = await dio.delete<Map<String, dynamic>>(
      '/api/tags/${Uri.encodeComponent(tag)}',
    );
    return response.data!;
  }

  Future<ImageRecord> setImageRating(String imageId, int rating) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/images/$imageId/rating',
      data: {'rating': rating},
    );
    return ImageRecord.fromJson(response.data!);
  }

  Future<ImageRecord> setImageTags(String imageId, List<String> tags) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/images/$imageId/tags',
      data: {'tags': tags},
    );
    return ImageRecord.fromJson(response.data!);
  }

  Future<ImageRecord> generateImageTags(
    String imageId, {
    required String modelName,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/images/$imageId/generate-tags',
      data: {'model_name': modelName},
    );
    return ImageRecord.fromJson(response.data!);
  }

  Future<ImageRecord> restoreImage(String imageId) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/images/$imageId/restore',
    );
    return ImageRecord.fromJson(response.data!);
  }

  Future<void> deleteImage(String imageId) async {
    try {
      await dio.delete<void>('/api/images/$imageId');
    } on DioException catch (error) {
      if (error.response?.statusCode == 405 ||
          error.response?.statusCode == 404) {
        await dio.post<void>('/api/images/$imageId/delete');
        return;
      }
      rethrow;
    }
  }

  Future<List<int>> fetchImageBytes(String imageUrl) async {
    final response = await dio.get<List<int>>(
      imageUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? <int>[];
  }
}
