import 'dart:io';

import 'package:flutter/services.dart';

class PlatformBridgeService {
  static const MethodChannel _channel = MethodChannel('stock_pulse/platform');

  Future<String> getStorageDirectoryPath() async {
    if (!Platform.isAndroid) {
      final directory = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}stock_pulse');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      return directory.path;
    }

    try {
      final path = await _channel.invokeMethod<String>('getStorageDirectoryPath');
      if (path != null && path.trim().isNotEmpty) {
        return path;
      }
    } on PlatformException {
      // Fall through to a writable temporary directory.
    }

    final directory = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}stock_pulse');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory.path;
  }

  Future<void> startForegroundMonitorService({required String summary}) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('startForegroundMonitorService', {
        'summary': summary,
      });
    } on PlatformException {
      // Ignore and keep the Flutter side usable.
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

  Future<void> stopForegroundMonitorService() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopForegroundMonitorService');
    } on PlatformException {
      // Ignore and keep the Flutter side usable.
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
