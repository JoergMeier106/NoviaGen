import 'dart:async';

import 'package:flutter/material.dart';

import 'package:noviagen/shared/app_formatters.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';

import 'package:noviagen/features/settings/settings_view_model.dart';

class SystemInfoPage extends StatefulWidget {
  const SystemInfoPage({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  State<SystemInfoPage> createState() => _SystemInfoPageState();
}

class _SystemInfoPageState extends State<SystemInfoPage> {
  bool _loaded = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loaded && widget.viewModel.baseUrl.isNotEmpty) {
        _loaded = true;
        widget.viewModel.loadSystemInfo();
      }
      _startAutoRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.viewModel.systemInfo;
    final isLoading = widget.viewModel.loadingSystemInfo;
    final baseUrl = widget.viewModel.baseUrl;
    return Scaffold(
          appBar: AppBar(
            title: const Text('System Info'),
            actions: [
              IconButton(
                onPressed: isLoading
                    ? null
                    : () => widget.viewModel.loadSystemInfo(),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh system info',
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => widget.viewModel.loadSystemInfo(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (baseUrl.trim().isEmpty)
                  const InfoCard(
                    title: 'Backend',
                    child: Text('Set a backend URL first.'),
                  )
                else if (isLoading && info == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (info == null)
                  const InfoCard(
                    title: 'System Info',
                    child: Text('No backend system info is available yet.'),
                  )
                else ...[
                  InfoCard(
                    title: 'Live overview',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final columns = width >= 900
                                ? 4
                                : width >= 560
                                ? 2
                                : 1;
                            final tileWidth =
                                (width - (12 * (columns - 1))) / columns;
                            final tiles = [
                              SystemMetricTile(
                                label: 'GPU',
                                value: info.gpus.isEmpty
                                    ? 'Unknown'
                                    : formatOptionalPercent(
                                        info.gpus.first.utilizationPercent,
                                      ),
                                helper: info.gpus.isEmpty
                                    ? 'No GPU detected'
                                    : info.gpus.first.name,
                              ),
                              SystemMetricTile(
                                label: 'VRAM',
                                value: info.gpus.isEmpty
                                    ? 'Unknown'
                                    : formatMemoryPair(
                                        info.gpus.first.vramFreeBytes,
                                        info.gpus.first.vramTotalBytes,
                                      ),
                                helper: 'Available / total',
                              ),
                              SystemMetricTile(
                                label: 'CPU',
                                value: formatOptionalPercent(
                                  info.cpuUtilizationPercent,
                                ),
                                helper: info.cpuModel,
                              ),
                              SystemMetricTile(
                                label: 'RAM',
                                value: formatMemoryPair(
                                  info.availableRamBytes,
                                  info.totalRamBytes,
                                ),
                                helper: 'Available / total',
                              ),
                            ];
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final tile in tiles)
                                  SizedBox(width: tileWidth, child: tile),
                              ],
                            );
                          },
                        ),
                        if (info.collectedAt.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Updated ${formatTimestamp(info.collectedAt)} • refreshes every 3 seconds',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Host',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ErrorDetailLine(label: 'Platform', value: info.system),
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Release',
                          value: info.release.isEmpty
                              ? 'Unknown'
                              : info.release,
                        ),
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Machine',
                          value: info.machine.isEmpty
                              ? 'Unknown'
                              : info.machine,
                        ),
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Hostname',
                          value: info.hostname.isEmpty
                              ? 'Unknown'
                              : info.hostname,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'CPU',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ErrorDetailLine(label: 'Model', value: info.cpuModel),
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Physical cores',
                          value: formatOptionalCount(info.physicalCores),
                        ),
                        const SizedBox(height: 8),
                        ErrorDetailLine(
                          label: 'Logical cores',
                          value: formatOptionalCount(info.logicalCores),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Memory',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ErrorDetailLine(
                          label: 'Total RAM',
                          value: formatOptionalBytes(info.totalRamBytes),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (info.gpus.isEmpty)
                    const InfoCard(
                      title: 'GPU',
                      child: Text(
                        'No GPU information was detected on the backend host.',
                      ),
                    )
                  else
                    ...info.gpus.asMap().entries.map((entry) {
                      final index = entry.key;
                      final gpu = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == info.gpus.length - 1 ? 0 : 12,
                        ),
                        child: InfoCard(
                          title: info.gpus.length == 1
                              ? 'GPU'
                              : 'GPU ${index + 1}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ErrorDetailLine(label: 'Name', value: gpu.name),
                              const SizedBox(height: 8),
                              ErrorDetailLine(
                                label: 'Vendor',
                                value: gpu.vendor ?? 'Unknown',
                              ),
                              const SizedBox(height: 8),
                              ErrorDetailLine(
                                label: 'Total VRAM',
                                value: formatOptionalBytes(gpu.vramTotalBytes),
                              ),
                              const SizedBox(height: 8),
                              ErrorDetailLine(
                                label: 'Driver',
                                value: gpu.driverVersion ?? 'Unknown',
                              ),
                              const SizedBox(height: 8),
                              ErrorDetailLine(
                                label: 'Source',
                                value: gpu.source ?? 'Unknown',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ],
            ),
          ),
    );
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) {
        return;
      }
      if (widget.viewModel.baseUrl.trim().isEmpty ||
          widget.viewModel.loadingSystemInfo) {
        return;
      }
      widget.viewModel.loadSystemInfo(silent: true);
    });
  }
}
