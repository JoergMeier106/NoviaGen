import '../../models/jobs.dart';
import '../../models/media.dart';
import '../auto_prompt_state.dart';
import '../chat_model_catalog_state.dart';
import '../generation_defaults_state.dart';
import '../generation_job_factory.dart';
import '../generation_source_state.dart';
import '../image_model_selection_state.dart';
import '../request_errors.dart';
import '../prompt_library_state.dart';
import '../video_asset_selection_state.dart';
import '../video_generation_settings_state.dart';
import '../video_regeneration_job_factory.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_generation_draft_state.dart';


class AppGenerationStateDependencies {
  const AppGenerationStateDependencies({
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

  final AppConnectionState connection;
  final AppGenerationDraftState generationDrafts;
  final ChatModelCatalogState chatModelCatalog;
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

class AppGenerationStates {
  AppGenerationStates(AppGenerationStateDependencies dependencies)
    : promptLibrary = PromptLibraryState(onChanged: dependencies.notifyChanged),
      defaults = GenerationDefaultsState(onChanged: dependencies.notifyChanged),
      imageModels = ImageModelSelectionState(
        setMessage: (value) => dependencies.connection.message = value,
        onChanged: dependencies.notifyChanged,
      ),
      videoAssets = VideoAssetSelectionState(
        onChanged: dependencies.notifyChanged,
      ) {
    jobs = GenerationJobFactory(defaults: defaults, videoAssets: videoAssets);
    videoRegenerationJobs = VideoRegenerationJobFactory(
      videoAssets: videoAssets,
      findKnownMedia: dependencies.findKnownMediaById,
    );
    sources = GenerationSourceState(
      setMessage: (value) => dependencies.connection.message = value,
      setGenerateMode: (value) => dependencies.generationDrafts.mode = value,
      syncVideoDraftOrientation: () =>
          videoSettings.syncDraftOrientationToSource(),
      persistSource: dependencies.persistGenerationSource,
      setRequestError: dependencies.setRequestError,
      onChanged: dependencies.notifyChanged,
    );
    videoSettings = VideoGenerationSettingsState(
      selectedPreset: () => videoAssets.selectedPreset,
      sourceOrientation: () => sources.videoSourceOrientation,
      setMessage: (value) => dependencies.connection.message = value,
      persistDraft: dependencies.persistVideoDraft,
      onChanged: dependencies.notifyChanged,
    );
    autoPrompts = AutoPromptState(
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

  final PromptLibraryState promptLibrary;
  final GenerationDefaultsState defaults;
  final ImageModelSelectionState imageModels;
  final VideoAssetSelectionState videoAssets;
  late final GenerationJobFactory jobs;
  late final VideoRegenerationJobFactory videoRegenerationJobs;
  late final GenerationSourceState sources;
  late final VideoGenerationSettingsState videoSettings;
  late final AutoPromptState autoPrompts;
}
