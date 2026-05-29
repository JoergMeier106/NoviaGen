import 'package:get_it/get_it.dart';

import 'package:flutter_app/models/chat_models.dart';
import 'package:flutter_app/models/chat_sessions.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/features/generate/domain/generation_settings.dart';
import 'package:flutter_app/features/settings/system/wake_on_lan_settings.dart' as wol;
import 'package:flutter_app/di/app_locator.dart';

extension AppLocatorSelectors on GetIt {
  bool get loadingGallery {
    return galleryBrowser.loadingFirstPage || galleryBrowser.loadingNextPage;
  }

  bool get loadingChat => chatModelCatalog.loading || chat.loading;
  bool get applyingBackup => system.applyingBackup;
  bool get applyingAppBackup => system.applyingAppBackup;

  int get numInferenceSteps => generationDefaults.numInferenceSteps;
  double get guidanceScale => generationDefaults.guidanceScale;

  int get imageToImageNumInferenceSteps {
    return generationDefaults.imageToImageNumInferenceSteps;
  }

  double get imageToImageGuidanceScale {
    return generationDefaults.imageToImageGuidanceScale;
  }

  ImageOrientationSetting get imageOrientation {
    return generationDefaults.imageOrientation;
  }

  String get promptGeneratorBasePrompt {
    return generationDefaults.promptGeneratorBasePrompt;
  }

  String get imageToImagePromptGeneratorBasePrompt {
    return generationDefaults.imageToImagePromptGeneratorBasePrompt;
  }

  String get textToVideoPromptGeneratorBasePrompt {
    return generationDefaults.textToVideoPromptGeneratorBasePrompt;
  }

  String get imageToVideoPromptGeneratorBasePrompt {
    return generationDefaults.imageToVideoPromptGeneratorBasePrompt;
  }

  double get imageToImageStrength => generationDefaults.imageToImageStrength;
  wol.WakeOnLanSettings get wakeOnLan => system.wakeOnLan;
  PromptPreset? get selectedImagePromptPreset =>
      promptLibrary.selectedImagePreset;
  PromptPreset? get selectedVideoPromptPreset =>
      promptLibrary.selectedVideoPreset;

  JobStatus? get activeRunningJob {
    for (final job in jobRuntime.jobs) {
      if (job.status == 'running') {
        return job;
      }
    }
    final job = jobRuntime.latestJob;
    return job?.status == 'running' ? job : null;
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

  String get selectedAutoPromptModelName {
    return chatModelCatalog.selectedAutoPromptModelName;
  }

  OllamaModelInfo? get selectedAutoPromptModelInfo {
    return chatModelCatalog.selectedAutoPromptModelInfo;
  }

  String get selectedImageToImageAutoPromptModelName {
    return chatModelCatalog.selectedImageToImageAutoPromptModelName;
  }

  String get selectedTextToVideoAutoPromptModelName {
    return chatModelCatalog.selectedTextToVideoAutoPromptModelName;
  }

  String get selectedImageToVideoAutoPromptModelName {
    return chatModelCatalog.selectedImageToVideoAutoPromptModelName;
  }

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
}
