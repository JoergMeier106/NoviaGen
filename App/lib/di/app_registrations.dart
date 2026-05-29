import 'package:get_it/get_it.dart';

import 'package:flutter_app/app/app_change_bus.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/features/chat/controllers/chat_job_message_controller.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/chat/state/chat_session_store.dart';
import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/state/generation_source_store.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/features/jobs/services/job_notification_service.dart';
import 'package:flutter_app/features/jobs/controllers/job_operations_controller.dart';
import 'package:flutter_app/features/settings/logs/log_store.dart';
import 'package:flutter_app/features/gallery/controllers/media_actions_controller.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/settings/system/system_operations_controller.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/app/controllers/asset_refresh_controller.dart';
import 'package:flutter_app/app/controllers/backend_refresh_controller.dart';
import 'package:flutter_app/features/chat/controllers/chat_message_controller.dart';
import 'package:flutter_app/app/composition/chat_bundle.dart';
import 'package:flutter_app/app/controllers/configuration_controller.dart';
import 'package:flutter_app/app/composition/gallery_job_bundle.dart';
import 'package:flutter_app/features/generate/controllers/generation_source_controller.dart';
import 'package:flutter_app/app/composition/generation_bundle.dart';
import 'package:flutter_app/features/generate/controllers/image_generation_controller.dart';
import 'package:flutter_app/features/jobs/controllers/job_polling_controller.dart';
import 'package:flutter_app/features/jobs/controllers/job_queue_controller.dart';
import 'package:flutter_app/features/jobs/services/job_status_fetcher.dart';
import 'package:flutter_app/features/gallery/services/media_index_synchronizer.dart';
import 'package:flutter_app/features/gallery/controllers/media_job_controller.dart';
import 'package:flutter_app/features/gallery/controllers/pending_media_refresh_controller.dart';
import 'package:flutter_app/app/persistence/settings_persistence_scope.dart';
import 'package:flutter_app/app/composition/system_bundle.dart';
import 'package:flutter_app/features/generate/controllers/video_generation_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_lucky_generation_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_result_preview_controller.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_chat_runtime_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/generation_draft_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';
import 'package:flutter_app/app/runtime/scaling_preferences_store.dart';

void registerAppDependencies(GetIt locator) {
  _registerRuntimeState(locator);
  _registerCoreControllers(locator);
  _registerSystemState(locator);
  _registerChatState(locator);
  _registerGalleryState(locator);
  _registerGenerationState(locator);
  _registerFeatureControllers(locator);
}

void _registerRuntimeState(GetIt locator) {
  locator
    ..registerLazySingleton(AppConnectionStore.new)
    ..registerLazySingleton(AppActivityStore.new)
    ..registerLazySingleton(AppChatRuntimeStore.new)
    ..registerLazySingleton(GenerationDraftStore.new)
    ..registerLazySingleton(JobRuntimeStore.new)
    ..registerLazySingleton(MediaRuntimeStore.new)
    ..registerLazySingleton(ScalingPreferencesStore.new)
    ..registerLazySingleton(JobNotificationService.new);
}

