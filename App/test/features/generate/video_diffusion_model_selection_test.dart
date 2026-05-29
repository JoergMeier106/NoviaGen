import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/features/generate/domain/video_diffusion_model_selection.dart';
import 'package:flutter_app/features/generate/services/generation_job_factory.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/models/assets.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('buildVideoDiffusionModelSelectionOptions groups High/Low pairs', () {
    final options = buildVideoDiffusionModelSelectionOptions(const <String>[
      'video-high.safetensors',
      'video-low.safetensors',
      'solo-model.safetensors',
    ]);

    expect(
      options.map((item) => item.label),
      contains('video-High/Low.safetensors'),
    );
    expect(
      options
          .where((item) => item.label == 'video-High/Low.safetensors')
          .single
          .highModelName,
      'video-high.safetensors',
    );
    expect(
      options
          .where((item) => item.label == 'video-High/Low.safetensors')
          .single
          .lowModelName,
      'video-low.safetensors',
    );
    expect(
      options
          .where((item) => item.label == 'solo-model.safetensors')
          .single
          .highModelName,
      'solo-model.safetensors',
    );
    expect(
      options
          .where((item) => item.label == 'solo-model.safetensors')
          .single
          .lowModelName,
      'solo-model.safetensors',
    );
  });

  test('i2v selection sets matching high and low overrides automatically', () {
    final store = VideoAssetSelectionStore(onChanged: () {});
    store.applyAssets(
      videoModels: <VideoModelAsset>[],
      diffusionModels: <VideoDiffusionModelAsset>[
        VideoDiffusionModelAsset(name: 'motion-H.safetensors'),
        VideoDiffusionModelAsset(name: 'motion-L.safetensors'),
      ],
      presets: <VideoPresetOption>[],
    );

    store.setImageToVideoDiffusionModelSelection('motion-H.safetensors');

    expect(store.selectedImageToVideoHighDiffusionModel, 'motion-H.safetensors');
    expect(store.selectedImageToVideoLowDiffusionModel, 'motion-L.safetensors');
  });

  test(
    'i2v selection repair resolves stored mismatches to a matching pair',
    () {
      final store = VideoAssetSelectionStore(onChanged: () {});
      store.selectedImageToVideoHighDiffusionModelName = 'clip-H.safetensors';
      store.selectedImageToVideoLowDiffusionModelName = 'wrong-low.safetensors';

      store.applyAssets(
        videoModels: <VideoModelAsset>[],
        diffusionModels: <VideoDiffusionModelAsset>[
          VideoDiffusionModelAsset(name: 'clip-H.safetensors'),
          VideoDiffusionModelAsset(name: 'clip-L.safetensors'),
          VideoDiffusionModelAsset(name: 'wrong-low.safetensors'),
        ],
        presets: <VideoPresetOption>[],
      );

      expect(
        store.selectedImageToVideoHighDiffusionModel,
        'clip-H.safetensors',
      );
      expect(store.selectedImageToVideoLowDiffusionModel, 'clip-L.safetensors');
    },
  );

  test('videoGenerationPayload includes paired i2v diffusion models', () {
    final defaults = GenerationDefaultsStore(onChanged: () {});
    final store = VideoAssetSelectionStore(onChanged: () {});
    store.applyAssets(
      videoModels: <VideoModelAsset>[],
      diffusionModels: <VideoDiffusionModelAsset>[
        VideoDiffusionModelAsset(name: 'demo-high.safetensors'),
        VideoDiffusionModelAsset(name: 'demo-low.safetensors'),
      ],
      presets: <VideoPresetOption>[],
    );
    store.setImageToVideoDiffusionModelSelection('demo-high.safetensors');
    final factory = GenerationJobFactory(
      defaults: defaults,
      videoAssets: store,
      chatModelCatalog: ChatModelCatalogStore(
        api: () => null,
        setRequestError: (_, {required generalMessage}) {},
        onChanged: () {},
      ),
    );

    final payload = factory.videoGenerationPayload(
      prompt: 'animate this',
      defaultPositivePrompt: 'best quality',
      defaultNegativePrompt: 'bad quality',
      presetId: 'preview',
      settings: <String, int>{'width': 640, 'height': 384},
      storedSource: null,
      uploadRef: 'upload-ref',
    );

    expect(payload['high_diffusion_model_name'], 'demo-high.safetensors');
    expect(payload['low_diffusion_model_name'], 'demo-low.safetensors');
  });
}
