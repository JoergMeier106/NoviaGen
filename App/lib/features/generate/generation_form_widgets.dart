import 'dart:async';

import 'package:flutter/material.dart';


class PromptGenerateField extends StatelessWidget {
  const PromptGenerateField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    required this.generatingPrompt,
    required this.disableGenerate,
    required this.onGenerate,
    this.additionalActions = const <Widget>[],
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool generatingPrompt;
  final bool disableGenerate;
  final Future<void> Function() onGenerate;
  final List<Widget> additionalActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    onPressed: disableGenerate
                        ? null
                        : () => unawaited(onGenerate()),
                    tooltip: generatingPrompt
                        ? 'Queue another prompt job'
                        : 'Generate prompt',
                    icon: const Icon(Icons.auto_fix_high),
                  ),
                  ...additionalActions,
                  IconButton.outlined(
                    onPressed: value.text.isEmpty
                        ? null
                        : () {
                            controller.clear();
                            onChanged('');
                          },
                    tooltip: 'Clear prompt',
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
