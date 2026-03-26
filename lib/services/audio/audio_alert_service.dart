import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class AudioAlertService {
  Future<bool> preload();
  Future<bool> speak(String text);
}

class FlutterTtsAudioAlertService implements AudioAlertService {
  FlutterTtsAudioAlertService({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;
  bool _preloaded = false;

  bool _isSuccessfulResult(dynamic result) {
    return result == null || result == true || result == 1;
  }

  @override
  Future<bool> preload() async {
    if (_preloaded) {
      return true;
    }

    try {
      final result = await _flutterTts.awaitSpeakCompletion(true);
      final ready = _isSuccessfulResult(result);
      _preloaded = ready;
      return ready;
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
      await _flutterTts.stop();
      final result = await _flutterTts.speak(trimmed);
      return _isSuccessfulResult(result);
    } on PlatformException {
      return false;
    }
  }
}
