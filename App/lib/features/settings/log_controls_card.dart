import 'package:flutter/material.dart';

import 'package:noviagen/models/system.dart';
import 'package:noviagen/shared/app_formatters.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';
import 'package:noviagen/features/settings/log_filters.dart';


class LogControlsCard extends StatelessWidget {
  const LogControlsCard({
    super.key,
    required this.selectedSource,
    required this.searchQuery,
    required this.severityFilter,
    required this.rowLimit,
    required this.snapshot,
    required this.loading,
    required this.onShowSource,
    required this.onShowSearch,
    required this.onShowSeverity,
    required this.onShowRowLimit,
    required this.onClearSearch,
    required this.onClearSeverity,
  });

  final LogSource selectedSource;
  final String searchQuery;
  final LogSeverityFilter severityFilter;
  final int rowLimit;
  final BackendLogSnapshot? snapshot;
  final bool loading;
  final VoidCallback onShowSource;
  final VoidCallback onShowSearch;
  final VoidCallback onShowSeverity;
  final VoidCallback onShowRowLimit;
  final VoidCallback onClearSearch;
  final VoidCallback onClearSeverity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(),
        const SizedBox(height: 8),
        _buildStatusRow(context),
        if (_hasActiveFilters) ...[
          const SizedBox(height: 8),
          _buildActiveFilters(),
        ],
      ],
    );
  }

  Widget _buildToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ToolbarButton(
            icon: selectedSource == LogSource.server
                ? Icons.storage_outlined
                : Icons.memory_outlined,
            label:
                'Source: ${selectedSource == LogSource.server ? 'Server' : 'Comfy'}',
            onTap: onShowSource,
          ),
          const SizedBox(width: 8),
          ToolbarButton(
            icon: Icons.search,
            label: _trimmedSearchQuery.isEmpty
                ? 'Search'
                : 'Search: $_trimmedSearchQuery',
            onTap: onShowSearch,
          ),
          const SizedBox(width: 8),
          ToolbarButton(
            icon: Icons.filter_alt_outlined,
            label: 'Severity: ${logSeverityFilterLabel(severityFilter)}',
            onTap: onShowSeverity,
          ),
          const SizedBox(width: 8),
          ToolbarButton(
            icon: Icons.format_list_numbered_outlined,
            label: 'Rows: $rowLimit',
            onTap: onShowRowLimit,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    return Row(
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.schedule_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        Expanded(
          child: Text(
            '$_updatedLabel • $_truncationLabel',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (_trimmedSearchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActiveChip(
                label: 'Search: $_trimmedSearchQuery',
                onDeleted: onClearSearch,
              ),
            ),
          if (severityFilter != LogSeverityFilter.all)
            ActiveChip(
              label: 'Severity: ${logSeverityFilterLabel(severityFilter)}',
              onDeleted: onClearSeverity,
            ),
        ],
      ),
    );
  }

  String get _trimmedSearchQuery => searchQuery.trim();

  bool get _hasActiveFilters {
    return _trimmedSearchQuery.isNotEmpty ||
        severityFilter != LogSeverityFilter.all;
  }

  String get _updatedLabel {
    if (snapshot == null || snapshot!.refreshedAt.isEmpty) {
      return 'Not loaded yet';
    }
    return 'Updated ${formatTimestamp(snapshot!.refreshedAt)}';
  }

  String get _truncationLabel {
    if (snapshot == null) {
      return 'Select a source to load logs.';
    }
    if (snapshot!.truncated) {
      return 'Showing the latest ${snapshot!.rows.length} of ${snapshot!.limit}+ rows.';
    }
    return 'Showing ${snapshot!.rows.length} row(s).';
  }
}
