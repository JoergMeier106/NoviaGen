import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noviagen/features/generate/domain/video_workflow_lora_selection.dart';
import 'package:noviagen/features/generate/state/video_asset_selection_store.dart';
import 'package:noviagen/models/assets.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('buildVideoWorkflowLoraSelectionOptions groups High/Low pairs', () {
    final options =
        buildVideoWorkflowLoraSelectionOptions(<VideoWorkflowLoraAsset>[
          VideoWorkflowLoraAsset(
            id: 'high',
            name: 'motion-high.safetensors',
            label: 'motion-high.safetensors',
            defaultStrength: 1.0,
            enabled: true,
            nodeTitle: 'LoRA High',
          ),
          VideoWorkflowLoraAsset(
            id: 'low',
            name: 'motion-low.safetensors',
            label: 'motion-low.safetensors',
            defaultStrength: 1.0,
            enabled: true,
            nodeTitle: 'LoRA Low',
          ),
          VideoWorkflowLoraAsset(
            id: 'solo',
            name: 'solo-lora.safetensors',
            label: 'solo-lora.safetensors',
            defaultStrength: 0.8,
            enabled: true,
            nodeTitle: 'Solo',
          ),
        ]);

    expect(
      options.map((item) => item.label),
      contains('motion-High/Low.safetensors'),
    );
    expect(
      options
          .where((item) => item.label == 'motion-High/Low.safetensors')
          .single
          .loraIds,
      <String>['high', 'low'],
    );
    expect(
      options
          .where((item) => item.label == 'solo-lora.safetensors')
          .single
          .loraIds,
      <String>['solo'],
    );
  });

  test('text-to-video grouped workflow lora strength updates both raw ids', () {
    final store = VideoAssetSelectionStore(onChanged: () {});
    store.applyAssets(
      videoModels: <VideoModelAsset>[
        VideoModelAsset(
          id: 'comfy-text-to-video',
          label: 'Text to video',
          workflowLoras: <VideoWorkflowLoraAsset>[
            VideoWorkflowLoraAsset(
              id: 'high',
              name: 'adapter-H.safetensors',
              label: 'adapter-H.safetensors',
              defaultStrength: 1.0,
              enabled: true,
              nodeTitle: 'High',
            ),
            VideoWorkflowLoraAsset(
              id: 'low',
              name: 'adapter-L.safetensors',
              label: 'adapter-L.safetensors',
              defaultStrength: 1.0,
              enabled: true,
              nodeTitle: 'Low',
            ),
          ],
        ),
      ],
      diffusionModels: <VideoDiffusionModelAsset>[],
      presets: <VideoPresetOption>[],
    );

    store.setTextToVideoWorkflowLoraStrength('high', 0.65);

    final payloadLoras = store.workflowLoraStrengths(imageToVideo: false);
    expect(
      payloadLoras.where((item) => item.loraId == 'high').single.strength,
      0.65,
    );
    expect(
      payloadLoras.where((item) => item.loraId == 'low').single.strength,
      0.65,
    );
  });

  test(
    'grouped workflow lora strength repair normalizes mismatched saved values',
    () {
      final store = VideoAssetSelectionStore(onChanged: () {});
      store.textToVideoWorkflowLoraStrengths = <String, double>{
        'high': 0.4,
        'low': 1.2,
      };

      store.applyAssets(
        videoModels: <VideoModelAsset>[
          VideoModelAsset(
            id: 'comfy-text-to-video',
            label: 'Text to video',
            workflowLoras: <VideoWorkflowLoraAsset>[
              VideoWorkflowLoraAsset(
                id: 'high',
                name: 'adapter-H.safetensors',
                label: 'adapter-H.safetensors',
                defaultStrength: 1.0,
                enabled: true,
                nodeTitle: 'High',
              ),
              VideoWorkflowLoraAsset(
                id: 'low',
                name: 'adapter-L.safetensors',
                label: 'adapter-L.safetensors',
                defaultStrength: 1.0,
                enabled: true,
                nodeTitle: 'Low',
              ),
            ],
          ),
        ],
        diffusionModels: <VideoDiffusionModelAsset>[],
        presets: <VideoPresetOption>[],
      );

      expect(store.textToVideoWorkflowLoraStrengths['high'], 0.4);
      expect(store.textToVideoWorkflowLoraStrengths['low'], 0.4);
      expect(store.textToVideoWorkflowLoraSelectionStrengths['high'], 0.4);
    },
  );
}
