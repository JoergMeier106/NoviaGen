import 'package:injectable/injectable.dart';

import 'package:flutter_app/app/app_change_bus.dart';


@module
abstract class InjectableModule {
  @lazySingleton
  AppChangeBus get changeBus => AppChangeBus();
}
