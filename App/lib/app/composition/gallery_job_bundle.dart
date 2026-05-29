import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/jobs/controllers/job_operations_controller.dart';
import 'package:flutter_app/features/gallery/controllers/media_actions_controller.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/jobs/controllers/job_polling_controller.dart';
import 'package:flutter_app/features/gallery/services/media_index_synchronizer.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/features/chat/controllers/chat_job_message_controller.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';

class GalleryJobBundleDependencies {
  const GalleryJobBundleDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.chatModelCatalog,
    required this.generationDefaults,
    required this.navigation,
    required this.chatJobMessages,
    required this.mediaIndex,
    required this.jobPolling,
    required this.setRequestError,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final ChatModelCatalogStore chatModelCatalog;
  final GenerationDefaultsStore generationDefaults;
  final AppNavigationController navigation;
  final ChatJobMessageController chatJobMessages;
  final MediaIndexSynchronizer mediaIndex;
  final JobPollingController jobPolling;
  final RequestErrorHandler setRequestError;
  final void Function() notifyChanged;
}

class GalleryJobBundle {
  GalleryJobBundle(GalleryJobBundleDependencies dependencies) {
    galleryBrowser = GalleryBrowserStore(
      reloadFirstPage: () => mediaActions.loadGalleryFirstPage(),
      sortLoadedItems: dependencies.mediaIndex.sortLoadedGalleryItems,
      onChanged: dependencies.notifyChanged,
    );
    jobOperations = JobOperationsController(
      api: () => dependencies.connection.api,
      setMessage: (value) => dependencies.connection.message = value,
      onChanged: dependencies.notifyChanged,
      replaceJob: dependencies.mediaIndex.replaceJob,
      setJobs: (value) => dependencies.jobRuntime.jobs = value,
      setLoadingJobs: (value) => dependencies.activity.loadingJobs = value,
      syncDeletedScalingSource:
          dependencies.mediaIndex.syncDeletedScalingSource,
      schedulePollingForFirstActiveJob:
          dependencies.jobPolling.schedulePollingForFirstActiveJob,
      syncMediaRefreshTimer: dependencies.jobPolling.syncMediaRefreshTimer,
      setLatestJob: (value) => dependencies.jobRuntime.latestJob = value,
      latestJob: () => dependencies.jobRuntime.latestJob,
      setLatestImage: (value) => dependencies.mediaRuntime.latestImage = value,
      setRunningJob: (value) => dependencies.activity.runningJob = value,
      pollJob: dependencies.jobPolling.pollJob,
      loadLatestResult: ({silent = false}) =>
          mediaActions.loadLatestResult(silent: silent),
      chatJobMessages: dependencies.chatJobMessages,
      navigation: dependencies.navigation,
      getInterJobDelaySeconds: () =>
          dependencies.jobRuntime.interJobDelaySeconds,
      setInterJobDelaySeconds: (value) =>
          dependencies.jobRuntime.interJobDelaySeconds = value,
    );
    mediaActions = MediaActionsController(
      api: () => dependencies.connection.api,
      galleryBrowser: galleryBrowser,
      gallery: () => dependencies.mediaRuntime.gallery,
      setGallery: (value) => dependencies.mediaRuntime.gallery = value,
      latestImage: () => dependencies.mediaRuntime.latestImage,
      setLatestImage: (value) => dependencies.mediaRuntime.latestImage = value,
      setSuggestedTags: (value) =>
          dependencies.mediaRuntime.suggestedTags = value,
      setImportingGalleryMedia: (value) =>
          dependencies.activity.importingGalleryMedia = value,
      findKnownMedia: dependencies.mediaIndex.findKnownMediaById,
      removeGalleryItem: dependencies.mediaIndex.removeGalleryItemById,
      replaceGalleryItem: dependencies.mediaIndex.replaceGalleryItem,
      loadJobs: () => jobOperations.loadJobs(),
      syncMediaRefreshTimer: dependencies.jobPolling.syncMediaRefreshTimer,
      setMessage: (value) => dependencies.connection.message = value,
      setRequestError: dependencies.setRequestError,
      selectedMetadataModelName: (image) => _selectedMetadataModelName(
        image,
        dependencies.chatModelCatalog,
        dependencies.generationDefaults,
      ),
      onChanged: dependencies.notifyChanged,
      galleryPageSize: MediaActionsController.defaultGalleryPageSize,
    );
  }

  late final GalleryBrowserStore galleryBrowser;
  late final JobOperationsController jobOperations;
  late final MediaActionsController mediaActions;

  String? _selectedMetadataModelName(
    ImageRecord image,
    ChatModelCatalogStore chatModelCatalog,
    GenerationDefaultsStore generationDefaults,
  ) {
    final preferredModelName = image.sourceImageId == null
        ? generationDefaults.textToImageAutoMetadataModelName
        : generationDefaults.imageToImageAutoMetadataModelName;
    final preferred = preferredModelName?.trim() ?? '';
    if (preferred.isNotEmpty &&
        (chatModelCatalog.autoPromptModels.isEmpty ||
            chatModelCatalog.autoPromptModels.any(
              (item) => item.name == preferred,
            ))) {
      return preferred;
    }
    if (chatModelCatalog.autoPromptModels.isNotEmpty) {
      return chatModelCatalog.autoPromptModels.first.name;
    }
    return null;
  }
}
