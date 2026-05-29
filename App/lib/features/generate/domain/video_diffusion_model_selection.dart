class VideoDiffusionModelSelectionOption {
  const VideoDiffusionModelSelectionOption({
    required this.value,
    required this.label,
    this.highModelName,
    this.lowModelName,
  });

  final String value;
  final String label;
  final String? highModelName;
  final String? lowModelName;
}

List<VideoDiffusionModelSelectionOption>
buildVideoDiffusionModelSelectionOptions(Iterable<String> modelNames) {
  final normalizedNames =
      modelNames.map(_normalizeName).whereType<String>().toSet().toList()..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );

  final pairedNames = <String>{};
  final candidates = <_VideoDiffusionModelPairCandidate>[];

  for (var leftIndex = 0; leftIndex < normalizedNames.length; leftIndex++) {
    for (
      var rightIndex = leftIndex + 1;
      rightIndex < normalizedNames.length;
      rightIndex++
    ) {
      final candidate = _VideoDiffusionModelPairCandidate.tryBuild(
        normalizedNames[leftIndex],
        normalizedNames[rightIndex],
      );
      if (candidate != null) {
        candidates.add(candidate);
      }
    }
  }

  candidates.sort((left, right) {
    final labelComparison = left.label.toLowerCase().compareTo(
      right.label.toLowerCase(),
    );
    if (labelComparison != 0) {
      return labelComparison;
    }
    final rankComparison = left.variantRank.compareTo(right.variantRank);
    if (rankComparison != 0) {
      return rankComparison;
    }
    return left.value.toLowerCase().compareTo(right.value.toLowerCase());
  });

  final options = <VideoDiffusionModelSelectionOption>[];
  for (final candidate in candidates) {
    if (pairedNames.contains(candidate.highModelName) ||
        pairedNames.contains(candidate.lowModelName)) {
      continue;
    }
    pairedNames.add(candidate.highModelName);
    pairedNames.add(candidate.lowModelName);
    options.add(candidate.toOption());
  }

  for (final modelName in normalizedNames) {
    if (pairedNames.contains(modelName)) {
      continue;
    }
    options.add(
      VideoDiffusionModelSelectionOption(
        value: modelName,
        label: modelName,
        highModelName: modelName,
        lowModelName: modelName,
      ),
    );
  }

  options.sort(
    (left, right) =>
        left.label.toLowerCase().compareTo(right.label.toLowerCase()),
  );
  return options;
}

VideoDiffusionModelSelectionOption? resolveVideoDiffusionModelSelectionOption(
  Iterable<VideoDiffusionModelSelectionOption> options, {
  String? highModelName,
  String? lowModelName,
}) {
  final normalizedHigh = _normalizeName(highModelName);
  final normalizedLow = _normalizeName(lowModelName);
  if (normalizedHigh == null && normalizedLow == null) {
    return null;
  }

  for (final option in options) {
    if (option.highModelName == normalizedHigh &&
        option.lowModelName == normalizedLow) {
      return option;
    }
  }
  if (normalizedHigh != null) {
    for (final option in options) {
      if (option.highModelName == normalizedHigh) {
        return option;
      }
    }
  }
  if (normalizedLow != null) {
    for (final option in options) {
      if (option.lowModelName == normalizedLow) {
        return option;
      }
    }
  }
  return null;
}

String? _normalizeName(String? modelName) {
  final trimmedName = modelName?.trim() ?? '';
  return trimmedName.isEmpty ? null : trimmedName;
}

enum _VideoDiffusionModelVariant { high, low }

class _VideoDiffusionModelPairCandidate {
  const _VideoDiffusionModelPairCandidate({
    required this.highModelName,
    required this.lowModelName,
    required this.label,
    required this.variantRank,
  });

  final String highModelName;
  final String lowModelName;
  final String label;
  final int variantRank;

  String get value => highModelName;

  VideoDiffusionModelSelectionOption toOption() {
    return VideoDiffusionModelSelectionOption(
      value: value,
      label: label,
      highModelName: highModelName,
      lowModelName: lowModelName,
    );
  }

  static _VideoDiffusionModelPairCandidate? tryBuild(
    String leftName,
    String rightName,
  ) {
    if (leftName == rightName) {
      return null;
    }

    var prefixLength = 0;
    final shortestLength = leftName.length < rightName.length
        ? leftName.length
        : rightName.length;
    while (prefixLength < shortestLength &&
        leftName.codeUnitAt(prefixLength) == rightName.codeUnitAt(prefixLength)) {
      prefixLength++;
    }

    var leftSuffixIndex = leftName.length - 1;
    var rightSuffixIndex = rightName.length - 1;
    while (leftSuffixIndex >= prefixLength &&
        rightSuffixIndex >= prefixLength &&
        leftName.codeUnitAt(leftSuffixIndex) ==
            rightName.codeUnitAt(rightSuffixIndex)) {
      leftSuffixIndex--;
      rightSuffixIndex--;
    }

    final leftDiff = leftName.substring(prefixLength, leftSuffixIndex + 1);
    final rightDiff = rightName.substring(prefixLength, rightSuffixIndex + 1);
    final leftVariant = _variantForDiff(leftDiff);
    final rightVariant = _variantForDiff(rightDiff);
    if (leftVariant == null || rightVariant == null || leftVariant == rightVariant) {
      return null;
    }
    if (!_matchingVariantWidth(leftDiff, rightDiff)) {
      return null;
    }

    final label = _labelWithoutVariant(
      leftName,
      prefixLength,
      leftSuffixIndex + 1,
    );
    final highModelName =
        leftVariant == _VideoDiffusionModelVariant.high ? leftName : rightName;
    final lowModelName =
        leftVariant == _VideoDiffusionModelVariant.low ? leftName : rightName;

    return _VideoDiffusionModelPairCandidate(
      highModelName: highModelName,
      lowModelName: lowModelName,
      label: label,
      variantRank: leftDiff.length + rightDiff.length,
    );
  }

  static _VideoDiffusionModelVariant? _variantForDiff(String diff) {
    final normalized = diff.toLowerCase();
    if (normalized == 'high' || normalized == 'h') {
      return _VideoDiffusionModelVariant.high;
    }
    if (normalized == 'low' || normalized == 'l') {
      return _VideoDiffusionModelVariant.low;
    }
    return null;
  }

  static String _labelWithoutVariant(
    String name,
    int prefixLength,
    int suffixStart,
  ) {
    var prefix = name.substring(0, prefixLength);
    var suffix = name.substring(suffixStart);
    if (prefix.isNotEmpty && suffix.isNotEmpty) {
      final prefixLast = prefix[prefix.length - 1];
      final suffixFirst = suffix[0];
      if (_isPairSeparator(prefixLast) && _isPairSeparator(suffixFirst)) {
        suffix = suffix.substring(1);
      } else if (_isPairSeparator(prefixLast) && suffixFirst == '.') {
        prefix = prefix.substring(0, prefix.length - 1);
      }
    }
    return prefix + suffix;
  }

  static bool _isPairSeparator(String value) {
    return value == '_' || value == '-' || value == ' ' || value == '.';
  }

  static bool _matchingVariantWidth(String leftDiff, String rightDiff) {
    final left = leftDiff.toLowerCase();
    final right = rightDiff.toLowerCase();
    return (left == 'high' && right == 'low') ||
        (left == 'low' && right == 'high') ||
        (left == 'h' && right == 'l') ||
        (left == 'l' && right == 'h');
  }
}
