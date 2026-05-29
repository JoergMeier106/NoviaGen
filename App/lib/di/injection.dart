import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_app/di/app_registrations.dart';
import 'package:flutter_app/di/injection.config.dart';


final GetIt getIt = GetIt.instance;
bool _dependenciesConfigured = false;

@InjectableInit()
Future<void> configureDependencies({bool reset = false}) async {
  if (reset) {
    await getIt.reset(dispose: true);
    _dependenciesConfigured = false;
  }
  configureDependenciesSync();
}

void configureDependenciesSync() {
  if (_dependenciesConfigured) {
    return;
  }
  getIt.init();
  registerAppDependencies(getIt);
  _dependenciesConfigured = true;
}
