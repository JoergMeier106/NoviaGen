import 'package:noviagen/models/assets.dart';

class VideoWorkflowLoraSelectionOption {
  const VideoWorkflowLoraSelectionOption({
    required this.key,
    required this.label,
    required this.loraIds,
    required this.defaultStrength,
    this.subtitle = '',
    this.tooltip = '',
  });

  final String key;
  final String label;
  final List<String> loraIds;
  final double defaultStrength;
  final String subtitle;
  final String tooltip;
}

List<VideoWorkflowLoraSelectionOption> buildVideoWorkflowLoraSelectionOptions(
  Iterable<VideoWorkflowLoraAsset> loras,
) {
  final groupedVariants = <String, _VideoWorkflowLoraSelectionDraft>{};
  final options = <VideoWorkflowLoraSelectionOption>[];

  for (final lora in loras) {
    final parsed = _ParsedVideoWorkflowLoraName.fromAsset(lora);
    final baseKey = parsed.baseKey;
    if (baseKey == null) {
      options.add(
        VideoWorkflowLoraSelectionOption(
          key: parsed.asset.id,
          label: parsed.asset.label,
          loraIds: <String>[parsed.asset.id],
          defaultStrength: parsed.asset.defaultStrength,
          subtitle: _workflowLoraSubtitle(<VideoWorkflowLoraAsset>[
            parsed.asset,
          ]),
          tooltip: parsed.asset.name,
        ),
      );
      continue;
    }
    final draft = groupedVariants.putIfAbsent(
      baseKey,
      () => _VideoWorkflowLoraSelectionDraft(baseKey),
    );
    draft.add(parsed);
  }

  for (final draft in groupedVariants.values) {
    options.addAll(draft.buildOptions());
  }

  options.sort(
    (left, right) =>
        left.label.toLowerCase().compareTo(right.label.toLowerCase()),
  );
  return options;
}

Map<String, double> normalizeVideoWorkflowLoraStrengths({
  required List<VideoWorkflowLoraAsset> loras,
  required Map<String, double> storedStrengths,
}) {
  final validIds = loras.map((item) => item.id).toSet();
  final filteredStrengths = <String, double>{
    for (final entry in storedStrengths.entries)
      if (validIds.contains(entry.key)) entry.key: entry.value,
  };
  if (filteredStrengths.isEmpty) {
    return filteredStrengths;
  }

  final normalizedStrengths = <String, double>{};
  final options = buildVideoWorkflowLoraSelectionOptions(loras);
  for (final option in options) {
    final savedStrength = option.loraIds
        .map((loraId) => filteredStrengths[loraId])
        .whereType<double>()
        .firstOrNull;
    if (savedStrength == null) {
      continue;
    }
    for (final loraId in option.loraIds) {
      normalizedStrengths[loraId] = savedStrength;
    }
  }
  return normalizedStrengths;
}

Map<String, double> resolveVideoWorkflowLoraSelectionStrengths({
  required List<VideoWorkflowLoraAsset> loras,
  required Map<String, double> storedStrengths,
}) {
  final normalizedStrengths = normalizeVideoWorkflowLoraStrengths(
    loras: loras,
    storedStrengths: storedStrengths,
  );
  final options = buildVideoWorkflowLoraSelectionOptions(loras);
  return <String, double>{
    for (final option in options)
      option.key:
          normalizedStrengths[option.loraIds.first] ?? option.defaultStrength,
  };
}

