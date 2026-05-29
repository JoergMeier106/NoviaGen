import 'package:injectable/injectable.dart';

import 'package:noviagen/app/app_change_bus.dart';


@module
abstract class InjectableModule {
  @lazySingleton
  AppChangeBus get changeBus => AppChangeBus();
}
