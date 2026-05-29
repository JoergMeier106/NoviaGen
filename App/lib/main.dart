import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_app/app/runtime/app_crash_report_store.dart';
import 'package:flutter_app/app/system_ui.dart';
import 'package:flutter_app/app/bootstrap/app_bootstrap.dart';

export 'package:flutter_app/app/noviagen_app.dart';
export 'package:flutter_app/app/home_shell.dart';
export 'package:flutter_app/app/text2image_app.dart';

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
