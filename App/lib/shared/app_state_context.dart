import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:noviagen/app/app_change_bus.dart';
import 'package:noviagen/models/chat_models.dart';
import 'package:noviagen/models/chat_sessions.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/app/navigation/app_navigation_controller.dart';
import 'package:noviagen/features/generate/controllers/auto_prompt_controller.dart';
import 'package:noviagen/features/chat/state/chat_attachment_store.dart';
import 'package:noviagen/features/chat/controllers/chat_job_message_controller.dart';
import 'package:noviagen/features/chat/state/chat_model_catalog_store.dart';
import 'package:noviagen/features/chat/state/chat_session_store.dart';
import 'package:noviagen/features/gallery/state/gallery_browser_store.dart';
import 'package:noviagen/features/generate/state/generation_defaults_store.dart';
import 'package:noviagen/features/generate/state/generation_source_store.dart';
import 'package:noviagen/features/generate/state/image_model_selection_store.dart';
import 'package:noviagen/features/jobs/services/job_notification_service.dart';
import 'package:noviagen/features/jobs/controllers/job_operations_controller.dart';
import 'package:noviagen/features/settings/logs/log_store.dart';
import 'package:noviagen/features/gallery/controllers/media_actions_controller.dart';
import 'package:noviagen/features/prompts/state/prompt_library_store.dart';
import 'package:noviagen/features/settings/system/system_operations_controller.dart';
import 'package:noviagen/features/generate/state/video_asset_selection_store.dart';
import 'package:noviagen/features/generate/state/video_generation_settings_store.dart';
import 'package:noviagen/app/controllers/asset_refresh_controller.dart';
import 'package:noviagen/features/chat/controllers/chat_message_controller.dart';
import 'package:noviagen/app/controllers/configuration_controller.dart';
import 'package:noviagen/features/generate/controllers/generation_source_controller.dart';
import 'package:noviagen/features/generate/controllers/image_generation_controller.dart';
import 'package:noviagen/features/gallery/controllers/media_job_controller.dart';
import 'package:noviagen/features/generate/controllers/video_generation_controller.dart';
import 'package:noviagen/features/generate/controllers/video_lucky_generation_controller.dart';
import 'package:noviagen/app/runtime/app_activity_store.dart';
import 'package:noviagen/app/runtime/app_chat_runtime_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/generation_draft_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';
import 'package:noviagen/app/runtime/media_runtime_store.dart';
import 'package:noviagen/app/runtime/scaling_preferences_store.dart';

extension AppStateContext on BuildContext {
  void watchAppChanges() => watch<AppChangeBus>();

  AppChangeBus get changes => read<AppChangeBus>();
  AppConnectionStore get connection => read<AppConnectionStore>();
  AppActivityStore get activity => read<AppActivityStore>();
  AppChatRuntimeStore get chatRuntime => read<AppChatRuntimeStore>();
  GenerationDraftStore get generationDrafts => read<GenerationDraftStore>();
  JobRuntimeStore get jobRuntime => read<JobRuntimeStore>();
  MediaRuntimeStore get mediaRuntime => read<MediaRuntimeStore>();
  ScalingPreferencesStore get scalingPreferences =>
      read<ScalingPreferencesStore>();
  AppNavigationController get navigation => read<AppNavigationController>();
  JobNotificationService get jobNotifications => read<JobNotificationService>();
  ConfigurationController get configuration =>
      read<ConfigurationController>();
  AssetRefreshController get assetRefresh =>
      read<AssetRefreshController>();
  SystemOperationsController get system => read<SystemOperationsController>();
  LogStore get logs => read<LogStore>();
  ChatAttachmentStore get chatContext => read<ChatAttachmentStore>();
  ChatModelCatalogStore get chatModelCatalog => read<ChatModelCatalogStore>();
  ChatSessionStore get chat => read<ChatSessionStore>();
  ChatJobMessageController get chatJobMessages => read<ChatJobMessageController>();
  GalleryBrowserStore get galleryBrowser => read<GalleryBrowserStore>();
  JobOperationsController get jobOperations => read<JobOperationsController>();
  MediaActionsController get mediaActions => read<MediaActionsController>();
  PromptLibraryStore get promptLibrary => read<PromptLibraryStore>();
  GenerationDefaultsStore get generationDefaults =>
      read<GenerationDefaultsStore>();
  ImageModelSelectionStore get imageModels => read<ImageModelSelectionStore>();
  VideoAssetSelectionStore get videoAssets => read<VideoAssetSelectionStore>();
  GenerationSourceStore get generationSources => read<GenerationSourceStore>();
  VideoGenerationSettingsStore get videoSettings =>
      read<VideoGenerationSettingsStore>();
  AutoPromptController get autoPrompts => read<AutoPromptController>();
  GenerationSourceController get generationSourceController =>
      read<GenerationSourceController>();
  ImageGenerationController get imageGenerationController =>
      read<ImageGenerationController>();
  VideoGenerationController get videoGenerationController =>
      read<VideoGenerationController>();
  VideoLuckyGenerationController get videoLuckyGenerationController =>
      read<VideoLuckyGenerationController>();
  MediaJobController get mediaJobController => read<MediaJobController>();
  ChatMessageController get chatMessageController =>
      read<ChatMessageController>();

  JobStatus? get activeRunningJob {
    for (final job in jobRuntime.jobs) {
      if (job.status == 'running') {
        return job;
      }
    }
    final job = jobRuntime.latestJob;
    return job?.status == 'running' ? job : null;
  }

  JobStatus? jobForImage(String imageId) {
    final latest = jobRuntime.latestJob;
    if (latest?.result?.id == imageId) {
      return latest;
    }
    for (final job in jobRuntime.jobs) {
      if (job.result?.id == imageId) {
        return job;
      }
    }
    return null;
  }

  ChatSessionRecord? get selectedChatSession => chat.selectedSession;

  String get selectedChatModelName {
    return chatModelCatalog.selectedChatModelName(selectedChatSession);
  }

  OllamaModelInfo? get selectedChatModelInfo {
    return chatModelCatalog.selectedChatModelInfo(selectedChatSession);
  }

  bool get effectiveChatThinkingEnabled {
    return chatModelCatalog.effectiveThinkingEnabled(
      chatThinkingEnabled: chatRuntime.thinkingEnabled,
      selectedSession: selectedChatSession,
    );
  }

  String get selectedAutoPromptModelName =>
      chatModelCatalog.selectedAutoPromptModelName;

  OllamaModelInfo? get selectedAutoPromptModelInfo =>
      chatModelCatalog.selectedAutoPromptModelInfo;

  String get selectedImageToImageAutoPromptModelName =>
      chatModelCatalog.selectedImageToImageAutoPromptModelName;

  String get selectedTextToVideoAutoPromptModelName =>
      chatModelCatalog.selectedTextToVideoAutoPromptModelName;

  String get selectedImageToVideoAutoPromptModelName =>
      chatModelCatalog.selectedImageToVideoAutoPromptModelName;

  bool get applyingBackup => system.applyingBackup;
  bool get applyingAppBackup => system.applyingAppBackup;

  bool get hasActiveOrQueuedJobs {
    for (final job in jobRuntime.jobs) {
      if (job.status == 'queued' || job.status == 'running') {
        return true;
      }
    }
    if (jobRuntime.latestJob?.canCancel ?? false) {
      return true;
    }
    final queueIdle = system.backendHealth?.queue['queue_idle'];
    return queueIdle is bool ? !queueIdle : false;
  }
}
