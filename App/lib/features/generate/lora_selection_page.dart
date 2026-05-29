import 'package:flutter/material.dart';

import 'package:noviagen/models/assets.dart';
import 'package:noviagen/features/generate/generation_view_model.dart';

class _LoraTile extends StatelessWidget {
  const _LoraTile({
    required this.lora,
    required this.enabled,
    required this.strength,
    required this.onChanged,
    required this.onStrengthChanged,
  });

  final LoraAsset lora;
  final bool enabled;
  final double strength;
  final ValueChanged<bool> onChanged;
  final ValueChanged<double> onStrengthChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(lora.label)),
                Switch(value: enabled, onChanged: onChanged),
              ],
            ),
            Row(
              children: [
                const Text('Strength'),
                Expanded(
                  child: Slider(
                    value: strength,
                    min: 0.1,
                    max: 2.0,
                    divisions: 19,
                    label: strength.toStringAsFixed(2),
                    onChanged: enabled ? onStrengthChanged : null,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    strength.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LoraSelectionPage extends StatelessWidget {
  const LoraSelectionPage({
    super.key,
    required this.viewModel,
  });

  final GenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final loras = viewModel.loras;
        final selectedStrengths = viewModel.selectedLoraStrengths;
        return Scaffold(
          appBar: AppBar(title: const Text('LoRAs')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _loraSelectionSummary(loras, selectedStrengths),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: selectedStrengths.isEmpty
                        ? null
                        : viewModel.clearSelectedLoras,
                    icon: const Icon(Icons.deselect_outlined),
                    label: const Text('Deselect all'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (loras.isEmpty)
                const Text('No LoRAs loaded yet.')
              else
                ...loras.map(
                  (lora) => _LoraTile(
                    lora: lora,
                    enabled: selectedStrengths.containsKey(lora.id),
                    strength: selectedStrengths[lora.id] ?? lora.defaultStrength,
                    onChanged: (enabled) =>
                        viewModel.toggleLora(lora, enabled),
                    onStrengthChanged: (value) =>
                        viewModel.setLoraStrength(lora.id, value),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _loraSelectionSummary(
  List<LoraAsset> loras,
  Map<String, double> selectedStrengths,
) {
  if (selectedStrengths.isEmpty) {
    return 'No LoRAs selected';
  }
  final labels = selectedStrengths.keys
      .map((loraId) {
        final lora = loras.where((item) => item.id == loraId).firstOrNull;
        return lora?.label ?? loraId;
      })
      .join(', ');
  return '${selectedStrengths.length} selected: $labels';
}
