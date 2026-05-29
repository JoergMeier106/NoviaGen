import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:noviagen/models/system.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';
import 'package:noviagen/features/settings/log_body.dart';
import 'package:noviagen/features/settings/log_controls_card.dart';
import 'package:noviagen/features/settings/log_filters.dart';
import 'package:noviagen/features/settings/log_sheets.dart';

import 'package:noviagen/features/settings/settings_view_model.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedRows = <String>{};
  final Map<LogSource, String?> _snapshotTokens = <LogSource, String?>{};
  Timer? _refreshTimer;
  LogSource _selectedSource = LogSource.server;
  LogSeverityFilter _severityFilter = LogSeverityFilter.all;
  int _rowLimit = 500;
  bool _followLatest = true;
  bool _showJumpToLatest = false;
  bool _loaded = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedSource = logSourceFromName(widget.viewModel.selectedSource);
    _severityFilter = logSeverityFilterFromName(
      widget.viewModel.severityFilter,
    );
    _rowLimit = widget.viewModel.rowLimit;
    _followLatest = true;
    _scrollController.addListener(_handleScroll);
    _searchController.addListener(() {
      final nextQuery = _searchController.text;
      if (nextQuery == _searchQuery) {
        return;
      }
      setState(() {
        _searchQuery = nextQuery;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_loaded && widget.viewModel.baseUrl.trim().isNotEmpty) {
        _loaded = true;
        await _refreshActiveLogs(forceScrollToLatest: true);
      }
      _startAutoRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceKey = logSourceKey(_selectedSource);
    final snapshot = widget.viewModel.snapshotForSource(sourceKey);
    final loading = widget.viewModel.isLoading(sourceKey);
    final filteredRows = _filterRows(
      snapshot?.rows ?? const <BackendLogRow>[],
    );
    final rowKeys = _buildStableRowKeys(filteredRows);
    return Scaffold(
          appBar: AppBar(
            title: const Text('Logs'),
            actions: [
              IconButton(
                onPressed: loading ? null : _refreshActiveLogs,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh logs',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: LogControlsCard(
                    selectedSource: _selectedSource,
                    searchQuery: _searchQuery,
                    severityFilter: _severityFilter,
                    rowLimit: _rowLimit,
                    snapshot: snapshot,
                    loading: loading,
                    onShowSource: () => _showSourceSheet(context),
                    onShowSearch: () => _showSearchSheet(context),
                    onShowSeverity: () => _showSeveritySheet(context),
                    onShowRowLimit: () => _showRowLimitSheet(context),
                    onClearSearch: _searchController.clear,
                    onClearSeverity: _clearSeverityFilter,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RefreshIndicator(
                          onRefresh: _refreshActiveLogs,
                          child: _buildLogBody(
                            snapshot: snapshot,
                            loading: loading,
                            filteredRows: filteredRows,
                            rowKeys: rowKeys,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: AnimatedScale(
                          scale: (!_followLatest || _showJumpToLatest) ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: LogScrollToBottomButton(
                            onTap: (!_followLatest || _showJumpToLatest)
                                ? _jumpToLatest
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildLogBody({
    required BackendLogSnapshot? snapshot,
    required bool loading,
    required List<BackendLogRow> filteredRows,
    required List<String> rowKeys,
  }) {
    return LogBody(
      baseUrlConfigured: widget.viewModel.baseUrl.trim().isNotEmpty,
      snapshot: snapshot,
      loading: loading,
      filteredRows: filteredRows,
      rowKeys: rowKeys,
      expandedRows: _expandedRows,
      scrollController: _scrollController,
      onToggleRow: _toggleExpandedRow,
      onCopyRow: (row) => _copyRow(context, row),
    );
  }

  void _toggleExpandedRow(String rowKey) {
    setState(() {
      if (_expandedRows.contains(rowKey)) {
        _expandedRows.remove(rowKey);
      } else {
        _expandedRows.add(rowKey);
      }
    });
  }

  List<BackendLogRow> _filterRows(List<BackendLogRow> rows) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return rows.where((row) {
      if (!_matchesSeverity(row.level)) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final haystack = [
        row.raw,
        row.message,
        row.logger ?? '',
        row.level ?? '',
        row.timestamp ?? '',
      ].join('\n').toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();
  }

  bool _matchesSeverity(String? level) {
    switch (_severityFilter) {
      case LogSeverityFilter.all:
        return true;
      case LogSeverityFilter.info:
        return normalizedLogLevel(level) == 'info';
      case LogSeverityFilter.warn:
        return normalizedLogLevel(level) == 'warn';
      case LogSeverityFilter.error:
        return normalizedLogLevel(level) == 'error';
    }
  }

  void _clearSeverityFilter() {
    setState(() {
      _severityFilter = LogSeverityFilter.all;
    });
    unawaited(
      widget.viewModel.savePreferences(severityFilter: _severityFilter.name),
    );
  }

  Future<void> _refreshActiveLogs({bool forceScrollToLatest = false}) async {
    final sourceKey = logSourceKey(_selectedSource);
    final previousToken = _snapshotTokens[_selectedSource];
    final shouldStickToBottom =
        forceScrollToLatest || (_followLatest && _isNearBottom());
    await widget.viewModel.load(source: sourceKey, limit: _rowLimit);
    if (!mounted) {
      return;
    }
    final snapshot = widget.viewModel.snapshotForSource(sourceKey);
    final nextToken = _snapshotToken(snapshot);
    if (nextToken != null) {
      _snapshotTokens[_selectedSource] = nextToken;
    }
    if (shouldStickToBottom) {
      if (_showJumpToLatest) {
        setState(() {
          _showJumpToLatest = false;
        });
      }
      _scheduleScrollToLatest(animated: false);
      return;
    }
    if (previousToken != null &&
        nextToken != null &&
        nextToken != previousToken) {
      setState(() {
        _showJumpToLatest = true;
      });
    }
  }

  Future<void> _showSourceSheet(BuildContext context) async {
    final nextSource = await showLogSourceSheet(
      context: context,
      selectedSource: _selectedSource,
    );
    if (nextSource == null || nextSource == _selectedSource || !mounted) {
      return;
    }
    setState(() {
      _selectedSource = nextSource;
      _followLatest = true;
      _showJumpToLatest = false;
    });
    await widget.viewModel.savePreferences(
      selectedSource: logSourceKey(nextSource),
    );
    await _refreshActiveLogs(forceScrollToLatest: true);
  }

  Future<void> _showSeveritySheet(BuildContext context) async {
    final nextFilter = await showLogSeveritySheet(
      context: context,
      selectedFilter: _severityFilter,
    );
    if (nextFilter == null || nextFilter == _severityFilter || !mounted) {
      return;
    }
    setState(() {
      _severityFilter = nextFilter;
    });
    await widget.viewModel.savePreferences(
      severityFilter: _severityFilter.name,
    );
  }

  Future<void> _showRowLimitSheet(BuildContext context) async {
    final nextLimit = await showLogRowLimitSheet(
      context: context,
      selectedLimit: _rowLimit,
    );
    if (nextLimit == null || nextLimit == _rowLimit || !mounted) {
      return;
    }
    setState(() {
      _rowLimit = nextLimit;
      _showJumpToLatest = false;
    });
    await widget.viewModel.savePreferences(rowLimit: _rowLimit);
    await _refreshActiveLogs();
  }

  Future<void> _showSearchSheet(BuildContext context) async {
    final result = await showLogSearchSheet(
      context: context,
      searchQuery: _searchQuery,
    );
    if (result == null) {
      return;
    }
    _searchController.text = result;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted ||
          widget.viewModel.baseUrl.trim().isEmpty ||
          !_followLatest) {
        return;
      }
      final sourceKey = logSourceKey(_selectedSource);
      final previousToken = _snapshotTokens[_selectedSource];
      final shouldStickToBottom = _followLatest && _isNearBottom();
      await widget.viewModel.load(
        source: sourceKey,
        limit: _rowLimit,
        silent: true,
      );
      if (!mounted) {
        return;
      }
      final snapshot = widget.viewModel.snapshotForSource(sourceKey);
      final nextToken = _snapshotToken(snapshot);
      if (nextToken != null) {
        _snapshotTokens[_selectedSource] = nextToken;
      }
      if (shouldStickToBottom) {
        _scheduleScrollToLatest(animated: false);
      } else if (previousToken != null &&
          nextToken != null &&
          nextToken != previousToken) {
        setState(() {
          _showJumpToLatest = true;
        });
      }
    });
  }

  void _handleScroll() {
    if (_isNearBottom()) {
      if (_showJumpToLatest || !_followLatest) {
        setState(() {
          _followLatest = true;
          _showJumpToLatest = false;
        });
        unawaited(_refreshActiveLogs(forceScrollToLatest: true));
      }
      return;
    }
    if (_followLatest) {
      setState(() {
        _followLatest = false;
      });
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) <= 72;
  }

  void _jumpToLatest() {
    setState(() {
      _followLatest = true;
      _showJumpToLatest = false;
    });
    unawaited(_refreshActiveLogs(forceScrollToLatest: true));
  }

  void _scheduleScrollToLatest({
    required bool animated,
    int attemptsRemaining = 6,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final scrolled = _scrollToLatest(animated: animated);
        if (!scrolled && attemptsRemaining > 1) {
          _scheduleScrollToLatest(
            animated: animated,
            attemptsRemaining: attemptsRemaining - 1,
          );
        }
      }
    });
  }

  bool _scrollToLatest({required bool animated}) {
    if (!_scrollController.hasClients) {
      return false;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    return true;
  }

  String? _snapshotToken(BackendLogSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    final lastRow = snapshot.rows.isEmpty ? null : snapshot.rows.last;
    return '${snapshot.source}|${snapshot.rows.length}|${lastRow?.raw ?? ''}';
  }

  List<String> _buildStableRowKeys(List<BackendLogRow> rows) {
    final sourceKey = logSourceKey(_selectedSource);
    final occurrences = <String, int>{};
    return rows.map((row) {
      final baseKey =
          '$sourceKey|${row.timestamp ?? ''}|${row.level ?? ''}|${row.logger ?? ''}|${row.raw}';
      final occurrence = (occurrences[baseKey] ?? 0) + 1;
      occurrences[baseKey] = occurrence;
      return '$baseKey|$occurrence';
    }).toList();
  }

  Future<void> _copyRow(BuildContext context, BackendLogRow row) async {
    await Clipboard.setData(ClipboardData(text: row.raw));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Log row copied.')));
  }
}
