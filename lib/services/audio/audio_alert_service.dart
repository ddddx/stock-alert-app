import 'package:flutter/services.dart';

abstract class AudioAlertService {
  Future<void> preload();
  Future<bool> speak(String text);
}

class PlatformTtsAudioAlertService implements AudioAlertService {
  static const MethodChannel _channel = MethodChannel('stock_alert_app/tts');

  @override
  Future<void> preload() async {
    try {
      await _channel.invokeMethod<void>('initTts');
    } on PlatformException {
      // Keep the app usable on platforms without native TTS wiring.
    }
  }

  @override
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'speak',
        <String, dynamic>{'text': trimmed},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
