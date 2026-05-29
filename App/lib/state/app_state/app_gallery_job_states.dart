import '../gallery_state.dart';
import '../job_operations_state.dart';
import '../media_actions_state.dart';
import '../request_errors.dart';
import 'app_job_polling_controller.dart';
import 'app_media_index_controller.dart';
import '../app_navigation_state.dart';
import '../chat_job_message_state.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppGalleryJobStateDependencies {
  const AppGalleryJobStateDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.navigation,
    required this.chatJobMessages,
    required this.mediaIndex,
    required this.jobPolling,
    required this.setRequestError,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final AppNavigationState navigation;
  final ChatJobMessageState chatJobMessages;
  final AppMediaIndexController mediaIndex;
  final AppJobPollingController jobPolling;
  final RequestErrorHandler setRequestError;
  final void Function() notifyChanged;
}

class AppGalleryJobStates {
  AppGalleryJobStates(AppGalleryJobStateDependencies dependencies) {
    galleryBrowser = GalleryBrowserState(
      reloadFirstPage: () => mediaActions.loadGalleryFirstPage(),
      sortLoadedItems: dependencies.mediaIndex.sortLoadedGalleryItems,
      onChanged: dependencies.notifyChanged,
    );
    jobOperations = JobOperationsState(
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
    mediaActions = MediaActionsState(
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
      onChanged: dependencies.notifyChanged,
      galleryPageSize: MediaActionsState.defaultGalleryPageSize,
    );
  }

  late final GalleryBrowserState galleryBrowser;
  late final JobOperationsState jobOperations;
  late final MediaActionsState mediaActions;
}
