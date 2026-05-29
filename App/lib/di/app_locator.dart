import 'package:get_it/get_it.dart';

import 'package:flutter_app/app/app_change_bus.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/features/generate/controllers/auto_prompt_controller.dart';
import 'package:flutter_app/features/chat/state/chat_attachment_store.dart';
import 'package:flutter_app/features/chat/controllers/chat_job_message_controller.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/chat/state/chat_session_store.dart';
import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/services/generation_job_factory.dart';
import 'package:flutter_app/features/generate/state/generation_source_store.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/features/jobs/services/job_notification_service.dart';
import 'package:flutter_app/features/jobs/controllers/job_operations_controller.dart';
import 'package:flutter_app/features/settings/logs/log_store.dart';
import 'package:flutter_app/features/gallery/controllers/media_actions_controller.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/features/settings/system/system_operations_controller.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/features/generate/services/video_regeneration_job_factory.dart';
import 'package:flutter_app/app/controllers/asset_refresh_controller.dart';
import 'package:flutter_app/app/controllers/backend_refresh_controller.dart';
import 'package:flutter_app/features/chat/controllers/chat_message_controller.dart';
import 'package:flutter_app/app/controllers/configuration_controller.dart';
import 'package:flutter_app/features/generate/controllers/generation_source_controller.dart';
import 'package:flutter_app/features/generate/controllers/image_generation_controller.dart';
import 'package:flutter_app/features/jobs/controllers/job_polling_controller.dart';
import 'package:flutter_app/features/jobs/controllers/job_queue_controller.dart';
import 'package:flutter_app/features/gallery/services/media_index_synchronizer.dart';
import 'package:flutter_app/features/gallery/controllers/media_job_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_generation_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_lucky_generation_controller.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_chat_runtime_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/generation_draft_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';
import 'package:flutter_app/app/runtime/scaling_preferences_store.dart';


extension AppLocator on GetIt {
  AppChangeBus get changes => this<AppChangeBus>();
  void notifyStateChanged() => changes.notifyStateChanged();
  AppConnectionStore get connection => this<AppConnectionStore>();
  AppActivityStore get activity => this<AppActivityStore>();
  AppChatRuntimeStore get chatRuntime => this<AppChatRuntimeStore>();
  GenerationDraftStore get generationDrafts {
    return this<GenerationDraftStore>();
  }

  JobRuntimeStore get jobRuntime => this<JobRuntimeStore>();
  MediaRuntimeStore get mediaRuntime => this<MediaRuntimeStore>();
  ScalingPreferencesStore get scalingPreferences {
    return this<ScalingPreferencesStore>();
  }

  ConfigurationController get configuration {
    return this<ConfigurationController>();
  }

  AssetRefreshController get assetRefresh {
    return this<AssetRefreshController>();
  }

  BackendRefreshController get backendRefresh {
    return this<BackendRefreshController>();
  }

  JobPollingController get jobPolling => this<JobPollingController>();
  JobQueueController get jobQueue => this<JobQueueController>();
  MediaIndexSynchronizer get mediaIndex => this<MediaIndexSynchronizer>();
  JobNotificationService get jobNotifications => this<JobNotificationService>();
  AppNavigationController get navigation => this<AppNavigationController>();
  SystemOperationsController get system => this<SystemOperationsController>();
  LogStore get logs => this<LogStore>();
  ChatAttachmentStore get chatContext => this<ChatAttachmentStore>();
  ChatModelCatalogStore get chatModelCatalog => this<ChatModelCatalogStore>();
  ChatSessionStore get chat => this<ChatSessionStore>();
  ChatJobMessageController get chatJobMessages => this<ChatJobMessageController>();
  GalleryBrowserStore get galleryBrowser => this<GalleryBrowserStore>();
  JobOperationsController get jobOperations => this<JobOperationsController>();
  MediaActionsController get mediaActions => this<MediaActionsController>();
  PromptLibraryStore get promptLibrary => this<PromptLibraryStore>();
  GenerationDefaultsStore get generationDefaults {
    return this<GenerationDefaultsStore>();
  }

  ImageModelSelectionStore get imageModels {
    return this<ImageModelSelectionStore>();
  }

  VideoAssetSelectionStore get videoAssets {
    return this<VideoAssetSelectionStore>();
  }

  GenerationJobFactory get generationJobs => this<GenerationJobFactory>();
  VideoRegenerationJobFactory get videoRegenerationJobs {
    return this<VideoRegenerationJobFactory>();
  }

  GenerationSourceStore get generationSources => this<GenerationSourceStore>();
  VideoGenerationSettingsStore get videoSettings {
    return this<VideoGenerationSettingsStore>();
  }

  AutoPromptController get autoPrompts => this<AutoPromptController>();
  GenerationSourceController get generationSourceController {
    return this<GenerationSourceController>();
  }

  ImageGenerationController get imageGenerationController {
    return this<ImageGenerationController>();
  }

  VideoGenerationController get videoGenerationController {
    return this<VideoGenerationController>();
  }

  VideoLuckyGenerationController get videoLuckyGenerationController {
    return this<VideoLuckyGenerationController>();
  }

  MediaJobController get mediaJobController {
    return this<MediaJobController>();
  }

  ChatMessageController get chatMessageController {
    return this<ChatMessageController>();
  }
}
