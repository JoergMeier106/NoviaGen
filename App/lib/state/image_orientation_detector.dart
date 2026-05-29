import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'generation_settings.dart';


ImageOrientationSetting imageOrientationFromDimensions(int width, int height) {
  return height > width
      ? ImageOrientationSetting.portrait
      : ImageOrientationSetting.landscape;
}

Future<ImageOrientationSetting?> detectLocalImageOrientation(
  String path,
) async {
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }
    final image = await _decodeUiImage(bytes);
    final orientation = imageOrientationFromDimensions(
      image.width,
      image.height,
    );
    image.dispose();
    return orientation;
  } catch (_) {
    return null;
  }
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, (image) {
    if (!completer.isCompleted) {
      completer.complete(image);
    }
  });
  return completer.future;
}
