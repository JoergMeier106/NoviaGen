import 'package:flutter/material.dart';

import 'package:flutter_app/job_text.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/shared/app_formatters.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';

import 'package:flutter_app/features/settings/settings_view_model.dart';

class ErrorsPage extends StatefulWidget {
  const ErrorsPage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  State<ErrorsPage> createState() => _ErrorsPageState();
}

class _ErrorsPageState extends State<ErrorsPage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loaded) {
        _loaded = true;
        widget.viewModel.loadErrors();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final errors = widget.viewModel.errors;
    final isLoading = widget.viewModel.loadingErrors;
    final isClearing = widget.viewModel.clearingErrors;
    return RefreshIndicator(
      onRefresh: widget.viewModel.loadErrors,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (errors.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: isClearing
                    ? null
                    : () => _confirmClearErrors(context),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(
                  isClearing ? 'Clearing reports...' : 'Clear all reports',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isLoading && errors.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errors.isEmpty)
            const InfoCard(
              title: 'Error Reports',
              child: Text(
                'No recorded server-side errors or app crash reports yet.',
              ),
            )
          else
            ...errors.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    leading: Icon(
                      entry.isAppCrashReport
                          ? Icons.bug_report_outlined
                          : Icons.error_outline,
                    ),
                    title: Text(
                      entry.isAppCrashReport
                          ? 'App crash report'
                          : jobTypeLabel(entry.jobType),
                    ),
                    subtitle: Text(
                      'Logged ${formatTimestamp(entry.loggedAt)}\n${_subtitleText(entry)}',
                    ),
                    children: [
                      ErrorDetailLine(
                        label: 'Source',
                        value: entry.isAppCrashReport ? 'App' : 'Server',
                      ),
                      if (entry.isAppCrashReport &&
                          _captureSourceLabel(entry).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Captured By',
                          value: _captureSourceLabel(entry),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ErrorDetailLine(
                        label: 'Cause',
                        value: entry.errorText.isEmpty
                            ? 'No error text recorded.'
                            : entry.errorText,
                        selectable: true,
                        valueColor: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      ErrorDetailLine(
                        label: 'Status',
                        value: entry.jobStatusText.isEmpty
                            ? sentenceCase(entry.jobStatus)
                            : '${sentenceCase(entry.jobStatus)} - ${entry.jobStatusText}',
                      ),
                      if (!entry.isAppCrashReport) ...[
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Progress',
                          value:
                              '${(entry.jobProgress.clamp(0.0, 1.0) * 100).round()}%',
                        ),
                      ],
                      if (entry.jobCreatedAt != null) ...[
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Created',
                          value: formatTimestamp(entry.jobCreatedAt!),
                        ),
                      ],
                      if (entry.jobUpdatedAt != null) ...[
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Updated',
                          value: formatTimestamp(entry.jobUpdatedAt!),
                        ),
                      ],
                      if (entry.jobCancelRequestedAt != null) ...[
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Cancel Requested',
                          value: formatTimestamp(entry.jobCancelRequestedAt!),
                        ),
                      ],
                      if (entry.jobCancelledAt != null) ...[
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Cancelled',
                          value: formatTimestamp(entry.jobCancelledAt!),
                        ),
                      ],
                      if (entry.stackTraceText?.trim().isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        ErrorDetailLine(
                          label: 'Stack Trace',
                          value: entry.stackTraceText!.trim(),
                          selectable: true,
                          monospace: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      ErrorDetailLine(
                        label: entry.isAppCrashReport
                            ? 'Crash Context'
                            : 'Job Information',
                        value: formatJsonMap(entry.jobPayload),
                        selectable: true,
                        monospace: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClearErrors(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all reports?'),
        content: const Text(
          'This removes every recorded server-side error and app crash report from the log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await widget.viewModel.clearErrors();
  }

  String _subtitleText(AppErrorRecord entry) {
    if (entry.isAppCrashReport) {
      return entry.jobStatusText.isEmpty ? 'App crash' : entry.jobStatusText;
    }
    return entry.jobId;
  }

  String _captureSourceLabel(AppErrorRecord entry) {
    final value = entry.jobPayload['capture_source']?.toString().trim() ?? '';
    return switch (value) {
      'flutter_framework' => 'Flutter framework',
      'platform_dispatcher' => 'Platform dispatcher',
      'zone' => 'Zone handler',
      _ => value,
    };
  }
}
