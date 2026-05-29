import 'package:flutter/material.dart';


class ChatMarkdownMessage extends StatelessWidget {
  const ChatMarkdownMessage({
    super.key,
    required this.text,
    required this.textColor,
    required this.bubbleColor,
    this.baseStyle,
  });

  final String text;
  final Color textColor;
  final Color bubbleColor;
  final TextStyle? baseStyle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle =
        (baseStyle ?? theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
          color: textColor,
          height: 1.45,
        );
    final blocks = _parseMarkdownBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          _MarkdownBlockView(
            block: blocks[index],
            defaultStyle: defaultStyle,
            textColor: textColor,
            bubbleColor: bubbleColor,
          ),
          if (index < blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MarkdownBlockView extends StatelessWidget {
  const _MarkdownBlockView({
    required this.block,
    required this.defaultStyle,
    required this.textColor,
    required this.bubbleColor,
  });

  final _MarkdownBlock block;
  final TextStyle defaultStyle;
  final Color textColor;
  final Color bubbleColor;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (block.type) {
      case _MarkdownBlockType.heading:
        final headingLevel = block.level.clamp(1, 6);
        final headingStyle = switch (headingLevel) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          3 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        return SelectableText.rich(
          TextSpan(
            style: (headingStyle ?? defaultStyle).copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            children: _buildInlineMarkdownSpans(
              block.text,
              (headingStyle ?? defaultStyle).copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        );
      case _MarkdownBlockType.unorderedListItem:
      case _MarkdownBlockType.orderedListItem:
        final marker = block.type == _MarkdownBlockType.orderedListItem
            ? '${block.marker}.'
            : '\u2022';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  marker,
                  style: defaultStyle.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SelectableText.rich(
                TextSpan(
                  style: defaultStyle,
                  children: _buildInlineMarkdownSpans(block.text, defaultStyle),
                ),
              ),
            ),
          ],
        );
      case _MarkdownBlockType.blockQuote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: textColor.withValues(alpha: 0.35),
                width: 3,
              ),
            ),
            color: bubbleColor.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText.rich(
            TextSpan(
              style: defaultStyle.copyWith(
                color: textColor.withValues(alpha: 0.92),
              ),
              children: _buildInlineMarkdownSpans(
                block.text,
                defaultStyle.copyWith(color: textColor.withValues(alpha: 0.92)),
              ),
            ),
          ),
        );
      case _MarkdownBlockType.codeFence:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              block.text,
              style: defaultStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (defaultStyle.fontSize ?? 16) * 0.92,
                height: 1.5,
              ),
            ),
          ),
        );
      case _MarkdownBlockType.horizontalRule:
        return Divider(
          height: 1,
          thickness: 1,
          color: textColor.withValues(alpha: 0.18),
        );
      case _MarkdownBlockType.paragraph:
        return SelectableText.rich(
          TextSpan(
            style: defaultStyle,
            children: _buildInlineMarkdownSpans(block.text, defaultStyle),
          ),
        );
    }
  }
}

enum _MarkdownBlockType {
  paragraph,
  heading,
  unorderedListItem,
  orderedListItem,
  blockQuote,
  codeFence,
  horizontalRule,
}

class _MarkdownBlock {
  const _MarkdownBlock({
    required this.type,
    required this.text,
    this.level = 0,
    this.marker,
  });

  final _MarkdownBlockType type;
  final String text;
  final int level;
  final String? marker;
}

