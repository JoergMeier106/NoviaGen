import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/state/gallery_state.dart';
import 'package:flutter_app/job_text.dart';
import 'package:flutter_app/models/generation.dart';
import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Gallery sorting', () {
    test('keeps playback duration and generation duration sorts distinct', () {
      final slowPlaybackFastGeneration = _imageRecord(
        id: 'slow-playback-fast-generation',
        durationSeconds: 30,
        generationDurationSeconds: 5,
      );
      final fastPlaybackSlowGeneration = _imageRecord(
        id: 'fast-playback-slow-generation',
        durationSeconds: 10,
        generationDurationSeconds: 20,
      );
      final gallery = <ImageRecord>[
        slowPlaybackFastGeneration,
        fastPlaybackSlowGeneration,
      ];
      late final GalleryBrowserState browser;
      browser = GalleryBrowserState(
        reloadFirstPage: () async {},
        sortLoadedItems: () => gallery.sort(browser.compareItems),
        onChanged: () {},
      );

      browser.setSortOption(GallerySortOption.durationHigh);
      expect(gallery.first.id, slowPlaybackFastGeneration.id);

      browser.setSortOption(GallerySortOption.generationDurationHigh);
      expect(gallery.first.id, fastPlaybackSlowGeneration.id);
    });
  });

  group('Job progress copy', () {
    test('does not expose Comfy internals in user-facing progress text', () {
      final queuedJob = _jobStatus('Queued in ComfyUI (2 pending)');
      final runningJob = _jobStatus('ComfyUI executing KSampler (3/8)');

      expect(jobStatusText(queuedJob), 'Waiting in queue');
      expect(jobStageText(queuedJob), 'Waiting in queue');
      expect(jobStageText(runningJob), 'Generating frames');
      expect(jobStatusText(queuedJob).contains('Comfy'), isFalse);
      expect(jobStageText(queuedJob)!.contains('Comfy'), isFalse);
      expect(jobStageText(runningJob)!.contains('Comfy'), isFalse);
      expect(jobStepText(runningJob), isNull);
    });

    test('uses the active step for chained workflow copy', () {
      final promptStepJob = _chainJob(
        currentStepId: 'prompt',
        steps: [
          JobChainStateStep(
            id: 'prompt',
            type: 'generate_prompt',
            status: 'running',
            childJobId: 'child-prompt',
          ),
          JobChainStateStep(id: 'image', type: 'generate', status: 'queued'),
        ],
        progress: 0.25,
        statusText: 'Queued for processing',
      );
      final imageStepJob = _chainJob(
        currentStepId: 'image',
        steps: [
          JobChainStateStep(
            id: 'prompt',
            type: 'generate_prompt',
            status: 'completed',
          ),
          JobChainStateStep(
            id: 'image',
            type: 'generate',
            status: 'running',
            childJobId: 'child-image',
          ),
        ],
        progress: 0.5,
        statusText: 'Loading model',
      );

      expect(jobTitleText(promptStepJob), 'Generating prompt');
      expect(jobStatusText(promptStepJob), 'Generating prompt');
      expect(jobProgressText(promptStepJob), '25% - Generating prompt');
      expect(jobTitleText(imageStepJob), 'Generating image');
      expect(jobStatusText(imageStepJob), 'Loading model');
      expect(jobProgressText(imageStepJob), '50% - Generating image');
    });
  });
}

JobStatus _jobStatus(String statusText) {
  return JobStatus(
    jobId: 'job-1',
    type: 'generate_video',
    parentJobId: null,
    chainStepId: null,
    status: 'running',
    progress: 0.5,
    statusText: statusText,
    cancelRequested: false,
    payload: const <String, dynamic>{},
  );
}

JobStatus _chainJob({
  required String currentStepId,
  required List<JobChainStateStep> steps,
  required double progress,
  required String statusText,
}) {
  return JobStatus(
    jobId: 'chain-1',
    type: 'chain',
    parentJobId: null,
    chainStepId: null,
    status: 'running',
    progress: progress,
    statusText: statusText,
    cancelRequested: false,
    payload: const <String, dynamic>{},
    chain: JobChainState(
      currentStepId: currentStepId,
      currentChildJobId: null,
      steps: steps,
    ),
  );
}

ImageRecord _imageRecord({
  required String id,
  required double durationSeconds,
  required double generationDurationSeconds,
}) {
  return ImageRecord(
    id: id,
    status: 'stored',
    mediaType: 'video',
    mimeType: 'video/mp4',
    width: 640,
    height: 360,
    prompt: 'prompt',
    defaultPositivePrompt: '',
    defaultNegativePrompt: '',
    finalPositivePrompt: 'prompt',
    modelId: 'demo-model',
    loras: const <SelectedLora>[],
    tags: const <String>[],
    caption: '',
    numInferenceSteps: 8,
    guidanceScale: 4,
    imageOrientation: 'landscape',
    fileUrl: 'http://example.invalid/file.mp4',
    previewUrl: 'http://example.invalid/preview.png',
    createdAt: '2026-04-16T10:00:00Z',
    rating: 3,
    durationSeconds: durationSeconds,
    generationDurationSeconds: generationDurationSeconds,
    fps: 8,
    numFrames: 80,
  );
}
