import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/app/controllers/asset_refresh_controller.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';
import 'package:flutter_app/features/gallery/controllers/media_actions_controller.dart';

abstract class AppShellViewModel implements Listenable {
  ThemeMode get themeMode;
  String get baseUrl;
  String? get message;
  JobStatus? get activeRunningJob;
  bool get importingGalleryMedia;
  bool get loadingAssets;
  int get openGeneratePageRequestCount;
  int get openGalleryDetailRequestCount;
  String? get openGalleryDetailMediaId;
  int get queuedJobToastRequestCount;
  String? get queuedJobToastMessage;
  List<ImageRecord> get gallery;

  Future<void> refreshAssets();
  Future<void> importGalleryImages(ImageSource source);
  Future<ImageRecord?> fetchImageById(String imageId, {bool refresh = false});
}

class AppAppShellViewModel implements AppShellViewModel {
  AppAppShellViewModel({
    required this.changes,
    required this.connection,
    required this.activity,
    required this.navigation,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.assetRefresh,
    required this.mediaActions,
  });

  final Listenable changes;
  final AppConnectionStore connection;
  final AppActivityStore activity;
  final AppNavigationController navigation;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final AssetRefreshController assetRefresh;
  final MediaActionsController mediaActions;

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => changes.removeListener(listener);

  @override
  ThemeMode get themeMode => connection.themeMode;

  @override
  String get baseUrl => connection.baseUrl;

  @override
  String? get message => connection.message;

  @override
  JobStatus? get activeRunningJob => jobRuntime.activeRunningJob;

  @override
  bool get importingGalleryMedia => activity.importingGalleryMedia;

  @override
  bool get loadingAssets => activity.loadingAssets;

  @override
  int get openGeneratePageRequestCount =>
      navigation.openGeneratePageRequestCount;

  @override
  int get openGalleryDetailRequestCount =>
      navigation.openGalleryDetailRequestCount;

  @override
  String? get openGalleryDetailMediaId => navigation.openGalleryDetailMediaId;

  @override
  int get queuedJobToastRequestCount => navigation.queuedJobToastRequestCount;

  @override
  String? get queuedJobToastMessage => navigation.queuedJobToastMessage;

  @override
  List<ImageRecord> get gallery => mediaRuntime.gallery;

  @override
  Future<void> refreshAssets() => assetRefresh.refreshAssets();

  @override
  Future<void> importGalleryImages(ImageSource source) =>
      mediaActions.importGalleryImages(source);

  @override
  Future<ImageRecord?> fetchImageById(String imageId, {bool refresh = false}) =>
      mediaActions.fetchImageById(imageId, refresh: refresh);
}
