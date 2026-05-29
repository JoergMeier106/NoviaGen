import 'package:noviagen/models/media.dart';
String downloadExtensionForMedia(ImageRecord media) {
  return switch (media.mimeType) {
    'image/gif' => 'gif',
    'video/mp4' => 'mp4',
    _ => media.isVideo ? 'mp4' : 'png',
  };
}
