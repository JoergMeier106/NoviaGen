String chatTimeLabel(String raw) {
  final timestamp = DateTime.tryParse(raw)?.toLocal();
  if (timestamp == null) {
    return raw;
  }
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String compactChatTimeLabel(String raw) {
  final timestamp = DateTime.tryParse(raw)?.toLocal();
  if (timestamp == null) {
    return raw;
  }
  final now = DateTime.now();
  final sameDay =
      now.year == timestamp.year &&
      now.month == timestamp.month &&
      now.day == timestamp.day;
  if (sameDay) {
    return chatTimeLabel(raw);
  }
  return '${timestamp.month}/${timestamp.day}';
}
