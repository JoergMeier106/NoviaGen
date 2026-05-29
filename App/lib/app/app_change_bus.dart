import 'package:flutter/foundation.dart';


class AppChangeBus extends ChangeNotifier {
  void notifyStateChanged() => notifyListeners();
}
