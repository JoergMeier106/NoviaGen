import 'dart:async';

import 'package:flutter/material.dart';

import 'package:noviagen/shared/app_formatters.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';
import 'package:noviagen/app/controllers/configuration_controller.dart';
import 'package:noviagen/features/settings/assets_page.dart';
import 'package:noviagen/features/settings/backups_page.dart';
import 'package:noviagen/features/settings/errors_page.dart';
import 'package:noviagen/features/settings/generation_defaults_pages.dart';
import 'package:noviagen/features/settings/jobs_page.dart';
import 'package:noviagen/features/settings/logs_page.dart';
import 'package:noviagen/features/settings/prompt_presets_page.dart';
import 'package:noviagen/features/settings/settings_validation.dart';
import 'package:noviagen/features/settings/settings_widgets.dart';
import 'package:noviagen/features/settings/system_info_page.dart';

import 'package:provider/provider.dart';
import 'package:noviagen/features/settings/settings_view_model.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsViewModel>(
      builder: (context, viewModel, _) =>
          _SettingsPageBody(viewModel: viewModel, isActive: isActive),
    );
  }
}

class _SettingsPageBody extends StatefulWidget {
  const _SettingsPageBody({required this.viewModel, required this.isActive});

  final SettingsViewModel viewModel;
  final bool isActive;

