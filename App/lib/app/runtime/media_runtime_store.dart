import 'package:flutter_app/models/media.dart';
class MediaRuntimeStore {
  List<ImageRecord> gallery = <ImageRecord>[];
  ImageRecord? latestImage;
  List<String> suggestedTags = <String>[];
}
