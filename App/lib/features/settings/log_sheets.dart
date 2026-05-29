import 'package:flutter/material.dart';

import 'package:noviagen/features/settings/log_filters.dart';


Future<LogSource?> showLogSourceSheet({
  required BuildContext context,
  required LogSource selectedSource,
}) {
  return showModalBottomSheet<LogSource>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Server'),
              trailing: selectedSource == LogSource.server
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(LogSource.server),
            ),
            ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: const Text('Comfy'),
              trailing: selectedSource == LogSource.comfy
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(LogSource.comfy),
            ),
          ],
        ),
      );
    },
  );
}

Future<LogSeverityFilter?> showLogSeveritySheet({
  required BuildContext context,
  required LogSeverityFilter selectedFilter,
}) {
  return showModalBottomSheet<LogSeverityFilter>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: LogSeverityFilter.values.map((filter) {
            return ListTile(
              title: Text(logSeverityFilterLabel(filter)),
              trailing: selectedFilter == filter
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(filter),
            );
          }).toList(),
        ),
      );
    },
  );
}

Future<int?> showLogRowLimitSheet({
  required BuildContext context,
  required int selectedLimit,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [200, 500, 1000, 2000].map((limit) {
            return ListTile(
              title: Text('$limit rows'),
              trailing: selectedLimit == limit ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(limit),
            );
          }).toList(),
        ),
      );
    },
  );
}

Future<String?> showLogSearchSheet({
  required BuildContext context,
  required String searchQuery,
}) async {
  final controller = TextEditingController(text: searchQuery);
  final result = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Filter message, logger, or raw text',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: controller.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(controller.text),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  return result;
}
