import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/generate/controllers/auto_prompt_controller.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/generate/state/generation_defaults_store.dart';
import 'package:flutter_app/features/generate/services/generation_job_factory.dart';
import 'package:flutter_app/features/generate/state/generation_source_store.dart';
import 'package:flutter_app/features/generate/state/image_model_selection_store.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/features/prompts/state/prompt_library_store.dart';
import 'package:flutter_app/features/generate/state/video_asset_selection_store.dart';
import 'package:flutter_app/features/generate/state/video_generation_settings_store.dart';
import 'package:flutter_app/features/generate/services/video_regeneration_job_factory.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/generation_draft_store.dart';

class GenerationBundleDependencies {
  const GenerationBundleDependencies({
    required this.connection,
    required this.generationDrafts,
    required this.chatModelCatalog,
    required this.findKnownMediaById,
    required this.registerQueuedJob,
    required this.announceQueuedJob,
    required this.waitForTerminalState,
    required this.loadErrors,
    required this.persistGenerationSource,
    required this.persistGenerateDraft,
    required this.persistVideoDraft,
    required this.setRequestError,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final GenerationDraftStore generationDrafts;
  final ChatModelCatalogStore chatModelCatalog;
  final ImageRecord? Function(String imageId) findKnownMediaById;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function(String message) announceQueuedJob;
  final Future<JobStatus?> Function(String jobId) waitForTerminalState;
  final Future<void> Function({bool silent}) loadErrors;
  final Future<void> Function({required bool forVideo}) persistGenerationSource;
  final Future<void> Function() persistGenerateDraft;
  final Future<void> Function() persistVideoDraft;
  final RequestErrorHandler setRequestError;
  final void Function() notifyChanged;
}

class GenerationBundle {
  GenerationBundle(GenerationBundleDependencies dependencies)
    : promptLibrary = PromptLibraryStore(onChanged: dependencies.notifyChanged),
      defaults = GenerationDefaultsStore(onChanged: dependencies.notifyChanged),
      imageModels = ImageModelSelectionStore(
        setMessage: (value) => dependencies.connection.message = value,
        onChanged: dependencies.notifyChanged,
      ),
      videoAssets = VideoAssetSelectionStore(
        onChanged: dependencies.notifyChanged,
      ) {
    jobs = GenerationJobFactory(
      defaults: defaults,
      videoAssets: videoAssets,
      chatModelCatalog: dependencies.chatModelCatalog,
    );
    videoRegenerationJobs = VideoRegenerationJobFactory(
      videoAssets: videoAssets,
      findKnownMedia: dependencies.findKnownMediaById,
    );
    sources = GenerationSourceStore(
      setMessage: (value) => dependencies.connection.message = value,
      setGenerateMode: (value) => dependencies.generationDrafts.mode = value,
      syncVideoDraftOrientation: () =>
          videoSettings.syncDraftOrientationToSource(),
      persistSource: dependencies.persistGenerationSource,
      setRequestError: dependencies.setRequestError,
      onChanged: dependencies.notifyChanged,
    );
    videoSettings = VideoGenerationSettingsStore(
      selectedPreset: () => videoAssets.selectedPreset,
      sourceOrientation: () => sources.videoSourceOrientation,
      setMessage: (value) => dependencies.connection.message = value,
      persistDraft: dependencies.persistVideoDraft,
      onChanged: dependencies.notifyChanged,
    );
    autoPrompts = AutoPromptController(
      api: () => dependencies.connection.api,
      registerQueuedJob: dependencies.registerQueuedJob,
      announceQueuedJob: dependencies.announceQueuedJob,
      waitForJobToReachTerminalState: dependencies.waitForTerminalState,
      loadErrors: dependencies.loadErrors,
      setMessage: (value) => dependencies.connection.message = value,
      setRequestError: dependencies.setRequestError,
      onChanged: dependencies.notifyChanged,
      saveImagePromptDraft: (value) async {
        dependencies.generationDrafts.imagePrompt = value;
        await dependencies.persistGenerateDraft();
      },
      saveVideoPromptDraft: (value) async {
        dependencies.generationDrafts.videoPrompt = value;
        await dependencies.persistVideoDraft();
      },
      hasImageSource: () => sources.hasImageSource,
      videoSource: () => sources.videoSource,
      videoLocalSource: () => sources.videoLocalSource,
      textToImageModelName: () =>
          dependencies.chatModelCatalog.selectedAutoPromptModelName,
      imageToImageModelName: () =>
          dependencies.chatModelCatalog.selectedImageToImageAutoPromptModelName,
      textToVideoModelName: () =>
          dependencies.chatModelCatalog.selectedTextToVideoAutoPromptModelName,
      imageToVideoModelName: () =>
          dependencies.chatModelCatalog.selectedImageToVideoAutoPromptModelName,
      textToImageBasePrompt: () => defaults.promptGeneratorBasePrompt,
      imageToImageBasePrompt: () =>
          defaults.imageToImagePromptGeneratorBasePrompt,
      textToVideoBasePrompt: () =>
          defaults.textToVideoPromptGeneratorBasePrompt,
      imageToVideoBasePrompt: () =>
          defaults.imageToVideoPromptGeneratorBasePrompt,
    );
  }

  final PromptLibraryStore promptLibrary;
  final GenerationDefaultsStore defaults;
  final ImageModelSelectionStore imageModels;
  final VideoAssetSelectionStore videoAssets;
  late final GenerationJobFactory jobs;
  late final VideoRegenerationJobFactory videoRegenerationJobs;
  late final GenerationSourceStore sources;
  late final VideoGenerationSettingsStore videoSettings;
  late final AutoPromptController autoPrompts;
}
