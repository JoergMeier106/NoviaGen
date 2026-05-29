import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';

typedef GalleryJobLookup = JobStatus? Function(String imageId);

class GallerySelectionCapabilities {
  const GallerySelectionCapabilities({
    required this.hasSelection,
    required this.canDownload,
    required this.canRegenerate,
    required this.canScale,
    required this.canGenerateAudioVideo,
    required this.canConvertVideoToGif,
    required this.canUseAsImageSource,
    required this.canCreateVideo,
    required this.canCreatePromptAndVideo,
    required this.canRestore,
    required this.canDelete,
    required this.canCancelJobs,
  });

  factory GallerySelectionCapabilities.fromImages(
    List<ImageRecord> images, {
    required GalleryJobLookup jobForImage,
  }) {
    final hasSelection = images.isNotEmpty;
    if (!hasSelection) {
      return const GallerySelectionCapabilities.empty();
    }

    final allDeleted = images.every((image) => image.isDeleted);
    final allNotDeleted = images.every((image) => !image.isDeleted);
    final allCancellable = images.every((image) {
      final job = jobForImage(image.id);
      return image.isPending &&
          job?.canCancel == true &&
          job?.cancelRequested == false;
    });

    return GallerySelectionCapabilities(
      hasSelection: true,
      canDownload: images.every((image) => image.canDownload),
      canRegenerate: images.every((image) => image.canRegenerate),
      canScale: images.every((image) => image.canScale),
      canGenerateAudioVideo: images.every((image) => image.isVideo),
      canConvertVideoToGif: images.every((image) => image.isVideo),
      canUseAsImageSource: images.length == 1 && images.first.isStillImage,
      canCreateVideo: images.length == 1 && images.first.isStillImage,
      canCreatePromptAndVideo:
          images.every((image) => image.isStillImage && image.isReady),
      canRestore: allDeleted,
      canDelete: allNotDeleted && images.every((image) => !image.isPending),
      canCancelJobs: allCancellable,
    );
  }

  const GallerySelectionCapabilities.empty()
    : hasSelection = false,
      canDownload = false,
      canRegenerate = false,
      canScale = false,
      canGenerateAudioVideo = false,
      canConvertVideoToGif = false,
      canUseAsImageSource = false,
      canCreateVideo = false,
      canCreatePromptAndVideo = false,
      canRestore = false,
      canDelete = false,
      canCancelJobs = false;

  final bool hasSelection;
  final bool canDownload;
  final bool canRegenerate;
  final bool canScale;
  final bool canGenerateAudioVideo;
  final bool canConvertVideoToGif;
  final bool canUseAsImageSource;
  final bool canCreateVideo;
  final bool canCreatePromptAndVideo;
  final bool canRestore;
  final bool canDelete;
  final bool canCancelJobs;

  bool get hasAnyAction =>
      canDownload ||
      canRegenerate ||
      canScale ||
      canGenerateAudioVideo ||
      canConvertVideoToGif ||
      canUseAsImageSource ||
      canCreateVideo ||
      canCreatePromptAndVideo ||
      canRestore ||
      canDelete ||
      canCancelJobs;
}