String _workflowLoraSubtitle(List<VideoWorkflowLoraAsset> loras) {
  final subtitleParts = <String>[];
  final nodeTitles = loras
      .map((item) => item.nodeTitle.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  if (nodeTitles.isNotEmpty) {
    subtitleParts.add(nodeTitles.join(' • '));
  }
  final enabledCount = loras.where((item) => item.enabled).length;
  if (enabledCount == 0) {
    subtitleParts.add('disabled in workflow');
  } else if (enabledCount < loras.length) {
    subtitleParts.add('partly disabled in workflow');
  }
  return subtitleParts.join(' • ');
}

enum _VideoWorkflowLoraVariant { high, low, none }

class _ParsedVideoWorkflowLoraName {
  const _ParsedVideoWorkflowLoraName({
    required this.asset,
    required this.variant,
    required this.variantStart,
    required this.variantEnd,
    required this.variantToken,
    required this.baseKey,
  });

  final VideoWorkflowLoraAsset asset;
  final _VideoWorkflowLoraVariant variant;
  final int? variantStart;
  final int? variantEnd;
  final String? variantToken;
  final String? baseKey;

  static final RegExp _tokenPattern = RegExp(r'[A-Za-z0-9]+');

  factory _ParsedVideoWorkflowLoraName.fromAsset(VideoWorkflowLoraAsset asset) {
    final matches = _tokenPattern.allMatches(asset.name).toList();
    var variant = _VideoWorkflowLoraVariant.none;
    Match? variantMatch;
    final baseTokens = <String>[];

    for (final match in matches) {
      final token = match.group(0) ?? '';
      final tokenVariant = _variantForToken(token);
      if (tokenVariant == _VideoWorkflowLoraVariant.none) {
        baseTokens.add(token.toLowerCase());
        continue;
      }
      if (variant != _VideoWorkflowLoraVariant.none) {
        return _ParsedVideoWorkflowLoraName(
          asset: asset,
          variant: _VideoWorkflowLoraVariant.none,
          variantStart: null,
          variantEnd: null,
          variantToken: null,
          baseKey: null,
        );
      }
      variant = tokenVariant;
      variantMatch = match;
    }

    if (variantMatch == null || baseTokens.isEmpty) {
      return _ParsedVideoWorkflowLoraName(
        asset: asset,
        variant: _VideoWorkflowLoraVariant.none,
        variantStart: null,
        variantEnd: null,
        variantToken: null,
        baseKey: null,
      );
    }

    return _ParsedVideoWorkflowLoraName(
      asset: asset,
      variant: variant,
      variantStart: variantMatch.start,
      variantEnd: variantMatch.end,
      variantToken: variantMatch.group(0),
      baseKey: baseTokens.join('|'),
    );
  }

  String pairLabel() {
    final start = variantStart;
    final end = variantEnd;
    final token = variantToken;
    if (start == null || end == null || token == null) {
      return asset.label;
    }
    final replacement = token.length == 1 ? 'H/L' : 'High/Low';
    return '${asset.label.substring(0, start)}$replacement${asset.label.substring(end)}';
  }

  static _VideoWorkflowLoraVariant _variantForToken(String token) {
    final normalized = token.toLowerCase();
    if (normalized == 'high' || normalized == 'h') {
      return _VideoWorkflowLoraVariant.high;
    }
    if (normalized == 'low' || normalized == 'l') {
      return _VideoWorkflowLoraVariant.low;
    }
    return _VideoWorkflowLoraVariant.none;
  }
}

class _VideoWorkflowLoraSelectionDraft {
  _VideoWorkflowLoraSelectionDraft(this.baseKey);

  final String baseKey;
  _ParsedVideoWorkflowLoraName? high;
  _ParsedVideoWorkflowLoraName? low;
  final List<_ParsedVideoWorkflowLoraName> extras =
      <_ParsedVideoWorkflowLoraName>[];

  void add(_ParsedVideoWorkflowLoraName parsed) {
    switch (parsed.variant) {
      case _VideoWorkflowLoraVariant.high:
        if (high == null) {
          high = parsed;
        } else {
          extras.add(parsed);
        }
      case _VideoWorkflowLoraVariant.low:
        if (low == null) {
          low = parsed;
        } else {
          extras.add(parsed);
        }
      case _VideoWorkflowLoraVariant.none:
        extras.add(parsed);
    }
  }

  List<VideoWorkflowLoraSelectionOption> buildOptions() {
    final options = <VideoWorkflowLoraSelectionOption>[];
    final highAsset = high?.asset;
    final lowAsset = low?.asset;

    if (highAsset != null && lowAsset != null) {
      options.add(
        VideoWorkflowLoraSelectionOption(
          key: highAsset.id,
          label: high!.pairLabel(),
          loraIds: <String>[highAsset.id, lowAsset.id],
          defaultStrength: highAsset.defaultStrength,
          subtitle: _workflowLoraSubtitle(<VideoWorkflowLoraAsset>[
            highAsset,
            lowAsset,
          ]),
          tooltip: '${highAsset.name}\n${lowAsset.name}',
        ),
      );
    } else {
      if (highAsset != null) {
        options.add(
          VideoWorkflowLoraSelectionOption(
            key: highAsset.id,
            label: highAsset.label,
            loraIds: <String>[highAsset.id],
            defaultStrength: highAsset.defaultStrength,
            subtitle: _workflowLoraSubtitle(<VideoWorkflowLoraAsset>[
              highAsset,
            ]),
            tooltip: highAsset.name,
          ),
        );
      }
      if (lowAsset != null) {
        options.add(
          VideoWorkflowLoraSelectionOption(
            key: lowAsset.id,
            label: lowAsset.label,
            loraIds: <String>[lowAsset.id],
            defaultStrength: lowAsset.defaultStrength,
            subtitle: _workflowLoraSubtitle(<VideoWorkflowLoraAsset>[lowAsset]),
            tooltip: lowAsset.name,
          ),
        );
      }
    }

    for (final parsed in extras) {
      options.add(
        VideoWorkflowLoraSelectionOption(
          key: parsed.asset.id,
          label: parsed.asset.label,
          loraIds: <String>[parsed.asset.id],
          defaultStrength: parsed.asset.defaultStrength,
          subtitle: _workflowLoraSubtitle(<VideoWorkflowLoraAsset>[
            parsed.asset,
          ]),
          tooltip: parsed.asset.name,
        ),
      );
    }

    return options;
  }
}
