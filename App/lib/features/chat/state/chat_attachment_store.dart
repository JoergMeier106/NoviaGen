import 'package:image_picker/image_picker.dart';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/models/chat_attachments.dart';
import 'package:noviagen/models/gallery.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/shared/request_errors.dart';


class ChatAttachmentStore {
  ChatAttachmentStore({
    required this.api,
    required this.setMessage,
    required this.setRequestError,
    required this.onChanged,
  });

  final ApiClient? Function() api;
  final void Function(String? value) setMessage;
  final RequestErrorHandler setRequestError;
  final void Function() onChanged;
  final ImagePicker _imagePicker = ImagePicker();

  List<ChatAttachmentRecord> attachments = <ChatAttachmentRecord>[];

  void addImages(Iterable<ImageRecord> images) {
    var changed = false;
    final nextAttachments = <ChatAttachmentRecord>[...attachments];
    final existingKeys = nextAttachments.map((item) => item.stableKey).toSet();
    for (final image in images) {
      final attachment = ChatAttachmentRecord.fromImageRecord(image);
      if (existingKeys.add(attachment.stableKey)) {
        nextAttachments.add(attachment);
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    attachments = nextAttachments;
    onChanged();
  }

  Future<void> pickImages(ImageSource source) async {
    try {
      final nextAttachments = <ChatAttachmentRecord>[...attachments];
      final existingKeys = nextAttachments
          .map((item) => item.stableKey)
          .toSet();
      if (source == ImageSource.gallery) {
        final files = await _imagePicker.pickMultiImage();
        if (files.isEmpty) {
          return;
        }
        for (final file in files) {
          _appendLocalFile(nextAttachments, existingKeys, file);
        }
      } else {
        final file = await _imagePicker.pickImage(source: source);
        if (file == null) {
          return;
        }
        _appendLocalFile(nextAttachments, existingKeys, file);
      }
      if (nextAttachments.length == attachments.length) {
        return;
      }
      attachments = nextAttachments;
      setMessage(
        source == ImageSource.camera
            ? 'Photo attached as chat context.'
            : 'Images attached as chat context.',
      );
    } catch (error) {
      setRequestError(
        error,
        generalMessage: 'Couldn\'t load the selected image. Please try again.',
      );
    }
    onChanged();
  }

  void remove(String stableKey) {
    final nextAttachments = attachments
        .where((item) => item.stableKey != stableKey)
        .toList();
    if (nextAttachments.length == attachments.length) {
      return;
    }
    attachments = nextAttachments;
    onChanged();
  }

  void clear({bool notify = true}) {
    if (attachments.isEmpty) {
      return;
    }
    attachments = <ChatAttachmentRecord>[];
    if (notify) {
      onChanged();
    }
  }

  void replaceAll(Iterable<ChatAttachmentRecord> next, {bool notify = true}) {
    attachments = List<ChatAttachmentRecord>.from(next);
    if (notify) {
      onChanged();
    }
  }

  Future<GalleryPageResponse> fetchAttachableGalleryImagesPage({
    String search = '',
    int page = 1,
    int pageSize = 60,
  }) async {
    final client = api();
    if (client == null) {
      return GalleryPageResponse(
        items: const <ImageRecord>[],
        page: page,
        pageSize: pageSize,
        total: 0,
        hasMore: false,
      );
    }
    final response = await client.fetchGalleryImagesPage(
      page: page,
      pageSize: pageSize,
      search: search,
      mediaType: 'images',
      sort: 'newest',
    );
    return GalleryPageResponse(
      items: response.items
          .where((item) => item.isReady && item.isStillImage)
          .toList(),
      page: response.page,
      pageSize: response.pageSize,
      total: response.total,
      hasMore: response.hasMore,
    );
  }

  Future<List<ImageRecord>> fetchImages({
    String search = '',
    int pageSize = 60,
  }) async {
    final page = await fetchAttachableGalleryImagesPage(
      search: search,
      pageSize: pageSize,
    );
    return page.items;
  }

  void _appendLocalFile(
    List<ChatAttachmentRecord> nextAttachments,
    Set<String> existingKeys,
    XFile file,
  ) {
    final attachment = ChatAttachmentRecord.fromLocalSource(
      LocalImageSource(path: file.path, name: file.name),
    );
    if (existingKeys.add(attachment.stableKey)) {
      nextAttachments.add(attachment);
    }
  }
}
