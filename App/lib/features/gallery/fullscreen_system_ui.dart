import 'package:flutter/services.dart';

import 'package:noviagen/models/media.dart';
class FullscreenSystemUi {
  bool? _appliedPortraitOrientation;

  Future<void> enterForMedia(
    ImageRecord image, {
    required int pageIndex,
    required void Function(int pageIndex) schedulePageCorrection,
  }) async {
    final wantsPortrait = image.height > image.width;
    if (_appliedPortraitOrientation == wantsPortrait) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(
      _orientationsFor(wantsPortrait),
    );
    _appliedPortraitOrientation = wantsPortrait;
    schedulePageCorrection(pageIndex);
  }

  Future<void> restore() async {
    _appliedPortraitOrientation = null;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  List<DeviceOrientation> _orientationsFor(bool wantsPortrait) {
    if (wantsPortrait) {
      return const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ];
    }
    return const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
  }
}
