import 'package:flutter/material.dart';

import 'package:flutter_app/models/chat_models.dart';
import 'package:flutter_app/models/system.dart';
import 'package:flutter_app/features/settings/settings_view_model.dart';

class SettingsEntryTile extends StatelessWidget {
  const SettingsEntryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class ServerHealthCard extends StatelessWidget {
  const ServerHealthCard({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final health = viewModel.backendHealth;
    final isBackendConfigured = viewModel.baseUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Server health', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        HealthStatusRow(
          title: 'Server',
          status: health?.backend,
          fallbackLabel: isBackendConfigured ? 'Unknown' : 'Not configured',
        ),
        const SizedBox(height: 8),
        HealthStatusRow(
          title: 'Comfy',
          status: health?.comfy,
          fallbackLabel: isBackendConfigured ? 'Unknown' : 'Not configured',
        ),
        const SizedBox(height: 8),
        HealthStatusRow(
          title: 'Ollama',
          status: health?.ollama,
          fallbackLabel: isBackendConfigured ? 'Unknown' : 'Not configured',
        ),
      ],
    );
  }
}

class HealthStatusRow extends StatelessWidget {
  const HealthStatusRow({
    super.key,
    required this.title,
    required this.status,
    required this.fallbackLabel,
  });

  final String title;
  final BackendHealthStatus? status;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedLabel = status?.label.trim();
    final label = resolvedLabel == null || resolvedLabel.isEmpty
        ? fallbackLabel
        : resolvedLabel;
    final isOk = status?.ok ?? false;
    final color = isOk ? Colors.green : Theme.of(context).colorScheme.error;
    return Row(
      children: [
        Expanded(child: Text(title)),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class AutoPromptModelDropdown extends StatelessWidget {
  const AutoPromptModelDropdown({
    super.key,
    required this.label,
    required this.selectedModelName,
    required this.models,
    required this.onChanged,
  });

  final String label;
  final String selectedModelName;
  final List<OllamaModelInfo> models;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasModels = models.isNotEmpty;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: hasModels && selectedModelName.isNotEmpty
          ? selectedModelName
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: hasModels
            ? 'Only models with vision support are shown.'
            : 'No vision-capable models found on the current backend.',
        border: const OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) =>
          models.map(_buildSelectedModel).toList(),
      items: models.map(_buildMenuItem).toList(),
      onChanged: hasModels
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return;
              }
              onChanged(value);
            }
          : null,
    );
  }

  Widget _buildSelectedModel(OllamaModelInfo model) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  DropdownMenuItem<String> _buildMenuItem(OllamaModelInfo model) {
    return DropdownMenuItem<String>(
      value: model.name,
      child: Tooltip(
        message: model.name,
        child: Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
