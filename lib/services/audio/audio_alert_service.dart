import 'package:flutter/services.dart';

abstract class AudioAlertService {
  Future<bool> preload();
  Future<bool> speak(String text);
}

class PlatformTtsAudioAlertService implements AudioAlertService {
  static const MethodChannel _channel = MethodChannel('stock_pulse/tts');

  @override
  Future<bool> preload() async {
    try {
      final result = await _channel.invokeMethod<bool>('initTts');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    try {
      final ready = await preload();
      if (!ready) {
        return false;
      }
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
