import 'package:flutter/material.dart';

import 'package:flutter_app/models/backups.dart';
import 'package:flutter_app/shared/app_formatters.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';

import 'package:flutter_app/features/settings/settings_view_model.dart';

class BackupsPage extends StatefulWidget {
  const BackupsPage({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loaded && widget.viewModel.baseUrl.isNotEmpty) {
        _loaded = true;
        _refreshBackups();
      }
    });
  }

  Future<void> _refreshBackups() async {
    await Future.wait<void>([
      widget.viewModel.loadBackups(),
      widget.viewModel.loadAppBackups(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final refreshing =
        widget.viewModel.loadingBackups || widget.viewModel.loadingAppBackups;
    final appBackups = widget.viewModel.appBackups;
    final serverBackups = widget.viewModel.backups;
    return Scaffold(
          appBar: AppBar(
            title: const Text('Backups'),
            actions: [
              IconButton(
                onPressed: refreshing ? null : _refreshBackups,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh backups',
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshBackups,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const InfoCard(
                  title: 'App data backups',
                  child: Text(
                    'Store your local app settings, prompt presets, drafts, filters, and other saved app data on the server so you can restore them after reinstalling the app.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      widget.viewModel.creatingAppBackup ||
                          widget.viewModel.applyingAppBackup
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await widget.viewModel.createAppBackup();
                          if (!mounted) {
                            return;
                          }
                          _showStateMessage(messenger);
                        },
                  icon: const Icon(Icons.phone_android_outlined),
                  label: Text(
                    widget.viewModel.creatingAppBackup
                        ? 'Creating app backup...'
                        : 'Create app backup',
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.viewModel.loadingAppBackups &&
                    appBackups.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (appBackups.isEmpty)
                  const InfoCard(
                    title: 'Saved app backups',
                    child: Text('No app backups available yet.'),
                  )
                else
                  ...appBackups.map(
                    (backup) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.phone_android_outlined),
                          title: Text(
                            backup.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${formatTimestamp(backup.createdAt)} • ${formatBytes(backup.sizeBytes)}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed:
                                    widget.viewModel.applyingAppBackup
                                    ? null
                                    : () => _confirmApplyAppBackup(
                                        context,
                                        backup,
                                      ),
                                icon: const Icon(
                                  Icons.settings_backup_restore_outlined,
                                ),
                                tooltip: 'Apply app backup',
                              ),
                              IconButton(
                                onPressed:
                                    widget.viewModel.creatingAppBackup ||
                                        widget.viewModel.applyingAppBackup
                                    ? null
                                    : () => _confirmDeleteAppBackup(
                                        context,
                                        backup,
                                      ),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete app backup',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const InfoCard(
                  title: 'Server data backups',
                  child: Text(
                    'Create archives of the server database, stored media, and recorded server-side errors.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      widget.viewModel.creatingBackup ||
                          widget.viewModel.applyingBackup
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await widget.viewModel.createBackup();
                          if (!mounted) {
                            return;
                          }
                          _showStateMessage(messenger);
                        },
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(
                    widget.viewModel.creatingBackup
                        ? 'Creating server backup...'
                        : 'Create server backup',
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.viewModel.loadingBackups &&
                    serverBackups.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (serverBackups.isEmpty)
                  const InfoCard(
                    title: 'Saved server backups',
                    child: Text('No server backups available yet.'),
                  )
                else
                  ...serverBackups.map(
                    (backup) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.archive_outlined),
                          title: Text(
                            backup.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${formatTimestamp(backup.createdAt)} • ${formatBytes(backup.sizeBytes)}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed:
                                    widget.viewModel.creatingBackup ||
                                        widget.viewModel.applyingBackup
                                    ? null
                                    : () => _confirmApplyServerBackup(
                                        context,
                                        backup,
                                      ),
                                icon: const Icon(
                                  Icons.settings_backup_restore_outlined,
                                ),
                                tooltip: 'Apply server backup',
                              ),
                              IconButton(
                                onPressed:
                                    widget.viewModel.creatingBackup ||
                                        widget.viewModel.applyingBackup
                                    ? null
                                    : () => _confirmDeleteServerBackup(
                                        context,
                                        backup,
                                      ),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete server backup',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    );
  }

  void _showStateMessage(ScaffoldMessengerState messenger) {
    final message = widget.viewModel.message;
    if (message == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmApplyAppBackup(
    BuildContext context,
    BackupRecord backup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply app backup'),
        content: Text(
          'Apply ${backup.name}? This replaces the app\'s current local settings and saved app data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await widget.viewModel.applyAppBackup(backup.name);
    if (!mounted) {
      return;
    }
    _showStateMessage(messenger);
  }

  Future<void> _confirmDeleteAppBackup(
    BuildContext context,
    BackupRecord backup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete app backup'),
        content: Text('Delete ${backup.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await widget.viewModel.deleteAppBackup(backup.name);
    if (!mounted) {
      return;
    }
    _showStateMessage(messenger);
  }

  Future<void> _confirmDeleteServerBackup(
    BuildContext context,
    BackupRecord backup,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete server backup'),
        content: Text('Delete ${backup.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await widget.viewModel.deleteBackup(backup.name);
    if (!mounted) {
      return;
    }
    _showStateMessage(messenger);
  }

  Future<void> _confirmApplyServerBackup(
    BuildContext context,
    BackupRecord backup,
  ) async {
    final restoreMode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore server backup'),
        content: Text(
          'Restore ${backup.name}.\n\nOverwrite replaces the current server database, stored media, and recorded server errors.\n\nMerge keeps the current data and imports only missing items from the backup, ignoring duplicates already present. Queued or running jobs must be stopped first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('merge'),
            child: const Text('Merge'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('overwrite'),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    if (restoreMode == null || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await widget.viewModel.applyBackup(
      backup.name,
      merge: restoreMode == 'merge',
    );
    if (!mounted) {
      return;
    }
    _showStateMessage(messenger);
  }
}
