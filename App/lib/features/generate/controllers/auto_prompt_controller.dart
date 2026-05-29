import 'dart:async';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
class AutoPromptController {
  AutoPromptController({
    required this.api,
    required this.registerQueuedJob,
    required this.announceQueuedJob,
    required this.waitForJobToReachTerminalState,
    required this.loadErrors,
    required this.setMessage,
    required this.setRequestError,
    required this.onChanged,
    required this.saveImagePromptDraft,
    required this.saveVideoPromptDraft,
    required this.hasImageSource,
    required this.videoSource,
    required this.videoLocalSource,
    required this.textToImageModelName,
    required this.imageToImageModelName,
    required this.textToVideoModelName,
    required this.imageToVideoModelName,
    required this.textToImageBasePrompt,
    required this.imageToImageBasePrompt,
    required this.textToVideoBasePrompt,
    required this.imageToVideoBasePrompt,
  });

  final ApiClient? Function() api;
  final ImageRecord? Function(JobStatus job, {String? queuedMessage})
  registerQueuedJob;
  final void Function(String messageText) announceQueuedJob;
  final Future<JobStatus?> Function(String jobId)
  waitForJobToReachTerminalState;
  final Future<void> Function({bool silent}) loadErrors;
  final void Function(String? value) setMessage;
  final void Function(Object error, {required String generalMessage})
  setRequestError;
  final void Function() onChanged;
  final Future<void> Function(String prompt) saveImagePromptDraft;
  final Future<void> Function(String prompt) saveVideoPromptDraft;
  final bool Function() hasImageSource;
  final ImageRecord? Function() videoSource;
  final LocalImageSource? Function() videoLocalSource;
  final String Function() textToImageModelName;
  final String Function() imageToImageModelName;
  final String Function() textToVideoModelName;
  final String Function() imageToVideoModelName;
  final String Function() textToImageBasePrompt;
  final String Function() imageToImageBasePrompt;
  final String Function() textToVideoBasePrompt;
  final String Function() imageToVideoBasePrompt;

  Future<String?>? _pendingImagePromptFuture;
  Future<String?>? _pendingVideoPromptFuture;

  bool get generatingPrompt =>
      _pendingImagePromptFuture != null || _pendingVideoPromptFuture != null;

  bool hasPendingPrompt({required bool forVideo}) {
    return forVideo
        ? _pendingVideoPromptFuture != null
        : _pendingImagePromptFuture != null;
  }

  Future<String?> generatePromptText({
    required bool forVideo,
    required String currentPrompt,
  }) async {
    final client = api();
    if (client == null) {
      setMessage('Set a backend URL first.');
      onChanged();
      return null;
    }

    final context = _promptContext(forVideo: forVideo);
    final modelName = context.modelName.trim();
    if (modelName.isEmpty) {
      setMessage(
        'Select a ${context.generationLabel} auto-prompt Ollama model in Settings first.',
      );
      onChanged();
      return null;
    }

    final promptInput = _combinePromptGenerationInput(
      currentPrompt,
      basePrompt: context.basePrompt,
    );
    if (promptInput.isEmpty) {
      setMessage(
        'Enter a ${context.generationLabel} base prompt or prompt text first.',
      );
      onChanged();
      return null;
    }

    setMessage(null);
    onChanged();
    announceQueuedJob(
      'Auto-prompt request was accepted and added to the queue.',
    );

    late final Future<String?> pendingFuture;
    pendingFuture = () async {
      try {
        final generatedPrompt = await _queuePromptTextJob(
          client: client,
          useImageToVideoPromptGenerator:
              context.useImageToVideoPromptGenerator,
          promptInput: promptInput,
          modelName: modelName,
          storedVideoSourceId: context.storedVideoSource?.id,
          localVideoSource: context.localVideoSource,
          emptyResultMessage: 'Prompt generation returned an empty result.',
          cancelledMessage: 'Prompt generation was cancelled.',
          errorMessage:
              'Couldn\'t generate a prompt right now. Please try again.',
        );
        if (generatedPrompt == null) {
          return null;
        }
        if (forVideo) {
          await saveVideoPromptDraft(generatedPrompt);
        } else {
          await saveImagePromptDraft(generatedPrompt);
        }
        return generatedPrompt;
      } catch (error) {
        setRequestError(
          error,
          generalMessage:
              'Couldn\'t generate a prompt right now. Please try again.',
        );
        return null;
      } finally {
        _clearPendingPrompt(forVideo: forVideo, pendingFuture: pendingFuture);
      }
    }();

    if (forVideo) {
      _pendingVideoPromptFuture = pendingFuture;
    } else {
      _pendingImagePromptFuture = pendingFuture;
    }
    onChanged();
    return pendingFuture;
  }

