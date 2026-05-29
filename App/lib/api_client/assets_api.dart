import 'dart:async';
import '../models/assets.dart';
import 'transport.dart';

mixin AssetApi on ApiClientTransport {
  Future<AssetResponse> fetchAssets() async {
    final response = await dio.get<Map<String, dynamic>>('/api/assets');
    return AssetResponse.fromJson(response.data!);
  }

  Future<void> deleteModel(String modelId) async {
    await dio.delete<void>('/api/assets/model/$modelId');
  }

  Future<void> deleteLora(String loraId) async {
    await dio.delete<void>('/api/assets/lora/$loraId');
  }
}
