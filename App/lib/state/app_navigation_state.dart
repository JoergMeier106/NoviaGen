import 'package:flutter/foundation.dart';


class AppNavigationState {
  AppNavigationState({required this.onChanged});

  final VoidCallback onChanged;

  int openGeneratePageRequestCount = 0;
  int openGalleryDetailRequestCount = 0;
  String? openGalleryDetailMediaId;
  int scrollGeneratePageToTopRequestCount = 0;
  int scrollToChatMessageRequestCount = 0;
  String? scrollToChatMessageId;
  int queuedJobToastRequestCount = 0;
  String? queuedJobToastMessage;

  void requestOpenGeneratePage({bool scrollToTop = false}) {
    openGeneratePageRequestCount += 1;
    if (scrollToTop) {
      scrollGeneratePageToTopRequestCount += 1;
    }
    onChanged();
  }

  void requestOpenGalleryDetail(String mediaId) {
    final trimmedId = mediaId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    openGalleryDetailMediaId = trimmedId;
    openGalleryDetailRequestCount += 1;
    onChanged();
  }

  void requestScrollToChatMessage(String messageId) {
    scrollToChatMessageId = messageId;
    scrollToChatMessageRequestCount += 1;
    onChanged();
  }

  void announceQueuedJob(String messageText) {
    queuedJobToastMessage = messageText;
    queuedJobToastRequestCount += 1;
    onChanged();
  }
}
