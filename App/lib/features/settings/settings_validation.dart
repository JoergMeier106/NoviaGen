import 'dart:io';


class SettingsValidationResult {
  const SettingsValidationResult({
    required this.stepsError,
    required this.guidanceError,
    required this.gallerySlideshowError,
    required this.chatContextWindowError,
    required this.wakeOnLanMacError,
    required this.wakeOnLanBroadcastError,
    required this.wakeOnLanPortError,
  });

  final String? stepsError;
  final String? guidanceError;
  final String? gallerySlideshowError;
  final String? chatContextWindowError;
  final String? wakeOnLanMacError;
  final String? wakeOnLanBroadcastError;
  final String? wakeOnLanPortError;

  bool get hasAutosaveBlockingError {
    return stepsError != null ||
        guidanceError != null ||
        gallerySlideshowError != null ||
        chatContextWindowError != null;
  }

  bool get canSendWakeOnLan {
    return wakeOnLanMacError == null &&
        wakeOnLanBroadcastError == null &&
        wakeOnLanPortError == null;
  }
}

class GenerationDefaultsValidationResult {
  const GenerationDefaultsValidationResult({
    required this.stepsError,
    required this.guidanceError,
  });

  final String? stepsError;
  final String? guidanceError;

  bool get hasAutosaveBlockingError =>
      stepsError != null || guidanceError != null;
}

GenerationDefaultsValidationResult validateGenerationDefaultsInput({
  required String steps,
  required String guidance,
}) {
  return GenerationDefaultsValidationResult(
    stepsError: _stepsError(int.tryParse(steps.trim())),
    guidanceError: _guidanceError(double.tryParse(guidance.trim())),
  );
}

SettingsValidationResult validateSettingsInput({
  required String steps,
  required String guidance,
  required String gallerySlideshow,
  required String chatContextWindow,
  required String wakeOnLanMac,
  required String wakeOnLanBroadcast,
  required String wakeOnLanPort,
}) {
  final parsedSteps = int.tryParse(steps.trim());
  final parsedGuidance = double.tryParse(guidance.trim());
  final parsedGallerySlideshow = int.tryParse(gallerySlideshow.trim());
  final parsedChatContextWindow = chatContextWindow.trim().isEmpty
      ? null
      : int.tryParse(chatContextWindow.trim());
  final parsedWakeOnLanBroadcast = wakeOnLanBroadcast.trim().isEmpty
      ? null
      : InternetAddress.tryParse(wakeOnLanBroadcast.trim());
  final parsedWakeOnLanPort = wakeOnLanPort.trim().isEmpty
      ? 9
      : int.tryParse(wakeOnLanPort.trim());

  return SettingsValidationResult(
    stepsError: _stepsError(parsedSteps),
    guidanceError: _guidanceError(parsedGuidance),
    gallerySlideshowError: _gallerySlideshowError(parsedGallerySlideshow),
    chatContextWindowError: _chatContextWindowError(
      chatContextWindow,
      parsedChatContextWindow,
    ),
    wakeOnLanMacError: _wakeOnLanMacError(wakeOnLanMac),
    wakeOnLanBroadcastError: _wakeOnLanBroadcastError(
      wakeOnLanBroadcast,
      parsedWakeOnLanBroadcast,
    ),
    wakeOnLanPortError: _wakeOnLanPortError(parsedWakeOnLanPort),
  );
}

String? _stepsError(int? value) {
  if (value == null || value < 1 || value > 150) {
    return 'Number of inference steps must be between 1 and 150.';
  }
  return null;
}

String? _guidanceError(double? value) {
  if (value == null || value < 0 || value > 30) {
    return 'Guidance scale must be between 0 and 30.';
  }
  return null;
}

String? _gallerySlideshowError(int? value) {
  if (value == null || value < 1 || value > 60) {
    return 'Slideshow speed must be between 1 and 60 seconds.';
  }
  return null;
}

String? _chatContextWindowError(String text, int? value) {
  if (text.trim().isNotEmpty &&
      (value == null || value < 256 || value > 1048576)) {
    return 'Context window must be between 256 and 1048576 tokens.';
  }
  return null;
}

String? _wakeOnLanMacError(String value) {
  if (value.trim().isNotEmpty && !_isValidWakeOnLanMacAddress(value)) {
    return 'Use 12 hex digits, for example AA:BB:CC:DD:EE:FF.';
  }
  return null;
}

bool _isValidWakeOnLanMacAddress(String value) {
  final hex = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  return hex.length == 12;
}

String? _wakeOnLanBroadcastError(String text, InternetAddress? value) {
  if (text.trim().isNotEmpty &&
      (value == null || value.type != InternetAddressType.IPv4)) {
    return 'Broadcast address must be a valid IPv4 address.';
  }
  return null;
}

String? _wakeOnLanPortError(int? value) {
  if (value == null || value < 1 || value > 65535) {
    return 'Wake-on-LAN UDP port must be between 1 and 65535.';
  }
  return null;
}