void _registerCoreControllers(GetIt locator) {
  locator
    ..registerLazySingleton(
      () => ConfigurationController(
        ConfigurationDependencies(
          persistence: SettingsPersistenceScope(
            connection: locator(),
            promptLibrary: () => locator<PromptLibraryStore>(),
            generationDefaults: () => locator<GenerationDefaultsStore>(),
            generationDrafts: locator(),
            chat: () => locator<ChatSessionStore>(),
            chatRuntime: locator(),
            chatModelCatalog: () => locator<ChatModelCatalogStore>(),
            imageModels: () => locator<ImageModelSelectionStore>(),
            videoAssets: () => locator<VideoAssetSelectionStore>(),
            videoSettings: () => locator<VideoGenerationSettingsStore>(),
            generationSources: () => locator<GenerationSourceStore>(),
            galleryBrowser: () => locator<GalleryBrowserStore>(),
            jobRuntime: locator(),
            scalingPreferences: locator(),
            logs: () => locator<LogStore>(),
            system: () => locator<SystemOperationsController>(),
          ),
          resetPolling: () => locator<JobPollingController>().reset(),
          syncMediaRefreshTimer: () =>
              locator<JobPollingController>().syncMediaRefreshTimer(),
          clearBackendBoundState: () => _clearBackendBoundState(locator),
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => AssetRefreshController(
        AssetRefreshDependencies(
          connection: locator(),
          activity: locator(),
          imageModels: () => locator<ImageModelSelectionStore>(),
          videoAssets: () => locator<VideoAssetSelectionStore>(),
          videoSettings: () => locator<VideoGenerationSettingsStore>(),
          persistGenerateDraft:
              locator<ConfigurationController>().persistGenerateDraft,
          persistSelectedVideoPreset:
              locator<ConfigurationController>().persistSelectedVideoPreset,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => MediaIndexSynchronizer(
        MediaIndexSynchronizerDependencies(
          mediaRuntime: locator(),
          jobRuntime: locator(),
          galleryBrowser: () => locator<GalleryBrowserStore>(),
          generationSources: () => locator<GenerationSourceStore>(),
          loadGalleryFirstPage: () =>
              locator<MediaActionsController>().loadGalleryFirstPage(),
        ),
      ),
    )
    ..registerLazySingleton(() => const JobStatusFetcher())
    ..registerLazySingleton(
      () => VideoResultPreviewController(
        VideoResultPreviewControllerDependencies(
          connection: locator(),
          jobRuntime: locator(),
          mediaRuntime: locator(),
          replaceJob: locator<MediaIndexSynchronizer>().replaceJob,
          replaceGalleryItem:
              locator<MediaIndexSynchronizer>().replaceGalleryItem,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => PendingMediaRefreshController(
        PendingMediaRefreshControllerDependencies(
          mediaRuntime: locator(),
          jobRuntime: locator(),
          replaceGalleryItem:
              locator<MediaIndexSynchronizer>().replaceGalleryItem,
          removeGalleryItemById:
              locator<MediaIndexSynchronizer>().removeGalleryItemById,
          latestCompletedGalleryItem:
              locator<MediaIndexSynchronizer>().latestCompletedGalleryItem,
        ),
      ),
    )
    ..registerLazySingleton(
      () => JobPollingController(
        JobPollingDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          mediaRuntime: locator(),
          jobNotifications: locator(),
          pendingMediaRefreshController: locator(),
          chatJobMessages: () => locator<ChatJobMessageController>(),
          loadErrors: ({silent = false}) =>
              locator<SystemOperationsController>().loadErrors(silent: silent),
          replaceJob: locator<MediaIndexSynchronizer>().replaceJob,
          replaceGalleryItem:
              locator<MediaIndexSynchronizer>().replaceGalleryItem,
          syncDeletedScalingSource:
              locator<MediaIndexSynchronizer>().syncDeletedScalingSource,
          latestCompletedGalleryItem:
              locator<MediaIndexSynchronizer>().latestCompletedGalleryItem,
          videoResultPreviewController: locator(),
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
      dispose: (controller) => controller.dispose(),
    )
    ..registerLazySingleton(
      () => JobQueueController(
        JobQueueDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          mediaRuntime: locator(),
          navigation: () => locator<AppNavigationController>(),
          replaceJob: locator<MediaIndexSynchronizer>().replaceJob,
          replaceGalleryItem:
              locator<MediaIndexSynchronizer>().replaceGalleryItem,
          syncMediaRefreshTimer:
              locator<JobPollingController>().syncMediaRefreshTimer,
          pollJob: locator<JobPollingController>().pollJob,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    );
}

void _registerSystemState(GetIt locator) {
  locator
    ..registerLazySingleton(
      () => SystemBundle(
        SystemBundleDependencies(
          connection: locator(),
          jobRuntime: locator(),
          mediaRuntime: locator(),
          refreshAssets: locator<AssetRefreshController>().refreshAssets,
          clearGenerationSources: () async =>
              locator<GenerationSourceStore>().clearAll(),
          resetLaunchJobRestore: () =>
              locator<JobOperationsController>().launchRestoreStarted = false,
          loadGalleryFirstPage: () =>
              locator<MediaActionsController>().loadGalleryFirstPage(),
          loadJobs: () => locator<JobOperationsController>().loadJobs(),
          loadLatestResult: ({silent = false}) =>
              locator<MediaActionsController>().loadLatestResult(
                silent: silent,
              ),
          loadSettings: locator<ConfigurationController>().loadSettings,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(() => locator<SystemBundle>().navigation)
    ..registerLazySingleton(() => locator<SystemBundle>().system)
    ..registerLazySingleton(() => locator<SystemBundle>().logs);
}

void _registerChatState(GetIt locator) {
  locator
    ..registerLazySingleton(
      () => ChatBundle(
        ChatBundleDependencies(
          connection: locator(),
          chatRuntime: locator(),
          mediaRuntime: locator(),
          navigation: locator(),
          loadErrors: locator<SystemOperationsController>().loadErrors,
          setRequestError: locator.setRequestError,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(() => locator<ChatBundle>().context)
    ..registerLazySingleton(() => locator<ChatBundle>().modelCatalog)
    ..registerLazySingleton(() => locator<ChatBundle>().session)
    ..registerLazySingleton(() => locator<ChatBundle>().jobMessages);
}

void _registerGalleryState(GetIt locator) {
  locator
    ..registerLazySingleton(
      () => GalleryJobBundle(
        GalleryJobBundleDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          mediaRuntime: locator(),
          chatModelCatalog: locator(),
          generationDefaults: locator(),
          navigation: locator(),
          chatJobMessages: locator(),
          mediaIndex: locator(),
          jobPolling: locator(),
          setRequestError: locator.setRequestError,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(() => locator<GalleryJobBundle>().galleryBrowser)
    ..registerLazySingleton(() => locator<GalleryJobBundle>().jobOperations)
    ..registerLazySingleton(() => locator<GalleryJobBundle>().mediaActions);
}

void _registerGenerationState(GetIt locator) {
  locator
    ..registerLazySingleton(
      () => GenerationBundle(
        GenerationBundleDependencies(
          connection: locator(),
          generationDrafts: locator(),
          chatModelCatalog: locator(),
          findKnownMediaById:
              locator<MediaIndexSynchronizer>().findKnownMediaById,
          registerQueuedJob: locator<JobQueueController>().registerQueuedJob,
          announceQueuedJob:
              locator<AppNavigationController>().announceQueuedJob,
          waitForTerminalState:
              locator<JobQueueController>().waitForTerminalState,
          loadErrors: locator<SystemOperationsController>().loadErrors,
          persistGenerationSource:
              locator<ConfigurationController>().persistGenerationSource,
          persistGenerateDraft:
              locator<ConfigurationController>().persistGenerateDraft,
          persistVideoDraft:
              locator<ConfigurationController>().persistVideoDraft,
          setRequestError: locator.setRequestError,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(() => locator<GenerationBundle>().promptLibrary)
    ..registerLazySingleton(() => locator<GenerationBundle>().defaults)
    ..registerLazySingleton(() => locator<GenerationBundle>().imageModels)
    ..registerLazySingleton(() => locator<GenerationBundle>().videoAssets)
    ..registerLazySingleton(() => locator<GenerationBundle>().jobs)
    ..registerLazySingleton(
      () => locator<GenerationBundle>().videoRegenerationJobs,
    )
    ..registerLazySingleton(() => locator<GenerationBundle>().sources)
    ..registerLazySingleton(() => locator<GenerationBundle>().videoSettings)
    ..registerLazySingleton(() => locator<GenerationBundle>().autoPrompts);
}

void _registerFeatureControllers(GetIt locator) {
  locator
    ..registerLazySingleton(
      () => BackendRefreshController(
        BackendRefreshDependencies(
          syncInterJobDelaySetting:
              locator<JobOperationsController>().syncInterJobDelaySetting,
          refreshAssets: locator<AssetRefreshController>().refreshAssets,
          loadJobs: locator<JobOperationsController>().loadJobs,
          loadLatestResult: ({silent = false}) =>
              locator<MediaActionsController>().loadLatestResult(
                silent: silent,
              ),
          loadHealth: ({silent = false}) =>
              locator<SystemOperationsController>().loadHealth(silent: silent),
          loadAutoPromptModels: ({silent = false}) =>
              locator<ChatModelCatalogStore>().loadAutoPromptModels(
                silent: silent,
              ),
        ),
      ),
    )
    ..registerLazySingleton(
      () => ChatMessageController(
        ChatMessageDependencies(
          connection: locator(),
          activity: locator(),
          chatRuntime: locator(),
          jobRuntime: locator(),
          context: locator(),
          modelCatalog: locator(),
          session: locator(),
          jobMessages: locator(),
          replaceJob: locator<MediaIndexSynchronizer>().replaceJob,
          pollJob: locator<JobPollingController>().pollJob,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => GenerationSourceController(
        GenerationSourceDependencies(
          generationDrafts: locator(),
          generationDefaults: locator(),
          generationSources: locator(),
          videoAssets: locator(),
          videoSettings: locator(),
          configuration: locator(),
          navigation: locator(),
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => ImageGenerationController(
        ImageGenerationDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          jobNotifications: locator(),
          navigation: locator(),
          autoPrompts: locator(),
          imageModels: locator(),
          promptLibrary: locator(),
          generationJobs: locator(),
          generationSources: locator(),
          registerQueuedJob: locator<JobQueueController>().registerQueuedJob,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => VideoGenerationController(
        VideoGenerationDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          jobNotifications: locator(),
          navigation: locator(),
          autoPrompts: locator(),
          videoAssets: locator(),
          videoSettings: locator(),
          promptLibrary: locator(),
          generationJobs: locator(),
          generationSources: locator(),
          registerQueuedJob: locator<JobQueueController>().registerQueuedJob,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => VideoLuckyGenerationController(
        VideoLuckyGenerationDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          jobNotifications: locator(),
          navigation: locator(),
          autoPrompts: locator(),
          imageModels: locator(),
          videoAssets: locator(),
          videoSettings: locator(),
          promptLibrary: locator(),
          generationJobs: locator(),
          registerQueuedJob: locator<JobQueueController>().registerQueuedJob,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    )
    ..registerLazySingleton(
      () => MediaJobController(
        MediaJobDependencies(
          connection: locator(),
          activity: locator(),
          jobRuntime: locator(),
          mediaRuntime: locator(),
          scalingPreferences: locator(),
          generationDefaults: locator(),
          jobNotifications: locator(),
          autoPrompts: locator(),
          promptLibrary: locator(),
          generationJobs: locator(),
          videoAssets: locator(),
          videoSettings: locator(),
          videoRegenerationJobs: locator(),
          registerQueuedJob: locator<JobQueueController>().registerQueuedJob,
          notifyChanged: locator.appNotifyChanged,
        ),
      ),
    );
}

void _clearBackendBoundState(GetIt locator) {
  locator<JobPollingController>().reset();
  locator<JobRuntimeStore>().latestJob = null;
  locator<MediaRuntimeStore>().latestImage = null;
  locator<SystemOperationsController>().backendHealth = null;
  locator<JobOperationsController>().launchRestoreStarted = false;
  locator<ChatModelCatalogStore>().clear();
  locator<ChatSessionStore>().clearAll();
  locator<MediaRuntimeStore>().gallery = [];
  locator<GalleryBrowserStore>().resetPaging();
}

extension _AppRegistrationCallbacks on GetIt {
  void appNotifyChanged() {
    this<AppChangeBus>().notifyStateChanged();
  }

  void setRequestError(Object error, {required String generalMessage}) {
    this<AppConnectionStore>().message = requestErrorMessage(
      error,
      generalMessage: generalMessage,
    );
  }
}
