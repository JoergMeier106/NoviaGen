import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:noviagen/di/app_locator.dart';
import 'package:noviagen/di/injection.dart';
import 'package:noviagen/app/app_shell_view_model.dart';
import 'package:noviagen/features/chat/chat_view_model.dart';
import 'package:noviagen/features/generate/generation_view_model.dart';
import 'package:noviagen/features/gallery/gallery_view_model.dart';
import 'package:noviagen/features/settings/settings_view_model.dart';

class CoreProviders extends StatelessWidget {
  const CoreProviders({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ListenableProvider<AppShellViewModel>(
          create: (_) => AppAppShellViewModel(
            changes: getIt.changes,
            connection: getIt.connection,
            activity: getIt.activity,
            navigation: getIt.navigation,
            jobRuntime: getIt.jobRuntime,
            mediaRuntime: getIt.mediaRuntime,
            assetRefresh: getIt.assetRefresh,
            mediaActions: getIt.mediaActions,
          ),
        ),
        ListenableProvider<ChatViewModel>(
          create: (_) => AppChatViewModel(
            changes: getIt.changes,
            navigation: getIt.navigation,
            runtime: getIt.chatRuntime,
            contextState: getIt.chatContext,
            modelCatalog: getIt.chatModelCatalog,
            sessionsState: getIt.chat,
            jobOperations: getIt.jobOperations,
            systemOperations: getIt.system,
            messageController: getIt.chatMessageController,
            promptLibrary: getIt.promptLibrary,
          ),
        ),
        ListenableProvider<GenerationViewModel>(
          create: (_) => AppGenerationViewModel(
            changes: getIt.changes,
            connection: getIt.connection,
            drafts: getIt.generationDrafts,
            mediaRuntime: getIt.mediaRuntime,
            jobOperations: getIt.jobOperations,
            assetRefresh: getIt.assetRefresh,
            sourceController: getIt.generationSourceController,
            imageController: getIt.imageGenerationController,
            videoController: getIt.videoGenerationController,
            videoLuckyController: getIt.videoLuckyGenerationController,
            autoPrompts: getIt.autoPrompts,
            chatContext: getIt.chatContext,
            defaults: getIt.generationDefaults,
            sources: getIt.generationSources,
            imageModels: getIt.imageModels,
            promptLibrary: getIt.promptLibrary,
            videoAssets: getIt.videoAssets,
            videoSettings: getIt.videoSettings,
            deleteStoredImageById: getIt.mediaActions.deleteStoredImage,
          ),
        ),
        ListenableProvider<GalleryViewModel>(
          create: (_) => AppGalleryViewModel(
            changes: getIt.changes,
            connection: getIt.connection,
            mediaRuntime: getIt.mediaRuntime,
            browser: getIt.galleryBrowser,
            jobRuntime: getIt.jobRuntime,
            actions: getIt.mediaActions,
            jobOperations: getIt.jobOperations,
            generationSourceController: getIt.generationSourceController,
            mediaJobController: getIt.mediaJobController,
          ),
        ),
        ListenableProvider<SettingsViewModel>(
          create: (_) => AppSettingsViewModel(
            changes: getIt.changes,
            connection: getIt.connection,
            activity: getIt.activity,
            chatRuntime: getIt.chatRuntime,
            jobRuntime: getIt.jobRuntime,
            scalingPreferences: getIt.scalingPreferences,
            assetRefresh: getIt.assetRefresh,
            backendRefresh: getIt.backendRefresh,
            configuration: getIt.configuration,
            chatModelCatalog: getIt.chatModelCatalog,
            chatSessions: getIt.chat,
            galleryBrowser: getIt.galleryBrowser,
            defaults: getIt.generationDefaults,
            imageModels: getIt.imageModels,
            jobOperations: getIt.jobOperations,
            logs: getIt.logs,
            mediaActions: getIt.mediaActions,
            promptLibrary: getIt.promptLibrary,
            systemOperations: getIt.system,
            videoAssets: getIt.videoAssets,
          ),
        ),
      ],
      child: child,
    );
  }
}
