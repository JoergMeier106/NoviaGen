bool isRecoverableCachedImageLoadError(Object error) {
  final message = error.toString();
  return message.contains('LocalFile:') &&
      message.contains('is empty and cannot be loaded as an image');
}
