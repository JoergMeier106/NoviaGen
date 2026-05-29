import 'package:noviagen/models/jobs.dart';

String jobTitleText(JobStatus job) {
  if (job.isChainParent && !job.isTerminal) {
    return _activeChainStepLabel(job) ?? jobTypeLabel(job.type);
  }
  return jobTypeLabel(job.type);
}

String jobTypeLabel(String type) {
  return switch (type) {
    'app_crash' => 'App crash report',
    'chain' => 'Chained workflow',
    'generate' => 'Image generation',
    'generate_from_image' => 'Image-to-image generation',
    'upscale' => 'Image scaling',
    'upscale_video' => 'Video scaling',
    'convert_video_to_gif' => 'GIF conversion',
    'generate_audio_video' => 'Audio video generation',
    'generate_video' => 'Video generation',
    'animate_image' => 'Image animation',
    'generate_prompt' => 'Prompt generation',
    'generate_i2v_prompt' => 'Image-to-video prompt generation',
    'chat_message' => 'Chat message',
    _ => sentenceCase(type),
  };
}

String jobStatusText(JobStatus job) {
  if (job.cancelRequested && job.status == 'running') {
    final stage = jobStageText(job);
    if (stage == 'Waiting for job to stop') {
      return 'Waiting for job to stop';
    }
    return 'Cancellation requested';
  }

  switch (job.status) {
    case 'queued':
      return 'Waiting in queue';
    case 'running':
      final activeChainStep = _activeChainStepLabel(job);
      final stage = jobStageText(job);
      if (activeChainStep != null &&
          (stage == null || stage == 'Waiting in queue')) {
        return activeChainStep;
      }
      return stage ?? activeChainStep ?? 'Working';
    case 'completed':
      return 'Finished successfully';
    case 'cancelled':
      return 'Cancelled';
    case 'failed':
      return 'Stopped with an error';
    default:
      return sentenceCase(job.status);
  }
}

String jobProgressText(JobStatus job) {
  final percent = '${(job.progress.clamp(0.0, 1.0) * 100).round()}%';
  final step = jobStepText(job);
  if (step != null) {
    return '$percent - $step';
  }
  final activeChainStep = _activeChainStepLabel(job);
  return activeChainStep == null ? percent : '$percent - $activeChainStep';
}

String? _activeChainStepLabel(JobStatus job) {
  final step = _activeChainStep(job);
  if (step == null) {
    return null;
  }
  return _chainStepActionLabel(step.type);
}

JobChainStateStep? _activeChainStep(JobStatus job) {
  final chain = job.chain;
  if (chain == null || chain.steps.isEmpty) {
    return null;
  }

  final currentStepId = chain.currentStepId?.trim();
  if (currentStepId != null && currentStepId.isNotEmpty) {
    for (final step in chain.steps) {
      if (step.id == currentStepId) {
        return step;
      }
    }
  }

  for (final step in chain.steps) {
    final status = step.status.trim();
    if (status == 'queued' || status == 'running') {
      return step;
    }
  }
  return null;
}

String _chainStepActionLabel(String type) {
  return switch (type) {
    'generate' => 'Generating image',
    'generate_from_image' => 'Generating image',
    'generate_prompt' => 'Generating prompt',
    'generate_i2v_prompt' => 'Generating video prompt',
    'generate_video' => 'Generating video',
    'animate_image' => 'Animating image',
    'upscale' => 'Scaling image',
    'upscale_video' => 'Scaling video',
    'convert_video_to_gif' => 'Converting video to GIF',
    'generate_audio_video' => 'Generating audio video',
    'chat_message' => 'Generating response',
    _ => jobTypeLabel(type),
  };
}

DateTime? jobStartedAt(JobStatus job) {
  final raw = job.startedAt?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}

Duration? jobElapsedDuration(JobStatus job, {DateTime? now}) {
  if (job.status != 'running') {
    return null;
  }
  final startedAt = jobStartedAt(job);
  if (startedAt == null) {
    return null;
  }
  final elapsed = (now ?? DateTime.now()).difference(startedAt);
  if (elapsed.isNegative) {
    return Duration.zero;
  }
  return elapsed;
}

String? jobElapsedText(JobStatus job, {DateTime? now}) {
  final elapsed = jobElapsedDuration(job, now: now);
  if (elapsed == null) {
    return null;
  }
  return 'Running for ${formatJobElapsedDuration(elapsed)}';
}

