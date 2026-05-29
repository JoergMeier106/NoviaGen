import 'dart:async';

import 'package:flutter_app/api_client.dart';
import 'package:flutter_app/models/assets.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';


class AssetRefreshDependencies {
  const AssetRefreshDependencies({
    required this.connection,
    required this.activity,
    required this.imageModels,
    required this.videoAssets,
    required this.videoSettings,
    required this.persistGenerateDraft,
    required this.persistSelectedVideoPreset,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final ImageModelSelectionStore Function() imageModels;
  final VideoAssetSelectionStore Function() videoAssets;
  final VideoGenerationSettingsStore Function() videoSettings;
  final Future<void> Function() persistGenerateDraft;
  final Future<void> Function() persistSelectedVideoPreset;
  final void Function() notifyChanged;
}

class AssetRefreshController {
  AssetRefreshController(this.dependencies);

  final AssetRefreshDependencies dependencies;

  Future<void> refreshAssets() async {
    final client = dependencies.connection.api;
    if (client == null) {
      dependencies.connection.message = 'Set a backend URL first.';
      dependencies.notifyChanged();
      return;
    }

    dependencies.activity.loadingAssets = true;
    dependencies.connection.message = null;
    dependencies.notifyChanged();
    try {
      final response = await _fetchAssets(client);
      dependencies.imageModels().applyAssets(
        models: response.models,
        loras: response.loras,
      );
      dependencies.videoAssets().applyAssets(
        videoModels: response.videoModels,
        diffusionModels: response.videoDiffusionModels,
        presets: response.videoPresets,
      );
      dependencies.videoSettings().ensureInitialized();
      unawaited(dependencies.persistGenerateDraft());
      unawaited(dependencies.persistSelectedVideoPreset());
    } catch (error) {
      dependencies.connection.message = requestErrorMessage(
        error,
        generalMessage: 'Couldn\'t load assets right now. Please try again.',
      );
    } finally {
      dependencies.activity.loadingAssets = false;
      dependencies.notifyChanged();
    }
  }

  Future<AssetResponse> _fetchAssets(ApiClient client) {
    return client.fetchAssets();
  }
}