List<_MarkdownBlock> _parseMarkdownBlocks(String text) {
  final normalized = text.replaceAll('\r\n', '\n').trimRight();
  if (normalized.isEmpty) {
    return const <_MarkdownBlock>[];
  }
  final lines = normalized.split('\n');
  final blocks = <_MarkdownBlock>[];
  final paragraphLines = <String>[];
  final codeLines = <String>[];
  var inCodeBlock = false;

  void flushParagraph() {
    if (paragraphLines.isEmpty) {
      return;
    }
    blocks.add(
      _MarkdownBlock(
        type: _MarkdownBlockType.paragraph,
        text: paragraphLines.join('\n').trim(),
      ),
    );
    paragraphLines.clear();
  }

  void flushCodeBlock() {
    if (codeLines.isEmpty) {
      blocks.add(
        const _MarkdownBlock(type: _MarkdownBlockType.codeFence, text: ''),
      );
    } else {
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.codeFence,
          text: codeLines.join('\n'),
        ),
      );
      codeLines.clear();
    }
  }

  for (final line in lines) {
    final trimmed = line.trimRight();
    final bare = trimmed.trimLeft();
    if (bare.startsWith('```')) {
      flushParagraph();
      if (inCodeBlock) {
        flushCodeBlock();
      }
      inCodeBlock = !inCodeBlock;
      continue;
    }
    if (inCodeBlock) {
      codeLines.add(trimmed);
      continue;
    }
    if (bare.isEmpty) {
      flushParagraph();
      continue;
    }

    final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(bare);
    if (headingMatch != null) {
      flushParagraph();
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.heading,
          text: headingMatch.group(2)!.trim(),
          level: headingMatch.group(1)!.length,
        ),
      );
      continue;
    }

    final quoteMatch = RegExp(r'^>\s?(.*)$').firstMatch(bare);
    if (quoteMatch != null) {
      flushParagraph();
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.blockQuote,
          text: quoteMatch.group(1) ?? '',
        ),
      );
      continue;
    }

    if (RegExp(r'^([-*_])(\s*\1){2,}\s*$').hasMatch(bare)) {
      flushParagraph();
      blocks.add(
        const _MarkdownBlock(type: _MarkdownBlockType.horizontalRule, text: ''),
      );
      continue;
    }

    final orderedMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(bare);
    if (orderedMatch != null) {
      flushParagraph();
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.orderedListItem,
          text: orderedMatch.group(2)!.trim(),
          marker: orderedMatch.group(1),
        ),
      );
      continue;
    }

    final unorderedMatch = RegExp(r'^[-*]\s+(.+)$').firstMatch(bare);
    if (unorderedMatch != null) {
      flushParagraph();
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.unorderedListItem,
          text: unorderedMatch.group(1)!.trim(),
        ),
      );
      continue;
    }

    paragraphLines.add(trimmed);
  }

  flushParagraph();
  if (inCodeBlock) {
    flushCodeBlock();
  }
  return blocks;
}

List<InlineSpan> _buildInlineMarkdownSpans(String text, TextStyle baseStyle) {
  if (text.isEmpty) {
    return <InlineSpan>[TextSpan(style: baseStyle, text: '')];
  }
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'(`[^`]+`|\*\*[^*][\s\S]*?\*\*|__[^_][\s\S]*?__|~~[^~][\s\S]*?~~|\*[^*\n][\s\S]*?\*|_[^_\n][\s\S]*?_|(?:\[(.*?)\]\((.*?)\)))',
    multiLine: true,
  );
  var currentIndex = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > currentIndex) {
      spans.add(
        TextSpan(
          text: text.substring(currentIndex, match.start),
          style: baseStyle,
        ),
      );
    }
    final token = match.group(0)!;
    if (token.startsWith('`') && token.endsWith('`')) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              token.substring(1, token.length - 1),
              style: baseStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (baseStyle.fontSize ?? 16) * 0.92,
              ),
            ),
          ),
        ),
      );
    } else if ((token.startsWith('**') && token.endsWith('**')) ||
        (token.startsWith('__') && token.endsWith('__'))) {
      spans.addAll(
        _buildInlineMarkdownSpans(
          token.substring(2, token.length - 2),
          baseStyle.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else if (token.startsWith('~~') && token.endsWith('~~')) {
      spans.addAll(
        _buildInlineMarkdownSpans(
          token.substring(2, token.length - 2),
          baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ),
      );
    } else if ((token.startsWith('*') && token.endsWith('*')) ||
        (token.startsWith('_') && token.endsWith('_'))) {
      spans.addAll(
        _buildInlineMarkdownSpans(
          token.substring(1, token.length - 1),
          baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else if (token.startsWith('[') &&
        token.contains('](') &&
        token.endsWith(')')) {
      final label = match.group(2) ?? '';
      final url = match.group(3) ?? '';
      final visibleText = url.isEmpty || url == label ? label : '$label ($url)';
      spans.add(
        TextSpan(
          text: visibleText,
          style: baseStyle.copyWith(
            color: baseStyle.color?.withValues(alpha: 0.92),
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    } else {
      spans.add(TextSpan(text: token, style: baseStyle));
    }
    currentIndex = match.end;
  }
  if (currentIndex < text.length) {
    spans.add(TextSpan(text: text.substring(currentIndex), style: baseStyle));
  }
  return spans;
}
