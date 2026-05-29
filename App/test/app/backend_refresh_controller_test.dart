import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/app/controllers/backend_refresh_controller.dart';

void main() {
  test('refreshBackendData reloads backend-backed app state in order', () async {
    final calls = <String>[];
    final controller = BackendRefreshController(
      BackendRefreshDependencies(
        syncInterJobDelaySetting: ({silent = false}) async {
          calls.add('syncInterJobDelaySetting:$silent');
        },
        refreshAssets: () async {
          calls.add('refreshAssets');
        },
        loadJobs: () async {
          calls.add('loadJobs');
        },
        loadLatestResult: ({silent = false}) async {
          calls.add('loadLatestResult:$silent');
        },
        loadHealth: ({silent = false}) async {
          calls.add('loadHealth:$silent');
        },
        loadAutoPromptModels: ({silent = false}) async {
          calls.add('loadAutoPromptModels:$silent');
        },
      ),
    );

    await controller.refreshBackendData();

    expect(calls, <String>[
      'syncInterJobDelaySetting:true',
      'refreshAssets',
      'loadJobs',
      'loadLatestResult:true',
      'loadHealth:true',
      'loadAutoPromptModels:true',
    ]);
  });
}
