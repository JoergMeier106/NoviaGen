import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:noviagen/job_text.dart';
import 'package:noviagen/shared/app_formatters.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';

import 'package:noviagen/features/settings/settings_view_model.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  Timer? _refreshTimer;
  Timer? _interJobDelaySaveDebounce;
  bool _loaded = false;
  String _filter = 'all';
  late final TextEditingController _interJobDelayController;
  String? _interJobDelayErrorText;

  @override
  void initState() {
    super.initState();
    _interJobDelayController = TextEditingController(
      text: widget.viewModel.interJobDelaySeconds.toString(),
    );
    _interJobDelayController.addListener(_scheduleInterJobDelaySave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loaded && widget.viewModel.baseUrl.isNotEmpty) {
        _loaded = true;
        widget.viewModel.loadJobs();
      }
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && widget.viewModel.baseUrl.isNotEmpty) {
        widget.viewModel.loadJobs();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _interJobDelaySaveDebounce?.cancel();
    _interJobDelayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allJobs = widget.viewModel.jobs;
        final hasActiveJobs = allJobs.any(
          (job) => job.status == 'queued' || job.status == 'running',
        );
        final hasCancelableJobs = allJobs.any(
          (job) => job.canCancel && !job.cancelRequested,
        );
        final hasFinishedJobs = allJobs.any((job) => job.isTerminal);
        final jobs = switch (_filter) {
          'queued' => allJobs.where((job) => job.status == 'queued').toList(),
          'running' => allJobs.where((job) => job.status == 'running').toList(),
          _ => allJobs,
        };
        if (widget.viewModel.loadingJobs && allJobs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (allJobs.isEmpty) {
          return Center(
            child: FilledButton.tonal(
              onPressed: widget.viewModel.loadJobs,
              child: const Text('Load jobs'),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: widget.viewModel.loadJobs,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.isEmpty ? 2 : jobs.length + 1,
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Running jobs are being processed now. Queued jobs are waiting for the worker.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Running'),
                          selected: _filter == 'running',
                          onSelected: (_) =>
                              setState(() => _filter = 'running'),
                        ),
                        ChoiceChip(
                          label: const Text('Queued'),
                          selected: _filter == 'queued',
                          onSelected: (_) => setState(() => _filter = 'queued'),
                        ),
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _filter == 'all',
                          onSelected: (_) => setState(() => _filter = 'all'),
                        ),
                      ],
                    ),
                    if (hasCancelableJobs || hasFinishedJobs) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (hasCancelableJobs)
                            FilledButton.tonalIcon(
                              onPressed: widget.viewModel.cancellingAllJobs
                                  ? null
                                  : () => _confirmCancelAllJobs(context),
                              icon: const Icon(
                                Icons.cancel_schedule_send_outlined,
                              ),
                              label: Text(
                                widget.viewModel.cancellingAllJobs
                                    ? 'Cancelling jobs...'
                                    : 'Cancel all',
                              ),
                            ),
                          if (hasFinishedJobs)
                            OutlinedButton.icon(
                              onPressed:
                                  widget.viewModel.clearingFinishedJobs
                                  ? null
                                  : () => _confirmClearFinishedJobs(context),
                              icon: const Icon(Icons.delete_sweep_outlined),
                              label: Text(
                                widget.viewModel.clearingFinishedJobs
                                    ? 'Clearing finished jobs...'
                                    : 'Clear finished jobs',
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delay between queued jobs',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Use 0 to disable it.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _interJobDelayController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Seconds',
                                errorText: _interJobDelayErrorText,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: SwitchListTile.adaptive(
                        value: widget.viewModel.shutdownWhenJobsComplete,
                        onChanged:
                            widget.viewModel.updatingShutdownWhenJobsComplete ||
                                (!hasActiveJobs &&
                                    !widget.viewModel.shutdownWhenJobsComplete)
                            ? null
                            : widget.viewModel.setShutdownWhenJobsComplete,
                        title: const Text('Shut down when jobs finish'),
                        subtitle: Text(
                          widget.viewModel.shutdownWhenJobsComplete
                              ? 'The server host will shut down after the current queue is done.'
                              : hasActiveJobs
                              ? 'Finish all queued and running jobs, then power off the server host.'
                              : 'No queued or running jobs are available right now.',
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (jobs.isEmpty) {
                return const InfoCard(
                  title: 'Jobs',
                  child: Text('No jobs match the current filter.'),
                );
              }

              final job = jobs[index - 1];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              jobTitleText(job),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (job.canCancel && !job.cancelRequested)
                            FilledButton.tonal(
                              onPressed: () =>
                                  widget.viewModel.cancelJob(job.jobId),
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(jobStatusText(job)),
                      const SizedBox(height: 4),
                      Text(jobProgressText(job)),
                      const SizedBox(height: 8),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: job.progress.clamp(0.0, 1.0)),
                        duration: const Duration(milliseconds: 350),
                        builder: (context, value, child) {
                          return LinearProgressIndicator(value: value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        job.createdAt == null
                            ? job.jobId
                            : '${job.jobId}\nCreated: ${formatTimestamp(job.createdAt!)}',
                      ),
                      if (job.status == 'completed' &&
                          job.result?.generationDurationSeconds != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Generation time: ${formatGenerationDurationLabel(job.result!.generationDurationSeconds)}',
                        ),
                      ],
                      if (job.cancelRequestedAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Cancellation requested: ${formatTimestamp(job.cancelRequestedAt!)}',
                        ),
                      ],
                      if (job.cancelledAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Cancellation finished: ${formatTimestamp(job.cancelledAt!)}',
                        ),
                      ],
                      if (job.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          jobFailureHelpText(job),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _confirmClearFinishedJobs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear finished jobs?'),
        content: const Text(
          'This removes completed, cancelled, and failed jobs from the list. Running and queued jobs stay available.',
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
    await widget.viewModel.clearFinishedJobs();
  }

  Future<void> _confirmCancelAllJobs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel all jobs?'),
        content: const Text(
          'This requests cancellation for all queued jobs and the currently running job. The running job may take a moment to stop safely.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep jobs'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await widget.viewModel.cancelAllJobs();
  }

  void _scheduleInterJobDelaySave() {
    final errorText = _validateInterJobDelay(_interJobDelayController.text);
    if (errorText != _interJobDelayErrorText && mounted) {
      setState(() {
        _interJobDelayErrorText = errorText;
      });
    }

    _interJobDelaySaveDebounce?.cancel();
    if (errorText != null) {
      return;
    }

    _interJobDelaySaveDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveInterJobDelay());
    });
  }

  Future<void> _saveInterJobDelay() async {
    if (!mounted) {
      return;
    }
    final parsedDelay = int.tryParse(_interJobDelayController.text.trim());
    if (parsedDelay == null) {
      return;
    }
    final changed = await widget.viewModel.saveInterJobDelaySeconds(
      parsedDelay,
    );
    if (changed && widget.viewModel.baseUrl.isNotEmpty) {
      await widget.viewModel.syncInterJobDelaySetting(silent: true);
    }
    if (!mounted) {
      return;
    }
    final normalizedValue = widget.viewModel.interJobDelaySeconds
        .toString();
    if (_interJobDelayController.text == normalizedValue) {
      return;
    }
    _interJobDelayController.value = TextEditingValue(
      text: normalizedValue,
      selection: TextSelection.collapsed(offset: normalizedValue.length),
    );
  }

  String? _validateInterJobDelay(String value) {
    final parsedDelay = int.tryParse(value.trim());
    if (parsedDelay == null || parsedDelay < 0 || parsedDelay > 3600) {
      return 'Cooldown must be between 0 and 3600 seconds.';
    }
    return null;
  }
}
