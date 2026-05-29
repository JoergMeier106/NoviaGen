import 'media.dart';

class ChatAttachmentRecord {
  ChatAttachmentRecord({
    this.id,
    this.messageId,
    this.attachmentIndex = 0,
    this.contextImageId,
    this.contextImage,
    this.contextImageUrl,
    this.localPath,
    this.localName,
  });

  final String? id;
  final String? messageId;
  final int attachmentIndex;
  final String? contextImageId;
  final ImageRecord? contextImage;
  final String? contextImageUrl;
  final String? localPath;
  final String? localName;

  factory ChatAttachmentRecord.fromImageRecord(ImageRecord image) {
    return ChatAttachmentRecord(
      contextImageId: image.id,
      contextImage: image,
      contextImageUrl: image.previewUrl,
    );
  }

  factory ChatAttachmentRecord.fromLocalSource(LocalImageSource source) {
    return ChatAttachmentRecord(localPath: source.path, localName: source.name);
  }

  String get stableKey {
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) {
      return 'local:$local';
    }
    final imageId = contextImageId?.trim();
    if (imageId != null && imageId.isNotEmpty) {
      return 'image:$imageId';
    }
    final attachmentId = id?.trim();
    if (attachmentId != null && attachmentId.isNotEmpty) {
      return 'attachment:$attachmentId';
    }
    final url = contextImageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return 'url:$url';
    }
    return 'attachment:${attachmentIndex}_unknown';
  }

  bool get isLocal => localPath?.trim().isNotEmpty ?? false;

  String? get previewUrl => contextImage?.previewUrl ?? contextImageUrl;

  String get label {
    if (localName?.trim().isNotEmpty ?? false) {
      return localName!.trim();
    }
    final prompt = contextImage?.prompt.trim();
    if (prompt?.isNotEmpty ?? false) {
      return prompt!;
    }
    if (contextImage != null) {
      return contextImage!.mediaTypeLabel;
    }
    return 'Attachment';
  }

  ChatAttachmentRecord copyWith({
    String? id,
    String? messageId,
    int? attachmentIndex,
    String? contextImageId,
    ImageRecord? contextImage,
    String? contextImageUrl,
    String? localPath,
    String? localName,
  }) {
    return ChatAttachmentRecord(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      attachmentIndex: attachmentIndex ?? this.attachmentIndex,
      contextImageId: contextImageId ?? this.contextImageId,
      contextImage: contextImage ?? this.contextImage,
      contextImageUrl: contextImageUrl ?? this.contextImageUrl,
      localPath: localPath ?? this.localPath,
      localName: localName ?? this.localName,
    );
  }

  factory ChatAttachmentRecord.fromJson(Map<String, dynamic> json) {
    return ChatAttachmentRecord(
      id: json['id'] as String?,
      messageId: json['message_id'] as String?,
      attachmentIndex: (json['attachment_index'] as num?)?.toInt() ?? 0,
      contextImageId: json['context_image_id'] as String?,
      contextImage: json['context_image'] == null
          ? null
          : ImageRecord.fromJson(json['context_image'] as Map<String, dynamic>),
      contextImageUrl: json['context_image_url'] as String?,
    );
  }
}
