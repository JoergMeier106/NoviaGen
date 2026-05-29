import '../../models/chat_attachments.dart';
import '../../models/media.dart';
class ChatMessageAttachments {
  const ChatMessageAttachments(this.records);

  factory ChatMessageAttachments.fromContext(
    Iterable<ChatAttachmentRecord> attachments,
  ) {
    return ChatMessageAttachments(List<ChatAttachmentRecord>.from(attachments));
  }

  final List<ChatAttachmentRecord> records;

  List<String> get contextImageIds {
    return records
        .map((item) => item.contextImageId?.trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<LocalImageSource> get localImages {
    return records
        .where((item) => item.localPath?.trim().isNotEmpty ?? false)
        .map(
          (item) => LocalImageSource(
            path: item.localPath!,
            name: item.localName ?? 'attachment',
          ),
        )
        .toList();
  }
}
