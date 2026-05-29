import '../app_navigation_state.dart';
import '../chat_context_state.dart';
import '../chat_job_message_state.dart';
import '../chat_model_catalog_state.dart';
import '../chat_session_state.dart';
import '../request_errors.dart';
import 'runtime/app_chat_runtime_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppChatStateDependencies {
  const AppChatStateDependencies({
    required this.connection,
    required this.chatRuntime,
    required this.mediaRuntime,
    required this.navigation,
    required this.loadErrors,
    required this.setRequestError,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppChatRuntimeState chatRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final AppNavigationState navigation;
  final Future<void> Function({bool silent}) loadErrors;
  final RequestErrorHandler setRequestError;
  final void Function() notifyChanged;
}

class AppChatStates {
  AppChatStates(AppChatStateDependencies dependencies)
    : context = ChatContextState(
        api: () => dependencies.connection.api,
        setMessage: (value) => dependencies.connection.message = value,
        setRequestError: dependencies.setRequestError,
        onChanged: dependencies.notifyChanged,
      ),
      modelCatalog = ChatModelCatalogState(
        api: () => dependencies.connection.api,
        setRequestError: dependencies.setRequestError,
        onChanged: dependencies.notifyChanged,
      ) {
    session = ChatSessionState(
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
    jobMessages = ChatJobMessageState(
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

  final ChatContextState context;
  final ChatModelCatalogState modelCatalog;
  late final ChatSessionState session;
  late final ChatJobMessageState jobMessages;
}
