import 'dart:async';

import 'package:flutter/material.dart';

import 'package:noviagen/features/generate/domain/video_diffusion_model_selection.dart';
import 'package:noviagen/features/generate/domain/video_workflow_lora_selection.dart';

class WorkflowLoraStrengthSection extends StatelessWidget {
  const WorkflowLoraStrengthSection({
    super.key,
    required this.loras,
    required this.strengths,
    required this.onStrengthChanged,
  });

  final List<VideoWorkflowLoraSelectionOption> loras;
  final Map<String, double> strengths;
  final void Function(String loraId, double strength) onStrengthChanged;

  @override
  Widget build(BuildContext context) {
    if (loras.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('No workflow LoRAs reported by the backend.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Workflow LoRAs', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final lora in loras)
          WorkflowLoraStrengthTile(
            lora: lora,
            strength: strengths[lora.key] ?? lora.defaultStrength,
            onStrengthChanged: (value) => onStrengthChanged(lora.key, value),
          ),
      ],
    );
  }
}

class VideoDiffusionModelSelectionDropdown extends StatelessWidget {
  const VideoDiffusionModelSelectionDropdown({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? selectedValue;
  final Iterable<VideoDiffusionModelSelectionOption> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final sortedOptions = options.toList()
      ..sort(
        (left, right) =>
            left.label.toLowerCase().compareTo(right.label.toLowerCase()),
      );
    final effectiveValue =
        selectedValue != null &&
            sortedOptions.any((item) => item.value == selectedValue)
        ? selectedValue!
        : '';
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: sortedOptions.isEmpty
            ? 'No ComfyUI diffusion models reported by the backend.'
            : null,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Workflow default'),
        ),
        for (final option in sortedOptions)
          DropdownMenuItem<String>(
            value: option.value,
            child: Tooltip(
              message: option.label,
              child: AutoScrollingDropdownText(option.label),
            ),
          ),
      ],
      onChanged: sortedOptions.isEmpty
          ? null
          : (value) => onChanged(value == null || value.isEmpty ? null : value),
    );
  }
}

class WorkflowLoraStrengthTile extends StatelessWidget {
  const WorkflowLoraStrengthTile({
    super.key,
    required this.lora,
    required this.strength,
    required this.onStrengthChanged,
  });

  final VideoWorkflowLoraSelectionOption lora;
  final double strength;
  final ValueChanged<double> onStrengthChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: lora.tooltip.isEmpty ? lora.label : lora.tooltip,
            child: Text(
              lora.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (lora.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(lora.subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
          Row(
            children: [
              const Text('Strength'),
              Expanded(
                child: Slider(
                  value: strength.clamp(0.0, 2.0),
                  min: 0.0,
                  max: 2.0,
                  divisions: 20,
                  label: strength.toStringAsFixed(2),
                  onChanged: onStrengthChanged,
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
    );
  }
}

class VideoDiffusionModelDropdown extends StatelessWidget {
  const VideoDiffusionModelDropdown({
    super.key,
    required this.label,
    required this.selectedModelName,
    required this.models,
    required this.onChanged,
  });

  final String label;
  final String? selectedModelName;
  final Iterable<String> models;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final sortedModels = models.toSet().toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    final effectiveValue =
        selectedModelName != null && sortedModels.contains(selectedModelName)
        ? selectedModelName!
        : '';
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: sortedModels.isEmpty
            ? 'No ComfyUI diffusion models reported by the backend.'
            : null,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Workflow default'),
        ),
        for (final model in sortedModels)
          DropdownMenuItem<String>(
            value: model,
            child: Tooltip(
              message: model,
              child: AutoScrollingDropdownText(model),
            ),
          ),
      ],
      onChanged: sortedModels.isEmpty
          ? null
          : (value) => onChanged(value == null || value.isEmpty ? null : value),
    );
  }
}

class AutoScrollingDropdownText extends StatefulWidget {
  const AutoScrollingDropdownText(this.text, {super.key});

  final String text;

  @override
  State<AutoScrollingDropdownText> createState() =>
      _AutoScrollingDropdownTextState();
}

class _AutoScrollingDropdownTextState extends State<AutoScrollingDropdownText> {
  final ScrollController _scrollController = ScrollController();
  bool _isAutoScrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
  }

  @override
  void didUpdateWidget(covariant AutoScrollingDropdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _isAutoScrolling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startAutoScroll() async {
    if (_isAutoScrolling || !mounted || !_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return;
    }
    _isAutoScrolling = true;
    while (mounted && _scrollController.hasClients) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final forwardDistance = _scrollController.position.maxScrollExtent;
      await _scrollController.animateTo(
        forwardDistance,
        duration: _scrollDuration(forwardDistance),
        curve: Curves.linear,
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      await _scrollController.animateTo(
        0,
        duration: _scrollDuration(forwardDistance),
        curve: Curves.linear,
      );
    }
  }

  Duration _scrollDuration(double distance) {
    final milliseconds = (distance * 55).round().clamp(3500, 12000);
    return Duration(milliseconds: milliseconds);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, maxLines: 1, softWrap: false),
    );
  }
}
