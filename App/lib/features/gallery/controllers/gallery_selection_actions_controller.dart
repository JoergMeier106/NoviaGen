import 'package:flutter/foundation.dart';

import 'package:flutter_app/features/gallery/gallery_view_model.dart';
import 'package:flutter_app/models/media.dart';

typedef GallerySelectionMessageSink = void Function(String message);
typedef GallerySelectionMountedLookup = bool Function();

class GallerySelectionActionsController {
  const GallerySelectionActionsController({
    required this.viewModel,
    required this.showMessage,
    required this.showStateMessage,
    required this.clearSelection,
    required this.isMounted,
  });

  final GalleryViewModel viewModel;
  final GallerySelectionMessageSink showMessage;
  final VoidCallback showStateMessage;
  final VoidCallback clearSelection;
  final GallerySelectionMountedLookup isMounted;

  Future<void> download(List<ImageRecord> images) async {
    var downloadedCount = 0;
    for (final image in images) {
      final savedPath = await viewModel.downloadStoredImage(image);
      if (savedPath != null) {
        downloadedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (downloadedCount > 0) {
      showMessage(
        downloadedCount == 1
            ? 'Downloaded 1 media item.'
            : 'Downloaded $downloadedCount media items.',
      );
      return;
    }
    showStateMessage();
  }

  Future<void> regenerate(List<ImageRecord> images) async {
    var queuedCount = 0;
    for (final image in images) {
      final regeneratedImage = image.isVideo
          ? await viewModel.regenerateVideo(image)
          : await viewModel.regenerateImage(image);
      if (regeneratedImage != null) {
        queuedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (queuedCount > 0) {
      showMessage(
        queuedCount == 1
            ? 'Regeneration job added to the queue.'
            : '$queuedCount regeneration jobs added to the queue.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  Future<void> scale(List<ImageRecord> images, double scaleFactor) async {
    var queuedCount = 0;
    for (final image in images) {
      final upscaledImage = await viewModel.upscaleImage(image, scaleFactor);
      if (upscaledImage != null) {
        queuedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (queuedCount > 0) {
      showMessage(
        queuedCount == 1
            ? 'Scaling job added to the queue.'
            : '$queuedCount scaling jobs added to the queue.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  Future<void> generateAudioVideo(List<ImageRecord> images) async {
    var queuedCount = 0;
    for (final image in images) {
      final generatedImage = await viewModel.generateAudioVideo(image);
      if (generatedImage != null) {
        queuedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (queuedCount > 0) {
      showMessage(
        queuedCount == 1
            ? 'Audio video generation added to the queue.'
            : '$queuedCount audio video jobs added to the queue.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  Future<void> convertVideosToGif(List<ImageRecord> images) async {
    var queuedCount = 0;
    for (final image in images) {
      final convertedImage = await viewModel.convertVideoToGif(image);
      if (convertedImage != null) {
        queuedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (queuedCount > 0) {
      showMessage(
        queuedCount == 1
            ? 'GIF conversion added to the queue.'
            : '$queuedCount GIF conversion jobs added to the queue.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  void useAsImageSource(List<ImageRecord> images) {
    if (images.length != 1) {
      return;
    }
    viewModel.attachStoredImageForGeneration(images.first);
    showMessage('${images.first.mediaTypeLabel} attached as source.');
    clearSelection();
  }

  void createVideoFromImage(List<ImageRecord> images) {
    if (images.length != 1) {
      return;
    }
    viewModel.attachStoredImageForVideoGeneration(images.first);
    showMessage('Image source attached for video generation.');
    clearSelection();
  }

  Future<void> createPromptAndVideo(List<ImageRecord> images) async {
    var queuedCount = 0;
    for (final image in images) {
      final queuedImage = await viewModel.createPromptAndAnimateImage(image);
      if (queuedImage != null) {
        queuedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (queuedCount > 0) {
      showMessage(
        queuedCount == 1
            ? 'Prompt + i2v workflow added to the queue.'
            : '$queuedCount prompt + video generation workflows added to the queue.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  Future<void> restore(List<ImageRecord> images) async {
    var restoredCount = 0;
    for (final image in images) {
      final restoredMessage = await viewModel.restoreDeletedImage(image.id);
      if (restoredMessage != null) {
        restoredCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (restoredCount > 0) {
      showMessage(
        restoredCount == 1
            ? 'Restored 1 media item.'
            : 'Restored $restoredCount media items.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  Future<void> delete(List<ImageRecord> images) async {
    var deletedCount = 0;
    for (final image in images) {
      final deletedMessage = await viewModel.deleteStoredImage(image.id);
      if (deletedMessage != null) {
        deletedCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (deletedCount > 0) {
      showMessage(
        deletedCount == 1
            ? 'Deleted 1 media item.'
            : 'Deleted $deletedCount media items.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }

  Future<void> cancelJobs(List<ImageRecord> images) async {
    var cancelledCount = 0;
    for (final image in images) {
      final job = viewModel.jobForImage(image.id);
      if (job?.canCancel == true && job?.cancelRequested == false) {
        await viewModel.cancelJob(job!.jobId);
        cancelledCount += 1;
      }
    }
    if (!isMounted()) {
      return;
    }
    if (cancelledCount > 0) {
      showMessage(
        cancelledCount == 1
            ? 'Cancellation requested for 1 job.'
            : 'Cancellation requested for $cancelledCount jobs.',
      );
      clearSelection();
      return;
    }
    showStateMessage();
  }
}
