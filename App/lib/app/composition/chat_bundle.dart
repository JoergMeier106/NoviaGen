import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/features/chat/state/chat_attachment_store.dart';
import 'package:flutter_app/features/chat/controllers/chat_job_message_controller.dart';
import 'package:flutter_app/features/chat/state/chat_model_catalog_store.dart';
import 'package:flutter_app/features/chat/state/chat_session_store.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/app/runtime/app_chat_runtime_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';


class ChatBundleDependencies {
  const ChatBundleDependencies({
    required this.connection,
    required this.chatRuntime,
    required this.mediaRuntime,
    required this.navigation,
    required this.loadErrors,
    required this.setRequestError,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppChatRuntimeStore chatRuntime;
  final MediaRuntimeStore mediaRuntime;
  final AppNavigationController navigation;
  final Future<void> Function({bool silent}) loadErrors;
  final RequestErrorHandler setRequestError;
  final void Function() notifyChanged;
}

class ChatBundle {
  ChatBundle(ChatBundleDependencies dependencies)
    : context = ChatAttachmentStore(
        api: () => dependencies.connection.api,
        setMessage: (value) => dependencies.connection.message = value,
        setRequestError: dependencies.setRequestError,
        onChanged: dependencies.notifyChanged,
      ),
      modelCatalog = ChatModelCatalogStore(
        api: () => dependencies.connection.api,
        setRequestError: dependencies.setRequestError,
        onChanged: dependencies.notifyChanged,
      ) {
    session = ChatSessionStore(
      api: () => dependencies.connection.api,
      modelCatalog: modelCatalog,
      context: context,
      loadModels: modelCatalog.loadChatModels,
      selectedModelName: () =>
          modelCatalog.selectedChatModelName(session.selectedSession),
      setMessage: (value) => dependencies.connection.message = value,
      setRequestError: dependencies.setRequestError,
      onChanged: dependencies.notifyChanged,
    );
    jobMessages = ChatJobMessageController(
      chat: session,
      context: context,
      gallery: () => dependencies.mediaRuntime.gallery,
      isActiveJob: (jobId) => dependencies.chatRuntime.activeJobId == jobId,
      setDraft: (value) => dependencies.chatRuntime.draft = value,
      setMessage: (value) => dependencies.connection.message = value,
      loadErrors: dependencies.loadErrors,
      selectedModelName: () =>
          modelCatalog.selectedChatModelName(session.selectedSession),
      requestScrollToMessage:
          dependencies.navigation.requestScrollToChatMessage,
    );
  }

  final ChatAttachmentStore context;
  final ChatModelCatalogStore modelCatalog;
  late final ChatSessionStore session;
  late final ChatJobMessageController jobMessages;
}
