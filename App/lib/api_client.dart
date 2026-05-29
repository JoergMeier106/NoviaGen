import 'package:dio/dio.dart';

import 'api_client/transport.dart';
import 'api_client/assets_api.dart';
import 'api_client/prompt_api.dart';
import 'api_client/chat_api.dart';
import 'api_client/image_jobs_api.dart';
import 'api_client/video_jobs_api.dart';
import 'api_client/media_jobs_api.dart';
import 'api_client/job_queue_api.dart';
import 'api_client/gallery_api.dart';
import 'api_client/backup_api.dart';
import 'api_client/system_api.dart';

class ApiClient
    extends ApiClientTransport
    with
        AssetApi,
        PromptApi,
        ChatApi,
        ImageJobApi,
        VideoJobApi,
        MediaJobApi,
        JobQueueApi,
        GalleryApi,
        BackupApi,
        SystemApi {
  ApiClient(String baseUrl)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

  final Dio _dio;

  @override
  Dio get dio => _dio;
}
