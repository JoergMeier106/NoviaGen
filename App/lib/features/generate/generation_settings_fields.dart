import 'package:flutter/material.dart';

import 'package:noviagen/models/assets.dart';
import 'package:noviagen/models/prompts.dart';
class VideoSettingField extends StatelessWidget {
  const VideoSettingField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class PromptPresetDropdown extends StatelessWidget {
  const PromptPresetDropdown({
    super.key,
    required this.label,
    required this.selectedPresetId,
    required this.presets,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final String? selectedPresetId;
  final List<PromptPreset> presets;
  final ValueChanged<String?> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final dropdownValue = selectedPresetId ?? '';
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$dropdownValue-${presets.length}'),
      initialValue: dropdownValue,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('No preset')),
        ...presets.map(
          (preset) => DropdownMenuItem<String>(
            value: preset.id,
            child: Text(preset.name),
          ),
        ),
      ],
      onChanged: (value) =>
          onChanged(value == null || value.isEmpty ? null : value),
    );
  }
}

String videoPresetDropdownLabel(VideoPresetOption preset) {
  return '${preset.label} - ${preset.numFrames} frames - ${preset.fps} FPS';
}
