import 'package:flutter/material.dart';

import 'package:flutter_app/models/system.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';
import 'package:flutter_app/features/settings/log_row_card.dart';


class LogBody extends StatelessWidget {
  const LogBody({
    super.key,
    required this.baseUrlConfigured,
    required this.snapshot,
    required this.loading,
    required this.filteredRows,
    required this.rowKeys,
    required this.expandedRows,
    required this.scrollController,
    required this.onToggleRow,
    required this.onCopyRow,
  });

  final bool baseUrlConfigured;
  final BackendLogSnapshot? snapshot;
  final bool loading;
  final List<BackendLogRow> filteredRows;
  final List<String> rowKeys;
  final Set<String> expandedRows;
  final ScrollController scrollController;
  final ValueChanged<String> onToggleRow;
  final ValueChanged<BackendLogRow> onCopyRow;

  @override
  Widget build(BuildContext context) {
    if (!baseUrlConfigured) {
      return _messageList(
        const InfoCard(
          title: 'Backend',
          child: Text('Set a backend URL first.'),
        ),
      );
    }
    if (loading && snapshot == null) {
      return _messageList(
        const Center(child: CircularProgressIndicator()),
        topPadding: 32,
      );
    }
    if (snapshot == null || snapshot!.rows.isEmpty) {
      return _messageList(
        const InfoCard(
          title: 'Logs',
          child: Text('No log rows are available yet for this source.'),
        ),
      );
    }
    if (filteredRows.isEmpty) {
      return _messageList(
        const InfoCard(
          title: 'No matches',
          child: Text(
            'No log rows match the current search or severity filter.',
          ),
        ),
      );
    }
    return _buildRows();
  }

  Widget _messageList(Widget child, {double topPadding = 0}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, 12),
      children: [child],
    );
  }

  Widget _buildRows() {
    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: filteredRows.length,
      itemBuilder: (context, index) {
        final row = filteredRows[index];
        final rowKey = rowKeys[index];
        return Padding(
          key: ValueKey<String>(rowKey),
          padding: const EdgeInsets.only(bottom: 8),
          child: LogRowCard(
            row: row,
            expanded: expandedRows.contains(rowKey),
            onToggle: () => onToggleRow(rowKey),
            onCopy: () => onCopyRow(row),
          ),
        );
      },
    );
  }
}