  @override
  State<_SettingsPageBody> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPageBody> {
  static const Duration _healthRefreshInterval = Duration(seconds: 10);

  late final TextEditingController _baseUrlController;
  late final TextEditingController _chatContextWindowController;
  late final TextEditingController _gallerySlideshowController;
  late final TextEditingController _wakeOnLanMacController;
  late final TextEditingController _wakeOnLanBroadcastController;
  late final TextEditingController _wakeOnLanPortController;
  Timer? _saveDebounce;
  String? _gallerySlideshowErrorText;
  String? _chatContextWindowErrorText;
  String? _wakeOnLanMacErrorText;
  String? _wakeOnLanBroadcastErrorText;
  String? _wakeOnLanPortErrorText;
  Timer? _healthRefreshTimer;
  bool _healthRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.viewModel.baseUrl);
    _chatContextWindowController = TextEditingController(
      text: widget.viewModel.contextWindow?.toString() ?? '',
    );
    _gallerySlideshowController = TextEditingController(
      text: widget.viewModel.slideshowIntervalSeconds.toString(),
    );
    _wakeOnLanMacController = TextEditingController(
      text: widget.viewModel.wakeOnLan.macAddress,
    );
    _wakeOnLanBroadcastController = TextEditingController(
      text: widget.viewModel.wakeOnLan.broadcastAddress,
    );
    _wakeOnLanPortController = TextEditingController(
      text: widget.viewModel.wakeOnLan.port,
    );
    _baseUrlController.addListener(_scheduleAutosave);
    _chatContextWindowController.addListener(_scheduleAutosave);
    _gallerySlideshowController.addListener(_scheduleAutosave);
    _wakeOnLanMacController.addListener(_scheduleAutosave);
    _wakeOnLanBroadcastController.addListener(_scheduleAutosave);
    _wakeOnLanPortController.addListener(_scheduleAutosave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.viewModel.baseUrl.isNotEmpty) {
        unawaited(widget.viewModel.loadAutoPromptModels(silent: true));
      }
      _syncHealthRefresh();
    });
  }

  @override
  void didUpdateWidget(covariant _SettingsPageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncHealthRefresh();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _healthRefreshTimer?.cancel();
    _baseUrlController.dispose();
    _chatContextWindowController.dispose();
    _gallerySlideshowController.dispose();
    _wakeOnLanMacController.dispose();
    _wakeOnLanBroadcastController.dispose();
    _wakeOnLanPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedChatModel = widget.viewModel.selectedChatModelInfo(
      widget.viewModel.selectedSession,
    );
    final chatContextHelperText = selectedChatModel?.modelContextLength != null
        ? 'Blank for model default (${selectedChatModel!.modelContextLength} tokens).'
        : 'Blank for model default.';
    const chatThinkingHelperText = 'Unsupported models ignore this setting.';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InfoCard(
          title: 'General',
          child: Column(
            children: [
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend base URL',
                  hintText: 'http://192.168.1.20:5000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemeMode>(
                initialValue: widget.viewModel.themeMode,
                decoration: const InputDecoration(
                  labelText: 'Theme mode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  widget.viewModel.themeMode = value;
                  widget.viewModel.notifyStateChanged();
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: 'Ollama Chat',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _chatContextWindowController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Context window',
                  helperText: chatContextHelperText,
                  errorText: _chatContextWindowErrorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable thinking'),
                subtitle: Text(chatThinkingHelperText),
                value: widget.viewModel.thinkingEnabled,
                onChanged: (value) {
                  setState(() {
                    widget.viewModel.thinkingEnabled = value;
                    widget.viewModel.notifyStateChanged();
                  });
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: 'Generation',
          child: Column(
            children: [
              SettingsEntryTile(
                icon: Icons.image_outlined,
                title: 'Text to image',
                subtitle: 'Steps, guidance, auto-prompt base, and LLM.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          TextToImageDefaultsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.transform_outlined,
                title: 'Image to image',
                subtitle: 'Steps, guidance, auto-prompt base, and LLM.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          ImageToImageDefaultsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.movie_outlined,
                title: 'Text to video',
                subtitle: 'Video diffusion models, auto-prompt base, and LLM.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          TextToVideoDefaultsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.video_camera_back_outlined,
                title: 'Image to video',
                subtitle: 'Video diffusion models, auto-prompt base, and LLM.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          ImageToVideoDefaultsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.text_snippet_outlined,
                title: 'Prompt presets',
                subtitle: widget.viewModel.presets.isEmpty
                    ? 'Create named positive and negative prompt pairs.'
                    : '${widget.viewModel.presets.length} preset(s) available',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          PromptPresetsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: 'Gallery',
          child: Column(
            children: [
              TextField(
                controller: _gallerySlideshowController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Slideshow speed (seconds)',
                  errorText: _gallerySlideshowErrorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Delete scaling source automatically'),
                value: widget.viewModel.deleteSourceAfterScaling,
                onChanged: (value) {
                  setState(() {
                    widget.viewModel.deleteSourceAfterScaling = value;
                    widget.viewModel.notifyStateChanged();
                  });
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: 'Data',
          child: Column(
            children: [
              SettingsEntryTile(
                icon: Icons.backup_outlined,
                title: 'Backups',
                subtitle: 'Manage server backups and restorable app data.',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          BackupsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.tune_outlined,
                title: 'Assets',
                subtitle:
                    '${widget.viewModel.models.length} model(s), ${widget.viewModel.loras.length} LoRA(s)',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          AssetsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.error_outline,
                title: 'Errors',
                subtitle: widget.viewModel.loadingErrors
                    ? 'Loading error reports...'
                    : widget.viewModel.errors.isEmpty
                    ? 'View recorded server errors and app crash reports.'
                    : '${widget.viewModel.errors.length} recorded report(s)',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          ErrorsRoutePage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.pending_actions_outlined,
                title: 'Jobs',
                subtitle: widget.viewModel.jobs.isEmpty
                    ? 'View queued, running, and finished jobs.'
                    : '${widget.viewModel.jobs.length} job(s) loaded',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          JobsRoutePage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.article_outlined,
                title: 'Logs',
                subtitle: 'Inspect backend server and Comfy logs.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          LogsPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          title: 'System',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ServerHealthCard(viewModel: widget.viewModel),
              const Divider(height: 20),
              SettingsEntryTile(
                icon: Icons.memory_outlined,
                title: 'System info',
                subtitle: widget.viewModel.loadingSystemInfo
                    ? 'Loading backend hardware details...'
                    : widget.viewModel.systemInfo == null
                    ? 'View backend CPU, GPU, VRAM, and RAM.'
                    : systemInfoSettingsSubtitle(widget.viewModel.systemInfo!),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          SystemInfoPage(viewModel: widget.viewModel),
                    ),
                  );
                },
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _forceUnloadAllModels(context),
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Force unload all models'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _confirmRestartServer(context),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Restart backend server'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _confirmShutdown(context),
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Shut down backend host'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _canSendWakeOnLan
                        ? () => _sendWakeOnLan(context)
                        : null,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Wake backend host'),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _wakeOnLanMacController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Wake-on-LAN MAC address',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                  errorText: _wakeOnLanMacErrorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wakeOnLanBroadcastController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Broadcast address',
                  hintText: '192.168.1.255',
                  helperText:
                      'Leave blank to use ${widget.viewModel.wakeOnLan.effectiveBroadcastAddress(widget.viewModel.baseUrl)}.',
                  errorText: _wakeOnLanBroadcastErrorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wakeOnLanPortController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Wake-on-LAN UDP port',
                  hintText: '9',
                  errorText: _wakeOnLanPortErrorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _forceUnloadAllModels(BuildContext context) async {
    await widget.viewModel.forceUnloadAllModels();
    if (!mounted) {
      return;
    }
    _showMessageSnackbar();
  }

  Future<void> _confirmShutdown(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shut down host'),
        content: const Text(
          'This will shut down the PC running the Flask server. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Shut down'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await widget.viewModel.shutdownHost();
    if (!mounted) {
      return;
    }
    _showMessageSnackbar();
  }

  Future<void> _confirmRestartServer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restart backend server'),
        content: const Text(
          'This will restart only the NoviaGen backend process. The app may briefly lose connection. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await widget.viewModel.restartServer();
    if (!mounted) {
      return;
    }
    _showMessageSnackbar();
  }

  Future<void> _sendWakeOnLan(BuildContext context) async {
    await widget.viewModel.sendWakeOnLan(
      macAddress: _wakeOnLanMacController.text,
      broadcastAddress: _wakeOnLanBroadcastController.text,
      port: _wakeOnLanPortController.text,
      baseUrl: widget.viewModel.baseUrl,
    );
    if (!mounted) {
      return;
    }
    _showMessageSnackbar();
  }

  void _showMessageSnackbar() {
    final message = widget.viewModel.message;
    if (!mounted || message == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scheduleAutosave() {
    final validation = _currentValidation();
    final changedValidation =
        validation.gallerySlideshowError != _gallerySlideshowErrorText ||
        validation.chatContextWindowError != _chatContextWindowErrorText ||
        validation.wakeOnLanMacError != _wakeOnLanMacErrorText ||
        validation.wakeOnLanBroadcastError != _wakeOnLanBroadcastErrorText ||
        validation.wakeOnLanPortError != _wakeOnLanPortErrorText;
    if (changedValidation && mounted) {
      setState(() {
        _gallerySlideshowErrorText = validation.gallerySlideshowError;
        _chatContextWindowErrorText = validation.chatContextWindowError;
        _wakeOnLanMacErrorText = validation.wakeOnLanMacError;
        _wakeOnLanBroadcastErrorText = validation.wakeOnLanBroadcastError;
        _wakeOnLanPortErrorText = validation.wakeOnLanPortError;
      });
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) {
        return;
      }
      final parsedGallerySlideshow = int.tryParse(
        _gallerySlideshowController.text.trim(),
      );
      final parsedChatContextWindow =
          _chatContextWindowController.text.trim().isEmpty
          ? null
          : int.tryParse(_chatContextWindowController.text.trim());
      if (validation.hasAutosaveBlockingError ||
          parsedGallerySlideshow == null) {
        return;
      }
      final shouldRefreshAssets = await widget.viewModel.saveSettings(
        SaveSettingsRequest(
          baseUrl: _baseUrlController.text,
          themeMode: widget.viewModel.themeMode,
          numInferenceSteps: widget.viewModel.numInferenceSteps,
          guidanceScale: widget.viewModel.guidanceScale,
          imageOrientation: widget.viewModel.imageOrientation,
          promptGeneratorBasePrompt: widget.viewModel.promptGeneratorBasePrompt,
          imageToVideoPromptGeneratorBasePrompt:
              widget.viewModel.imageToVideoPromptGeneratorBasePrompt,
          gallerySlideshowIntervalSeconds: parsedGallerySlideshow,
          interJobDelaySeconds: widget.viewModel.interJobDelaySeconds,
          deleteSourceAfterScaling: widget.viewModel.deleteSourceAfterScaling,
          chatContextWindow: parsedChatContextWindow,
          chatThinkingEnabled: widget.viewModel.thinkingEnabled,
          autoPromptModelName: widget.viewModel.preferredAutoPromptModelName,
          imageToVideoAutoPromptModelName:
              widget.viewModel.preferredImageToVideoAutoPromptModelName,
          wakeOnLanMacAddress: _wakeOnLanMacController.text,
          wakeOnLanBroadcastAddress: _wakeOnLanBroadcastController.text,
          wakeOnLanPort: _wakeOnLanPortController.text,
        ),
      );
      _syncHealthRefresh();
      if (shouldRefreshAssets && widget.viewModel.baseUrl.isNotEmpty) {
        await widget.viewModel.refreshBackendData();
      }
    });
  }

  void _syncHealthRefresh() {
    _healthRefreshTimer?.cancel();
    _healthRefreshTimer = null;
    if (!widget.isActive || widget.viewModel.baseUrl.trim().isEmpty) {
      return;
    }
    unawaited(_refreshHealth());
    _healthRefreshTimer = Timer.periodic(_healthRefreshInterval, (_) {
      unawaited(_refreshHealth());
    });
  }

  Future<void> _refreshHealth() async {
    if (!mounted ||
        _healthRefreshInFlight ||
        widget.viewModel.baseUrl.trim().isEmpty) {
      return;
    }
    _healthRefreshInFlight = true;
    try {
      await widget.viewModel.loadHealth(silent: true);
    } finally {
      _healthRefreshInFlight = false;
    }
  }

  bool get _canSendWakeOnLan =>
      _wakeOnLanMacController.text.trim().isNotEmpty &&
      _currentValidation().canSendWakeOnLan;

  SettingsValidationResult _currentValidation() {
    return validateSettingsInput(
      steps: widget.viewModel.numInferenceSteps.toString(),
      guidance: widget.viewModel.guidanceScale.toString(),
      gallerySlideshow: _gallerySlideshowController.text,
      chatContextWindow: _chatContextWindowController.text,
      wakeOnLanMac: _wakeOnLanMacController.text,
      wakeOnLanBroadcast: _wakeOnLanBroadcastController.text,
      wakeOnLanPort: _wakeOnLanPortController.text,
    );
  }
}

class JobsRoutePage extends StatelessWidget {
  const JobsRoutePage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jobs')),
      body: JobsPage(viewModel: viewModel),
    );
  }
}

class ErrorsRoutePage extends StatelessWidget {
  const ErrorsRoutePage({super.key, required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error Reports')),
      body: ErrorsPage(viewModel: viewModel),
    );
  }
}
