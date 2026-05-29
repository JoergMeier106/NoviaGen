import 'dart:async';

import '../../api_client.dart';
import '../../models/assets.dart';
import '../request_errors.dart';
import '../image_model_selection_state.dart';
import '../video_asset_selection_state.dart';
import '../video_generation_settings_state.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';


class AppAssetRefreshDependencies {
  const AppAssetRefreshDependencies({
    required this.connection,
    required this.activity,
    required this.imageModels,
    required this.videoAssets,
    required this.videoSettings,
    required this.persistGenerateDraft,
    required this.persistSelectedVideoPreset,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final ImageModelSelectionState Function() imageModels;
  final VideoAssetSelectionState Function() videoAssets;
  final VideoGenerationSettingsState Function() videoSettings;
  final Future<void> Function() persistGenerateDraft;
  final Future<void> Function() persistSelectedVideoPreset;
  final void Function() notifyChanged;
}

class AppAssetRefreshController {
  AppAssetRefreshController(this.dependencies);

  final AppAssetRefreshDependencies dependencies;

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
