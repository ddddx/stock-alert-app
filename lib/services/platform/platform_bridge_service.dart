import 'dart:io';

import 'package:flutter/services.dart';

class AndroidBackgroundAccessStatus {
  const AndroidBackgroundAccessStatus({
    required this.isAndroid,
    required this.sdkInt,
    required this.notificationsRuntimePermissionRequired,
    required this.notificationPermissionGranted,
    required this.notificationsEnabled,
    required this.ignoringBatteryOptimizations,
  });

  factory AndroidBackgroundAccessStatus.notAndroid() {
    return const AndroidBackgroundAccessStatus(
      isAndroid: false,
      sdkInt: 0,
      notificationsRuntimePermissionRequired: false,
      notificationPermissionGranted: true,
      notificationsEnabled: true,
      ignoringBatteryOptimizations: true,
    );
  }

  factory AndroidBackgroundAccessStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return AndroidBackgroundAccessStatus.notAndroid();
    }

    return AndroidBackgroundAccessStatus(
      isAndroid: map['isAndroid'] as bool? ?? false,
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      notificationsRuntimePermissionRequired:
          map['notificationsRuntimePermissionRequired'] as bool? ?? false,
      notificationPermissionGranted:
          map['notificationPermissionGranted'] as bool? ?? true,
      notificationsEnabled: map['notificationsEnabled'] as bool? ?? true,
      ignoringBatteryOptimizations:
          map['ignoringBatteryOptimizations'] as bool? ?? true,
    );
  }

  final bool isAndroid;
  final int sdkInt;
  final bool notificationsRuntimePermissionRequired;
  final bool notificationPermissionGranted;
  final bool notificationsEnabled;
  final bool ignoringBatteryOptimizations;

  bool get canPostNotifications =>
      notificationPermissionGranted && notificationsEnabled;

  bool get needsNotificationPermissionRequest =>
      notificationsRuntimePermissionRequired && !notificationPermissionGranted;

  bool get needsBatteryOptimizationGuidance => !ignoringBatteryOptimizations;
}

class PlatformBridgeService {
  static const MethodChannel _channel = MethodChannel('stock_pulse/platform');

  Future<String> getStorageDirectoryPath() async {
    if (!Platform.isAndroid) {
      final directory = Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}stock_pulse');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      return directory.path;
    }

    try {
      final path =
          await _channel.invokeMethod<String>('getStorageDirectoryPath');
      if (path != null && path.trim().isNotEmpty) {
        return path;
      }
    } on PlatformException {
      // Fall through to a writable temporary directory.
    }

    final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}stock_pulse');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory.path;
  }

  Future<bool> startForegroundMonitorService({required String summary}) async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel
              .invokeMethod<bool>('startForegroundMonitorService', {
            'summary': summary,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> updateForegroundMonitorSummary({required String summary}) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateForegroundMonitorSummary', {
        'summary': summary,
      });
    } on PlatformException {
      // Ignore and keep the Flutter side usable.
    }
  }

  Future<bool> reloadForegroundMonitorService() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel
              .invokeMethod<bool>('reloadForegroundMonitorService') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> refreshForegroundMonitorService() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel
              .invokeMethod<bool>('refreshForegroundMonitorService') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopForegroundMonitorService() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel
              .invokeMethod<bool>('stopForegroundMonitorService') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<AndroidBackgroundAccessStatus> getAndroidBackgroundAccessStatus() async {
    if (!Platform.isAndroid) {
      return AndroidBackgroundAccessStatus.notAndroid();
    }
    try {
      final payload = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAndroidBackgroundAccessStatus',
      );
      return AndroidBackgroundAccessStatus.fromMap(payload);
    } on PlatformException {
      return AndroidBackgroundAccessStatus.notAndroid();
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } on PlatformException {
      // Ignore.
    }
  }

  Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      // Ignore.
    }
  }
}
