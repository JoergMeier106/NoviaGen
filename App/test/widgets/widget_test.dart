import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/main.dart';
import 'package:flutter_app/app/app_shell_view_model.dart';
import 'package:flutter_app/features/chat/chat_page.dart';
import 'package:flutter_app/features/chat/chat_view_model.dart';
import 'package:flutter_app/features/gallery/gallery_page.dart';
import 'package:flutter_app/features/gallery/gallery_view_model.dart';
import 'package:flutter_app/features/generate/generate_page.dart';
import 'package:flutter_app/features/generate/generation_view_model.dart';
import 'package:flutter_app/features/settings/settings_pages.dart';
import 'package:flutter_app/features/settings/settings_view_model.dart';
import 'package:flutter_app/state/app_state/app_bootstrap.dart';

void main() {
  testWidgets('app shell renders main navigation', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestText2ImageApp());

    expect(find.text('Generate'), findsWidgets);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    final shellContext = tester.element(find.byType(HomeShell));
    expect(
      Provider.of<AppShellViewModel>(shellContext, listen: false),
      isA<AppShellViewModel>(),
    );

    final generateContext = tester.element(
      find.byType(GeneratePage, skipOffstage: false),
    );
    expect(
      Provider.of<GenerationViewModel>(generateContext, listen: false),
      isA<GenerationViewModel>(),
    );

    final galleryContext = tester.element(
      find.byType(GalleryPage, skipOffstage: false),
    );
    expect(
      Provider.of<GalleryViewModel>(galleryContext, listen: false),
      isA<GalleryViewModel>(),
    );

    final chatContext = tester.element(
      find.byType(ChatPage, skipOffstage: false),
    );
    expect(
      Provider.of<ChatViewModel>(chatContext, listen: false),
      isA<ChatViewModel>(),
    );

    final settingsContext = tester.element(
      find.byType(SettingsPage, skipOffstage: false),
    );
    expect(
      Provider.of<SettingsViewModel>(settingsContext, listen: false),
      isA<SettingsViewModel>(),
    );
  });
}
