import 'package:flutter/material.dart';

import 'package:flutter_app/models/system.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';
import 'package:flutter_app/features/settings/log_filters.dart';


class LogRowCard extends StatelessWidget {
  const LogRowCard({
    super.key,
    required this.row,
    required this.expanded,
    required this.onToggle,
    required this.onCopy,
  });

  final BackendLogRow row;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final levelColor = logLevelColor(context, row.level);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow(theme, scheme, levelColor),
                if (expanded) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  _buildExpandedDetails(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    ThemeData theme,
    ColorScheme scheme,
    Color levelColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: expanded ? 72 : 48,
          decoration: BoxDecoration(
            color: levelColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _buildRowText(theme, scheme)),
        const SizedBox(width: 4),
        _buildActions(),
      ],
    );
  }

  Widget _buildRowText(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            MetaChip(label: timestampLabel),
            MetaChip(label: loggerLabel),
            MetaChip(
              label: logLevelLabel(row.level),
              icon: Icons.flag_outlined,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          messageLabel,
          maxLines: expanded ? null : 3,
          overflow: expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.25,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        IconButton(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_all_outlined),
          tooltip: 'Copy row',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
        Icon(
          expanded ? Icons.expand_less_outlined : Icons.expand_more_outlined,
        ),
      ],
    );
  }

  Widget _buildExpandedDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ErrorDetailLine(
          label: 'Message',
          value: messageLabel,
          selectable: true,
          monospace: true,
        ),
        if (row.raw != messageLabel) ...[
          const SizedBox(height: 10),
          ErrorDetailLine(
            label: 'Raw',
            value: row.raw,
            selectable: true,
            monospace: true,
          ),
        ],
      ],
    );
  }

  String get loggerLabel {
    return row.logger?.trim().isNotEmpty == true
        ? row.logger!.trim()
        : 'unknown';
  }

  String get timestampLabel {
    return row.timestamp?.trim().isNotEmpty == true
        ? row.timestamp!.trim()
        : 'No timestamp';
  }

  String get messageLabel {
    return row.message.trim().isEmpty ? row.raw : row.message;
  }
}
