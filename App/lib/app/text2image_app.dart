import 'package:flutter/material.dart';

import 'package:noviagen/app/home_shell.dart';
import 'package:noviagen/app/noviagen_theme.dart';
import 'package:noviagen/app/providers/core_providers.dart';

import 'package:noviagen/app/app_shell_view_model.dart';
import 'package:provider/provider.dart';

class Text2ImageApp extends StatelessWidget {
  const Text2ImageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CoreProviders(
      child: Consumer<AppShellViewModel>(
        builder: (context, viewModel, _) {
          return MaterialApp(
            title: 'NoviaGen',
            theme: buildNoviaGenLightTheme(),
            darkTheme: buildNoviaGenDarkTheme(),
            themeMode: viewModel.themeMode,
            home: HomeShell(viewModel: viewModel),
          );
        },
      ),
    );
  }
}
