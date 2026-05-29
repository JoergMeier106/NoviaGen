import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:noviagen/app/runtime/app_crash_report_store.dart';
import 'package:noviagen/app/system_ui.dart';
import 'package:noviagen/app/bootstrap/app_bootstrap.dart';

export 'package:noviagen/app/noviagen_app.dart';
export 'package:noviagen/app/home_shell.dart';
export 'package:noviagen/app/text2image_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final crashReports = AppCrashReportStore.instance;
  await crashReports.initialize();
  FlutterError.onError = crashReports.recordFlutterError;
  PlatformDispatcher.instance.onError = crashReports.recordPlatformError;

  await runZonedGuarded(
    () async {
      await restoreStandardSystemUi();
      runApp(await buildBootstrappedText2ImageApp());
    },
    (error, stackTrace) {
      crashReports.recordZoneError(error, stackTrace);
    },
  );
}
