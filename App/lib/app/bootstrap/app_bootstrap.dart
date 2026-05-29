import 'package:flutter/widgets.dart';

import 'package:noviagen/app/text2image_app.dart';
import 'package:noviagen/di/app_locator.dart';
import 'package:noviagen/di/injection.dart';
import 'package:noviagen/job_notifications.dart';


Future<Widget> buildBootstrappedText2ImageApp() async {
  await configureDependencies(reset: true);
  final notifications = JobNotificationController();
  getIt.jobNotifications.attach(notifications);
  await getIt.configuration.loadSettings();
  await notifications.initialize(
    onOpenGeneratePage: getIt.navigation.requestOpenGeneratePage,
    onOpenMediaDetail: getIt.navigation.requestOpenGalleryDetail,
  );
  return buildText2ImageApp();
}

Widget buildTestText2ImageApp() {
  configureDependenciesSync();
  return buildText2ImageApp();
}

Text2ImageApp buildText2ImageApp() {
  return const Text2ImageApp();
}