String formatJobElapsedDuration(Duration duration) {
  final totalHours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (totalHours > 0) {
    return '${totalHours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
  return '${duration.inSeconds}s';
}

String? jobStageText(JobStatus job) {
  final text = job.statusText.trim();
  if (text.isEmpty) {
    return null;
  }

  if (text == 'Queued' || text == 'Queued for processing') {
    return 'Waiting in queue';
  }
  if (text == 'Starting generation') {
    return 'Starting the render';
  }
  if (text == 'Starting video generation') {
    return 'Starting the video render';
  }
  if (text == 'Starting video scaling') {
    return 'Starting the video upscale';
  }
  if (text == 'Preparing GIF conversion') {
    return 'Preparing GIF conversion';
  }
  if (text == 'Preparing audio video') {
    return 'Preparing audio video';
  }
  if (text == 'Preparing video generation') {
    return 'Preparing video generation';
  }
  if (text == 'Preparing video scaling') {
    return 'Preparing video scaling';
  }
  if (text == 'Preparing animation') {
    return 'Preparing animation';
  }
  if (text == 'Starting image-to-image generation') {
    return 'Starting image-to-image generation';
  }
  if (text == 'Starting image animation') {
    return 'Starting the animation';
  }
  if (text == 'Starting scaling') {
    return 'Starting the upscale';
  }
  if (text == 'Preparing job') {
    return 'Preparing the model';
  }
  if (text == 'Loading model') {
    return 'Loading model';
  }
  if (text == 'Encoding prompts') {
    return 'Encoding prompts';
  }
  if (text == 'Preparing upscale') {
    return 'Preparing the upscale';
  }
  if (text == 'Preparing source image') {
    return 'Preparing the source image';
  }
  if (text == 'Uploading source image') {
    return 'Uploading source image';
  }
  if (text == 'Waiting in video queue') {
    return 'Waiting in queue';
  }
  if (text == 'Generating frames') {
    return 'Generating video';
  }
  if (text.startsWith('Generating frames ')) {
    return 'Generating video';
  }
  if (text.startsWith('Generating video ')) {
    return 'Generating video';
  }
  if (text == 'Decoding frames') {
    return 'Decoding frames';
  }
  if (text == 'Encoding video') {
    return 'Encoding video';
  }
  if (text == 'Captioning video') {
    return 'Captioning video';
  }
  if (text == 'Planning audio') {
    return 'Planning audio';
  }
  if (text == 'Generating audio' || text.startsWith('Generating audio ')) {
    return 'Generating audio';
  }
  if (text == 'Combining audio and video') {
    return 'Combining audio and video';
  }
  if (text == 'Finalizing video') {
    return 'Finalizing video';
  }
  if (text == 'Saving image') {
    return 'Saving image';
  }
  if (text == 'Saving video') {
    return 'Saving video';
  }
  if (text == 'Saving GIF') {
    return 'Saving GIF';
  }
  if (text == 'Video ready') {
    return 'Finishing up';
  }
  if (text == 'Audio video ready') {
    return 'Finishing up';
  }
  if (text == 'Converting video to GIF' ||
      text.startsWith('Converting video to GIF ')) {
    return 'Converting video to GIF';
  }
  if (text == 'Generating image' || text.startsWith('Generating image ')) {
    return 'Generating image';
  }
  if (text == 'Generating video' || text.startsWith('Generating video ')) {
    return 'Generating video';
  }
  if (text == 'Scaling video' || text.startsWith('Scaling video ')) {
    return 'Scaling video';
  }
  if (text == 'Animating image' || text.startsWith('Animating image ')) {
    return 'Animating image';
  }
  if (text == 'Upscaling image' ||
      text == 'Scaling image' ||
      text.startsWith('Upscaling image ') ||
      text.startsWith('Scaling image ')) {
    return 'Scaling image';
  }
  if (text == 'Cancellation requested') {
    return 'Stopping after the current step';
  }
  if (text == 'Preparing prompt generation') {
    return 'Preparing prompt generation';
  }
  if (text == 'Generating prompt') {
    return 'Generating prompt';
  }
  if (text == 'Generating video prompt') {
    return 'Generating video prompt';
  }
  if (text == 'Preparing chat') {
    return 'Preparing chat';
  }
  if (text == 'Generating response') {
    return 'Generating response';
  }
  if (text == 'Saving chat messages') {
    return 'Saving chat messages';
  }
  if (text == 'Completed') {
    return 'Finished successfully';
  }
  if (text == 'Failed') {
    return 'Stopped with an error';
  }
  if (text == 'Cancelled') {
    return 'Cancelled';
  }
  if (text == 'Cancellation requested') {
    return 'Cancellation requested';
  }
  if (text == 'Waiting for job to stop') {
    return 'Waiting for job to stop';
  }
  if (text.toLowerCase().contains('comfy')) {
    final normalized = text.toLowerCase();
    if (normalized.contains('upload')) {
      return 'Uploading source image';
    }
    if (normalized.contains('queue')) {
      return 'Waiting in queue';
    }
    if (normalized.contains('download') || normalized.contains('final')) {
      return 'Finalizing video';
    }
    return 'Generating frames';
  }

  return sentenceCase(text);
}

String? jobStepText(JobStatus job) {
  final text = job.statusText.trim();
  if (text.startsWith('Generating image ')) {
    return text.substring('Generating image '.length);
  }
  if (text.startsWith('Upscaling image ')) {
    return text.substring('Upscaling image '.length);
  }
  if (text.startsWith('Scaling image ')) {
    return text.substring('Scaling image '.length);
  }
  if (text.startsWith('Generating video ')) {
    return text.substring('Generating video '.length);
  }
  if (text.startsWith('Generating frames ')) {
    return text.substring('Generating frames '.length);
  }
  if (text.startsWith('Scaling video ')) {
    return text.substring('Scaling video '.length);
  }
  if (text.startsWith('Generating audio ')) {
    return text.substring('Generating audio '.length);
  }
  if (text.startsWith('Converting video to GIF ')) {
    return text.substring('Converting video to GIF '.length);
  }
  if (text.startsWith('Animating image ')) {
    return text.substring('Animating image '.length);
  }
  if (text.toLowerCase().contains('comfy')) {
    return null;
  }
  return null;
}

String jobCompletionNotificationTitle(JobStatus job) {
  return switch (job.status) {
    'completed' => 'Job completed',
    'failed' => 'Job failed',
    'cancelled' => 'Job cancelled',
    _ => 'Job update',
  };
}

String jobCompletionNotificationBody(JobStatus job) {
  final lines = <String>[
    jobTitleText(job),
    'Status: ${jobStatusText(job)}',
    'Progress: ${jobProgressText(job)}',
    ...jobMetadataLines(job),
  ];
  if ((job.error ?? '').trim().isNotEmpty) {
    lines.add('Error: ${_truncate(job.error!.trim(), 160)}');
  }
  lines.add('Job ID: ${job.jobId}');
  return lines.join('\n');
}

List<String> jobMetadataLines(JobStatus job) {
  final payload = job.payload;
  final lines = <String>[];

  final prompt = _normalizeSingleLine(payload['prompt']);
  if (prompt != null) {
    lines.add('Prompt: ${_truncate(prompt, 160)}');
  }

  final modelId = _normalizeSingleLine(payload['model_id']);
  if (modelId != null) {
    lines.add('Model: $modelId');
  }

  final videoDisplayModelId = _normalizeSingleLine(payload['display_model_id']);
  if (videoDisplayModelId != null) {
    lines.add('Video model: $videoDisplayModelId');
  }

  final videoModelId = _normalizeSingleLine(payload['video_model_id']);
  if (videoModelId != null) {
    lines.add('Video workflow: $videoModelId');
  }

  final sourceImageId = _normalizeSingleLine(
    payload['source_image_id'] ?? payload['image_id'],
  );
  if (sourceImageId != null) {
    lines.add('Source image: $sourceImageId');
  }

  final orientation = _normalizeSingleLine(payload['image_orientation']);
  if (orientation != null) {
    lines.add('Orientation: ${sentenceCase(orientation)}');
  }

  final width = _intValue(payload['width']);
  final height = _intValue(payload['height']);
  if (width != null && height != null) {
    lines.add('Size: ${width}x$height');
  }

  final numFrames = _intValue(payload['num_frames']);
  final fps = _intValue(payload['fps']);
  if (numFrames != null && fps != null) {
    lines.add('Frames: $numFrames at $fps fps');
  }

  final numInferenceSteps = _intValue(payload['num_inference_steps']);
  if (numInferenceSteps != null) {
    lines.add('Steps: $numInferenceSteps');
  }

  final guidanceScale = _doubleValue(payload['guidance_scale']);
  if (guidanceScale != null) {
    lines.add('Guidance: ${_formatDecimal(guidanceScale)}');
  }

  final scaleFactor = _doubleValue(payload['scale_factor']);
  if (scaleFactor != null) {
    lines.add('Scale: ${_formatDecimal(scaleFactor)}x');
  }

  final strength = _doubleValue(payload['strength']);
  if (strength != null) {
    lines.add('Strength: ${_formatDecimal(strength)}');
  }

  final loraLabels = _loraLabels(payload['loras']);
  if (loraLabels.isNotEmpty) {
    lines.add('LoRAs: ${loraLabels.join(', ')}');
  }

  return lines;
}

String sentenceCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
}

String? _normalizeSingleLine(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

List<String> _loraLabels(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final labels = <String>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final rawId = item['lora_id']?.toString().trim() ?? '';
    if (rawId.isEmpty) {
      continue;
    }
    labels.add(rawId);
  }
  return labels;
}

String _formatDecimal(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength - 3)}...';
}
