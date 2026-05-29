import 'package:flutter_app/models/media.dart';

class GallerySelectionState {
  final Set<String> _selectedImageIds = <String>{};

  bool selectionMode = false;

  bool get hasSelection => _selectedImageIds.isNotEmpty;

  bool isSelected(String imageId) => _selectedImageIds.contains(imageId);

  void toggleSelectionMode() {
    selectionMode = !selectionMode;
    if (!selectionMode) {
      _selectedImageIds.clear();
    }
  }

  void startSelectionWith(String imageId) {
    selectionMode = true;
    _selectedImageIds.add(imageId);
  }

  void toggleImageSelection(String imageId) {
    if (_selectedImageIds.contains(imageId)) {
      _selectedImageIds.remove(imageId);
      if (_selectedImageIds.isEmpty) {
        selectionMode = false;
      }
    } else {
      selectionMode = true;
      _selectedImageIds.add(imageId);
    }
  }

  void clearSelection() {
    _selectedImageIds.clear();
    selectionMode = false;
  }

  List<ImageRecord> selectedImagesFrom(List<ImageRecord> images) {
    if (_selectedImageIds.isEmpty) {
      return <ImageRecord>[];
    }
    return [
      for (final image in images)
        if (_selectedImageIds.contains(image.id)) image,
    ];
  }
}
