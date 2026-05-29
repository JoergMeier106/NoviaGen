import 'dart:io';
import 'dart:typed_data';

import 'package:downloadsfolder/downloadsfolder.dart';
import 'package:path_provider/path_provider.dart';


class DeviceDownloads {
  static Future<String> savePng({
    required String fileName,
    required Uint8List bytes,
  }) {
    return saveBytes(fileName: fileName, bytes: bytes, extension: 'png');
  }

  static Future<String> saveBytes({
    required String fileName,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalizedExtension = extension.replaceFirst('.', '');
    final baseName = fileName.endsWith('.$normalizedExtension')
        ? basenameWithoutExtension(fileName)
        : fileName;
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(join(tempDir.path, '$baseName.$normalizedExtension'));

    await tempFile.writeAsBytes(bytes, flush: true);
    try {
      final saved = await copyFileIntoDownloadFolder(
        tempFile.path,
        baseName,
        desiredExtension: normalizedExtension,
      );
      if (saved != true) {
        throw Exception('Failed to copy file into the Downloads folder.');
      }

      final downloadsDir = await getDownloadDirectory();
      return join(downloadsDir.path, '$baseName.$normalizedExtension');
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