  Future<String?> resolvePromptForQueuedGeneration({
    required bool forVideo,
    required String submittedPrompt,
  }) async {
    final pendingFuture = forVideo
        ? _pendingVideoPromptFuture
        : _pendingImagePromptFuture;
    if (pendingFuture == null) {
      return submittedPrompt.trim();
    }
    final resolvedPrompt = await pendingFuture;
    return resolvedPrompt?.trim();
  }

  Future<String?> generateLuckyPrompt() async {
    final client = api();
    if (client == null) {
      setMessage('Set a backend URL first.');
      onChanged();
      return null;
    }
    final basePrompt = _requireLuckyBasePrompt(
      useImageToVideoPromptGenerator: false,
    );
    if (basePrompt == null) {
      return null;
    }

    final modelName = textToImageModelName().trim();
    if (modelName.isEmpty) {
      setMessage('Select an auto-prompt Ollama model in Settings first.');
      onChanged();
      return null;
    }

    try {
      return await _queuePromptTextJob(
        client: client,
        useImageToVideoPromptGenerator: false,
        promptInput: basePrompt,
        modelName: modelName,
        queuedMessage:
            'Feeling Lucky prompt job was accepted and added to the queue.',
        emptyResultMessage: 'Prompt generation returned an empty result.',
        cancelledMessage: 'Feeling Lucky prompt generation was cancelled.',
        errorMessage:
            'Couldn\'t generate a lucky prompt right now. Please try again.',
      );
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t generate a lucky prompt right now. Please try again.',
      );
      return null;
    }
  }

  JobChainStep? createLuckyPromptChainStep({required String stepId}) {
    final basePrompt = _requireLuckyBasePrompt(
      useImageToVideoPromptGenerator: false,
    );
    if (basePrompt == null) {
      return null;
    }

    final modelName = textToImageModelName().trim();
    if (modelName.isEmpty) {
      setMessage('Select an auto-prompt Ollama model in Settings first.');
      onChanged();
      return null;
    }
    return JobChainStep(
      id: stepId,
      type: 'generate_prompt',
      payload: {
        'prompt': basePrompt,
        'model_name': modelName,
      },
    );
  }

  Future<String?> generateLuckyImageToVideoPrompt({
    required String imageId,
  }) async {
    final client = api();
    if (client == null) {
      setMessage('Set a backend URL first.');
      onChanged();
      return null;
    }
    final basePrompt = _requireLuckyBasePrompt(
      useImageToVideoPromptGenerator: true,
    );
    if (basePrompt == null) {
      return null;
    }

    final modelName = imageToVideoModelName().trim();
    if (modelName.isEmpty) {
      setMessage('Select an i2v auto-prompt Ollama model in Settings first.');
      onChanged();
      return null;
    }

    try {
      return await _queuePromptTextJob(
        client: client,
        useImageToVideoPromptGenerator: true,
        promptInput: basePrompt,
        modelName: modelName,
        storedVideoSourceId: imageId,
        queuedMessage:
            'Feeling Lucky video prompt job was accepted and added to the queue.',
        emptyResultMessage: 'Prompt generation returned an empty result.',
        cancelledMessage:
            'Feeling Lucky video prompt generation was cancelled.',
        errorMessage:
            'Couldn\'t generate a lucky video prompt right now. Please try again.',
      );
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t generate a lucky video prompt right now. Please try again.',
      );
      return null;
    }
  }

  JobChainStep? createLuckyImageToVideoPromptChainStep({
    required String stepId,
    String? imageId,
    String? boundImageStepId,
  }) {
    final basePrompt = _requireLuckyBasePrompt(
      useImageToVideoPromptGenerator: true,
    );
    if (basePrompt == null) {
      return null;
    }

    final modelName = imageToVideoModelName().trim();
    if (modelName.isEmpty) {
      setMessage('Select an i2v auto-prompt Ollama model in Settings first.');
      onChanged();
      return null;
    }
    final hasStoredImage = imageId != null && imageId.trim().isNotEmpty;
    final hasBoundImage =
        boundImageStepId != null && boundImageStepId.trim().isNotEmpty;
    if (hasStoredImage == hasBoundImage) {
      setMessage('Select exactly one image source for i2v prompt generation.');
      onChanged();
      return null;
    }
    final normalizedImageId = imageId?.trim();
    final normalizedBoundImageStepId = boundImageStepId?.trim();
    return JobChainStep(
      id: stepId,
      type: 'generate_i2v_prompt',
      payload: {
        'prompt': basePrompt,
        'model_name': modelName,
        if (hasStoredImage && normalizedImageId != null)
          'image_id': normalizedImageId,
      },
      bindings: hasBoundImage
          ? {
              'image_id': JobChainBinding(
                stepId: normalizedBoundImageStepId!,
                output: 'result_image_id',
              ),
            }
          : const <String, JobChainBinding>{},
    );
  }

  Future<String?> _queuePromptTextJob({
    required ApiClient client,
    required bool useImageToVideoPromptGenerator,
    required String promptInput,
    required String? modelName,
    String? storedVideoSourceId,
    LocalImageSource? localVideoSource,
    String? queuedMessage,
    required String emptyResultMessage,
    required String cancelledMessage,
    required String errorMessage,
  }) async {
    final queuedJob = useImageToVideoPromptGenerator
        ? await client.createGenerateImageToVideoPromptJob(
            prompt: promptInput,
            imageId: storedVideoSourceId,
            imagePath: localVideoSource?.path,
            imageName: localVideoSource?.name,
            modelName: modelName,
          )
        : await client.createGeneratePromptJob(
            prompt: promptInput,
            modelName: modelName,
          );
    registerQueuedJob(queuedJob, queuedMessage: queuedMessage);
    final completedJob = await waitForJobToReachTerminalState(queuedJob.jobId);
    if (completedJob == null) {
      return null;
    }
    if (completedJob.status == 'cancelled') {
      setMessage(cancelledMessage);
      onChanged();
      return null;
    }
    if (completedJob.status != 'completed') {
      if (completedJob.status == 'failed') {
        unawaited(loadErrors(silent: true));
      }
      final jobError = completedJob.error?.trim();
      setMessage(
        jobError == null || jobError.isEmpty ? errorMessage : jobError,
      );
      onChanged();
      return null;
    }
    final generatedPrompt = (completedJob.resultData?['text'] as String? ?? '')
        .trim();
    if (generatedPrompt.isEmpty) {
      setMessage(emptyResultMessage);
      onChanged();
      return null;
    }
    return generatedPrompt;
  }

  _AutoPromptContext _promptContext({required bool forVideo}) {
    final storedVideoSource = forVideo ? videoSource() : null;
    final localVideoSource = forVideo ? videoLocalSource() : null;
    final usesImageSource = hasImageSource();
    final useImageToVideoPromptGenerator =
        forVideo && (storedVideoSource != null || localVideoSource != null);
    if (useImageToVideoPromptGenerator) {
      return _AutoPromptContext(
        useImageToVideoPromptGenerator: true,
        modelName: imageToVideoModelName(),
        basePrompt: imageToVideoBasePrompt(),
        generationLabel: 'i2v',
        storedVideoSource: storedVideoSource,
        localVideoSource: localVideoSource,
      );
    }
    if (forVideo) {
      return _AutoPromptContext(
        useImageToVideoPromptGenerator: false,
        modelName: textToVideoModelName(),
        basePrompt: textToVideoBasePrompt(),
        generationLabel: 't2v',
      );
    }
    if (usesImageSource) {
      return _AutoPromptContext(
        useImageToVideoPromptGenerator: false,
        modelName: imageToImageModelName(),
        basePrompt: imageToImageBasePrompt(),
        generationLabel: 'i2i',
      );
    }
    return _AutoPromptContext(
      useImageToVideoPromptGenerator: false,
      modelName: textToImageModelName(),
      basePrompt: textToImageBasePrompt(),
      generationLabel: 't2i',
    );
  }

  String? _requireLuckyBasePrompt({
    required bool useImageToVideoPromptGenerator,
  }) {
    final basePrompt = useImageToVideoPromptGenerator
        ? imageToVideoBasePrompt().trim()
        : textToImageBasePrompt().trim();
    if (basePrompt.isEmpty) {
      setMessage(
        useImageToVideoPromptGenerator
            ? 'Set an image to video base prompt in Settings first.'
            : 'Set a general base prompt in Settings first.',
      );
      onChanged();
      return null;
    }
    return basePrompt;
  }

  void _clearPendingPrompt({
    required bool forVideo,
    required Future<String?> pendingFuture,
  }) {
    if (forVideo) {
      if (identical(_pendingVideoPromptFuture, pendingFuture)) {
        _pendingVideoPromptFuture = null;
      }
    } else {
      if (identical(_pendingImagePromptFuture, pendingFuture)) {
        _pendingImagePromptFuture = null;
      }
    }
    onChanged();
  }

  static String _combinePromptGenerationInput(
    String currentPrompt, {
    required String basePrompt,
  }) {
    final trimmedBasePrompt = basePrompt.trim();
    final trimmedPrompt = currentPrompt.trim();
    if (trimmedBasePrompt.isEmpty) {
      return trimmedPrompt;
    }
    if (trimmedPrompt.isEmpty) {
      return trimmedBasePrompt;
    }
    return '$trimmedBasePrompt $trimmedPrompt';
  }
}

class _AutoPromptContext {
  const _AutoPromptContext({
    required this.useImageToVideoPromptGenerator,
    required this.modelName,
    required this.basePrompt,
    required this.generationLabel,
    this.storedVideoSource,
    this.localVideoSource,
  });

  final bool useImageToVideoPromptGenerator;
  final String modelName;
  final String basePrompt;
  final String generationLabel;
  final ImageRecord? storedVideoSource;
  final LocalImageSource? localVideoSource;
}
